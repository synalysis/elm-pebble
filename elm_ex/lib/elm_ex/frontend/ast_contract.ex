defmodule ElmEx.Frontend.AstContract do
  @moduledoc """
  Validates invariants of the frontend AST contract consumed by lowering/codegen.
  """

  alias ElmEx.Frontend.Module

  @spec validate_module(Module.t()) :: :ok | {:error, map()}
  def validate_module(%Module{} = module) do
    with :ok <- validate_module_name(module.name),
         :ok <- validate_imports(module.imports),
         :ok <- validate_declarations(module.declarations) do
      :ok
    end
  end

  @spec validate_module_name(term()) :: :ok | {:error, atom()}
  defp validate_module_name(name) when is_binary(name) and name != "", do: :ok

  defp validate_module_name(_),
    do: {:error, %{kind: :ast_contract_error, reason: :invalid_module_name}}

  @spec validate_imports(term()) :: :ok | {:error, atom()}
  defp validate_imports(imports) when is_list(imports) do
    if Enum.all?(imports, &(is_binary(&1) and &1 != "")) do
      :ok
    else
      {:error, %{kind: :ast_contract_error, reason: :invalid_imports}}
    end
  end

  defp validate_imports(_), do: {:error, %{kind: :ast_contract_error, reason: :invalid_imports}}

  @spec validate_declarations(term()) :: :ok | {:error, map()}
  defp validate_declarations(declarations) when is_list(declarations) do
    declarations
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {decl, index}, :ok ->
      case validate_declaration(decl) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error, %{kind: :ast_contract_error, declaration_index: index, reason: reason}}}
      end
    end)
  end

  defp validate_declarations(_),
    do: {:error, %{kind: :ast_contract_error, reason: :declarations_must_be_list}}

  @spec validate_declaration(map()) :: :ok | {:error, atom() | map()}
  defp validate_declaration(%{
         kind: :function_definition,
         name: name,
         args: args,
         expr: expr,
         span: span
       }) do
    with :ok <- validate_non_empty_binary(name, :invalid_function_name),
         :ok <- validate_function_args(args),
         :ok <- validate_span(span),
         :ok <- validate_expr(expr) do
      :ok
    end
  end

  defp validate_declaration(%{kind: :function_signature, name: name, type: type, span: span}) do
    with :ok <- validate_non_empty_binary(name, :invalid_signature_name),
         :ok <- validate_non_empty_binary(type, :invalid_signature_type),
         :ok <- validate_span(span) do
      :ok
    end
  end

  defp validate_declaration(%{kind: :type_alias, name: name, span: span}) do
    with :ok <- validate_non_empty_binary(name, :invalid_type_alias_name),
         :ok <- validate_span(span) do
      :ok
    end
  end

  defp validate_declaration(%{kind: :union, name: name, constructors: constructors, span: span}) do
    with :ok <- validate_non_empty_binary(name, :invalid_union_name),
         :ok <- validate_span(span),
         :ok <- validate_union_constructors(constructors) do
      :ok
    end
  end

  defp validate_declaration(%{kind: kind})
       when kind in [:function_definition, :function_signature, :type_alias, :union],
       do: {:error, :invalid_declaration_shape}

  defp validate_declaration(_), do: {:error, :unknown_declaration_kind}

  @spec validate_non_empty_binary(term(), atom()) :: :ok | {:error, atom()}
  defp validate_non_empty_binary(value, _reason) when is_binary(value) and value != "", do: :ok
  defp validate_non_empty_binary(_value, reason), do: {:error, reason}

  @spec validate_function_args(term()) :: :ok | {:error, atom()}
  defp validate_function_args(args) when is_list(args) do
    if Enum.all?(args, &(is_binary(&1) and &1 != "")) do
      :ok
    else
      {:error, :invalid_function_args}
    end
  end

  defp validate_function_args(_), do: {:error, :invalid_function_args}

  @spec validate_span(term()) :: :ok | {:error, atom()}
  defp validate_span(%{start_line: start_line, end_line: end_line})
       when is_integer(start_line) and is_integer(end_line) and start_line > 0 and
              end_line >= start_line,
       do: :ok

  defp validate_span(_), do: {:error, :invalid_span}

  @spec validate_union_constructors(term()) :: :ok | {:error, atom()}
  defp validate_union_constructors(constructors) when is_list(constructors) do
    if Enum.all?(constructors, &valid_union_constructor?/1) do
      :ok
    else
      {:error, :invalid_union_constructors}
    end
  end

  defp validate_union_constructors(_), do: {:error, :invalid_union_constructors}

  @spec valid_union_constructor?(term()) :: boolean()
  defp valid_union_constructor?(%{name: name, arg: arg})
       when is_binary(name) and name != "" and (is_nil(arg) or (is_binary(arg) and arg != "")),
       do: true

  defp valid_union_constructor?(_), do: false

  @spec validate_expr(term()) :: :ok | {:error, atom()}
  defp validate_expr(expr) when is_map(expr) do
    case expr[:op] do
      nil ->
        {:error, :missing_expr_op}

      :int_literal ->
        if(is_integer(expr[:value]), do: :ok, else: {:error, :invalid_int_literal})

      :string_literal ->
        validate_non_empty_or_empty_binary(expr[:value], :invalid_string_literal)

      :char_literal ->
        if(is_integer(expr[:value]), do: :ok, else: {:error, :invalid_char_literal})

      :float_literal ->
        validate_float_literal(expr)

      :var ->
        validate_non_empty_binary(expr[:name], :invalid_var_expr)

      :cmd_none ->
        :ok

      :add_const ->
        validate_add_const(expr)

      :add_vars ->
        validate_add_vars(expr)

      :sub_const ->
        validate_sub_const(expr)

      :compare ->
        validate_compare(expr)

      :tuple2 ->
        validate_tuple2(expr)

      :list_literal ->
        validate_list_literal(expr)

      :call ->
        validate_call_like(expr[:name], expr[:args], :invalid_call_expr)

      :qualified_call ->
        validate_call_like(expr[:target], expr[:args], :invalid_qualified_call_expr)

      :constructor_call ->
        validate_call_like(expr[:target], expr[:args], :invalid_constructor_call_expr)

      :field_access ->
        validate_field_access(expr)

      :field_call ->
        validate_field_call(expr)

      :compose_left ->
        validate_compose(expr, :invalid_compose_left_expr)

      :compose_right ->
        validate_compose(expr, :invalid_compose_right_expr)

      :lambda ->
        validate_lambda(expr)

      :let_in ->
        validate_let_in(expr)

      :if ->
        validate_if_expr(expr)

      :case ->
        validate_case_expr(expr)

      :record_literal ->
        validate_record_literal(expr)

      :record_update ->
        validate_record_update(expr)

      :tuple_first_expr ->
        validate_unary_wrapped_expr(expr, :arg)

      :tuple_second_expr ->
        validate_unary_wrapped_expr(expr, :arg)

      :string_length_expr ->
        validate_unary_wrapped_expr(expr, :arg)

      :char_from_code_expr ->
        validate_unary_wrapped_expr(expr, :arg)

      :unsupported ->
        validate_non_empty_or_empty_binary(expr[:source], :invalid_unsupported_expr)

      _ ->
        {:error, :unknown_expr_op}
    end
  end

  defp validate_expr(_), do: {:error, :invalid_function_expr}

  @spec validate_non_empty_or_empty_binary(term(), atom()) :: :ok | {:error, atom()}
  defp validate_non_empty_or_empty_binary(value, _reason) when is_binary(value), do: :ok
  defp validate_non_empty_or_empty_binary(_value, reason), do: {:error, reason}

  @spec validate_float_literal(term()) :: :ok | {:error, atom()}
  defp validate_float_literal(%{value: value}) when is_float(value) or is_integer(value), do: :ok
  defp validate_float_literal(_), do: {:error, :invalid_float_literal}

  @spec validate_add_const(term()) :: :ok | {:error, atom()}
  defp validate_add_const(%{var: var, value: value}) when is_binary(var) and is_integer(value),
    do: :ok

  defp validate_add_const(_), do: {:error, :invalid_add_const}

  @spec validate_add_vars(term()) :: :ok | {:error, atom()}
  defp validate_add_vars(%{left: left, right: right}) when is_binary(left) and is_binary(right),
    do: :ok

  defp validate_add_vars(_), do: {:error, :invalid_add_vars}

  @spec validate_sub_const(term()) :: :ok | {:error, atom()}
  defp validate_sub_const(%{var: var, value: value}) when is_binary(var) and is_integer(value),
    do: :ok

  defp validate_sub_const(_), do: {:error, :invalid_sub_const}

  @spec validate_compare(term()) :: :ok | {:error, atom()}
  defp validate_compare(%{left: left, right: right, kind: kind})
       when kind in [:eq, :neq, :gt, :gte, :lt, :lte] do
    with :ok <- validate_expr(left),
         :ok <- validate_expr(right) do
      :ok
    end
  end

  defp validate_compare(_), do: {:error, :invalid_compare_expr}

  @spec validate_tuple2(term()) :: :ok | {:error, atom()}
  defp validate_tuple2(%{left: left, right: right}) do
    with :ok <- validate_expr(left),
         :ok <- validate_expr(right) do
      :ok
    end
  end

  defp validate_tuple2(_), do: {:error, :invalid_tuple_expr}

  @spec validate_list_literal(term()) :: :ok | {:error, atom()}
  defp validate_list_literal(%{items: items}) when is_list(items) do
    validate_expr_list(items, :invalid_list_literal)
  end

  defp validate_list_literal(_), do: {:error, :invalid_list_literal}

  @spec validate_call_like(term(), term(), atom()) :: :ok | {:error, atom()}
  defp validate_call_like(name_or_target, args, reason) do
    with :ok <- validate_non_empty_binary(name_or_target, reason),
         :ok <- validate_expr_list(args || [], reason) do
      :ok
    end
  end

  @spec validate_field_access(term()) :: :ok | {:error, atom()}
  defp validate_field_access(%{arg: arg, field: field}) when is_binary(arg) and is_binary(field),
    do: :ok

  defp validate_field_access(%{arg: arg, field: field}) when is_map(arg) and is_binary(field),
    do: validate_expr(arg)

  defp validate_field_access(_), do: {:error, :invalid_field_access_expr}

  @spec validate_field_call(term()) :: :ok | {:error, atom()}
  defp validate_field_call(%{arg: arg, field: field, args: args})
       when is_binary(arg) and is_binary(field) and is_list(args),
       do: validate_expr_list(args, :invalid_field_call_expr)

  defp validate_field_call(_), do: {:error, :invalid_field_call_expr}

  @spec validate_compose(term(), atom()) :: :ok | {:error, atom()}
  defp validate_compose(%{f: f, g: g}, _reason)
       when is_binary(f) and f != "" and is_binary(g) and g != "",
       do: :ok

  defp validate_compose(_, reason), do: {:error, reason}

  @spec validate_lambda(term()) :: :ok | {:error, atom()}
  defp validate_lambda(%{args: args, body: body}) when is_list(args) do
    with :ok <- validate_function_args(args),
         :ok <- validate_expr(body) do
      :ok
    end
  end

  defp validate_lambda(_), do: {:error, :invalid_lambda_expr}

  @spec validate_let_in(term()) :: :ok | {:error, atom()}
  defp validate_let_in(%{name: name, value_expr: value_expr, in_expr: in_expr}) do
    with :ok <- validate_non_empty_binary(name, :invalid_let_name),
         :ok <- validate_expr(value_expr),
         :ok <- validate_expr(in_expr) do
      :ok
    end
  end

  defp validate_let_in(_), do: {:error, :invalid_let_expr}

  @spec validate_if_expr(term()) :: :ok | {:error, atom()}
  defp validate_if_expr(%{cond: cond_expr, then_expr: then_expr, else_expr: else_expr}) do
    with :ok <- validate_expr(cond_expr),
         :ok <- validate_expr(then_expr),
         :ok <- validate_expr(else_expr) do
      :ok
    end
  end

  defp validate_if_expr(_), do: {:error, :invalid_if_expr}

  @spec validate_case_expr(term()) :: :ok | {:error, atom()}
  defp validate_case_expr(%{subject: subject, branches: branches}) when is_list(branches) do
    with :ok <- validate_case_subject(subject) do
      if Enum.all?(branches, &valid_case_branch?/1) do
        :ok
      else
        {:error, :invalid_case_branches}
      end
    end
  end

  defp validate_case_expr(_), do: {:error, :invalid_case_expr}

  @spec validate_case_subject(term()) :: :ok | {:error, atom()}
  defp validate_case_subject(subject) when is_binary(subject), do: :ok
  defp validate_case_subject(subject) when is_map(subject), do: validate_expr(subject)
  defp validate_case_subject(_), do: {:error, :invalid_case_expr}

  @spec valid_case_branch?(term()) :: boolean()
  defp valid_case_branch?(%{pattern: pattern, expr: expr}) do
    with :ok <- validate_pattern(pattern),
         :ok <- validate_expr(expr) do
      true
    else
      _ -> false
    end
  end

  defp valid_case_branch?(_), do: false

  @spec validate_pattern(term()) :: :ok | {:error, atom()}
  defp validate_pattern(%{kind: :wildcard}), do: :ok
  defp validate_pattern(%{kind: :var, name: name}) when is_binary(name) and name != "", do: :ok
  defp validate_pattern(%{kind: :unknown, source: source}) when is_binary(source), do: :ok

  defp validate_pattern(%{kind: :tuple, elements: elements}) when is_list(elements) do
    if Enum.all?(elements, &(validate_pattern(&1) == :ok)) do
      :ok
    else
      {:error, :invalid_tuple_pattern}
    end
  end

  defp validate_pattern(%{kind: :constructor, name: name} = pattern)
       when is_binary(name) and name != "" do
    bind_valid = is_nil(pattern[:bind]) or (is_binary(pattern[:bind]) and pattern[:bind] != "")

    arg_pattern_valid =
      is_nil(pattern[:arg_pattern]) or
        (is_map(pattern[:arg_pattern]) and validate_pattern(pattern[:arg_pattern]) == :ok)

    if bind_valid and arg_pattern_valid do
      :ok
    else
      {:error, :invalid_constructor_pattern}
    end
  end

  defp validate_pattern(%{kind: :int, value: value}) when is_integer(value), do: :ok
  defp validate_pattern(%{kind: :string, value: value}) when is_binary(value), do: :ok

  defp validate_pattern(%{kind: :record, fields: fields} = pattern) when is_list(fields) do
    fields_valid = Enum.all?(fields, &(is_binary(&1) and &1 != ""))
    bind_valid = is_nil(pattern[:bind]) or (is_binary(pattern[:bind]) and pattern[:bind] != "")

    if fields_valid and bind_valid do
      :ok
    else
      {:error, :invalid_record_pattern}
    end
  end

  defp validate_pattern(_), do: {:error, :invalid_pattern}

  @spec validate_record_literal(term()) :: :ok | {:error, atom()}
  defp validate_record_literal(%{fields: fields}) when is_list(fields) do
    if Enum.all?(fields, &valid_record_field?/1) do
      :ok
    else
      {:error, :invalid_record_literal}
    end
  end

  defp validate_record_literal(_), do: {:error, :invalid_record_literal}

  @spec validate_record_update(term()) :: :ok | {:error, atom()}
  defp validate_record_update(%{base: base, fields: fields}) when is_list(fields) do
    with :ok <- validate_expr(base) do
      if Enum.all?(fields, &valid_record_field?/1) do
        :ok
      else
        {:error, :invalid_record_update}
      end
    end
  end

  defp validate_record_update(_), do: {:error, :invalid_record_update}

  @spec valid_record_field?(term()) :: boolean()
  defp valid_record_field?(%{name: name, expr: expr}) when is_binary(name) and is_map(expr) do
    validate_expr(expr) == :ok
  end

  defp valid_record_field?(_), do: false

  @spec validate_unary_wrapped_expr(term(), atom()) :: :ok | {:error, atom()}
  defp validate_unary_wrapped_expr(expr, key) when is_map(expr) do
    case expr[key] do
      child when is_map(child) -> validate_expr(child)
      _ -> {:error, :invalid_unary_expr}
    end
  end

  @spec validate_expr_list(term(), atom()) :: :ok | {:error, atom()}
  defp validate_expr_list(items, reason) when is_list(items) do
    if Enum.all?(items, &(validate_expr(&1) == :ok)) do
      :ok
    else
      {:error, reason}
    end
  end

  defp validate_expr_list(_items, reason), do: {:error, reason}
end
