defmodule ElmEx.IR.Lowerer do
  @moduledoc """
  Lowers frontend modules into ownership-annotated IR.
  """

  alias ElmEx.Frontend.Project
  alias ElmEx.Frontend.DefaultImports
  alias ElmEx.IR
  alias ElmEx.IR.Declaration
  alias ElmEx.IR.Module

  @typep expr() :: term()
  @typep lookup() :: map()
  @typep payload_kind() :: :none | :single | :multi | :function_like
  @typep diagnostic() :: map()

  @dialyzer [
    {:nowarn_function, rewrite_expr: 2},
    {:nowarn_function, rewrite_case_subject: 2},
    {:nowarn_function, rewrite_pattern: 2},
    {:nowarn_function, resolve_constructor_tag: 2},
    {:nowarn_function, build_constructor_payload: 1},
    {:nowarn_function, lower_declaration: 2}
  ]

  @spec lower_project(Project.t()) :: {:ok, IR.t()} | {:error, map()}
  def lower_project(%Project{} = project) do
    global_constructor_lookup =
      project.modules
      |> Enum.flat_map(fn frontend_module ->
        frontend_module.declarations
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.with_index(1)
          |> Enum.map(fn {constructor, index} -> {constructor.name, index} end)
        end)
      end)
      |> Map.new()

    global_qualified_constructor_lookup =
      project.modules
      |> Enum.flat_map(fn frontend_module ->
        frontend_module.declarations
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.with_index(1)
          |> Enum.map(fn {constructor, index} ->
            {"#{frontend_module.name}.#{constructor.name}", index}
          end)
        end)
      end)
      |> Map.new()

    global_payload_kind_lookup =
      project.modules
      |> Enum.flat_map(fn frontend_module ->
        frontend_module.declarations
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.map(fn constructor ->
            {constructor.name, payload_kind_for_spec(constructor.arg)}
          end)
        end)
      end)
      |> Map.new()

    global_qualified_payload_kind_lookup =
      project.modules
      |> Enum.flat_map(fn frontend_module ->
        frontend_module.declarations
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.map(fn constructor ->
            {"#{frontend_module.name}.#{constructor.name}",
             payload_kind_for_spec(constructor.arg)}
          end)
        end)
      end)
      |> Map.new()

    global_payload_arity_lookup =
      project.modules
      |> Enum.flat_map(fn frontend_module ->
        frontend_module.declarations
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.map(fn constructor ->
            {constructor.name, payload_arity_for_spec(constructor.arg)}
          end)
        end)
      end)
      |> Map.new()

    global_qualified_payload_arity_lookup =
      project.modules
      |> Enum.flat_map(fn frontend_module ->
        frontend_module.declarations
        |> Enum.filter(&(&1.kind == :union))
        |> Enum.flat_map(fn union ->
          constructors = Map.get(union, :constructors, [])

          constructors
          |> Enum.map(fn constructor ->
            {"#{frontend_module.name}.#{constructor.name}",
             payload_arity_for_spec(constructor.arg)}
          end)
        end)
      end)
      |> Map.new()

    project_module_exports = build_project_module_exports(project.modules)

    modules =
      Enum.map(project.modules, fn frontend_module ->
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

        definition_decls =
          others
          |> Enum.filter(&(&1.kind == :function_definition))

        definitions =
          others
          |> Enum.filter(&(&1.kind == :function_definition))
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

            {alias_map, import_unqualified_map, wildcard_import_modules} =
              build_import_resolution(
                Map.get(frontend_module, :import_entries) || [],
                project_module_exports
              )

            rewrite_lookup = %{
              local: local_constructor_lookup,
              unqualified: global_constructor_lookup,
              qualified: global_qualified_constructor_lookup,
              current_module: frontend_module.name,
              alias_map: alias_map,
              import_unqualified_map: import_unqualified_map,
              wildcard_import_modules: wildcard_import_modules,
              local_call_names: MapSet.new(Enum.map(defs, & &1.name))
            }

            {defs, rewrite_lookup}
          end)
          |> then(fn {defs, rewrite_lookup} ->
            defs
            |> Map.new(fn defn ->
              expr = rewrite_expr(defn.expr, rewrite_lookup)
              {defn.name, %{defn | expr: expr}}
            end)
          end)

        signature_names = signatures |> Enum.map(& &1.name) |> MapSet.new()

        signature_declarations =
          signatures
          |> Enum.map(fn sig ->
            lower_declaration(sig, Map.get(definitions, sig.name))
          end)
          |> Enum.reject(&is_nil/1)

        definition_only_declarations =
          definition_decls
          |> Enum.reject(&MapSet.member?(signature_names, &1.name))
          |> Enum.map(fn defn ->
            lowered = Map.get(definitions, defn.name, defn)
            lower_declaration(lowered, nil)
          end)
          |> Enum.reject(&is_nil/1)

        signature_by_name = Map.new(signature_declarations, &{&1.name, &1})
        definition_only_by_name = Map.new(definition_only_declarations, &{&1.name, &1})

        type_alias_declarations =
          others
          |> Enum.filter(&(&1.kind == :type_alias))
          |> Enum.map(&lower_declaration(&1, nil))
          |> Enum.reject(&is_nil/1)

        ordered_function_names =
          frontend_module.declarations
          |> Enum.filter(&(&1.kind in [:function_signature, :function_definition]))
          |> Enum.map(& &1.name)
          |> Enum.reduce({[], MapSet.new()}, fn name, {acc, seen} ->
            if MapSet.member?(seen, name) do
              {acc, seen}
            else
              {[name | acc], MapSet.put(seen, name)}
            end
          end)
          |> elem(0)
          |> Enum.reverse()

        ordered_declarations =
          type_alias_declarations ++
            (ordered_function_names
             |> Enum.map(fn name ->
               Map.get(signature_by_name, name) || Map.get(definition_only_by_name, name)
             end)
             |> Enum.reject(&is_nil/1))

        %Module{
          name: frontend_module.name,
          imports: frontend_module.imports,
          unions: unions,
          declarations: ordered_declarations
        }
      end)

    diagnostics =
      collect_constructor_arity_diagnostics(
        modules,
        global_payload_kind_lookup,
        global_qualified_payload_kind_lookup
      ) ++
        collect_constructor_call_arity_diagnostics(
          project.modules,
          global_payload_arity_lookup,
          global_qualified_payload_arity_lookup
        )

    {:ok, %IR{modules: modules, diagnostics: diagnostics}}
  end

  @spec lower_declaration(map(), map() | nil) :: ElmEx.IR.Declaration.t() | nil
  defp lower_declaration(%{kind: :function_signature, name: name, type: type} = sig, definition) do
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
  end

  defp lower_declaration(%{kind: :function_definition, name: name} = definition, _signature) do
    %Declaration{
      kind: :function,
      name: name,
      type: nil,
      args: Map.get(definition, :args),
      expr: Map.get(definition, :expr),
      span: Map.get(definition, :span),
      ownership: ownership_for_type(nil)
    }
  end

  defp lower_declaration(%{kind: :type_alias, name: name} = decl, _definition) do
    fields = Map.get(decl, :fields) || []

    %Declaration{
      kind: :type_alias,
      name: name,
      expr: type_alias_expr(fields),
      span: Map.get(decl, :span),
      ownership: [:retain_on_assign, :release_on_scope_exit]
    }
  end

  defp lower_declaration(%{kind: :union, name: name} = decl, _definition) do
    %Declaration{
      kind: :union,
      name: name,
      span: Map.get(decl, :span),
      ownership: [:retain_on_constructor, :release_on_match_exit]
    }
  end

  defp type_alias_expr(fields) when is_list(fields) and fields != [] do
    %{
      op: :record_alias,
      fields: Enum.map(fields, &to_string/1)
    }
  end

  defp type_alias_expr(_fields), do: nil

  @spec ownership_for_type(String.t() | nil) :: [atom()]
  defp ownership_for_type(type) do
    cond do
      not is_binary(type) -> [:borrow_arg, :borrow_result]
      String.contains?(type, "List") -> [:borrow_arg, :retain_result]
      String.contains?(type, "String") -> [:retain_arg, :retain_result]
      String.contains?(type, "->") -> [:borrow_arg, :borrow_result]
      true -> [:borrow_arg, :borrow_result]
    end
  end

  @spec rewrite_expr(expr(), lookup()) :: expr()
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
    resolved_target = resolve_alias(target, lookup)
    rewritten_args = Enum.map(args || [], &rewrite_expr(&1, lookup))

    case rewrite_constructor_value(resolved_target, rewritten_args, lookup) do
      nil ->
        %{expr | target: resolved_target, args: rewritten_args}

      rewritten ->
        rewritten
    end
  end

  defp rewrite_expr(%{op: :qualified_call1, target: target} = expr, lookup) do
    resolved_target = resolve_alias(target, lookup)
    %{expr | target: resolved_target}
  end

  defp rewrite_expr(%{op: :call, name: name, args: args}, lookup) when is_binary(name) do
    rewritten_args = Enum.map(args || [], &rewrite_expr(&1, lookup))
    resolved_name = resolve_alias(name, lookup)

    if String.contains?(resolved_name, ".") do
      %{op: :qualified_call, target: resolved_name, args: rewritten_args}
    else
      %{op: :call, name: resolved_name, args: rewritten_args}
    end
  end

  defp rewrite_expr(%{op: :call, args: args} = expr, lookup) do
    %{expr | args: Enum.map(args || [], &rewrite_expr(&1, lookup))}
  end

  defp rewrite_expr(%{op: :let_in, value_expr: value_expr, in_expr: in_expr} = expr, lookup) do
    local_name = Map.get(expr, :name) || Map.get(expr, "name")

    scoped_lookup =
      if is_binary(local_name) and local_name != "" do
        Map.update(
          lookup,
          :local_call_names,
          MapSet.new([local_name]),
          &MapSet.put(&1, local_name)
        )
      else
        lookup
      end

    %{
      expr
      | value_expr: rewrite_expr(value_expr, scoped_lookup),
        in_expr: rewrite_expr(in_expr, scoped_lookup)
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

    %{op: :record_literal, fields: Enum.sort_by(rewritten_fields, & &1.name)}
  end

  defp rewrite_expr(%{op: :record_update, base: base, fields: fields}, lookup) do
    rewritten_fields =
      fields
      |> Enum.map(fn field -> %{field | expr: rewrite_expr(field.expr, lookup)} end)
      |> Enum.sort_by(& &1.name)

    %{op: :record_update, base: rewrite_expr(base, lookup), fields: rewritten_fields}
  end

  defp rewrite_expr(%{op: :field_access, arg: arg, field: field}, lookup) do
    rewritten_arg = rewrite_expr(arg, lookup)

    case {field, rewritten_arg} do
      {"value", %{op: :tuple2} = tuple_expr} -> %{op: :tuple_first, arg: tuple_expr}
      _ -> %{op: :field_access, arg: rewritten_arg, field: field}
    end
  end

  defp rewrite_expr(%{op: :list_literal, items: items} = expr, lookup) do
    %{expr | items: Enum.map(items || [], &rewrite_expr(&1, lookup))}
  end

  defp rewrite_expr(%{op: :case, branches: branches} = expr, lookup) do
    rewritten =
      Enum.map(branches, fn branch ->
        %{
          branch
          | pattern: rewrite_pattern(branch.pattern, lookup),
            expr: rewrite_expr(branch.expr, lookup)
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

  defp rewrite_expr(%{op: :lambda, body: body} = expr, lookup) do
    lambda_args =
      Map.get(expr, :args) || Map.get(expr, "args") || Map.get(expr, :params) ||
        Map.get(expr, "params") ||
        []

    scoped_lookup =
      Enum.reduce(lambda_args, lookup, fn arg_name, acc ->
        if is_binary(arg_name) and arg_name != "" do
          Map.update(acc, :local_call_names, MapSet.new([arg_name]), &MapSet.put(&1, arg_name))
        else
          acc
        end
      end)

    %{expr | body: rewrite_expr(body, scoped_lookup)}
  end

  defp rewrite_expr(%{op: :compose_left, f: f, g: g}, lookup) do
    # (f << g) = \x -> f(g(x))
    arg_name = "__compose_arg__"
    inner_call = %{op: :call, name: g, args: [%{op: :var, name: arg_name}]}
    outer_call = %{op: :call, name: f, args: [inner_call]}
    rewrite_expr(%{op: :lambda, args: [arg_name], body: outer_call}, lookup)
  end

  defp rewrite_expr(%{op: :compose_right, f: f, g: g}, lookup) do
    # (f >> g) = \x -> g(f(x))
    arg_name = "__compose_arg__"
    inner_call = %{op: :call, name: f, args: [%{op: :var, name: arg_name}]}
    outer_call = %{op: :call, name: g, args: [inner_call]}
    rewrite_expr(%{op: :lambda, args: [arg_name], body: outer_call}, lookup)
  end

  defp rewrite_expr(expr, _lookup), do: expr

  @spec rewrite_case_subject(expr() | String.t(), lookup()) :: expr() | String.t()
  defp rewrite_case_subject(subject, lookup) when is_map(subject),
    do: rewrite_expr(subject, lookup)

  defp rewrite_case_subject(subject, _lookup), do: subject

  @spec resolve_alias(String.t(), map()) :: String.t()
  defp resolve_alias(target, lookup) when is_binary(target) do
    alias_map = Map.get(lookup, :alias_map, %{})
    import_unqualified_map = Map.get(lookup, :import_unqualified_map, %{})
    local_call_names = Map.get(lookup, :local_call_names, MapSet.new())

    case String.split(target, ".", parts: 2) do
      [prefix, rest] ->
        case Map.get(alias_map, prefix) do
          nil -> target
          real_module -> "#{real_module}.#{rest}"
        end

      [single] ->
        if MapSet.member?(local_call_names, single) do
          target
        else
          case Map.get(import_unqualified_map, single) do
            module when is_binary(module) and module != "" ->
              "#{module}.#{single}"

            :ambiguous ->
              target

            _ ->
              target
          end
        end

      _other ->
        target
    end
  end

  defp resolve_alias(target, _lookup), do: target

  @spec build_import_resolution([map()], map()) :: {map(), map(), [String.t()]}
  defp build_import_resolution(import_entries, project_module_exports)
       when is_list(import_entries) and is_map(project_module_exports) do
    entries = ensure_default_import_entries(import_entries)

    Enum.reduce(entries, {%{}, %{}, []}, fn entry, {alias_acc, unqualified_acc, wildcard_acc} ->
      module_name = Map.get(entry, "module")
      as_name = Map.get(entry, "as")
      exposing = Map.get(entry, "exposing")

      if is_binary(module_name) and module_name != "" do
        segments = String.split(module_name, ".", trim: true)
        compact_name = Enum.join(segments, "")

        alias_acc =
          alias_acc
          |> maybe_put_alias(as_name, module_name)
          |> maybe_put_alias(compact_name, module_name)

        {unqualified_acc, wildcard_acc} =
          case exposing do
            ".." ->
              {
                register_wildcard_exports(unqualified_acc, module_name, project_module_exports),
                add_unique_string(wildcard_acc, module_name)
              }

            names when is_list(names) ->
              expanded_names =
                expand_import_exposing_names(names, module_name, project_module_exports)

              mapped =
                expanded_names
                |> Enum.filter(&is_binary/1)
                |> Enum.reduce(unqualified_acc, fn name, acc ->
                  put_unqualified_name(acc, name, module_name)
                end)

              {mapped, wildcard_acc}

            _ ->
              {unqualified_acc, wildcard_acc}
          end

        {alias_acc, unqualified_acc, wildcard_acc}
      else
        {alias_acc, unqualified_acc, wildcard_acc}
      end
    end)
  end

  defp build_import_resolution(_import_entries, _project_module_exports), do: {%{}, %{}, []}

  @spec build_project_module_exports([map()]) :: map()
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

  @spec collect_module_exports(map()) :: map()
  defp collect_module_exports(frontend_module) when is_map(frontend_module) do
    exposing = Map.get(frontend_module, :module_exposing)
    union_constructors = module_union_constructors(frontend_module)

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

    %{names: Enum.uniq(names), union_constructors: union_constructors}
  end

  defp collect_module_exports(_), do: %{names: [], union_constructors: %{}}

  @spec module_union_constructors(map()) :: map()
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

  defp module_union_constructors(_), do: %{}

  @spec expand_exposing_names([String.t()], map()) :: [String.t()]
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

  @spec union_export_names(map()) :: [String.t()]
  defp union_export_names(union_constructors) when is_map(union_constructors) do
    union_constructors
    |> Enum.flat_map(fn {type_name, constructors} -> [type_name | constructors] end)
  end

  defp union_export_names(_), do: []

  @spec type_wildcard_name(String.t()) :: String.t() | nil
  defp type_wildcard_name(name) when is_binary(name) do
    if String.ends_with?(name, "(..)"), do: String.replace_suffix(name, "(..)", ""), else: nil
  end

  defp type_wildcard_name(_), do: nil

  @spec expand_import_exposing_names([String.t()], String.t(), map()) :: [String.t()]
  defp expand_import_exposing_names(names, module_name, project_module_exports)
       when is_list(names) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{names: [], union_constructors: %{}})

    union_constructors = Map.get(module_exports, :union_constructors, %{})

    names
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil -> [name]
        type_name -> [type_name | Map.get(union_constructors, type_name, [])]
      end
    end)
  end

  defp expand_import_exposing_names(_names, _module_name, _project_module_exports), do: []

  @spec ensure_default_import_entries([map()]) :: [map()]
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

  @spec maybe_put_alias(term(), term(), term()) :: term()
  defp maybe_put_alias(map, alias_name, module_name)
       when is_map(map) and is_binary(alias_name) and alias_name != "" and is_binary(module_name) do
    Map.put_new(map, alias_name, module_name)
  end

  defp maybe_put_alias(map, _alias_name, _module_name), do: map

  @spec add_unique_string(term(), term()) :: term()
  defp add_unique_string(values, value) when is_list(values) and is_binary(value) do
    if value in values, do: values, else: values ++ [value]
  end

  defp add_unique_string(values, _value), do: values

  @spec put_unqualified_name(map(), String.t(), String.t()) :: map()
  defp put_unqualified_name(acc, name, module_name)
       when is_map(acc) and is_binary(name) and is_binary(module_name) do
    case Map.get(acc, name) do
      nil -> Map.put(acc, name, module_name)
      ^module_name -> acc
      _other_module -> Map.put(acc, name, :ambiguous)
    end
  end

  @spec register_wildcard_exports(map(), String.t(), map()) :: map()
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

  defp known_wildcard_exports("Tuple"), do: ~w(first second mapFirst mapSecond pair)
  defp known_wildcard_exports("Debug"), do: ~w(log todo toString)
  defp known_wildcard_exports(_), do: []

  @spec rewrite_pattern(map() | nil, lookup()) :: map() | nil
  defp rewrite_pattern(%{kind: :constructor, name: name} = pattern, lookup) do
    resolved_name = resolve_alias(name, lookup)
    tag = resolve_constructor_tag(resolved_name, lookup)

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

  @spec rewrite_constructor_value(String.t(), [expr()], lookup()) :: expr() | nil
  defp rewrite_constructor_value(resolved_target, rewritten_args, lookup)
       when is_binary(resolved_target) and is_list(rewritten_args) do
    tag = resolve_constructor_tag(resolved_target, lookup)

    if is_integer(tag) do
      case rewritten_args do
        [] ->
          %{op: :int_literal, value: tag}

        [arg] ->
          %{
            op: :tuple2,
            left: %{op: :int_literal, value: tag},
            right: arg
          }

        many_args ->
          %{
            op: :tuple2,
            left: %{op: :int_literal, value: tag},
            right: build_constructor_payload(many_args)
          }
      end
    end
  end

  @spec builtin_constructor_tag(String.t()) :: integer() | nil
  defp builtin_constructor_tag("Ok"), do: 1
  defp builtin_constructor_tag("Err"), do: 0
  defp builtin_constructor_tag("Just"), do: 1
  defp builtin_constructor_tag("Nothing"), do: 0
  defp builtin_constructor_tag(_), do: nil

  @spec resolve_constructor_tag(String.t(), lookup()) :: integer() | nil
  defp resolve_constructor_tag(target, lookup) when is_binary(target) do
    segments = String.split(target, ".")
    unqualified_name = List.last(segments)

    case segments do
      [_single] ->
        lookup.local[unqualified_name] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_tag(unqualified_name)

      _many ->
        lookup.qualified[target] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_tag(unqualified_name)
    end
  end

  @spec build_constructor_payload([expr()]) :: expr()
  defp build_constructor_payload([left, right]), do: %{op: :tuple2, left: left, right: right}

  defp build_constructor_payload([head | tail]) do
    %{op: :tuple2, left: head, right: build_constructor_payload(tail)}
  end

  @spec collect_constructor_arity_diagnostics([ElmEx.IR.Module.t()], map(), map()) :: [
          diagnostic()
        ]
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

  @spec collect_constructor_call_arity_diagnostics([map()], map(), map()) :: [diagnostic()]
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

  @spec expr_constructor_call_arity_diagnostics(
          expr(),
          lookup(),
          term() | nil,
          term() | nil,
          integer() | nil
        ) :: [diagnostic()]
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

  @spec resolve_constructor_arity(term(), term()) :: term()
  defp resolve_constructor_arity(target, lookup) when is_binary(target) do
    segments = String.split(target, ".")
    unqualified_name = List.last(segments)

    case segments do
      [_single] ->
        lookup.local[unqualified_name] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_arity(unqualified_name)

      _many ->
        lookup.qualified[target] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_arity(unqualified_name)
    end
  end

  @spec resolve_constructor_payload_kind(term(), term()) :: term()
  defp resolve_constructor_payload_kind(target, lookup) when is_binary(target) do
    segments = String.split(target, ".")
    unqualified_name = List.last(segments)

    case segments do
      [_single] ->
        lookup.local[unqualified_name] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_payload_kind(unqualified_name)

      _many ->
        lookup.qualified[target] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_payload_kind(unqualified_name)
    end
  end

  @spec expr_constructor_arity_diagnostics(
          expr(),
          lookup(),
          term() | nil,
          term() | nil,
          integer() | nil
        ) :: [diagnostic()]
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
          term(),
          lookup(),
          term() | nil,
          term() | nil,
          integer() | nil
        ) :: [diagnostic()]
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
