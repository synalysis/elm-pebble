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
  alias ElmEx.IR.Declaration
  alias ElmEx.IR.FunctionCallCheck
  alias ElmEx.IR.ImportResolution
  alias ElmEx.IR.Module
  alias ElmEx.IR.PipeChain

  alias ElmEx.IR.Types.{Diagnostic, Expr, Lookup, ModuleExports, Pattern}

  @typep name() :: String.t() | nil
  @typep payload_kind() :: Lookup.payload_kind()
  @typep preferences_alias_fields :: %{optional(String.t()) => [String.t()]}

  @pebble_ui_window_stack_tag 1000
  @pebble_ui_window_node_tag 1001
  @pebble_ui_canvas_layer_tag 1002

  @spec lower_project(Project.t()) :: {:ok, IR.t()}
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

        {definitions, rewrite_lookup} =
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

            {alias_map, import_unqualified_map, wildcard_import_modules, type_unqualified_map} =
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
              unqualified: global_constructor_lookup,
              qualified: global_qualified_constructor_lookup,
              payload_arity_local: local_payload_arity_lookup,
              payload_arity_unqualified: global_payload_arity_lookup,
              payload_arity_qualified: global_qualified_payload_arity_lookup,
              current_module: frontend_module.name,
              alias_map: alias_map,
              import_unqualified_map: import_unqualified_map,
              type_unqualified_map: type_unqualified_map,
              wildcard_import_modules: wildcard_import_modules,
              local_call_names: MapSet.new(Enum.map(defs, & &1.name))
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
          ports: Map.get(frontend_module, :ports, []),
          port_module: Map.get(frontend_module, :port_module, false)
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
        ) ++
        FunctionCallCheck.collect_project_diagnostics(
          project.modules,
          project_module_exports,
          project.project_dir,
          Map.get(project.elm_json, "source-directories", ["src"])
        ) ++
        collect_preferences_schema_field_order_diagnostics(project.modules)

    {:ok, %IR{modules: modules, diagnostics: diagnostics}}
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

  defp type_alias_expr(fields, field_types) when is_list(fields) and fields != [] do
    %{
      op: :record_alias,
      fields: Enum.map(fields, &to_string/1),
      field_types: normalize_record_alias_field_types(field_types)
    }
  end

  defp type_alias_expr(_fields, _field_types), do: nil

  defp normalize_record_alias_field_types(field_types) when is_map(field_types) do
    Map.new(field_types, fn {field, type} -> {to_string(field), to_string(type)} end)
  end

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

  defp rewrite_expr(%{op: :pipe_chain, steps: steps, base: base} = expr, lookup) do
    %{
      expr
      | steps: Enum.map(steps || [], &rewrite_expr(&1, lookup)),
        base: rewrite_expr(base, lookup)
    }
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

    cond do
      MapSet.member?(local_call_names, name) ->
        expr

      imported_value_reference?(name, lookup) ->
        %{op: :qualified_call, target: resolve_alias(name, lookup), args: []}

      true ->
        expr
    end
  end

  defp rewrite_expr(expr, _lookup), do: expr

  defp imported_value_reference?(name, lookup) when is_binary(name) do
    let_bound = Map.get(lookup, :let_bound_names, MapSet.new())

    not MapSet.member?(let_bound, name) and
      not constructor_reference?(name, lookup) and
      case resolve_alias(name, lookup) do
        ^name -> false
        resolved when is_binary(resolved) -> String.contains?(resolved, ".")
      end
  end

  defp put_let_bound_name(lookup, name) when is_binary(name) do
    bound = Map.get(lookup, :let_bound_names, MapSet.new())
    Map.put(lookup, :let_bound_names, MapSet.put(bound, name))
  end

  defp put_let_bound_name(lookup, _name), do: lookup

  defp extend_lookup_with_pattern(pattern, lookup) do
    Enum.reduce(pattern_bound_names(pattern), lookup, fn name, acc ->
      put_let_bound_name(acc, name)
    end)
  end

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

  defp constructor_reference?(name, lookup) when is_binary(name) do
    Map.has_key?(Map.get(lookup, :local, %{}), name) or
      Map.has_key?(Map.get(lookup, :unqualified, %{}), name)
  end

  defp apply_expr_to_arg(%{op: :qualified_call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
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

  defp apply_expr_to_operand(%{op: :qualified_call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
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

  defp canonicalize_qualified_type_aliases(type, alias_map) when is_map(alias_map) do
    alias_map
    |> Enum.sort_by(fn {alias_name, _module_name} -> -String.length(alias_name) end)
    |> Enum.reduce(type, fn {alias_name, module_name}, acc ->
      replace_type_alias_prefix(acc, alias_name, module_name)
    end)
  end

  defp canonicalize_qualified_type_aliases(type, _alias_map), do: type

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

  defp replace_type_alias_prefix(type, alias_name, module_name)
       when is_binary(type) and is_binary(alias_name) and is_binary(module_name) do
    pattern = ~r/(^|[^A-Za-z0-9_'.])#{Regex.escape(alias_name)}\./

    Regex.replace(pattern, type, fn _match, prefix ->
      "#{prefix}#{module_name}."
    end)
  end

  defp replace_unqualified_type_name(type, name, module_name)
       when is_binary(type) and is_binary(name) and is_binary(module_name) do
    pattern = ~r/(^|[^A-Za-z0-9_'.])#{Regex.escape(name)}($|[^A-Za-z0-9_'.])/

    Regex.replace(pattern, type, fn _match, prefix, suffix ->
      "#{prefix}#{module_name}.#{name}#{suffix}"
    end)
  end

  defp type_name?(<<first::utf8, _rest::binary>>) do
    first >= ?A and first <= ?Z
  end

  defp type_name?(_name), do: false

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

  @spec build_import_resolution(
          [ImportEntry.wire_map()],
          ModuleExports.project_exports()
        ) :: Lookup.import_resolution_bundle()
  defp build_import_resolution(import_entries, project_module_exports)
       when is_list(import_entries) and is_map(project_module_exports) do
    entries = ensure_default_import_entries(import_entries)

    Enum.reduce(entries, {%{}, %{}, [], %{}}, fn entry,
                                                 {alias_acc, unqualified_acc, wildcard_acc,
                                                  type_acc} ->
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

        {alias_acc, unqualified_acc, wildcard_acc, type_acc}
      else
        {alias_acc, unqualified_acc, wildcard_acc, type_acc}
      end
    end)
  end

  defp build_import_resolution(_import_entries, _project_module_exports), do: {%{}, %{}, [], %{}}

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
    if String.ends_with?(name, "(..)"), do: String.replace_suffix(name, "(..)", ""), else: nil
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

  @spec maybe_put_alias(Lookup.name_map(), String.t(), String.t()) :: Lookup.name_map()
  defp maybe_put_alias(map, alias_name, module_name)
       when is_map(map) and is_binary(alias_name) and alias_name != "" and is_binary(module_name) do
    Map.put_new(map, alias_name, module_name)
  end

  defp maybe_put_alias(map, _alias_name, _module_name), do: map

  @spec add_unique_string([String.t()], String.t()) :: [String.t()]
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

  defp known_wildcard_exports("Tuple"), do: ~w(first second mapFirst mapSecond pair)
  defp known_wildcard_exports("Debug"), do: ~w(log todo toString)
  defp known_wildcard_exports(_), do: []

  @spec rewrite_pattern(Pattern.t() | nil, Lookup.t()) :: Pattern.t() | nil
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

  @spec rewrite_constructor_value(String.t(), [Expr.t()], Lookup.t()) :: Expr.t() | nil
  defp rewrite_constructor_value(resolved_target, rewritten_args, lookup)
       when is_binary(resolved_target) and is_list(rewritten_args) do
    case rewrite_virtual_ui_constructor(resolved_target, rewritten_args, lookup) do
      nil ->
        tag = resolve_constructor_tag(resolved_target, lookup)

        if is_integer(tag) do
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
            tagged_constructor_value(tag, rewritten_args, resolved_target)
          end
        end

      rewritten ->
        rewritten
    end
  end

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
        lookup.local[unqualified_name] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_tag(unqualified_name)

      _many ->
        lookup.qualified[target] ||
          lookup.unqualified[unqualified_name] ||
          builtin_constructor_tag(unqualified_name)
    end
  end

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

  @spec resolve_constructor_payload_kind(String.t(), Lookup.constructor_t()) ::
          payload_kind() | nil
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
