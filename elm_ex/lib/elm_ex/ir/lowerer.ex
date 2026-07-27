defmodule ElmEx.IR.Lowerer do
  @moduledoc """
  Lowers frontend modules into ownership-annotated IR.
  """

  alias ElmEx.Frontend.AstContract.Types.Declaration, as: AstDeclaration
  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.Frontend.Types.ImportEntry
  alias ElmEx.Frontend.Project
  alias ElmEx.Frontend.DefaultImports
  alias ElmEx.IR
  alias ElmEx.IR.DeadCode
  alias ElmEx.IR.Declaration
  alias ElmEx.IR.FrontendReachability
  alias ElmEx.IR.FunctionCallCheck
  alias ElmEx.IR.ImportResolution
  alias ElmEx.IR.LowererCache
  alias ElmEx.IR.Module
  alias ElmEx.IR.PipeChain
  alias ElmEx.IR.Wire3HelperResolution

  alias ElmEx.IR.Types.{Diagnostic, Expr, Lookup, ModuleExports, Pattern}

  @typep name() :: String.t() | nil
  @typep payload_kind() :: Lookup.payload_kind()
  @typep preferences_alias_fields :: %{optional(String.t()) => [String.t()]}

  @pebble_ui_window_stack_tag 1000
  @pebble_ui_window_node_tag 1001
  @pebble_ui_canvas_layer_tag 1002

  # Union constructors from common Elm package dependencies. These modules are
  # not always loaded into the frontend project graph, but apps import their
  # types with exposing (Type(..)) and reference constructors unqualified.
  @known_dependency_union_constructors %{
    "List.Nonempty" => %{"Nonempty" => ["Nonempty"]},
    "Svg.PathD" => %{
      "Segment" => ~w(M L H V Z C S Q T A Md Ld Hd Vd Zd Cd Sd Qd Td Ad)
    },
    # Scene3d.Entity imports `Node(..)` and matches Group/EmptyNode unqualified.
    # Without these ctors in import_unqualified_map, bare `Group` falls through to the
    # global short-name table and can collide with Internal.Compiler.Group (tag 5),
    # which is also PointNode — transformBy then treats Groups as Points / Empty.
    "Scene3d.Types" => %{
      "Node" =>
        ~w(EmptyNode OpaqueMeshNode TransparentMeshNode ShadowNode PointNode Group Transformed),
      "Entity" => ["Entity"],
      "Mesh" =>
        ~w(EmptyMesh Triangles Facets Indexed MeshWithNormals MeshWithUvs MeshWithNormalsAndUvs MeshWithTangents LineSegments Polyline Points),
      "Shadow" => ~w(EmptyShadow Shadow)
    }
  }

  @internal_diagram_peer_redirects %{
    "Internal.Vec2.init" => "Diagram.Vec2.init",
    "Internal.Svg.Config.withCellAttributesFunction" =>
      "Diagram.Svg.Config.withCellAttributesFunction"
  }

  @doc """
  Public export map used by reachability and import resolution.
  """
  @spec project_module_exports([FrontendModule.t()]) :: ModuleExports.project_exports()
  def project_module_exports(modules), do: build_project_module_exports(modules)

  @doc """
  Import-resolution bundle for a frontend module.
  """
  @spec import_resolution_for(FrontendModule.t() | map(), ModuleExports.project_exports()) ::
          Lookup.import_resolution_bundle()
  def import_resolution_for(frontend_module, project_module_exports) when is_map(frontend_module) do
    build_import_resolution(
      Map.get(frontend_module, :import_entries) || [],
      project_module_exports
    )
  end

  @spec lower_project(Project.t(), keyword()) :: {:ok, IR.t()}
  def lower_project(%Project{} = project, opts \\ []) do
    opts = normalize_lower_opts(opts, project)

    globals = build_global_tables(project.modules)
    project_module_exports = build_project_module_exports(project.modules)

    reachable =
      if Keyword.get(opts, :reachable_only, false) do
        entry = Keyword.get(opts, :entry_module, "Main")
        progress_log(opts, "computing reachable functions from #{entry}…")
        keys = FrontendReachability.reachable_function_keys(project, entry, opts)

        if MapSet.size(keys) == 0 do
          progress_log(opts, "reachable set empty; lowering all functions")
          :all
        else
          progress_log(opts, "reachable functions: #{MapSet.size(keys)}")
          keys
        end
      else
        :all
      end

    cache_opts =
      opts
      |> Keyword.put(:reachable_fp, LowererCache.fingerprint_reachable(reachable))

    cache =
      LowererCache.init(
        cache_opts,
        globals.fingerprint,
        project.project_dir
      )

    modules =
      lower_all_modules(
        project.modules,
        globals,
        project_module_exports,
        reachable,
        cache,
        opts
      )

    diagnostics =
      collect_constructor_arity_diagnostics(
        modules,
        globals.payload_kind_unqualified,
        globals.payload_kind_qualified
      ) ++
        collect_constructor_call_arity_diagnostics(
          project.modules,
          globals.payload_arity_unqualified,
          globals.payload_arity_qualified
        ) ++
        FunctionCallCheck.collect_project_diagnostics(
          project.modules,
          project_module_exports,
          project.project_dir,
          Map.get(project.elm_json, "source-directories", ["src"])
        ) ++
        collect_preferences_schema_field_order_diagnostics(project.modules)

    modules =
      Wire3HelperResolution.augment_cross_module_wire3(
        modules,
        Wire3HelperResolution.union_meta_from_lowerer(unions_from_modules(modules))
      )

    # Reachable-only may miss callees only visible after import normalize / Wire3
    # synthesis. Pull those frontend defs in until the IR call graph is closed.
    modules =
      close_missing_callees(
        modules,
        project,
        globals,
        project_module_exports,
        reachable,
        opts
      )

    {:ok, %IR{modules: modules, diagnostics: diagnostics}}
  end

  @spec normalize_lower_opts(list(), map()) :: list()

  defp normalize_lower_opts(opts, %Project{} = project) when is_list(opts) do
    opts
    |> Keyword.put_new(:entry_module, "Main")
    |> Keyword.put_new(:progress, false)
    |> Keyword.put_new(:parallel, 1)
    |> Keyword.put_new(:reachable_only, false)
    |> Keyword.put_new(:cache, false)
    |> then(fn o ->
      if Keyword.get(o, :cache) == true and is_nil(Keyword.get(o, :cache_dir)) do
        Keyword.put(o, :cache_dir, LowererCache.default_cache_dir(project.project_dir))
      else
        o
      end
    end)
  end

  @spec progress_log(list(), String.t()) :: Types.expr()

  defp progress_log(opts, message) when is_list(opts) and is_binary(message) do
    if Keyword.get(opts, :progress, false) do
      IO.puts(:stderr, "[elmc] #{message}")
    end

    :ok
  end

  @spec build_global_tables(list()) :: Types.expr()

  defp build_global_tables(modules) when is_list(modules) do
    init = %{
      constructor_unqualified: [],
      constructor_qualified: [],
      payload_kind_unqualified: [],
      payload_kind_qualified: [],
      payload_arity_unqualified: [],
      payload_arity_qualified: [],
      record_alias_unqualified: [],
      record_alias_qualified: [],
      fingerprint_parts: []
    }

    acc =
      Enum.reduce(modules, init, fn frontend_module, acc ->
        Enum.reduce(frontend_module.declarations, acc, fn decl, acc ->
          case decl do
            %{kind: :union, name: union_name, constructors: constructors}
            when is_list(constructors) ->
              tags =
                constructors
                |> Enum.with_index(1)
                |> Enum.map(fn {constructor, index} -> {constructor.name, index} end)

              kinds =
                Enum.map(constructors, fn constructor ->
                  {constructor.name, payload_kind_for_spec(constructor.arg)}
                end)

              arities =
                Enum.map(constructors, fn constructor ->
                  {constructor.name, payload_arity_for_spec(constructor.arg)}
                end)

              qualified_tags =
                Enum.map(tags, fn {name, index} ->
                  {"#{frontend_module.name}.#{name}", index}
                end)

              qualified_kinds =
                Enum.map(kinds, fn {name, kind} ->
                  {"#{frontend_module.name}.#{name}", kind}
                end)

              qualified_arities =
                Enum.map(arities, fn {name, arity} ->
                  {"#{frontend_module.name}.#{name}", arity}
                end)

              %{
                acc
                | constructor_unqualified: tags ++ acc.constructor_unqualified,
                  constructor_qualified: qualified_tags ++ acc.constructor_qualified,
                  payload_kind_unqualified: kinds ++ acc.payload_kind_unqualified,
                  payload_kind_qualified: qualified_kinds ++ acc.payload_kind_qualified,
                  payload_arity_unqualified: arities ++ acc.payload_arity_unqualified,
                  payload_arity_qualified: qualified_arities ++ acc.payload_arity_qualified,
                  fingerprint_parts: [
                    {:u, frontend_module.name, union_name, tags} | acc.fingerprint_parts
                  ]
              }

            %{kind: :type_alias, name: name, fields: fields}
            when is_list(fields) and fields != [] ->
              field_names = Enum.map(fields, &to_string/1)

              %{
                acc
                | record_alias_unqualified: [{name, field_names} | acc.record_alias_unqualified],
                  record_alias_qualified: [
                    {"#{frontend_module.name}.#{name}", field_names} | acc.record_alias_qualified
                  ],
                  fingerprint_parts: [
                    {:a, frontend_module.name, name, field_names} | acc.fingerprint_parts
                  ]
              }

            _ ->
              acc
          end
        end)
      end)

    fingerprint =
      acc.fingerprint_parts
      |> Enum.reverse()
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, [&1]))
      |> Base.encode16(case: :lower)

    %{
      # Drop short names that appear under multiple modules (e.g. Group). Last-wins
      # Map.new would otherwise bind Group to Internal.Compiler.Group (tag 5) and
      # poison Scene3d.Types.Group (tag 6) pattern matches / constructor builds.
      constructor_unqualified: unique_short_name_map(acc.constructor_unqualified),
      constructor_qualified: Map.new(acc.constructor_qualified),
      payload_kind_unqualified: unique_short_name_map(acc.payload_kind_unqualified),
      payload_kind_qualified: Map.new(acc.payload_kind_qualified),
      payload_arity_unqualified: unique_short_name_map(acc.payload_arity_unqualified),
      payload_arity_qualified: Map.new(acc.payload_arity_qualified),
      record_alias_unqualified: unique_short_name_map(acc.record_alias_unqualified),
      record_alias_qualified: Map.new(acc.record_alias_qualified),
      fingerprint: fingerprint
    }
  end

  @spec lower_all_modules(String.t(), Types.expr(), String.t(), Types.expr(), Types.expr(), keyword()) :: Types.expr()

  defp lower_all_modules(modules, globals, project_module_exports, reachable, cache, opts) do
    total = length(modules)
    parallel = max(1, Keyword.get(opts, :parallel, 1))
    progress? = Keyword.get(opts, :progress, false)

    lower_one = fn frontend_module, index ->
      if progress? and (rem(index, 25) == 0 or index == total) do
        progress_log(opts, "lowering module #{index}/#{total}: #{frontend_module.name}")
      end

      case LowererCache.fetch(cache, frontend_module) do
        {:hit, ir_mod} ->
          ir_mod

        :miss ->
          ir_mod =
            lower_frontend_module(
              frontend_module,
              globals,
              project_module_exports,
              reachable
            )

          LowererCache.put(cache, frontend_module, ir_mod)
          ir_mod
      end
    end

    if parallel > 1 do
      modules
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {mod, idx} -> lower_one.(mod, idx) end,
        max_concurrency: parallel,
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, ir_mod} -> ir_mod end)
    else
      modules
      |> Enum.with_index(1)
      |> Enum.map(fn {mod, idx} -> lower_one.(mod, idx) end)
    end
  end

  @spec lower_frontend_module(String.t(), Types.expr(), String.t(), Types.expr()) :: Types.expr()

  defp lower_frontend_module(frontend_module, globals, project_module_exports, reachable) do
    ports = Map.get(frontend_module, :ports, []) || []

    {signatures, others} =
      Enum.split_with(frontend_module.declarations, &(&1.kind == :function_signature))

    unions =
      others
      |> Enum.filter(&(&1.kind == :union))
      |> Enum.map(fn union ->
        constructors = Map.get(union, :constructors, [])

        tag_map =
          constructors
          |> Enum.with_index(1)
          |> Map.new(fn {constructor, index} ->
            {constructor.name, index}
          end)

        payload_specs =
          constructors
          |> Map.new(fn constructor ->
            {constructor.name, constructor.arg}
          end)

        payload_kinds =
          payload_specs
          |> Map.new(fn {name, spec} ->
            {name, payload_kind_for_spec(spec)}
          end)

        {union.name,
         %{
           constructors: constructors,
           tags: tag_map,
           payload_specs: payload_specs,
           payload_kinds: payload_kinds
         }}
      end)
      |> Map.new()

    all_definition_decls =
      others
      |> Enum.filter(&(&1.kind == :function_definition))

    # Wire3 synthesis must see encode*ForClient / encode* sources even when those
    # helpers are not yet in the reachable set (they are only referenced via the
    # synthesized w3_* bindings). Filter to reachable + synthesized helpers after.
    definition_decls =
      all_definition_decls
      |> then(
        &Wire3HelperResolution.augment_function_definitions(
          frontend_module.name,
          &1,
          Wire3HelperResolution.union_meta_from_lowerer(unions)
        )
      )
      |> Enum.filter(fn defn ->
        function_reachable?(reachable, frontend_module.name, defn.name, ports) or
          String.starts_with?(defn.name, "w3_")
      end)

    {definitions, rewrite_lookup} =
      definition_decls
      |> then(fn defs ->
        local_constructor_lookup =
          unions
          |> Map.values()
          |> Enum.flat_map(fn union_info ->
            union_info
            |> Map.get(:tags, %{})
            |> Enum.to_list()
          end)
          |> Map.new()

        {alias_map, alias_member_map, import_unqualified_map, wildcard_import_modules,
         type_unqualified_map} =
          build_import_resolution(
            Map.get(frontend_module, :import_entries) || [],
            project_module_exports
          )

        local_payload_arity_lookup =
          unions
          |> Map.values()
          |> Enum.flat_map(fn union_info ->
            union_info
            |> Map.get(:payload_specs, %{})
            |> Enum.map(fn {name, spec} -> {name, payload_arity_for_spec(spec)} end)
          end)
          |> Map.new()

        rewrite_lookup = %{
          local: local_constructor_lookup,
          unqualified: globals.constructor_unqualified,
          qualified: globals.constructor_qualified,
          payload_arity_local: local_payload_arity_lookup,
          payload_arity_unqualified: globals.payload_arity_unqualified,
          payload_arity_qualified: globals.payload_arity_qualified,
          current_module: frontend_module.name,
          alias_map: alias_map,
          alias_member_map: alias_member_map,
          import_unqualified_map: import_unqualified_map,
          type_unqualified_map: type_unqualified_map,
          wildcard_import_modules: wildcard_import_modules,
          local_call_names: MapSet.new(Enum.map(defs, & &1.name)),
          record_alias_fields_local: local_record_alias_field_lookup(frontend_module),
          record_alias_fields_unqualified: globals.record_alias_unqualified,
          record_alias_fields_qualified: globals.record_alias_qualified
        }

        {defs, rewrite_lookup}
      end)
      |> then(fn {defs, rewrite_lookup} ->
        definitions =
          defs
          |> Map.new(fn defn ->
            fn_lookup =
              Enum.reduce(defn.args || [], rewrite_lookup, fn arg, acc ->
                put_let_bound_name(acc, arg)
              end)

            expr = rewrite_expr(defn.expr, fn_lookup)
            {defn.name, %{defn | expr: expr}}
          end)

        {definitions, rewrite_lookup}
      end)

    signature_names = signatures |> Enum.map(& &1.name) |> MapSet.new()

    signature_declarations =
      signatures
      |> Enum.filter(&function_reachable?(reachable, frontend_module.name, &1.name, ports))
      |> Enum.map(fn sig ->
        lower_declaration(sig, Map.get(definitions, sig.name), rewrite_lookup)
      end)
      |> Enum.reject(&is_nil/1)

    definition_only_declarations =
      definition_decls
      |> Enum.reject(&MapSet.member?(signature_names, &1.name))
      |> Enum.map(fn defn ->
        lowered = Map.get(definitions, defn.name, defn)
        lower_declaration(lowered, nil, rewrite_lookup)
      end)
      |> Enum.reject(&is_nil/1)

    signature_by_name = Map.new(signature_declarations, &{&1.name, &1})
    definition_only_by_name = Map.new(definition_only_declarations, &{&1.name, &1})

    type_alias_declarations =
      others
      |> Enum.filter(&(&1.kind == :type_alias))
      |> Enum.map(&lower_declaration(&1, nil, rewrite_lookup))
      |> Enum.reject(&is_nil/1)

    ordered_function_names =
      frontend_module.declarations
      |> Enum.filter(&(&1.kind in [:function_signature, :function_definition]))
      |> Enum.map(& &1.name)
      |> Enum.filter(&function_reachable?(reachable, frontend_module.name, &1, ports))
      |> Enum.reduce({[], MapSet.new()}, fn name, {acc, seen} ->
        if MapSet.member?(seen, name) do
          {acc, seen}
        else
          {[name | acc], MapSet.put(seen, name)}
        end
      end)
      |> elem(0)
      |> Enum.reverse()

    # Ports are signature-only (no body) so they never appear in the reachable
    # function walk; always retain their decls for plan/port lowering.
    ordered_function_names =
      (ordered_function_names ++ ports)
      |> Enum.reduce({[], MapSet.new()}, fn name, {acc, seen} ->
        if MapSet.member?(seen, name) do
          {acc, seen}
        else
          {[name | acc], MapSet.put(seen, name)}
        end
      end)
      |> elem(0)
      |> Enum.reverse()

    wire3_extra_names =
      definition_decls
      |> Enum.map(& &1.name)
      |> Enum.reject(&(&1 in ordered_function_names))

    ordered_declarations =
      type_alias_declarations ++
        (ordered_function_names
         |> Enum.map(fn name ->
           Map.get(signature_by_name, name) || Map.get(definition_only_by_name, name)
         end)
         |> Enum.reject(&is_nil/1)) ++
        (wire3_extra_names
         |> Enum.map(&Map.get(definition_only_by_name, &1))
         |> Enum.reject(&is_nil/1))
      |> Enum.map(fn decl ->
        case Map.get(decl, :expr) do
          nil -> decl
          expr -> %{decl | expr: ImportResolution.normalize_expr(expr, rewrite_lookup)}
        end
      end)

    %Module{
      name: frontend_module.name,
      imports: frontend_module.imports,
      unions: unions,
      declarations: ordered_declarations,
      ports: ports,
      port_module: Map.get(frontend_module, :port_module, false)
    }
  end

  @spec function_reachable?(Types.expr() | map(), Types.expr(), String.t(), Types.expr()) :: boolean()

  defp function_reachable?(:all, _mod, _name, _ports), do: true

  defp function_reachable?(%MapSet{} = reachable, mod, name, ports)
       when is_binary(mod) and is_binary(name) and is_list(ports) do
    MapSet.member?(reachable, "#{mod}.#{name}") or name in ports
  end

  defp function_reachable?(%MapSet{} = reachable, mod, name, _ports)
       when is_binary(mod) and is_binary(name) do
    MapSet.member?(reachable, "#{mod}.#{name}")
  end

  # After reachable-only lower + Wire3 synthesis, IR may reference frontend
  # functions that were never walked. Re-lower those modules with an expanded
  # reachable set until referenced frontend callees are present (or give up).
  @spec close_missing_callees(String.t(), Types.expr(), Types.expr(), Types.expr() | String.t(), Types.expr() | map(), keyword()) :: Types.expr()

  defp close_missing_callees(modules, _project, _globals, _exports, :all, _opts), do: modules

  defp close_missing_callees(
         modules,
         project,
         globals,
         project_module_exports,
         %MapSet{} = reachable,
         opts
       )
       when is_list(modules) do
    frontend_by_name = Map.new(project.modules, &{&1.name, &1})
    frontend_keys = frontend_function_keys(project.modules)

    do_close_missing_callees(
      modules,
      frontend_by_name,
      frontend_keys,
      globals,
      project_module_exports,
      reachable,
      opts,
      0
    )
  end

  @spec do_close_missing_callees(String.t(), String.t(), Types.expr(), Types.expr(), String.t(), Types.expr(), keyword(), Types.expr()) :: Types.expr()

  defp do_close_missing_callees(
         modules,
         _frontend_by_name,
         _frontend_keys,
         _globals,
         _project_module_exports,
         _reachable,
         opts,
         iter
       )
       when iter >= 8 do
    progress_log(opts, "reachable callee closure stopped after #{iter} passes")
    modules
  end

  defp do_close_missing_callees(
         modules,
         frontend_by_name,
         frontend_keys,
         globals,
         project_module_exports,
         reachable,
         opts,
         iter
       ) do
    ir = %IR{modules: modules, diagnostics: []}
    present = DeadCode.present_keys(ir)

    missing =
      ir
      |> DeadCode.referenced_keys()
      |> MapSet.intersection(frontend_keys)
      |> MapSet.difference(present)

    case MapSet.size(missing) do
      0 ->
        modules

      n ->
        progress_log(opts, "pulling #{n} referenced callees missing from IR (pass #{iter + 1})…")
        reachable2 = MapSet.union(reachable, missing)

        affected =
          missing
          |> MapSet.to_list()
          |> Enum.map(&module_of_function_key/1)
          |> MapSet.new()

        modules2 =
          Enum.map(modules, fn mod ->
            if MapSet.member?(affected, mod.name) do
              case Map.get(frontend_by_name, mod.name) do
                nil ->
                  mod

                frontend ->
                  fresh =
                    lower_frontend_module(
                      frontend,
                      globals,
                      project_module_exports,
                      reachable2
                    )

                  merge_module_declarations(mod, fresh)
              end
            else
              mod
            end
          end)

        modules3 =
          Wire3HelperResolution.augment_cross_module_wire3(
            modules2,
            Wire3HelperResolution.union_meta_from_lowerer(unions_from_modules(modules2))
          )

        do_close_missing_callees(
          modules3,
          frontend_by_name,
          frontend_keys,
          globals,
          project_module_exports,
          reachable2,
          opts,
          iter + 1
        )
    end
  end

  @spec frontend_function_keys(list()) :: Types.expr()

  defp frontend_function_keys(modules) when is_list(modules) do
    modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind in [:function_definition, :function_signature]))
      |> Enum.map(&"#{mod.name}.#{&1.name}")
    end)
    |> MapSet.new()
  end

  @spec module_of_function_key(String.t()) :: Types.expr()

  defp module_of_function_key(key) when is_binary(key) do
    case String.split(key, ".") do
      parts when length(parts) >= 2 ->
        parts |> Enum.drop(-1) |> Enum.join(".")

      _ ->
        key
    end
  end

  @spec merge_module_declarations(map(), map()) :: Types.expr()

  defp merge_module_declarations(%Module{} = existing, %Module{} = fresh) do
    by_name = Map.new(existing.declarations, &{&1.name, &1})

    merged_decls =
      Enum.reduce(fresh.declarations, existing.declarations, fn decl, acc ->
        if Map.has_key?(by_name, decl.name) do
          acc
        else
          acc ++ [decl]
        end
      end)

    ports =
      (Map.get(existing, :ports, []) ++ Map.get(fresh, :ports, []))
      |> Enum.uniq()

    %{existing | declarations: merged_decls, ports: ports}
  end

  @spec unions_from_modules(list()) :: Types.expr()

  defp unions_from_modules(modules) when is_list(modules) do
    Enum.reduce(modules, %{}, fn mod, acc ->
      Map.merge(acc, Map.get(mod, :unions) || %{})
    end)
  end

  @spec lower_declaration(AstDeclaration.t(), AstDeclaration.t() | nil, Lookup.t()) ::
          Declaration.t() | nil
  defp lower_declaration(decl, definition, lookup)

  defp lower_declaration(
         %{kind: :function_signature, name: name, type: type} = sig,
         definition,
         lookup
       ) do
    type = canonicalize_type_annotation(type, lookup)

    span =
      case definition do
        %{span: definition_span} when is_map(definition_span) -> definition_span
        _ -> nil
      end

    signature_span =
      case Map.get(sig, :span) do
        span_map when is_map(span_map) -> span_map
        _ -> nil
      end

    %Declaration{
      kind: :function,
      name: name,
      type: type,
      args: definition && definition.args,
      expr: definition && definition.expr,
      span: span || signature_span,
      ownership: ownership_for_type(type)
    }
    |> ElmEx.IR.FnArgDesugar.desugar_function()
  end

  defp lower_declaration(
         %{kind: :function_definition, name: name} = definition,
         _signature,
         _lookup
       ) do
    %Declaration{
      kind: :function,
      name: name,
      type: nil,
      args: Map.get(definition, :args),
      expr: Map.get(definition, :expr),
      span: Map.get(definition, :span),
      ownership: ownership_for_type(nil)
    }
    |> ElmEx.IR.FnArgDesugar.desugar_function()
  end

  defp lower_declaration(%{kind: :type_alias, name: name} = decl, _definition, lookup) do
    fields = Map.get(decl, :fields) || []

    field_types =
      decl
      |> Map.get(:field_types)
      |> canonicalize_record_field_types(lookup)

    %Declaration{
      kind: :type_alias,
      name: name,
      expr: type_alias_expr(fields, field_types),
      span: Map.get(decl, :span),
      ownership: [:retain_on_assign, :release_on_scope_exit]
    }
  end

  defp lower_declaration(%{kind: :union, name: name} = decl, _definition, _lookup) do
    %Declaration{
      kind: :union,
      name: name,
      span: Map.get(decl, :span),
      ownership: [:retain_on_constructor, :release_on_match_exit]
    }
  end

  @spec type_alias_expr(list() | Types.expr(), Types.expr()) :: Types.expr()

  defp type_alias_expr(fields, field_types) when is_list(fields) and fields != [] do
    %{
      op: :record_alias,
      fields: Enum.map(fields, &to_string/1),
      field_types: normalize_record_alias_field_types(field_types)
    }
  end

  defp type_alias_expr(_fields, _field_types), do: nil

  @spec normalize_record_alias_field_types(map()) :: map()

  defp normalize_record_alias_field_types(field_types) when is_map(field_types) do
    Map.new(field_types, fn {field, type} -> {to_string(field), to_string(type)} end)
  end

  @spec ownership_for_type(String.t() | nil) :: [atom()]
  defp ownership_for_type(type) do
    cond do
      not is_binary(type) ->
        [:borrow_arg, :borrow_result]

      # Function types must be classified from the *result* side. Matching
      # "String"/"List" on the full signature incorrectly marked `Model -> String`
      # (and similar) as `:retain_arg`, so callers released borrowed params.
      String.contains?(type, "->") ->
        [:borrow_arg, ownership_result_for_type(function_result_type(type))]

      String.contains?(type, "List") ->
        [:borrow_arg, :retain_result]

      String.contains?(type, "String") ->
        [:retain_arg, :retain_result]

      true ->
        [:borrow_arg, :borrow_result]
    end
  end

  @spec function_result_type(String.t()) :: Types.expr()

  defp function_result_type(type) when is_binary(type) do
    type
    |> String.split("->")
    |> List.last()
    |> String.trim()
  end

  @spec ownership_result_for_type(String.t()) :: Types.expr()

  defp ownership_result_for_type(result) when is_binary(result) do
    cond do
      String.contains?(result, "List") -> :retain_result
      String.contains?(result, "String") -> :retain_result
      true -> :borrow_result
    end
  end

  @spec rewrite_expr(Expr.t(), Lookup.t()) :: Expr.t()
  defp rewrite_expr(nil, _lookup), do: nil

  defp rewrite_expr(%{op: :constructor_call, target: target, args: args} = expr, lookup) do
    rewritten_args = Enum.map(args || [], &rewrite_expr(&1, lookup))
    resolved_target = resolve_alias(target, lookup)

    case rewrite_constructor_value(resolved_target, rewritten_args, lookup) do
      nil ->
        %{expr | target: resolved_target, args: rewritten_args}

      rewritten ->
        rewritten
    end
  end

  defp rewrite_expr(%{op: :qualified_call, target: target, args: args} = expr, lookup) do
    cond do
      target == "|." ->
        rewrite_expr(
          %{op: :qualified_call, target: "Parser.Advanced.ignorer", args: args || []},
          lookup
        )

      target == "|=" ->
        rewrite_expr(
          %{op: :qualified_call, target: "Parser.Advanced.keeper", args: args || []},
          lookup
        )

      true ->
        resolved_target =
          target
          |> resolve_alias(lookup)
          |> redirect_diagram_init_peer()
        rewritten_args = Enum.map(args || [], &rewrite_expr(&1, lookup))

        case rewrite_constructor_value(resolved_target, rewritten_args, lookup) do
          nil ->
            %{expr | target: resolved_target, args: rewritten_args}

          rewritten ->
            rewritten
        end
    end
  end

  defp rewrite_expr(%{op: :qualified_call1, target: target} = expr, lookup) do
    resolved_target = resolve_alias(target, lookup)
    %{expr | target: resolved_target}
  end

  defp rewrite_expr(%{op: :qualified_ref, target: target} = expr, lookup) when is_binary(target) do
    resolved_target = resolve_alias(target, lookup)

    case resolved_target do
      "Tuple.first" ->
        arg = "__tuple_ref_arg__"
        %{op: :lambda, args: [arg], body: %{op: :tuple_first_expr, arg: %{op: :var, name: arg}}}

      "Tuple.second" ->
        arg = "__tuple_ref_arg__"
        %{op: :lambda, args: [arg], body: %{op: :tuple_second_expr, arg: %{op: :var, name: arg}}}

      _ ->
        %{expr | target: resolved_target}
    end
  end

  defp rewrite_expr(%{op: :pipe_chain, steps: steps, base: base} = expr, lookup) do
    %{
      expr
      | steps: Enum.map(steps || [], &rewrite_expr(&1, lookup)),
        base: rewrite_expr(base, lookup)
    }
  end

  defp rewrite_expr(%{op: :apply_left} = expr, lookup) do
    expr
    |> ElmEx.Frontend.ApplyLeft.expand()
    |> rewrite_expr(lookup)
  end

  defp rewrite_expr(%{op: op} = expr, lookup) when op in [:bool_and, :bool_or] do
    expr
    |> ElmEx.Frontend.BoolOps.expand()
    |> rewrite_expr(lookup)
  end

  defp rewrite_expr(%{op: :call, name: name, args: args}, lookup) when is_binary(name) do
    rewritten_args = Enum.map(args || [], &rewrite_expr(&1, lookup))
    let_bound = Map.get(lookup, :let_bound_names, MapSet.new())

    cond do
      name == "|=" ->
        rewrite_expr(
          %{op: :qualified_call, target: "Parser.Advanced.keeper", args: rewritten_args},
          lookup
        )

      name == "|." ->
        rewrite_expr(
          %{op: :qualified_call, target: "Parser.Advanced.ignorer", args: rewritten_args},
          lookup
        )

      name == "<|" ->
        rewrite_expr(
          %{
            op: :call,
            name: "__apply__",
            args: rewritten_args
          },
          lookup
        )

      MapSet.member?(let_bound, name) and rewritten_args != [] ->
        # Pattern/let-bound function values must apply as closures, not as
        # `Module.name` callees (e.g. `run (Parser parse) src` → `parse state`).
        Enum.reduce(rewritten_args, %{op: :var, name: name}, fn arg, acc ->
          %{op: :call, name: "__apply__", args: [acc, arg]}
        end)

      true ->
        resolved_name = resolve_alias(name, lookup)

        if String.contains?(resolved_name, ".") do
          %{op: :qualified_call, target: resolved_name, args: rewritten_args}
        else
          %{op: :call, name: resolved_name, args: rewritten_args}
        end
    end
  end

  defp rewrite_expr(%{op: :call, args: args} = expr, lookup) do
    %{expr | args: Enum.map(args || [], &rewrite_expr(&1, lookup))}
  end

  alias ElmEx.Frontend.LetBindings

  defp rewrite_expr(%{op: :let_bindings} = expr, lookup) do
    expr
    |> LetBindings.expand()
    |> rewrite_expr(lookup)
  end

  defp rewrite_expr(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = expr, lookup) do
    # Let-bound names (including local functions) must stay as unqualified :call ops so
    # codegen can resolve them from the compile env. Adding them to local_call_names would
    # rewrite `label x y z` into `Main.label`, which is wrong for let-bound lambdas.
    # Value expressions are compiled in the outer scope; only the body sees the binding.
    inner_lookup = put_let_bound_name(lookup, name)

    %{
      expr
      | value_expr: rewrite_expr(value_expr, lookup),
        in_expr: rewrite_expr(in_expr, inner_lookup)
    }
  end

  defp rewrite_expr(%{op: :let_in, value_expr: value_expr, in_expr: in_expr} = expr, lookup) do
    %{
      expr
      | value_expr: rewrite_expr(value_expr, lookup),
        in_expr: rewrite_expr(in_expr, lookup)
    }
  end

  defp rewrite_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr} = expr,
         lookup
       ) do
    %{
      expr
      | cond: rewrite_expr(cond_expr, lookup),
        then_expr: rewrite_expr(then_expr, lookup),
        else_expr: rewrite_expr(else_expr, lookup)
    }
  end

  defp rewrite_expr(%{op: :compare, left: left, right: right} = expr, lookup) do
    %{expr | left: rewrite_expr(left, lookup), right: rewrite_expr(right, lookup)}
  end

  defp rewrite_expr(%{op: :tuple2, left: left, right: right} = expr, lookup) do
    %{expr | left: rewrite_expr(left, lookup), right: rewrite_expr(right, lookup)}
  end

  defp rewrite_expr(%{op: :tuple_first_expr, arg: arg} = expr, lookup) do
    %{expr | arg: rewrite_expr(arg, lookup)}
  end

  defp rewrite_expr(%{op: :tuple_second_expr, arg: arg} = expr, lookup) do
    %{expr | arg: rewrite_expr(arg, lookup)}
  end

  defp rewrite_expr(%{op: :string_length_expr, arg: arg} = expr, lookup) do
    %{expr | arg: rewrite_expr(arg, lookup)}
  end

  defp rewrite_expr(%{op: :char_from_code_expr, arg: arg} = expr, lookup) do
    %{expr | arg: rewrite_expr(arg, lookup)}
  end

  defp rewrite_expr(%{op: :record_literal, fields: fields}, lookup) do
    rewritten_fields =
      fields
      |> Enum.map(fn field -> %{field | expr: rewrite_expr(field.expr, lookup)} end)

    %{op: :record_literal, fields: rewritten_fields}
  end

  defp rewrite_expr(%{op: :record_update, base: base, fields: fields}, lookup) do
    rewritten_fields =
      fields
      |> Enum.map(fn field -> %{field | expr: rewrite_expr(field.expr, lookup)} end)

    %{op: :record_update, base: rewrite_expr(base, lookup), fields: rewritten_fields}
  end

  defp rewrite_expr(%{op: :field_access, arg: arg, field: field}, lookup) do
    rewritten_arg = rewrite_expr(arg, lookup)

    case ImportResolution.resolve_imported_member(rewritten_arg, field, lookup) do
      {:ok, qualified_target} ->
        %{op: :qualified_call, target: qualified_target, args: []}

      :error ->
        case {field, rewritten_arg} do
          {"value", %{op: :tuple2} = tuple_expr} -> %{op: :tuple_first, arg: tuple_expr}
          _ -> %{op: :field_access, arg: rewritten_arg, field: field}
        end
    end
  end

  defp rewrite_expr(%{op: :list_literal, items: items} = expr, lookup) do
    %{expr | items: Enum.map(items || [], &rewrite_expr(&1, lookup))}
  end

  defp rewrite_expr(%{op: :case, branches: branches} = expr, lookup) do
    rewritten =
      Enum.map(branches, fn branch ->
        branch_lookup = extend_lookup_with_pattern(branch.pattern, lookup)

        %{
          branch
          | pattern: rewrite_pattern(branch.pattern, lookup),
            expr: rewrite_expr(branch.expr, branch_lookup)
        }
      end)

    %{expr | subject: rewrite_case_subject(expr.subject, lookup), branches: rewritten}
  end

  defp rewrite_expr(%{op: :field_call, arg: arg, args: args} = expr, lookup) do
    %{
      expr
      | arg: rewrite_expr(arg, lookup),
        args: Enum.map(args || [], &rewrite_expr(&1, lookup))
    }
  end

  defp rewrite_expr(%{op: :lambda, args: args, body: body} = expr, lookup) do
    inner_lookup =
      Enum.reduce(args || [], lookup, fn arg, acc -> put_let_bound_name(acc, arg) end)

    %{expr | body: rewrite_expr(body, inner_lookup)}
  end

  defp rewrite_expr(%{op: :lambda, body: body} = expr, lookup) do
    %{expr | body: rewrite_expr(body, lookup)}
  end

  defp rewrite_expr(%{op: :compose_left, f: f, g: g}, lookup) when is_binary(f) and is_binary(g) do
    # (f << g) = \x -> f(g(x))
    arg_name = "__compose_arg__"
    inner_call = %{op: :call, name: g, args: [%{op: :var, name: arg_name}]}
    outer_call = %{op: :call, name: f, args: [inner_call]}
    rewrite_expr(%{op: :lambda, args: [arg_name], body: outer_call}, lookup)
  end

  defp rewrite_expr(%{op: :compose_left, f: f, g: g}, lookup) do
    arg_name = "__compose_arg__"
    inner = apply_expr_to_arg(rewrite_expr(g, lookup), arg_name)
    body = apply_expr_to_operand(rewrite_expr(f, lookup), inner)
    rewrite_expr(%{op: :lambda, args: [arg_name], body: body}, lookup)
  end

  defp rewrite_expr(%{op: :compose_right, f: f, g: g}, lookup) when is_binary(f) and is_binary(g) do
    # (f >> g) = \x -> g(f(x))
    arg_name = "__compose_arg__"
    inner_call = %{op: :call, name: f, args: [%{op: :var, name: arg_name}]}
    outer_call = %{op: :call, name: g, args: [inner_call]}
    rewrite_expr(%{op: :lambda, args: [arg_name], body: outer_call}, lookup)
  end

  defp rewrite_expr(%{op: :compose_right, f: f, g: g}, lookup) do
    arg_name = "__compose_arg__"
    inner = apply_expr_to_arg(rewrite_expr(f, lookup), arg_name)
    body = apply_expr_to_operand(rewrite_expr(g, lookup), inner)
    rewrite_expr(%{op: :lambda, args: [arg_name], body: body}, lookup)
  end

  defp rewrite_expr(%{op: :var, name: name} = expr, lookup) when is_binary(name) do
    local_call_names = Map.get(lookup, :local_call_names, MapSet.new())
    let_bound = Map.get(lookup, :let_bound_names, MapSet.new())

    cond do
      name == "<|" ->
        # Basics.(<|) / apL as a first-class value: \f x -> f x
        rewrite_expr(
          %{
            op: :lambda,
            args: ["__apL_f", "__apL_x"],
            body: %{
              op: :call,
              name: "__apply__",
              args: [%{op: :var, name: "__apL_f"}, %{op: :var, name: "__apL_x"}]
            }
          },
          lookup
        )

      name == "|>" ->
        rewrite_expr(
          %{
            op: :lambda,
            args: ["__apR_x", "__apR_f"],
            body: %{
              op: :call,
              name: "__apply__",
              args: [%{op: :var, name: "__apR_f"}, %{op: :var, name: "__apR_x"}]
            }
          },
          lookup
        )

      MapSet.member?(local_call_names, name) ->
        expr

      MapSet.member?(let_bound, name) ->
        expr

      imported_value_reference?(name, lookup) ->
        %{op: :qualified_call, target: resolve_alias(name, lookup), args: []}

      true ->
        resolved = resolve_alias(name, lookup)

        if resolved != name and String.contains?(resolved, ".") do
          %{op: :qualified_ref, target: resolved}
        else
          expr
        end
    end
  end

  defp rewrite_expr(%{op: :var, target: target}, lookup) when is_binary(target) do
    rewrite_expr(%{op: :var, name: target}, lookup)
  end

  defp rewrite_expr(expr, _lookup), do: expr

  @spec imported_value_reference?(String.t(), Types.expr()) :: boolean()

  defp imported_value_reference?(name, lookup) when is_binary(name) do
    let_bound = Map.get(lookup, :let_bound_names, MapSet.new())

    not MapSet.member?(let_bound, name) and
      not constructor_reference?(name, lookup) and
      case resolve_alias(name, lookup) do
        ^name -> false
        resolved when is_binary(resolved) -> String.contains?(resolved, ".")
      end
  end

  @spec put_let_bound_name(Types.expr(), String.t()) :: Types.expr()

  defp put_let_bound_name(lookup, name) when is_binary(name) do
    bound = Map.get(lookup, :let_bound_names, MapSet.new())
    Map.put(lookup, :let_bound_names, MapSet.put(bound, name))
  end

  defp put_let_bound_name(lookup, _name), do: lookup

  @spec extend_lookup_with_pattern(Types.pattern(), Types.expr()) :: Types.expr()

  defp extend_lookup_with_pattern(pattern, lookup) do
    Enum.reduce(pattern_bound_names(pattern), lookup, fn name, acc ->
      put_let_bound_name(acc, name)
    end)
  end

  @spec pattern_bound_names(map() | Types.pattern()) :: Types.expr()

  defp pattern_bound_names(%{kind: :var, name: name}) when name not in ["_", ""], do: [name]
  defp pattern_bound_names(%{kind: :wildcard}), do: []

  defp pattern_bound_names(%{kind: :tuple, elements: elements}) when is_list(elements),
    do: Enum.flat_map(elements, &pattern_bound_names/1)

  defp pattern_bound_names(%{kind: :list, elements: elements}) when is_list(elements),
    do: Enum.flat_map(elements, &pattern_bound_names/1)

  defp pattern_bound_names(%{kind: :cons, head: head, tail: tail}),
    do: pattern_bound_names(head) ++ pattern_bound_names(tail)

  defp pattern_bound_names(%{kind: :alias, bind: bind, pattern: inner}) when is_binary(bind),
    do: [bind | pattern_bound_names(inner)]

  defp pattern_bound_names(%{kind: :alias, pattern: inner}), do: pattern_bound_names(inner)

  defp pattern_bound_names(%{kind: :constructor, bind: bind, arg_pattern: arg})
       when is_binary(bind),
       do: [bind | pattern_bound_names(arg)]

  defp pattern_bound_names(%{kind: :constructor, arg_pattern: arg}),
    do: pattern_bound_names(arg)

  defp pattern_bound_names(_pattern), do: []

  @spec constructor_reference?(String.t(), Types.expr()) :: boolean()

  defp constructor_reference?(name, lookup) when is_binary(name) do
    Map.has_key?(Map.get(lookup, :local, %{}), name) or
      Map.has_key?(Map.get(lookup, :unqualified, %{}), name)
  end

  @spec apply_expr_to_arg(map() | Types.expr(), String.t()) :: Types.expr()

  defp apply_expr_to_arg(%{op: :qualified_call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  # Never append into `__apply__` — nest binary applies (same as pipe_chain).
  # Appending turns `f >> g >> h` / expand chains into ternary `__apply__`, which
  # plan Call only lowers as binary (StencilTest.testSeparate).
  defp apply_expr_to_arg(%{op: :call, name: "__apply__"} = expr, arg_name) do
    %{op: :call, name: "__apply__", args: [expr, %{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :constructor_call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :var, name: name}, arg_name) do
    %{op: :call, name: name, args: [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :qualified_ref, target: target}, arg_name) do
    %{op: :qualified_call, target: target, args: [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :constructor_ref, target: target}, arg_name) do
    %{op: :constructor_call, target: target, args: [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(expr, arg_name) do
    %{op: :call, name: "__apply__", args: [expr, %{op: :var, name: arg_name}]}
  end

  @spec apply_expr_to_operand(map() | Types.expr(), Types.expr()) :: Types.expr()

  defp apply_expr_to_operand(%{op: :qualified_call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  defp apply_expr_to_operand(%{op: :call, name: "__apply__"} = expr, operand) do
    %{op: :call, name: "__apply__", args: [expr, operand]}
  end

  defp apply_expr_to_operand(%{op: :call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  defp apply_expr_to_operand(%{op: :constructor_call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  defp apply_expr_to_operand(%{op: :var, name: name}, operand) when is_binary(name) do
    %{op: :call, name: name, args: [operand]}
  end

  defp apply_expr_to_operand(%{op: :qualified_ref, target: target}, operand) do
    %{op: :qualified_call, target: target, args: [operand]}
  end

  defp apply_expr_to_operand(%{op: :constructor_ref, target: target}, operand) do
    %{op: :constructor_call, target: target, args: [operand]}
  end

  defp apply_expr_to_operand(expr, operand) do
    %{op: :call, name: "__apply__", args: [expr, operand]}
  end

  @spec rewrite_case_subject(Expr.t() | String.t(), Lookup.t()) :: Expr.t() | String.t()
  defp rewrite_case_subject(subject, lookup) when is_map(subject),
    do: rewrite_expr(subject, lookup)

  defp rewrite_case_subject(subject, _lookup), do: subject

  @spec canonicalize_record_field_types(ModuleExports.record_field_types() | nil, Lookup.t()) ::
          ModuleExports.record_field_types()
  defp canonicalize_record_field_types(field_types, lookup) when is_map(field_types) do
    Map.new(field_types, fn {field, type} ->
      {field, canonicalize_type_annotation(type, lookup)}
    end)
  end

  defp canonicalize_record_field_types(_field_types, _lookup), do: %{}

  @spec canonicalize_type_annotation(String.t() | nil, Lookup.t()) :: String.t() | nil
  defp canonicalize_type_annotation(type, lookup) when is_binary(type) do
    alias_map = Map.get(lookup, :alias_map, %{})
    type_unqualified_map = Map.get(lookup, :type_unqualified_map, %{})

    type
    |> canonicalize_qualified_type_aliases(alias_map)
    |> canonicalize_unqualified_type_names(type_unqualified_map)
  end

  defp canonicalize_type_annotation(type, _lookup), do: type

  @spec canonicalize_qualified_type_aliases(Types.expr(), map()) :: Types.expr()

  defp canonicalize_qualified_type_aliases(type, alias_map) when is_map(alias_map) do
    alias_map
    |> Enum.sort_by(fn {alias_name, _module_name} -> -String.length(alias_name) end)
    |> Enum.reduce(type, fn {alias_name, module_name}, acc ->
      replace_type_alias_prefix(acc, alias_name, module_name)
    end)
  end

  defp canonicalize_qualified_type_aliases(type, _alias_map), do: type

  @spec canonicalize_unqualified_type_names(Types.expr(), map()) :: Types.expr()

  defp canonicalize_unqualified_type_names(type, type_unqualified_map)
       when is_map(type_unqualified_map) do
    type_unqualified_map
    |> Enum.filter(fn
      {name, module_name} ->
        type_name?(name) and is_binary(module_name) and
          not builtin_type_name?(name)
    end)
    |> Enum.sort_by(fn {name, _module_name} -> -String.length(name) end)
    |> Enum.reduce(type, fn {name, module_name}, acc ->
      replace_unqualified_type_name(acc, name, module_name)
    end)
  end

  defp canonicalize_unqualified_type_names(type, _type_unqualified_map), do: type

  @spec replace_type_alias_prefix(Types.expr(), String.t(), String.t()) :: Types.expr()

  defp replace_type_alias_prefix(type, alias_name, module_name)
       when is_binary(type) and is_binary(alias_name) and is_binary(module_name) do
    pattern = ~r/(^|[^A-Za-z0-9_'.])#{Regex.escape(alias_name)}\./

    Regex.replace(pattern, type, fn _match, prefix ->
      "#{prefix}#{module_name}."
    end)
  end

  @spec replace_unqualified_type_name(Types.expr(), String.t(), String.t()) :: Types.expr()

  defp replace_unqualified_type_name(type, name, module_name)
       when is_binary(type) and is_binary(name) and is_binary(module_name) do
    pattern = ~r/(^|[^A-Za-z0-9_'.])#{Regex.escape(name)}($|[^A-Za-z0-9_'.])/

    Regex.replace(pattern, type, fn _match, prefix, suffix ->
      "#{prefix}#{module_name}.#{name}#{suffix}"
    end)
  end


  @spec type_name?(term()) :: boolean()

  defp type_name?(<<first::utf8, _rest::binary>>) do
    first >= ?A and first <= ?Z
  end

  defp type_name?(_name), do: false

  @spec builtin_type_name?(String.t()) :: boolean()

  defp builtin_type_name?(name)
       when name in [
              "Bool",
              "Char",
              "Cmd",
              "Float",
              "Int",
              "List",
              "Maybe",
              "Never",
              "Result",
              "String"
            ],
       do: true

  defp builtin_type_name?(_name), do: false

  @spec resolve_alias(String.t(), Lookup.t()) :: String.t()
  defp resolve_alias(target, lookup) when is_binary(target),
    do: ImportResolution.resolve(target, lookup)

  defp resolve_alias(target, _lookup), do: target

  @spec redirect_diagram_init_peer(String.t()) :: Types.expr()

  defp redirect_diagram_init_peer(target) when is_binary(target) do
    Map.get(@internal_diagram_peer_redirects, target, target)
  end

  @spec build_import_resolution(
          [ImportEntry.wire_map()],
          ModuleExports.project_exports()
        ) :: Lookup.import_resolution_bundle()
  defp build_import_resolution(import_entries, project_module_exports)
       when is_list(import_entries) and is_map(project_module_exports) do
    entries = ensure_default_import_entries(import_entries)

    {alias_map, alias_modules, unqualified_acc, wildcard_acc, type_acc} =
      Enum.reduce(entries, {%{}, %{}, %{}, [], %{}}, fn entry,
                                                       {alias_acc, alias_modules_acc, unqualified_acc,
                                                        wildcard_acc, type_acc} ->
        module_name = Map.get(entry, "module")
        as_name = Map.get(entry, "as")
        exposing = Map.get(entry, "exposing")

        if is_binary(module_name) and module_name != "" do
          segments = String.split(module_name, ".", trim: true)
          compact_name = Enum.join(segments, "")

          {alias_acc, alias_modules_acc} =
            {alias_acc, alias_modules_acc}
            |> put_alias_binding(as_name, module_name)
            |> put_alias_binding(compact_name, module_name)

          {unqualified_acc, wildcard_acc, type_acc} =
            case exposing do
              ".." ->
                {
                  register_wildcard_exports(unqualified_acc, module_name, project_module_exports),
                  add_unique_string(wildcard_acc, module_name),
                  register_wildcard_type_exports(type_acc, module_name, project_module_exports)
                }

              names when is_list(names) ->
                expanded_names =
                  expand_import_exposing_names(names, module_name, project_module_exports)

                exposed_types =
                  expand_import_exposing_type_names(names, module_name, project_module_exports)

                mapped =
                  expanded_names
                  |> Enum.filter(&is_binary/1)
                  |> Enum.reduce(unqualified_acc, fn name, acc ->
                    put_unqualified_name(acc, name, module_name)
                  end)

                type_mapped =
                  exposed_types
                  |> Enum.filter(&is_binary/1)
                  |> Enum.reduce(type_acc, fn name, acc ->
                    put_unqualified_name(acc, name, module_name)
                  end)

                {mapped, wildcard_acc, type_mapped}

              _ ->
                {unqualified_acc, wildcard_acc, type_acc}
            end

          {alias_acc, alias_modules_acc, unqualified_acc, wildcard_acc, type_acc}
        else
          {alias_acc, alias_modules_acc, unqualified_acc, wildcard_acc, type_acc}
        end
      end)

    alias_member_map = build_alias_member_map(alias_modules, project_module_exports)
    {alias_map, alias_member_map, unqualified_acc, wildcard_acc, type_acc}
  end

  defp build_import_resolution(_import_entries, _project_module_exports),
    do: {%{}, %{}, %{}, [], %{}}

  @spec put_alias_binding(term(), String.t(), String.t()) :: Types.expr()

  defp put_alias_binding({alias_acc, alias_modules_acc}, alias_name, module_name)
       when is_binary(alias_name) and alias_name != "" and is_binary(module_name) do
    {
      # Last import wins for bare alias fallback (types / unknown members).
      Map.put(alias_acc, alias_name, module_name),
      Map.update(alias_modules_acc, alias_name, [module_name], fn modules ->
        if module_name in modules, do: modules, else: modules ++ [module_name]
      end)
    }
  end

  defp put_alias_binding(acc, _alias_name, _module_name), do: acc

  @spec build_alias_member_map(String.t() | term(), String.t() | term()) :: Types.expr()

  defp build_alias_member_map(alias_modules, project_module_exports)
       when is_map(alias_modules) and is_map(project_module_exports) do
    Enum.reduce(alias_modules, %{}, fn {alias_name, modules}, acc ->
      members =
        modules
        # Later imports shadow earlier ones for the same exported name.
        |> Enum.reverse()
        |> Enum.reduce(%{}, fn module_name, member_acc ->
          export = Map.get(project_module_exports, module_name, %{})
          names = Map.get(export, :names, []) || []

          Enum.reduce(names, member_acc, fn name, inner ->
            if is_binary(name), do: Map.put_new(inner, name, module_name), else: inner
          end)
        end)

      if members == %{}, do: acc, else: Map.put(acc, alias_name, members)
    end)
  end

  defp build_alias_member_map(_, _), do: %{}

  @spec build_project_module_exports([FrontendModule.t()]) :: ModuleExports.project_exports()
  defp build_project_module_exports(frontend_modules) when is_list(frontend_modules) do
    frontend_modules
    |> Enum.reduce(%{}, fn frontend_module, acc ->
      module_name = Map.get(frontend_module, :name)

      if is_binary(module_name) and module_name != "" do
        Map.put(acc, module_name, collect_module_exports(frontend_module))
      else
        acc
      end
    end)
  end

  defp build_project_module_exports(_), do: %{}

  @spec collect_module_exports(FrontendModule.t()) :: ModuleExports.module_export()
  defp collect_module_exports(frontend_module) when is_map(frontend_module) do
    exposing = Map.get(frontend_module, :module_exposing)
    union_constructors = module_union_constructors(frontend_module)
    type_names = module_type_names(frontend_module)

    names =
      cond do
        exposing == ".." ->
          value_names =
            frontend_module
            |> Map.get(:declarations, [])
            |> Enum.flat_map(fn decl ->
              kind = Map.get(decl, :kind)
              name = Map.get(decl, :name)

              case {kind, name} do
                {k, n} when k in [:function_signature, :function_definition] and is_binary(n) ->
                  [n]

                _ ->
                  []
              end
            end)

          value_names ++ union_export_names(union_constructors)

        is_list(exposing) ->
          expand_exposing_names(exposing, union_constructors)

        true ->
          []
      end

    exposed_types =
      cond do
        exposing == ".." -> type_names
        is_list(exposing) -> exposed_type_names(exposing, type_names)
        true -> []
      end

    %{
      names: Enum.uniq(names),
      types: Enum.uniq(exposed_types),
      union_constructors: union_constructors
    }
  end

  @spec module_type_names(map()) :: Types.expr()

  defp module_type_names(frontend_module) when is_map(frontend_module) do
    frontend_module
    |> Map.get(:declarations, [])
    |> Enum.flat_map(fn decl ->
      case {Map.get(decl, :kind), Map.get(decl, :name)} do
        {kind, name} when kind in [:type_alias, :union] and is_binary(name) -> [name]
        _ -> []
      end
    end)
  end

  @spec exposed_type_names(list() | Types.expr(), list() | String.t()) :: Types.expr()

  defp exposed_type_names(exposing, type_names) when is_list(exposing) and is_list(type_names) do
    exposing
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil -> [name]
        type_name -> [type_name]
      end
    end)
    |> Enum.filter(&(&1 in type_names))
  end

  defp exposed_type_names(_exposing, _type_names), do: []

  @spec module_union_constructors(FrontendModule.t()) :: ModuleExports.union_constructors()
  defp module_union_constructors(frontend_module) when is_map(frontend_module) do
    frontend_module
    |> Map.get(:declarations, [])
    |> Enum.reduce(%{}, fn decl, acc ->
      if Map.get(decl, :kind) == :union and is_binary(Map.get(decl, :name)) do
        ctors =
          decl
          |> Map.get(:constructors, [])
          |> Enum.map(&Map.get(&1, :name))
          |> Enum.filter(&is_binary/1)

        Map.put(acc, Map.get(decl, :name), ctors)
      else
        acc
      end
    end)
  end

  @spec expand_exposing_names([String.t()], ModuleExports.union_constructors()) :: [String.t()]
  defp expand_exposing_names(names, union_constructors) do
    names
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil ->
          [name]

        type_name ->
          [type_name | Map.get(union_constructors, type_name, [])]
      end
    end)
  end

  @spec union_export_names(ModuleExports.union_constructors()) :: [String.t()]
  defp union_export_names(union_constructors) when is_map(union_constructors) do
    union_constructors
    |> Enum.flat_map(fn {type_name, constructors} -> [type_name | constructors] end)
  end

  @spec type_wildcard_name(String.t()) :: String.t() | nil
  defp type_wildcard_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      String.ends_with?(trimmed, "(..)") ->
        trimmed |> String.replace_suffix("(..)", "") |> String.trim()

      String.ends_with?(trimmed, "( .. )") ->
        trimmed |> String.replace_suffix("( .. )", "") |> String.trim()

      true ->
        nil
    end
  end

  defp type_wildcard_name(_), do: nil

  @spec expand_import_exposing_names(
          [String.t()],
          String.t(),
          ModuleExports.project_exports()
        ) :: [String.t()]
  defp expand_import_exposing_names(names, module_name, project_module_exports)
       when is_list(names) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{names: [], union_constructors: %{}})

    union_constructors =
      module_exports
      |> Map.get(:union_constructors, %{})
      |> Map.merge(Map.get(@known_dependency_union_constructors, module_name, %{}))

    names
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil -> [name]
        type_name -> [type_name | Map.get(union_constructors, type_name, [])]
      end
    end)
  end

  defp expand_import_exposing_names(_names, _module_name, _project_module_exports), do: []

  @spec expand_import_exposing_type_names(
          [String.t()],
          String.t(),
          ModuleExports.project_exports()
        ) :: [String.t()]
  defp expand_import_exposing_type_names(names, module_name, project_module_exports)
       when is_list(names) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{types: []})

    exported_types = Map.get(module_exports, :types, [])
    module_type_name = module_name |> String.split(".") |> List.last()

    names
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil -> [name]
        type_name -> [type_name]
      end
    end)
    |> Enum.filter(fn name ->
      name in exported_types or (type_name?(name) and name == module_type_name)
    end)
  end

  defp expand_import_exposing_type_names(_names, _module_name, _project_module_exports), do: []

  @spec ensure_default_import_entries([ImportEntry.wire_map()]) :: [ImportEntry.wire_map()]
  defp ensure_default_import_entries(import_entries) do
    existing_modules =
      import_entries
      |> Enum.map(&Map.get(&1, "module"))
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    default_entries =
      DefaultImports.import_entries()
      |> Enum.reject(fn entry ->
        module_name = Map.get(entry, "module")
        not is_binary(module_name) or MapSet.member?(existing_modules, module_name)
      end)

    import_entries ++ default_entries
  end

  @spec add_unique_string(list() | Types.expr(), String.t() | integer()) :: Types.expr()

  defp add_unique_string(values, value) when is_list(values) and is_binary(value) do
    if value in values, do: values, else: values ++ [value]
  end

  defp add_unique_string(values, _value), do: values

  @spec put_unqualified_name(Lookup.import_unqualified_map(), String.t(), String.t()) ::
          Lookup.import_unqualified_map()
  defp put_unqualified_name(acc, name, module_name)
       when is_map(acc) and is_binary(name) and is_binary(module_name) do
    case Map.get(acc, name) do
      nil -> Map.put(acc, name, module_name)
      ^module_name -> acc
      _other_module -> Map.put(acc, name, :ambiguous)
    end
  end

  @spec register_wildcard_exports(
          Lookup.import_unqualified_map(),
          String.t(),
          ModuleExports.project_exports()
        ) :: Lookup.import_unqualified_map()
  defp register_wildcard_exports(acc, module_name, project_module_exports)
       when is_map(acc) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      known_wildcard_exports(module_name) ++
        (project_module_exports
         |> Map.get(module_name, %{names: []})
         |> Map.get(:names, []))

    module_exports
    |> Enum.reduce(acc, fn name, a -> put_unqualified_name(a, name, module_name) end)
  end

  @spec register_wildcard_type_exports(
          Lookup.import_unqualified_map(),
          String.t(),
          ModuleExports.project_exports()
        ) :: Lookup.import_unqualified_map()
  defp register_wildcard_type_exports(acc, module_name, project_module_exports)
       when is_map(acc) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      project_module_exports
      |> Map.get(module_name, %{types: []})
      |> Map.get(:types, [])

    module_exports
    |> Enum.reduce(acc, fn name, a -> put_unqualified_name(a, name, module_name) end)
  end

  defp register_wildcard_type_exports(acc, _module_name, _project_module_exports), do: acc

  @spec known_wildcard_exports(String.t()) :: [String.t()]
  defp known_wildcard_exports("Basics") do
    ~w(
      identity always never
      abs negate max min compare
      not xor
      toFloat round floor ceiling truncate
      sqrt logBase e pi cos sin tan acos asin atan atan2
      degrees radians turns toPolar fromPolar
      isNaN isInfinite
      modBy remainderBy
    )
  end

  defp known_wildcard_exports("Array") do
    ~w(
      empty repeat initialize fromList toList
      isEmpty length get set push append
      slice toIndexedList
      map indexedMap foldl foldr filter
    )
  end

  defp known_wildcard_exports("List") do
    ~w(
      singleton repeat range
      map indexedMap foldl foldr filter filterMap
      length reverse member all any maximum minimum sum product
      append concat concatMap intersperse map2 map3 map4 map5
      sort sortBy sortWith
      isEmpty head tail take drop partition unzip
    )
  end

  defp known_wildcard_exports("Maybe"), do: ~w(withDefault map map2 map3 map4 map5 andThen)

  defp known_wildcard_exports("Result"),
    do: ~w(map map2 map3 map4 map5 andThen withDefault toMaybe fromMaybe)

  defp known_wildcard_exports("String"),
    do:
      ~w(isEmpty length reverse repeat replace append concat split join words lines slice left right dropLeft dropRight contains startsWith endsWith indexes toInt toFloat fromChar cons uncons toList fromList toUpper toLower pad padLeft padRight trim trimLeft trimRight)

  defp known_wildcard_exports("Char"),
    do:
      ~w(fromCode toCode toUpper toLower toLocaleUpper toLocaleLower isUpper isLower isAlpha isAlphaNum isDigit isOctDigit isHexDigit)

  defp known_wildcard_exports("Bitwise"),
    do: ~w(and or xor complement shiftLeftBy shiftRightBy shiftRightZfBy)

  defp known_wildcard_exports("Tuple"), do: ~w(first second mapFirst mapSecond mapBoth pair)
  defp known_wildcard_exports("Debug"), do: ~w(log todo toString)
  defp known_wildcard_exports(_), do: []

  @spec rewrite_pattern(Pattern.t() | nil, Lookup.t()) :: Pattern.t() | nil
  defp rewrite_pattern(%{kind: :constructor, name: name} = pattern, lookup) do
    resolved_name = resolve_alias(name, lookup)

    tag =
      Map.get(lookup.local, name) || resolve_constructor_tag(resolved_name, lookup)

    arg_pattern =
      case pattern[:arg_pattern] do
        ap when is_map(ap) -> rewrite_pattern(ap, lookup)
        _ -> pattern[:arg_pattern]
      end

    pattern
    |> Map.put(:tag, tag)
    |> Map.put(:resolved_name, resolved_name)
    |> Map.put(:arg_pattern, arg_pattern)
  end

  defp rewrite_pattern(%{kind: :tuple, elements: elements} = pattern, lookup)
       when is_list(elements) do
    %{pattern | elements: Enum.map(elements, &rewrite_pattern(&1, lookup))}
  end

  defp rewrite_pattern(%{kind: :list, elements: elements} = pattern, lookup)
       when is_list(elements) do
    %{pattern | elements: Enum.map(elements, &rewrite_pattern(&1, lookup))}
  end

  defp rewrite_pattern(%{kind: :cons, head: head, tail: tail} = pattern, lookup) do
    %{
      pattern
      | head: rewrite_pattern(head, lookup),
        tail: rewrite_pattern(tail, lookup)
    }
  end

  defp rewrite_pattern(%{kind: :alias, pattern: inner} = pattern, lookup) when is_map(inner) do
    %{pattern | pattern: rewrite_pattern(inner, lookup)}
  end

  defp rewrite_pattern(pattern, _lookup), do: pattern

  @spec rewrite_constructor_value(String.t(), [Expr.t()], Lookup.t()) :: Expr.t() | nil
  defp rewrite_constructor_value(resolved_target, rewritten_args, lookup)
       when is_binary(resolved_target) and is_list(rewritten_args) do
    case rewrite_virtual_ui_constructor(resolved_target, rewritten_args, lookup) do
      nil ->
        tag = resolve_constructor_tag(resolved_target, lookup)

        record_alias_rewrite =
          if is_integer(tag) do
            nil
          else
            rewrite_record_alias_constructor(resolved_target, rewritten_args, lookup)
          end

        case record_alias_rewrite do
          nil when is_integer(tag) ->
            expected_arity = resolve_payload_arity(resolved_target, lookup)
            bound = length(rewritten_args)

            if is_integer(expected_arity) and bound < expected_arity do
              %{
                op: :partial_constructor,
                target: resolved_target,
                tag: tag,
                args: rewritten_args,
                arity: expected_arity
              }
            else
              qualified = qualify_constructor_target(resolved_target, lookup)
              tagged_constructor_value(tag, rewritten_args, qualified)
            end

          rewritten when is_map(rewritten) ->
            rewritten

          _ ->
            nil
        end

      rewritten ->
        rewritten
    end
  end

  @spec rewrite_record_alias_constructor(String.t(), [String.t()], Types.expr()) :: String.t()

  defp rewrite_record_alias_constructor(resolved_target, rewritten_args, lookup)
       when is_binary(resolved_target) and is_list(rewritten_args) do
    qualified = qualify_constructor_target(resolved_target, lookup)
    expected_fields = resolve_record_alias_fields(qualified, resolved_target, lookup)

    case expected_fields do
      fields when is_list(fields) and fields != [] ->
        arity = length(fields)
        bound = length(rewritten_args)

        cond do
          bound > arity ->
            nil

          bound == arity ->
            record_alias_record_literal(qualified, fields, rewritten_args)

          true ->
            remaining = Enum.drop(fields, bound)
            arg_names = Enum.map(remaining, fn f -> "__record_ctor__" <> f end)

            applied_args =
              rewritten_args ++ Enum.map(arg_names, fn n -> %{op: :var, name: n} end)

            %{
              op: :lambda,
              args: arg_names,
              body: record_alias_record_literal(qualified, fields, applied_args)
            }
        end

      _ ->
        nil
    end
  end

  @spec record_alias_record_literal(Types.expr(), list(), Types.expr()) :: Types.expr()

  defp record_alias_record_literal(qualified, fields, arg_exprs)
       when is_binary(qualified) and is_list(fields) and is_list(arg_exprs) do
    %{
      op: :record_literal,
      type: qualified,
      fields:
        fields
        |> Enum.zip(arg_exprs)
        |> Enum.map(fn {field, expr} -> %{name: to_string(field), expr: expr} end)
    }
  end

  @spec resolve_record_alias_fields(Types.expr(), String.t(), Types.expr()) :: Types.expr()

  defp resolve_record_alias_fields(qualified, resolved_target, lookup)
       when is_binary(qualified) and is_binary(resolved_target) do
    local = Map.get(lookup, :record_alias_fields_local, %{})
    unqualified = Map.get(lookup, :record_alias_fields_unqualified, %{})
    qualified_map = Map.get(lookup, :record_alias_fields_qualified, %{})

    cond do
      Map.has_key?(qualified_map, qualified) ->
        Map.get(qualified_map, qualified)

      Map.has_key?(local, resolved_target) ->
        Map.get(local, resolved_target)

      Map.has_key?(unqualified, resolved_target) ->
        Map.get(unqualified, resolved_target)

      true ->
        nil
    end
  end

  @spec local_record_alias_field_lookup(map() | term()) :: Types.expr()

  defp local_record_alias_field_lookup(%{declarations: declarations}) when is_list(declarations) do
    declarations
    |> Enum.filter(&(&1.kind == :type_alias))
    |> Enum.flat_map(fn decl ->
      case Map.get(decl, :fields) do
        fields when is_list(fields) and fields != [] ->
          [{decl.name, Enum.map(fields, &to_string/1)}]

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  defp local_record_alias_field_lookup(_), do: %{}

  @spec rewrite_virtual_ui_constructor(String.t(), [Expr.t()], Lookup.t()) :: Expr.t() | nil
  defp rewrite_virtual_ui_constructor(resolved_target, rewritten_args, lookup) do
    case qualify_constructor_target(resolved_target, lookup) do
      "Pebble.Ui.WindowStack" ->
        case rewritten_args do
          [windows] ->
            tagged_constructor_value(
              @pebble_ui_window_stack_tag,
              [windows],
              "Pebble.Ui.WindowStack"
            )

          _ ->
            nil
        end

      "Pebble.Ui.WindowNode" ->
        case rewritten_args do
          [window_id, layers] ->
            tagged_constructor_value(
              @pebble_ui_window_node_tag,
              [window_id, layers],
              "Pebble.Ui.WindowNode"
            )

          _ ->
            nil
        end

      "Pebble.Ui.CanvasLayer" ->
        case rewritten_args do
          [layer_id, ops] ->
            tagged_constructor_value(
              @pebble_ui_canvas_layer_tag,
              [layer_id, ops],
              "Pebble.Ui.CanvasLayer"
            )

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @spec qualify_constructor_target(String.t(), Lookup.t()) :: String.t()
  defp qualify_constructor_target(target, lookup) when is_binary(target) do
    if String.contains?(target, ".") do
      target
    else
      current_module = Map.get(lookup, :current_module)

      if is_binary(current_module) and current_module != "" do
        "#{current_module}.#{target}"
      else
        target
      end
    end
  end

  @spec tagged_constructor_value(integer(), [Expr.t()], String.t()) :: Expr.t()
  defp tagged_constructor_value(tag, rewritten_args, qualified) when is_binary(qualified) do
    case rewritten_args do
      [] ->
        %{op: :int_literal, value: tag, union_ctor: qualified}

      [arg] ->
        %{
          op: :tuple2,
          left: %{op: :int_literal, value: tag, union_ctor: qualified},
          right: arg
        }

      many_args ->
        %{
          op: :tuple2,
          left: %{op: :int_literal, value: tag, union_ctor: qualified},
          right: build_constructor_payload(many_args)
        }
    end
  end

  @spec builtin_constructor_tag(String.t()) :: integer() | nil
  defp builtin_constructor_tag("Ok"), do: 1
  defp builtin_constructor_tag("Err"), do: 0
  defp builtin_constructor_tag("Just"), do: 1
  defp builtin_constructor_tag("Nothing"), do: 0
  defp builtin_constructor_tag(_), do: nil

  @spec resolve_constructor_tag(String.t(), Lookup.t()) :: integer() | nil
  defp resolve_constructor_tag(target, lookup) when is_binary(target) do
    segments = String.split(target, ".")
    unqualified_name = List.last(segments)

    case segments do
      [_single] ->
        import_mod = import_module_for_ctor(lookup, unqualified_name)
        current_mod = Map.get(lookup, :current_module)

        lookup.local[unqualified_name] ||
          (is_binary(import_mod) &&
             Map.get(lookup.qualified, "#{import_mod}.#{unqualified_name}")) ||
          lookup_qualified_affinity(lookup.qualified, current_mod, unqualified_name) ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_tag(unqualified_name)

      _many ->
        # Qualified targets must not fall back to an ambiguous short-name table
        # (Group → Internal.Compiler.Group tag 5 vs Scene3d.Types.Group tag 6).
        Map.get(lookup.qualified, target) ||
          lookup_qualified_affinity(lookup.qualified, Map.get(lookup, :current_module), unqualified_name) ||
          builtin_constructor_tag(unqualified_name)
    end
  end

  @spec import_module_for_ctor(map() | term(), String.t() | term()) :: Types.expr()

  defp import_module_for_ctor(lookup, name) when is_map(lookup) and is_binary(name) do
    case Map.get(lookup, :import_unqualified_map, %{}) |> Map.get(name) do
      mod when is_binary(mod) and mod != "" -> mod
      _ -> nil
    end
  end

  defp import_module_for_ctor(_, _), do: nil

  # When short names collide across packages, prefer the candidate that shares the
  # most module-path prefix with the call-site module (Scene3d.Entity + Group →
  # Scene3d.Types.Group), never an unrelated Internal.Compiler.Group.
  @spec lookup_qualified_affinity(Types.expr() | term(), String.t() | term(), String.t() | term()) :: Types.expr()

  defp lookup_qualified_affinity(qualified, current_module, short_name)
       when is_map(qualified) and is_binary(short_name) do
    suffix = "." <> short_name

    candidates =
      for {key, tag} <- qualified,
          is_binary(key) and is_integer(tag),
          String.ends_with?(key, suffix),
          do: {key, tag}

    case candidates do
      [] ->
        nil

      [{_key, tag}] ->
        tag

      many when is_binary(current_module) ->
        target_mod = current_module |> String.split(".") |> Enum.drop(-1)

        scored =
          Enum.map(many, fn {key, tag} ->
            key_mod = key |> String.split(".") |> Enum.drop(-1)
            leading = shared_prefix_len(target_mod, key_mod)
            {{leading}, String.length(key), tag}
          end)

        max_score = scored |> Enum.map(&elem(&1, 0)) |> Enum.max()

        if max_score == {0} do
          nil
        else
          scored
          |> Enum.filter(&(elem(&1, 0) == max_score))
          |> Enum.max_by(&elem(&1, 1))
          |> elem(2)
        end

      _many ->
        nil
    end
  end

  defp lookup_qualified_affinity(_, _, _), do: nil

  @spec shared_prefix_len(Types.expr() | term(), Types.expr() | term(), integer()) :: Types.expr()

  defp shared_prefix_len(a, b), do: shared_prefix_len(a, b, 0)
  defp shared_prefix_len([x | as], [x | bs], n), do: shared_prefix_len(as, bs, n + 1)
  defp shared_prefix_len(_, _, n), do: n

  # Keep only short names that map to a single tag across the project.
  @spec unique_short_name_map(list() | term()) :: Types.expr()

  defp unique_short_name_map(pairs) when is_list(pairs) do
    pairs
    |> Enum.group_by(fn {name, _value} -> name end)
    |> Enum.flat_map(fn {name, values} ->
      distinct = values |> Enum.map(fn {_n, v} -> v end) |> Enum.uniq()

      case distinct do
        [value] -> [{name, value}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp unique_short_name_map(_), do: %{}

  @spec build_constructor_payload([Expr.t()]) :: Expr.t()
  defp build_constructor_payload([left, right]), do: %{op: :tuple2, left: left, right: right}

  defp build_constructor_payload([head | tail]) do
    %{op: :tuple2, left: head, right: build_constructor_payload(tail)}
  end

  @spec collect_constructor_arity_diagnostics(
          [Module.t()],
          Lookup.kind_map(),
          Lookup.kind_map()
        ) :: [Diagnostic.t()]
  defp collect_constructor_arity_diagnostics(
         modules,
         payload_kind_lookup,
         qualified_payload_kind_lookup
       ) do
    Enum.flat_map(modules, fn module ->
      local_payload_kind_lookup =
        module.unions
        |> Map.values()
        |> Enum.flat_map(fn union_info ->
          union_info
          |> Map.get(:payload_kinds, %{})
          |> Enum.to_list()
        end)
        |> Map.new()

      lookup = %{
        local: local_payload_kind_lookup,
        unqualified: payload_kind_lookup,
        qualified: qualified_payload_kind_lookup,
        alias_map: %{}
      }

      module.declarations
      |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
      |> Enum.flat_map(fn decl ->
        line =
          case Map.get(decl, :span) do
            %{start_line: start_line} when is_integer(start_line) -> start_line
            _ -> nil
          end

        expr_constructor_arity_diagnostics(decl.expr, lookup, module.name, decl.name, line)
      end)
    end)
  end

  @spec collect_constructor_call_arity_diagnostics(
          [FrontendModule.t()],
          Lookup.arity_map(),
          Lookup.arity_map()
        ) :: [Diagnostic.t()]
  defp collect_constructor_call_arity_diagnostics(
         frontend_modules,
         payload_arity_lookup,
         qualified_payload_arity_lookup
       )
       when is_list(frontend_modules) do
    Enum.flat_map(frontend_modules, fn frontend_module ->
      module_name = Map.get(frontend_module, :name)

      local_payload_arity_lookup =
        frontend_module
        |> Map.get(:declarations, [])
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.map(fn constructor ->
            {constructor.name, payload_arity_for_spec(constructor.arg)}
          end)
        end)
        |> Map.new()

      arity_lookup = %{
        local: local_payload_arity_lookup,
        unqualified: payload_arity_lookup,
        qualified: qualified_payload_arity_lookup,
        alias_map: %{}
      }

      frontend_module
      |> Map.get(:declarations, [])
      |> Enum.filter(&(&1.kind == :function_definition and is_map(&1.expr)))
      |> Enum.flat_map(fn decl ->
        line =
          case Map.get(decl, :span) do
            %{start_line: start_line} when is_integer(start_line) -> start_line
            _ -> nil
          end

        expr_constructor_call_arity_diagnostics(
          decl.expr,
          arity_lookup,
          module_name,
          decl.name,
          line
        )
      end)
    end)
  end

  @spec collect_preferences_schema_field_order_diagnostics([FrontendModule.t()]) :: [Diagnostic.t()]
  defp collect_preferences_schema_field_order_diagnostics(frontend_modules)
       when is_list(frontend_modules) do
    Enum.flat_map(frontend_modules, fn frontend_module ->
      module_name = Map.get(frontend_module, :name)

      alias_fields =
        frontend_module
        |> Map.get(:declarations, [])
        |> Enum.filter(&(&1.kind == :type_alias))
        |> Map.new(fn alias_decl ->
          {Map.get(alias_decl, :name), Map.get(alias_decl, :fields) || []}
        end)

      frontend_module
      |> Map.get(:declarations, [])
      |> Enum.filter(&(&1.kind == :function_definition and is_map(&1.expr)))
      |> Enum.flat_map(fn decl ->
        line =
          case Map.get(decl, :span) do
            %{start_line: start_line} when is_integer(start_line) -> start_line
            _ -> nil
          end

        expr_preferences_schema_field_order_diagnostics(
          decl.expr,
          alias_fields,
          module_name,
          decl.name,
          line
        )
      end)
    end)
  end

  @spec expr_preferences_schema_field_order_diagnostics(
          Expr.t(),
          preferences_alias_fields(),
          name() | nil,
          name() | nil,
          integer() | nil
        ) :: [Diagnostic.t()]
  defp expr_preferences_schema_field_order_diagnostics(
         expr,
         alias_fields,
         module_name,
         function_name,
         line
       )
       when is_map(expr) do
    case preferences_schema_field_order(expr) do
      {:ok, alias_name, field_order} ->
        expected_order = Map.get(alias_fields, alias_name)

        if is_list(expected_order) and expected_order != [] and expected_order != field_order do
          [
            %{
              severity: "error",
              source: "lowerer/preferences",
              code: "preferences_schema_field_order",
              module: module_name,
              function: function_name,
              line: line,
              constructor: alias_name,
              expected_fields: expected_order,
              actual_fields: field_order,
              message:
                "Preference schema for #{alias_name} adds fields in #{inspect(field_order)}, but the record constructor expects #{inspect(expected_order)}. Fields must be added in constructor order."
            }
          ]
        else
          []
        end

      _ ->
        nested_preferences_schema_field_order_diagnostics(
          expr,
          alias_fields,
          module_name,
          function_name,
          line
        )
    end
  end

  defp expr_preferences_schema_field_order_diagnostics(
         _expr,
         _alias_fields,
         _module_name,
         _function_name,
         _line
       ),
       do: []

  @spec nested_preferences_schema_field_order_diagnostics(
          Expr.t(),
          preferences_alias_fields(),
          name() | nil,
          name() | nil,
          integer() | nil
        ) :: [Diagnostic.t()]
  defp nested_preferences_schema_field_order_diagnostics(
         expr,
         alias_fields,
         module_name,
         function_name,
         line
       ) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn value ->
      cond do
        is_map(value) ->
          expr_preferences_schema_field_order_diagnostics(
            value,
            alias_fields,
            module_name,
            function_name,
            line
          )

        is_list(value) ->
          Enum.flat_map(value, fn item ->
            if is_map(item) do
              expr_preferences_schema_field_order_diagnostics(
                item,
                alias_fields,
                module_name,
                function_name,
                line
              )
            else
              []
            end
          end)

        true ->
          []
      end
    end)
  end

  @spec preferences_schema_field_order(Expr.t()) ::
          {:ok, String.t(), [String.t()]} | :error
  defp preferences_schema_field_order(%{op: :pipe_chain, base: base, steps: steps})
       when is_list(steps) do
    steps
    |> Enum.reduce(base, &PipeChain.append_pipe_arg/2)
    |> preferences_schema_field_order()
  end

  defp preferences_schema_field_order(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    cond do
      preferences_call?(target, "schema") ->
        case args do
          [
            _title,
            %{op: :constructor_call, target: constructor_target}
          ]
          when is_binary(constructor_target) ->
            {:ok, constructor_target |> String.split(".") |> List.last(), []}

          _ ->
            :error
        end

      preferences_call?(target, "section") ->
        case args do
          [_title, %{op: :lambda, body: body}, previous] ->
            with {:ok, alias_name, previous_fields} <- preferences_schema_field_order(previous),
                 {:ok, section_fields} <- preferences_section_fields(body) do
              {:ok, alias_name, previous_fields ++ section_fields}
            end

          _ ->
            :error
        end

      true ->
        :error
    end
  end

  defp preferences_schema_field_order(_expr), do: :error

  @spec preferences_section_fields(Expr.t()) :: {:ok, [String.t()]} | :error
  defp preferences_section_fields(%{op: :pipe_chain, base: base, steps: steps})
       when is_list(steps) do
    steps
    |> Enum.reduce(base, &PipeChain.append_pipe_arg/2)
    |> preferences_section_fields()
  end

  defp preferences_section_fields(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    if preferences_call?(target, "field") do
      case args do
        [%{op: :string_literal, value: field_id}, _control, previous]
        when is_binary(field_id) ->
          with {:ok, previous_fields} <- preferences_section_fields(previous) do
            {:ok, previous_fields ++ [field_id]}
          end

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp preferences_section_fields(%{op: :var}), do: {:ok, []}
  defp preferences_section_fields(_expr), do: :error

  @spec preferences_call?(String.t(), String.t()) :: boolean()
  defp preferences_call?(target, function_name) when is_binary(target) do
    target in [
      "Preferences.#{function_name}",
      "Pebble.Companion.Preferences.#{function_name}"
    ]
  end

  @spec expr_constructor_call_arity_diagnostics(
          Expr.t(),
          Lookup.t(),
          name() | nil,
          name() | nil,
          integer() | nil
        ) :: [Diagnostic.t()]
  defp expr_constructor_call_arity_diagnostics(
         %{op: :constructor_call, target: target, args: args},
         arity_lookup,
         module_name,
         function_name,
         line
       )
       when is_binary(target) and is_list(args) do
    constructor_name = target |> String.split(".") |> List.last()
    expected_arity = resolve_constructor_arity(target, arity_lookup)
    argc = length(args)

    current =
      case expected_arity do
        expected when is_integer(expected) and argc > expected ->
          [
            %{
              severity: "warning",
              source: "lowerer/expression",
              code: "constructor_call_arity",
              module: module_name,
              function: function_name,
              line: line,
              constructor: constructor_name,
              expected_arity: expected,
              args_count: argc,
              message:
                "Constructor #{constructor_name} expects at most #{expected} argument(s), but was called with #{argc} argument(s)."
            }
          ]

        _ ->
          []
      end

    nested =
      args
      |> Enum.flat_map(fn arg ->
        if is_map(arg),
          do:
            expr_constructor_call_arity_diagnostics(
              arg,
              arity_lookup,
              module_name,
              function_name,
              line
            ),
          else: []
      end)

    current ++ nested
  end

  defp expr_constructor_call_arity_diagnostics(
         expr,
         arity_lookup,
         module_name,
         function_name,
         line
       )
       when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn value ->
      cond do
        is_map(value) ->
          expr_constructor_call_arity_diagnostics(
            value,
            arity_lookup,
            module_name,
            function_name,
            line
          )

        is_list(value) ->
          value
          |> Enum.flat_map(fn item ->
            if is_map(item),
              do:
                expr_constructor_call_arity_diagnostics(
                  item,
                  arity_lookup,
                  module_name,
                  function_name,
                  line
                ),
              else: []
          end)

        true ->
          []
      end
    end)
  end

  defp expr_constructor_call_arity_diagnostics(
         _expr,
         _lookup,
         _module_name,
         _function_name,
         _line
       ),
       do: []

  @spec resolve_payload_arity(String.t(), Lookup.t()) :: non_neg_integer() | nil
  defp resolve_payload_arity(target, lookup) when is_binary(target) do
    segments = String.split(target, ".")
    unqualified_name = List.last(segments)

    case segments do
      [_single] ->
        Map.get(lookup, :payload_arity_local, %{})[unqualified_name] ||
          Map.get(lookup, :payload_arity_unqualified, %{})[unqualified_name] ||
          builtin_constructor_arity(unqualified_name)

      _many ->
        Map.get(lookup, :payload_arity_qualified, %{})[target] ||
          Map.get(lookup, :payload_arity_unqualified, %{})[unqualified_name] ||
          builtin_constructor_arity(unqualified_name)
    end
  end

  @spec resolve_constructor_arity(String.t(), Lookup.constructor_t()) :: non_neg_integer() | nil
  defp resolve_constructor_arity(target, lookup) when is_binary(target) do
    unqualified_name = target |> String.split(".") |> List.last()

    lookup.local[unqualified_name] ||
      lookup.qualified[target] ||
      lookup.unqualified[unqualified_name] ||
      builtin_constructor_arity(unqualified_name)
  end

  @spec resolve_constructor_payload_kind(String.t(), Lookup.constructor_t()) ::
          payload_kind() | nil
  defp resolve_constructor_payload_kind(target, lookup) when is_binary(target) do
    unqualified_name = target |> String.split(".") |> List.last()

    lookup.local[unqualified_name] ||
      lookup.qualified[target] ||
      lookup.unqualified[unqualified_name] ||
      builtin_constructor_payload_kind(unqualified_name)
  end

  @spec expr_constructor_arity_diagnostics(
          Expr.t(),
          Lookup.t(),
          name() | nil,
          name() | nil,
          integer() | nil
        ) :: [Diagnostic.t()]
  defp expr_constructor_arity_diagnostics(
         %{op: :case, subject: subject, branches: branches},
         lookup,
         module_name,
         function_name,
         line
       )
       when is_list(branches) do
    subject_diagnostics =
      if is_map(subject) do
        expr_constructor_arity_diagnostics(subject, lookup, module_name, function_name, line)
      else
        []
      end

    branch_diagnostics =
      branches
      |> Enum.flat_map(fn branch ->
        pattern =
          case branch do
            %{pattern: p} -> p
            _ -> nil
          end

        branch_expr =
          case branch do
            %{expr: e} -> e
            _ -> nil
          end

        pattern_diagnostics =
          pattern_constructor_arity_diagnostics(pattern, lookup, module_name, function_name, line)

        nested_diagnostics =
          if is_map(branch_expr) do
            expr_constructor_arity_diagnostics(
              branch_expr,
              lookup,
              module_name,
              function_name,
              line
            )
          else
            []
          end

        pattern_diagnostics ++ nested_diagnostics
      end)

    subject_diagnostics ++ branch_diagnostics
  end

  defp expr_constructor_arity_diagnostics(expr, lookup, module_name, function_name, line)
       when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn value ->
      cond do
        is_map(value) ->
          expr_constructor_arity_diagnostics(value, lookup, module_name, function_name, line)

        is_list(value) ->
          value
          |> Enum.flat_map(fn item ->
            if is_map(item),
              do:
                expr_constructor_arity_diagnostics(item, lookup, module_name, function_name, line),
              else: []
          end)

        true ->
          []
      end
    end)
  end

  defp expr_constructor_arity_diagnostics(_expr, _lookup, _module_name, _function_name, _line),
    do: []

  @spec pattern_constructor_arity_diagnostics(
          Pattern.t(),
          Lookup.t(),
          name() | nil,
          name() | nil,
          integer() | nil
        ) :: [Diagnostic.t()]
  defp pattern_constructor_arity_diagnostics(
         %{kind: :constructor, name: name} = pattern,
         lookup,
         module_name,
         function_name,
         line
       ) do
    resolved_name = Map.get(pattern, :resolved_name, name)
    expected_kind = resolve_constructor_payload_kind(resolved_name, lookup)

    has_arg_pattern =
      case pattern do
        %{arg_pattern: arg} when is_map(arg) -> true
        %{bind: bind} when is_binary(bind) and bind != "" -> true
        _ -> false
      end

    current =
      case {expected_kind, has_arg_pattern} do
        {:none, true} ->
          [
            %{
              severity: "warning",
              source: "lowerer/pattern",
              code: "constructor_payload_arity",
              module: module_name,
              function: function_name,
              line: line,
              constructor: resolved_name,
              expected_kind: :none,
              has_arg_pattern: true,
              message:
                "Constructor #{resolved_name} is used with an argument pattern, but its payload kind is none."
            }
          ]

        {kind, false} when kind in [:single, :multi, :function_like] ->
          [
            %{
              severity: "warning",
              source: "lowerer/pattern",
              code: "constructor_payload_arity",
              module: module_name,
              function: function_name,
              line: line,
              constructor: resolved_name,
              expected_kind: kind,
              has_arg_pattern: false,
              message:
                "Constructor #{resolved_name} expects a payload pattern (kind #{kind}), but no argument pattern was provided."
            }
          ]

        _ ->
          []
      end

    nested =
      case pattern do
        %{arg_pattern: arg} when is_map(arg) ->
          pattern_constructor_arity_diagnostics(arg, lookup, module_name, function_name, line)

        %{elements: elements} when is_list(elements) ->
          Enum.flat_map(
            elements,
            &pattern_constructor_arity_diagnostics(&1, lookup, module_name, function_name, line)
          )

        _ ->
          []
      end

    current ++ nested
  end

  defp pattern_constructor_arity_diagnostics(
         %{kind: :tuple, elements: elements},
         lookup,
         module_name,
         function_name,
         line
       )
       when is_list(elements) do
    Enum.flat_map(
      elements,
      &pattern_constructor_arity_diagnostics(&1, lookup, module_name, function_name, line)
    )
  end

  defp pattern_constructor_arity_diagnostics(
         _pattern,
         _lookup,
         _module_name,
         _function_name,
         _line
       ),
       do: []

  @spec builtin_constructor_payload_kind(String.t()) :: payload_kind() | nil
  defp builtin_constructor_payload_kind("Ok"), do: :single
  defp builtin_constructor_payload_kind("Err"), do: :single
  defp builtin_constructor_payload_kind("Just"), do: :single
  defp builtin_constructor_payload_kind("Nothing"), do: :none
  defp builtin_constructor_payload_kind(_), do: nil

  @spec builtin_constructor_arity(String.t()) :: non_neg_integer() | nil
  defp builtin_constructor_arity("Ok"), do: 1
  defp builtin_constructor_arity("Err"), do: 1
  defp builtin_constructor_arity("Just"), do: 1
  defp builtin_constructor_arity("Nothing"), do: 0
  defp builtin_constructor_arity(_), do: nil

  @spec payload_kind_for_spec(String.t() | nil) :: payload_kind()
  defp payload_kind_for_spec(nil), do: :none

  defp payload_kind_for_spec(spec) when is_binary(spec) do
    text = String.trim(spec)

    cond do
      text == "" ->
        :none

      String.contains?(text, "->") ->
        :function_like

      String.contains?(text, " ") ->
        :multi

      true ->
        :single
    end
  end

  @spec payload_arity_for_spec(String.t() | nil) :: non_neg_integer()
  defp payload_arity_for_spec(nil), do: 0

  defp payload_arity_for_spec(spec) when is_binary(spec) do
    spec
    |> split_top_level_type_tokens()
    |> length()
  end

  @spec split_top_level_type_tokens(String.t()) :: [String.t()]
  defp split_top_level_type_tokens(text) when is_binary(text) do
    chars = String.to_charlist(String.trim(text))

    {parts, current, _, _, _} =
      Enum.reduce(chars, {[], [], 0, 0, 0}, fn char,
                                               {parts, current, paren_depth, bracket_depth,
                                                brace_depth} ->
        cond do
          char == ?( ->
            {parts, [char | current], paren_depth + 1, bracket_depth, brace_depth}

          char == ?) ->
            {parts, [char | current], max(paren_depth - 1, 0), bracket_depth, brace_depth}

          char == ?[ ->
            {parts, [char | current], paren_depth, bracket_depth + 1, brace_depth}

          char == ?] ->
            {parts, [char | current], paren_depth, max(bracket_depth - 1, 0), brace_depth}

          char == ?{ ->
            {parts, [char | current], paren_depth, bracket_depth, brace_depth + 1}

          char == ?} ->
            {parts, [char | current], paren_depth, bracket_depth, max(brace_depth - 1, 0)}

          (char == ?\s or char == ?\n or char == ?\t or char == ?\r) and paren_depth == 0 and
            bracket_depth == 0 and brace_depth == 0 ->
            token = current |> Enum.reverse() |> to_string() |> String.trim()

            if token == "" do
              {parts, [], paren_depth, bracket_depth, brace_depth}
            else
              {parts ++ [token], [], paren_depth, bracket_depth, brace_depth}
            end

          true ->
            {parts, [char | current], paren_depth, bracket_depth, brace_depth}
        end
      end)

    last = current |> Enum.reverse() |> to_string() |> String.trim()
    all = if last == "", do: parts, else: parts ++ [last]
    Enum.reject(all, &(&1 == ""))
  end
end
