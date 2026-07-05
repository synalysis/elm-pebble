defmodule Elmc.Backend.CCodegen.Expr do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.RecordViewPeel
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordFieldMacros
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec record_field_expr(Types.ir_expr(), String.t()) :: Types.ir_expr() | nil
  @spec record_field_expr(nil, String.t()) :: nil
  def record_field_expr(%{op: :record_literal, fields: fields}, field) do
    fields
    |> Enum.find(&(&1.name == field))
    |> case do
      nil -> nil
      %{expr: expr} -> expr
    end
  end

  def record_field_expr(%{op: :record_update, base: base, fields: fields}, field) do
    fields
    |> Enum.find(&(&1.name == field))
    |> case do
      nil -> record_field_expr(base, field) || %{op: :field_access, arg: base, field: field}
      %{expr: expr} -> expr
    end
  end

  def record_field_expr(%{op: :qualified_call, target: target, args: args}, field)
      when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> nil
      rewritten -> record_field_expr(rewritten, field)
    end
  end

  def record_field_expr(%{op: :call, name: name, args: args}, field) when is_binary(name) do
    case Host.special_value_from_target(name, args || []) do
      nil -> nil
      rewritten -> record_field_expr(rewritten, field)
    end
  end

  def record_field_expr(%{op: :var}, _field), do: nil
  def record_field_expr(%{op: :field_access}, _field), do: nil
  def record_field_expr(_expr, _field), do: nil

  @spec substitute_expr(Types.ir_expr() | [Types.ir_expr()], Types.let_substitutions()) ::
          Types.ir_expr() | [Types.ir_expr()]
  def substitute_expr(%{op: :var, name: name}, substitutions) do
    key = Host.binding_key(name)

    case Map.fetch(substitutions, key) do
      {:ok, bound} ->
        substitute_expr(bound, Map.delete(substitutions, key))

      :error ->
        case Map.fetch(substitutions, name) do
          {:ok, bound} ->
            substitute_expr(bound, Map.delete(substitutions, name))

          :error ->
            %{op: :var, name: name}
        end
    end
  end

  def substitute_expr(%{op: :add_const, var: name, value: value}, substitutions) do
    case Map.fetch(substitutions, name) do
      {:ok, expr} ->
        %{
          op: :call,
          name: "__add__",
          args: [
            substitute_expr(expr, Map.delete(substitutions, name)),
            %{op: :int_literal, value: value}
          ]
        }

      :error ->
        %{op: :add_const, var: name, value: value}
    end
  end

  def substitute_expr(%{op: :sub_const, var: name, value: value}, substitutions) do
    case Map.fetch(substitutions, name) do
      {:ok, expr} ->
        %{
          op: :call,
          name: "__sub__",
          args: [
            substitute_expr(expr, Map.delete(substitutions, name)),
            %{op: :int_literal, value: value}
          ]
        }

      :error ->
        %{op: :sub_const, var: name, value: value}
    end
  end

  def substitute_expr(%{op: :add_vars, left: left, right: right}, substitutions) do
    left_expr = Map.get(substitutions, left, %{op: :var, name: left})
    right_expr = Map.get(substitutions, right, %{op: :var, name: right})

    %{
      op: :call,
      name: "__add__",
      args: [
        substitute_expr(left_expr, Map.delete(substitutions, left)),
        substitute_expr(right_expr, Map.delete(substitutions, right))
      ]
    }
  end

  def substitute_expr(
        %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = expr,
        substitutions
      ) do
    %{
      expr
      | value_expr: substitute_expr(value_expr, substitutions),
        in_expr: substitute_expr(in_expr, Map.delete(substitutions, name))
    }
  end

  def substitute_expr(%{op: :lambda, args: args, body: body} = expr, substitutions)
      when is_list(args) do
    scoped = Enum.reduce(args, substitutions, &Map.delete(&2, &1))
    %{expr | body: substitute_expr(body, scoped)}
  end

  def substitute_expr(%{op: :field_access, arg: arg, field: field} = expr, substitutions)
      when is_binary(arg) do
    case Map.fetch(substitutions, arg) do
      {:ok, bound} -> %{op: :field_access, arg: bound, field: field}
      :error -> expr
    end
  end

  def substitute_expr(
        %{op: :field_access, arg: %{op: :var, name: name}, field: field},
        substitutions
      ) do
    key = Host.binding_key(name)

    case Map.fetch(substitutions, key) do
      {:ok, bound} -> %{op: :field_access, arg: bound, field: field}
      :error -> %{op: :field_access, arg: %{op: :var, name: name}, field: field}
    end
  end

  def substitute_expr(%{op: :field_call, arg: arg, args: args} = expr, substitutions)
      when is_binary(arg) and is_list(args) do
    %{expr | arg: Map.get(substitutions, arg, arg), args: substitute_expr(args, substitutions)}
  end

  def substitute_expr(expr, substitutions) when is_map(expr) do
    expr
    |> Enum.map(fn {key, value} -> {key, substitute_expr(value, substitutions)} end)
    |> Map.new()
  end

  def substitute_expr(values, substitutions) when is_list(values) do
    Enum.map(values, &substitute_expr(&1, substitutions))
  end

  def substitute_expr(value, _substitutions), do: value

  @spec normalize_field_access_arg(Types.ir_expr() | Types.binding_name()) :: Types.ir_expr()
  def normalize_field_access_arg(name) when is_binary(name) or is_atom(name),
    do: %{op: :var, name: name}

  def normalize_field_access_arg(arg_expr), do: arg_expr

  @spec inline_record_field_expr(Types.ir_expr(), String.t(), Types.compile_env()) ::
          Types.ir_expr() | nil
  def inline_record_field_expr(arg_expr, field, env) do
    arg_expr = arg_expr |> Host.unwrap_affine_bindings() |> normalize_field_access_arg()

    case arg_expr do
      %{op: :var, name: name} when is_binary(name) or is_atom(name) ->
        case RecordViewPeel.field_expr(env, name, field) do
          field_expr when is_map(field_expr) -> field_expr
          _ -> inline_record_field_expr_var(arg_expr, field, env)
        end

      _ ->
        inline_record_field_expr_var(arg_expr, field, env)
    end
  end

  defp inline_record_field_expr_var(arg_expr, field, env) do
    case inline_from_let_binding(arg_expr, field, env) do
      field_expr when is_map(field_expr) ->
        field_expr

      nil ->
        if bound_record_var?(arg_expr, env) do
          nil
        else
          inline_record_field_expr_uncached(arg_expr, field, env)
        end
    end
  end

  defp inline_from_let_binding(%{op: :var, name: name}, field, env)
       when is_binary(name) or is_atom(name) do
    case EnvBindings.let_value_expr(env, name) do
      bound when is_map(bound) -> inline_record_field_expr(bound, field, env)
      _ -> nil
    end
  end

  defp inline_from_let_binding(_arg_expr, _field, _env), do: nil

  defp bound_record_var?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    bound_record_name?(env, name)
  end

  defp bound_record_var?(_arg_expr, _env), do: false

  defp bound_record_name?(env, name) do
    case EnvBindings.lookup_binding(env, name) do
      source when is_binary(source) -> true
      {:native_record, _} -> true
      _ -> false
    end
  end

  defp inline_record_field_expr_uncached(arg_expr, field, env) do
    case arg_expr do
      %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr} ->
        case {branch_field_expr(then_expr, field, env), branch_field_expr(else_expr, field, env)} do
          {then_field, else_field} when not is_nil(then_field) and not is_nil(else_field) ->
            %{op: :direct_native_if, cond: cond, then_expr: then_field, else_expr: else_field}

          _ ->
            inline_record_field_from_helper(arg_expr, field, env)
        end

      _ ->
        branch_field_expr(arg_expr, field, env) ||
          inline_record_field_from_helper(arg_expr, field, env)
    end
  end

  @spec unwrap_let_chain(Types.ir_expr(), Types.let_substitutions()) ::
          {Types.ir_expr(), Types.let_substitutions()}
  def unwrap_let_chain(
        %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
        bindings
      ) do
    unwrap_let_chain(in_expr, Map.put(bindings, name, value_expr))
  end

  def unwrap_let_chain(expr, bindings), do: {expr, bindings}

  defp branch_field_expr(branch_expr, field, _env) do
    {branch_expr, let_bindings} = unwrap_let_chain(branch_expr, %{})

    branch_expr =
      if map_size(let_bindings) > 0 do
        substitute_expr(branch_expr, let_bindings)
      else
        branch_expr
      end

    case record_field_expr(branch_expr, field) do
      nil -> nil
      field_expr -> resolve_branch_let_bindings(field_expr, let_bindings)
    end
  end

  defp resolve_branch_let_bindings(expr, let_bindings) when map_size(let_bindings) == 0,
    do: expr

  defp resolve_branch_let_bindings(%{op: :var, name: name}, let_bindings)
       when is_binary(name) or is_atom(name) do
    key = Host.binding_key(name)

    case Map.fetch(let_bindings, key) do
      {:ok, bound} -> resolve_branch_let_bindings(bound, let_bindings)
      :error -> %{op: :var, name: name}
    end
  end

  defp resolve_branch_let_bindings(%{op: :field_access, arg: arg, field: field}, let_bindings)
       when is_binary(arg) do
    case Map.fetch(let_bindings, arg) do
      {:ok, bound} -> %{op: :field_access, arg: bound, field: field}
      :error -> %{op: :field_access, arg: arg, field: field}
    end
  end

  defp resolve_branch_let_bindings(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         let_bindings
       ) do
    key = Host.binding_key(name)

    case Map.fetch(let_bindings, key) do
      {:ok, bound} -> %{op: :field_access, arg: bound, field: field}
      :error -> %{op: :field_access, arg: %{op: :var, name: name}, field: field}
    end
  end

  defp resolve_branch_let_bindings(%{op: :call, name: name, args: args}, let_bindings)
       when is_binary(name) and args in [[], nil] do
    case Map.fetch(let_bindings, name) do
      {:ok, bound} -> resolve_branch_let_bindings(bound, let_bindings)
      :error -> %{op: :call, name: name, args: []}
    end
  end

  defp resolve_branch_let_bindings(expr, let_bindings) when is_map(expr) do
    expr
    |> Map.new(fn
      {key, value} when is_list(value) ->
        {key, Enum.map(value, &resolve_branch_let_bindings(&1, let_bindings))}

      {key, value} when is_map(value) ->
        {key, resolve_branch_let_bindings(value, let_bindings)}

      {key, value} ->
        {key, value}
    end)
  end

  defp resolve_branch_let_bindings(expr, let_bindings) when is_list(expr),
    do: Enum.map(expr, &resolve_branch_let_bindings(&1, let_bindings))

  defp resolve_branch_let_bindings(expr, _let_bindings), do: expr

  defp inline_record_field_from_helper(arg_expr, field, env) do
    with target_key when not is_nil(target_key) <- record_helper_target(arg_expr, env),
         decl_map <- Map.get(env, :__program_decls__, %{}),
         %{args: arg_names, expr: expr} when is_list(arg_names) <- Map.get(decl_map, target_key),
         args <- Map.get(arg_expr, :args, []),
         true <- field_inline_args_static?(args, env),
         true <- length(arg_names) == length(args),
         substituted <- substitute_expr(expr, Map.new(Enum.zip(arg_names, args))),
         {_inner, let_bindings} <- unwrap_let_chain(substituted, %{}),
         field_expr when not is_nil(field_expr) <-
           inline_record_field_expr(substituted, field, env),
         false <- unresolved_let_ref?(field_expr, MapSet.new(Map.keys(let_bindings))) do
      field_expr
    else
      _ -> nil
    end
  end

  defp unresolved_let_ref?(%{op: :var, name: name}, let_names)
       when is_binary(name) or is_atom(name),
       do: MapSet.member?(let_names, Host.binding_key(name))

  defp unresolved_let_ref?(%{op: :field_access, arg: arg}, let_names) when is_binary(arg),
    do: MapSet.member?(let_names, arg)

  defp unresolved_let_ref?(%{op: :field_access, arg: %{op: :var, name: name}}, let_names)
       when is_binary(name) or is_atom(name),
       do: MapSet.member?(let_names, Host.binding_key(name))

  defp unresolved_let_ref?(expr, let_names) when is_map(expr) do
    Enum.any?(expr, fn
      {_key, value} when is_map(value) or is_list(value) -> unresolved_let_ref?(value, let_names)
      _ -> false
    end)
  end

  defp unresolved_let_ref?(values, let_names) when is_list(values),
    do: Enum.any?(values, &unresolved_let_ref?(&1, let_names))

  defp unresolved_let_ref?(_expr, _let_names), do: false

  defp field_inline_args_static?(args, env) when is_list(args),
    do: Enum.all?(args, &field_inline_arg_static?(&1, env))

  defp field_inline_arg_static?(%{op: :int_literal}, _env), do: true
  defp field_inline_arg_static?(%{op: :char_literal}, _env), do: true
  defp field_inline_arg_static?(%{op: :float_literal}, _env), do: true
  defp field_inline_arg_static?(%{op: :string_literal}, _env), do: true
  defp field_inline_arg_static?(%{op: :bool_literal}, _env), do: true
  defp field_inline_arg_static?(%{op: :record_literal}, _env), do: true
  defp field_inline_arg_static?(%{op: :c_int_expr}, _env), do: true

  defp field_inline_arg_static?(arg, env),
    do: Elmc.Backend.CCodegen.Native.Int.expr?(arg, env)

  @spec record_helper_target(Types.ir_expr(), Types.compile_env()) ::
          Types.function_decl_key() | nil
  def record_helper_target(%{op: :call, name: name}, env) when is_binary(name) do
    {Map.get(env, :__module__, "Main"), name}
  end

  def record_helper_target(%{op: :qualified_call, target: target}, _env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
  end

  def record_helper_target(_expr, _env), do: nil

  @spec record_shape(Types.ir_expr(), Types.compile_env()) :: Types.record_shape()
  def record_shape(%{op: :record_literal, fields: fields}, _env) when is_list(fields) do
    Enum.map(fields, & &1.name)
  end

  def record_shape(%{op: :let_in, in_expr: in_expr}, env), do: record_shape(in_expr, env)

  def record_shape(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env) do
    common_record_shape([record_shape(then_expr, env), record_shape(else_expr, env)])
  end

  def record_shape(%{op: :case, branches: branches}, env) when is_list(branches) do
    branches
    |> Enum.map(fn branch -> record_shape(Map.get(branch, :expr), env) end)
    |> common_record_shape()
  end

  def record_shape(%{op: :record_update, base: base}, env), do: record_shape(base, env)

  def record_shape(name, env) when is_binary(name) or is_atom(name) do
    record_shape(%{op: :var, name: name}, env)
  end

  def record_shape(%{op: :var, name: name}, env) do
    record_shape_for_var(env, name) ||
      subexpr_record_shape(name, env) ||
      case Map.get(env, :__var_types__, %{}) |> Map.get(name) do
        type when is_binary(type) -> record_shape_from_type(type, env)
        _ -> record_shape_for_function_return({Map.get(env, :__module__, "Main"), name}, env, 0)
      end
  end

  def record_shape(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    record_shape_for_function_return(
      {Map.get(env, :__module__, "Main"), name},
      env,
      length(args || [])
    )
  end

  def record_shape(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    normalized = Host.normalize_special_target(target)

    case Host.special_value_from_target(normalized, args || []) do
      nil ->
        normalized
        |> Host.split_qualified_function_target()
        |> record_shape_for_function_return(env, length(args || []))

      rewritten ->
        record_shape(rewritten, env)
    end
  end

  def record_shape(
        %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default, _maybe]},
        env
      ) do
    record_shape(default, env)
  end

  def record_shape(%{op: :runtime_call, function: "elmc_maybe_or_tuple_just_payload", args: [arg | _]}, env) do
    maybe_payload_record_shape(arg, env)
  end

  def record_shape(
        %{op: :runtime_call, function: "elmc_maybe_or_tuple_just_payload_borrow", args: [arg | _]},
        env
      ) do
    maybe_payload_record_shape(arg, env)
  end

  def record_shape(%{op: :field_access, arg: arg, field: field}, env) do
    case RecordFields.field_type(env, arg, field) do
      type when is_binary(type) -> record_shape_from_type(type, env)
      _ -> nil
    end
  end

  def record_shape(_expr, _env), do: nil

  defp maybe_payload_record_shape(arg, env) do
    synthetic = %{op: :runtime_call, function: "elmc_maybe_or_tuple_just_payload_borrow", args: [arg]}

    payload_type =
      case record_container_type_for_expr(synthetic, env) do
        type when is_binary(type) -> type
        _ -> Map.get(env, :__case_subject_payload_type__)
      end

    case payload_type do
      type when is_binary(type) ->
        record_shape_from_type(type, env) || record_shape(arg, env)

      _ ->
        record_shape(arg, env)
    end
  end

  defp common_record_shape([]), do: nil

  defp common_record_shape([first | rest]) when is_list(first) do
    if Enum.all?(rest, &(&1 == first)), do: first, else: nil
  end

  defp common_record_shape(_shapes), do: nil

  @spec nested_record_get_int_expr(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def nested_record_get_int_expr(%{op: :field_access, arg: arg, field: field}, env) do
    with {source, path} <- nested_field_access_path(arg, field),
         false <- zero_arg_function_binding?(env, source),
         true <- nested_field_access_path_int?(env, source, path),
         getter when is_binary(getter) <- nested_field_int_get_expr(source, path, env) do
      getter
    else
      _ -> nil
    end
  end

  def nested_record_get_int_expr(_expr, _env), do: nil

  defp zero_arg_function_binding?(env, name) when is_binary(name) do
    case EnvBindings.lookup_binding(env, name) do
      source when is_binary(source) ->
        false

      _ ->
        module_name = Map.get(env, :__module__, "Main")

        case Map.get(EnvBindings.effective_program_decls(env), {module_name, name}) do
          %{args: args} when args in [[], nil] -> true
          _ -> false
        end
    end
  end

  defp nested_field_access_path(%{op: :var, name: name}, field) when is_binary(name),
    do: {name, [field]}

  defp nested_field_access_path(name, field) when is_binary(name),
    do: {name, [field]}

  defp nested_field_access_path(%{op: :field_access, arg: arg, field: parent_field}, field) do
    case nested_field_access_path(arg, parent_field) do
      {source, path} -> {source, path ++ [field]}
      nil -> nil
    end
  end

  defp nested_field_access_path(_, _), do: nil

  defp nested_field_access_path_int?(env, source, path) do
    {final_field, intermediate_fields} = List.pop_at(path, -1)

    source
    |> build_nested_field_access(intermediate_fields)
    |> then(fn access_expr ->
      RecordFields.int_field?(env, access_expr, final_field) and
        not RecordFields.union_tag_field?(env, access_expr, final_field)
    end)
  end

  defp build_nested_field_access(source, fields) when is_binary(source) do
    Enum.reduce(fields, %{op: :var, name: source}, fn field, acc ->
      %{op: :field_access, arg: acc, field: field}
    end)
  end

  defp nested_field_int_get_expr(source, path, env) do
    {final_field, intermediate_fields} = List.pop_at(path, -1)

    getter =
      Enum.reduce(Enum.with_index(intermediate_fields), source, fn {field, idx}, cur ->
        prior = Enum.take(intermediate_fields, idx)

        case record_shape_for_path(env, source, prior) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field)) do
              nil ->
                throw(:unsupported)

              index ->
                index_ref =
                  nested_field_index_ref(env, source, prior, field, index)

                "ELMC_RECORD_GET_INDEX(#{cur}, #{index_ref})"
            end

          _ ->
            throw(:unsupported)
        end
      end)

    case record_shape_for_path(env, source, intermediate_fields) do
      fields when is_list(fields) ->
        case Enum.find_index(fields, &(&1 == final_field)) do
          nil ->
            nil

          index ->
            index_ref =
              nested_field_index_ref(
                env,
                source,
                intermediate_fields,
                final_field,
                index
              )

            "ELMC_RECORD_GET_INDEX_INT(#{getter}, #{index_ref})"
        end

      _ ->
        nil
    end
  catch
    :unsupported -> nil
  end

  defp record_shape_for_path(env, source, prior_fields) do
    source
    |> build_nested_field_access(prior_fields)
    |> then(&record_shape(&1, env))
  end

  @spec record_get_borrow_expr(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def record_get_borrow_expr(%{op: :field_access, arg: arg, field: field}, env) do
    case peeled_record_get_borrow_expr(arg, field, env) do
      ref when is_binary(ref) ->
        ref

      nil ->
        case nested_field_access_path(arg, field) do
          {source, path} -> borrow_record_field_ref(source, path, env)
          nil -> nil
        end
    end
  end

  def record_get_borrow_expr(_expr, _env), do: nil

  defp peeled_record_get_borrow_expr(arg, field, env) do
    with source_name when is_binary(source_name) <- field_access_source_name(arg),
         field_expr when is_map(field_expr) <- RecordViewPeel.field_expr(env, source_name, field),
         {:record_peel, source_ref, helper_key, helper_call} <-
           Map.get(env, source_name) || EnvBindings.lookup_binding(env, source_name) do
      peel_env = RecordViewPeel.peel_compile_env(env, helper_key, helper_call, source_ref)

      record_get_borrow_expr(normalize_field_access_expr(field_expr), peel_env)
    else
      _ -> nil
    end
  end

  defp field_access_source_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp field_access_source_name(name) when is_binary(name), do: name
  defp field_access_source_name(_), do: nil

  defp normalize_field_access_expr(%{op: :field_access} = expr), do: expr

  defp normalize_field_access_expr(%{op: :var, name: name}) when is_binary(name),
    do: %{op: :var, name: name}

  defp normalize_field_access_expr(expr) when is_map(expr), do: expr

  defp borrow_record_field_ref(source_name, path, env) do
    with source_ref when is_binary(source_ref) <- borrow_record_source_ref(source_name, env) do
      build_borrow_record_field_ref(source_ref, source_name, path, env)
    else
      _ -> nil
    end
  end

  defp borrow_record_source_ref(name, env) do
    case Map.get(env, name) do
      ref when is_binary(ref) ->
        ref

      {:native_record, _} ->
        nil

      {:forward_ref, _} ->
        nil

      _ ->
        if zero_arg_function_binding?(env, name), do: nil, else: name
    end
  end

  defp build_borrow_record_field_ref(cur_ref, source_name, path, env) do
    {final_field, intermediate_fields} = List.pop_at(path, -1)

    cur_ref =
      Enum.reduce(Enum.with_index(intermediate_fields), cur_ref, fn {field, idx}, cur ->
        prior = Enum.take(intermediate_fields, idx)

        case record_shape_for_path(env, source_name, prior) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field)) do
              nil ->
                throw(:unsupported)

              index ->
                index_ref =
                  nested_field_index_ref(env, source_name, prior, field, index)

                "ELMC_RECORD_GET_INDEX(#{cur}, #{index_ref})"
            end

          _ ->
            throw(:unsupported)
        end
      end)

    case record_shape_for_path(env, source_name, intermediate_fields) do
      fields when is_list(fields) ->
        case Enum.find_index(fields, &(&1 == final_field)) do
          nil ->
            nil

          index ->
            index_ref =
              nested_field_index_ref(
                env,
                source_name,
                intermediate_fields,
                final_field,
                index
              )

            "ELMC_RECORD_GET_INDEX(#{cur_ref}, #{index_ref})"
        end

      _ ->
        nil
    end
  catch
    :unsupported -> nil
  end

  @spec put_subexpr_record_meta(String.t(), map()) :: :ok
  def put_subexpr_record_meta(var, meta) when is_binary(var) and is_map(meta) do
    Process.put(
      :elmc_subexpr_record_meta,
      Map.put(Process.get(:elmc_subexpr_record_meta, %{}), var, meta)
    )

    :ok
  end

  @spec record_get_expr(String.t(), String.t(), Types.record_shape(), Types.compile_env(), String.t() | nil) ::
          String.t()
  def record_get_expr(source, field, shape, env \\ %{}, type \\ nil) do
    cond do
      is_list(shape) ->
        index_ref = record_field_index_ref(field, shape, type, env)
        "elmc_record_get_index(#{source}, #{index_ref})"

      field_index_ambiguous?(field, shape, type, env) and field in ["x", "y"] ->
        index_ref = if(field == "x", do: "0", else: "1")
        "elmc_record_get_index(#{source}, #{index_ref} /* #{Util.escape_c_comment(field)} */)"

      field_index_ambiguous?(field, shape, type, env) ->
        runtime_record_get_expr(source, field)

      true ->
        index_ref = record_field_index_ref(field, shape, type, env)
        "elmc_record_get_index(#{source}, #{index_ref})"
    end
  end

  defp field_index_ambiguous?(field, shape, type, env) do
    resolved_shape = shape || record_shape_from_type(type, env)

    resolved_shape == nil and infer_record_shape_from_field(field, env) == nil
  end

  defp runtime_record_get_expr(source, field) do
    "elmc_record_get(#{source}, \"#{Util.escape_c_string(field)}\")"
  end

  @spec function_decl_return_shape(Types.compile_env(), String.t(), String.t()) ::
          Types.record_shape()
  def function_decl_return_shape(env, module, name) do
    decls = Elmc.Backend.CCodegen.EnvBindings.effective_program_decls(env)

    case Map.get(decls, {module, name}) do
      %{expr: expr} -> unwrap_decl_return_record_shape(expr, env)
      _ -> nil
    end
  end

  defp unwrap_decl_return_record_shape(expr, env) do
    record_shape(expr, env) ||
      case expr do
        %{op: :let_in, in_expr: in_expr} -> unwrap_decl_return_record_shape(in_expr, env)
        _ -> nil
      end
  end

  @spec record_update_expr(String.t(), String.t(), String.t(), Types.record_shape(), keyword()) ::
          String.t()
  def record_update_expr(record_var, field, value_var, fields, opts \\ []) do
    env = Keyword.get(opts, :env, %{})
    type = Keyword.get(opts, :type)
    index_ref = record_field_index_ref(field, fields, type, env)

    update_fn =
      if Keyword.get(opts, :cow, false),
        do: "elmc_record_update_index_cow",
        else: "elmc_record_update_index"

    "#{update_fn}(#{RcRuntimeEmit.value_expr(record_var)}, #{index_ref}, #{RcRuntimeEmit.value_expr(value_var)})"
  end

  @spec record_get_int_expr(String.t(), String.t(), Types.record_shape(), Types.compile_env(), String.t() | nil) ::
          String.t()
  def record_get_int_expr(source, field, shape, env \\ %{}, type \\ nil) do
    index_ref = record_field_index_ref(field, shape, type, env)
    "ELMC_RECORD_GET_INDEX_INT(#{source}, #{index_ref})"
  end

  @spec record_field_index_ref(String.t(), Types.record_shape(), String.t() | nil, Types.compile_env()) ::
          String.t()
  def record_field_index_ref(field, shape, type, env) do
    payload_type = Map.get(env, :__case_subject_payload_type__)

    resolved_shape =
      shape ||
        record_shape_from_type(type, env) ||
        record_shape_from_type(payload_type, env) ||
        infer_record_shape_from_field(field, env)

    resolved_type = type || payload_type || record_type_for_shape(resolved_shape, env)

    RecordFieldMacros.index_ref(field, shape: resolved_shape, type: resolved_type, env: env) ||
      fallback_record_field_index(field, resolved_shape, resolved_type, env)
  end

  @spec record_shape_from_type(String.t(), Types.compile_env()) :: Types.record_shape()
  def record_shape_from_type(type, env) when is_binary(type) do
    record_shape_for_type(type, env) ||
      case maybe_inner_type(type) do
        inner when is_binary(inner) -> record_shape_for_type(inner, env)
        _ -> nil
      end
  end

  def record_shape_from_type(_type, _env), do: nil

  defp fallback_record_field_index(field, shape, type, env) do
    payload_type = Map.get(env, :__case_subject_payload_type__)

    fields =
      shape ||
        (if is_binary(payload_type), do: record_shape_from_type(payload_type, env), else: nil) ||
        if(is_binary(type), do: record_shape_from_type(type, env), else: nil) ||
        infer_record_shape_from_field(field, env)

    with fields when is_list(fields) <- fields,
         index when is_integer(index) <- Enum.find_index(fields, &(&1 == field)) do
      type_key = RecordFieldMacros.resolve_type_key(type, fields, env)
      RecordFieldMacros.format_index(index, field, type_key)
    else
      _ -> RecordFieldMacros.format_index(0, field, nil)
    end
  end

  defp infer_record_shape_from_field(field, env) when is_binary(field) do
    module = Map.get(env, :__module__, "Main")

    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    module_shapes =
      alias_shapes
      |> Enum.filter(fn {{mod, _name}, fields} -> mod == module and field in fields end)
      |> Enum.map(fn {_key, fields} -> fields end)
      |> Enum.uniq()

    case module_shapes do
      [shape] ->
        shape

      _ ->
        alias_shapes
        |> Enum.filter(fn {_key, fields} -> field in fields end)
        |> Enum.map(fn {_key, fields} -> fields end)
        |> Enum.uniq()
        |> case do
          [shape] -> shape
          _ -> nil
        end
    end
  end

  @spec maybe_unwrapped_record_type(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def maybe_unwrapped_record_type(expr, env) do
    with type when is_binary(type) <- decl_return_type(expr, env) || record_type_for_expr(expr, env),
         inner when is_binary(inner) <- maybe_inner_type(type) || type,
         fields when is_list(fields) <- record_shape_from_type(inner, env) do
      inner
    else
      _ -> nil
    end
  end

  defp decl_return_type(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    decl_return_type_for_target({Map.get(env, :__module__, "Main"), name}, length(args || []), env)
  end

  defp decl_return_type(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {module, name} -> decl_return_type_for_target({module, name}, length(args || []), env)
      _ -> nil
    end
  end

  defp decl_return_type(_expr, _env), do: nil

  defp decl_return_type_for_target(target_key, arg_count, env) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target_key) do
      %{type: type} ->
        if length(Host.function_arg_types(type)) == arg_count do
          Host.function_return_type(type) |> Host.normalize_type_name()
        end

      _ ->
        nil
    end
  end

  @spec unwrap_container_record_type(String.t()) :: String.t()
  def unwrap_container_record_type(type) when is_binary(type) do
    case maybe_inner_type(type) do
      inner when is_binary(inner) -> inner
      _ -> type
    end
  end

  defp maybe_inner_type(type) when is_binary(type) do
    case Regex.run(~r/^Maybe\s+(.+)$/s, String.trim(type)) do
      [_, inner] -> String.trim(inner)
      _ -> nil
    end
  end

  defp nested_field_index_ref(env, source_name, prior_fields, field, index) do
    container_shape = record_shape_for_path(env, source_name, prior_fields)
    container_type = record_type_for_nested_path(env, source_name, prior_fields)

    RecordFieldMacros.index_ref(field,
      shape: container_shape,
      type: container_type,
      env: env
    ) || RecordFieldMacros.format_index(index, field, nil)
  end

  @spec record_type_for_nested_path(Types.compile_env(), String.t(), [String.t()]) ::
          String.t() | nil
  def record_type_for_nested_path(env, source_name, prior_fields) do
    base_type =
      RecordFields.record_type_name(env, source_name) ||
        case Map.get(env, :__var_types__, %{}) |> Map.get(source_name) do
          type when is_binary(type) -> Host.normalize_type_name(type)
          _ -> subexpr_record_type(source_name)
        end

    Enum.reduce(prior_fields, base_type, fn field, current_type ->
      if is_binary(current_type) do
        RecordFields.lookup_field_type(current_type, field, env)
      end
    end)
  end

  defp subexpr_record_shape(name, env) do
    case subexpr_record_meta(name) do
      %{shape: shape} when is_list(shape) -> shape
      %{type: type} when is_binary(type) -> record_shape_for_type(type, env)
      _ -> nil
    end
  end

  defp subexpr_record_type(name) do
    case subexpr_record_meta(name) do
      %{type: type} when is_binary(type) -> type
      _ -> nil
    end
  end

  defp subexpr_record_meta(name) when is_binary(name) do
    Map.get(Process.get(:elmc_subexpr_record_meta, %{}), name)
  end

  @spec record_shape_for_var(Types.compile_env(), String.t()) :: Types.record_shape()
  def record_shape_for_var(env, name) when is_binary(name) do
    key = EnvBindings.binding_key(name)

    case Map.get(env, :__record_shapes__, %{}) |> Map.get(key) do
      fields when is_list(fields) ->
        fields

      _ ->
        subexpr_record_shape(name, env) ||
          case Map.get(Map.get(env, :__var_types__, %{}), key) do
            type when is_binary(type) -> record_shape_from_type(type, env)
            _ -> nil
          end
    end
  end

  @spec record_type_for_var(Types.compile_env(), String.t()) :: String.t() | nil
  def record_type_for_var(env, name) when is_binary(name) do
    Map.get(Map.get(env, :__var_types__, %{}), name) ||
      subexpr_record_type(name) ||
      case record_shape_for_var(env, name) do
        fields when is_list(fields) -> record_type_for_shape(fields, env)
        _ -> nil
      end
  end

  @spec record_payload_type_for_var(Types.compile_env(), String.t()) :: String.t() | nil
  def record_payload_type_for_var(env, name) when is_binary(name) do
    case record_type_for_var(env, name) do
      type when is_binary(type) -> maybe_inner_type(type) || type
      _ -> nil
    end
  end

  @spec record_shape_for_function_return(
          Types.qualified_function_target(),
          Types.compile_env(),
          non_neg_integer()
        ) :: Types.record_shape()
  def record_shape_for_function_return(nil, _env, _arg_count), do: nil

  def record_shape_for_function_return(target_key, env, arg_count) do
    stack = Map.get(env, :__record_shape_stack__, MapSet.new())

    if MapSet.member?(stack, {target_key, arg_count}) do
      nil
    else
      record_shape_for_function_return_uncached(target_key, env, arg_count, stack)
    end
  end

  defp record_shape_for_function_return_uncached(target_key, env, arg_count, stack) do
    decls = Elmc.Backend.CCodegen.EnvBindings.effective_program_decls(env)
    decl = Map.get(decls, target_key)
    nested_env = Map.put(env, :__record_shape_stack__, MapSet.put(stack, {target_key, arg_count}))

    cond do
      not is_map(decl) ->
        nil

      Map.has_key?(decl, :type) and length(Host.function_arg_types(decl.type)) == arg_count ->
        record_shape_for_type(Host.function_return_type(decl.type), env) ||
          record_shape_from_decl_body(decl, nested_env, arg_count)

      true ->
        record_shape_from_decl_body(decl, nested_env, arg_count)
    end
  end

  defp record_shape_from_decl_body(%{args: args, expr: expr}, env, arg_count)
       when is_list(args) do
    if length(args) == arg_count, do: record_shape(expr, env), else: nil
  end

  defp record_shape_from_decl_body(_decl, _env, _arg_count), do: nil

  defp record_shape_by_type_suffix(alias_shapes, type_name) do
    suffix = type_name |> String.split(".") |> List.last()

    alias_shapes
    |> Enum.find_value(fn
      {{_mod, ^suffix}, shape} -> shape
      _ -> nil
    end)
  end

  @spec record_shape_for_type(String.t(), Types.compile_env()) :: Types.record_shape()
  def record_shape_for_type(type, env) when is_binary(type) do
    type_name = Host.normalize_type_name(type)
    current_module = Map.get(env, :__module__, "Main")

    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    cond do
      Map.has_key?(alias_shapes, {current_module, type_name}) ->
        Map.get(alias_shapes, {current_module, type_name})

      String.contains?(type_name, ".") ->
        case split_qualified_type_name(type_name) do
          nil ->
            nil

          target_key ->
            Map.get(alias_shapes, target_key) ||
              record_shape_by_type_suffix(alias_shapes, type_name)
        end

      true ->
        record_shape_by_type_suffix(alias_shapes, type_name)
    end
  end

  def record_shape_for_type(_type, _env), do: nil

  @spec record_type_for_expr(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def record_type_for_expr(%{op: :record_literal, fields: fields}, env) when is_list(fields) do
    fields
    |> Enum.map(& &1.name)
    |> record_type_for_field_names(env)
  end

  def record_type_for_expr(%{op: :record_update, base: base}, env),
    do: record_type_for_expr(base, env)

  def record_type_for_expr(%{op: :field_access, arg: arg, field: field}, env) do
    record_container_type_for_expr(%{op: :field_access, arg: arg, field: field}, env)
  end

  def record_type_for_expr(%{op: :var, name: name}, env) do
    Map.get(Map.get(env, :__var_types__, %{}), name) ||
      subexpr_record_type(name) ||
      record_type_for_function_return({Map.get(env, :__module__, "Main"), name}, env, 0)
  end

  def record_type_for_expr(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    record_type_for_function_return(
      {Map.get(env, :__module__, "Main"), name},
      env,
      length(args || [])
    )
  end

  def record_type_for_expr(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    normalized = Host.normalize_special_target(target)

    case Host.special_value_from_target(normalized, args || []) do
      nil ->
        normalized
        |> Host.split_qualified_function_target()
        |> record_type_for_function_return(env, length(args || []))

      rewritten ->
        record_type_for_expr(rewritten, env)
    end
  end

  def record_type_for_expr(_expr, _env), do: nil

  @spec record_container_type_for_expr(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def record_container_type_for_expr(%{op: :record_literal, fields: fields}, env)
      when is_list(fields) do
    fields
    |> Enum.map(& &1.name)
    |> record_type_for_field_names(env)
  end

  def record_container_type_for_expr(%{op: :record_update, base: base}, env),
    do: record_container_type_for_expr(base, env)

  def record_container_type_for_expr(%{op: :var, name: name}, env) do
    record_payload_type_for_var(env, name) || Map.get(env, :__case_subject_payload_type__)
  end

  def record_container_type_for_expr(
        %{op: :runtime_call, function: function, args: [arg | _]},
        env
      )
      when function in [
             "elmc_maybe_or_tuple_just_payload",
             "elmc_maybe_or_tuple_just_payload_borrow"
           ] do
    case record_container_type_for_expr(arg, env) do
      type when is_binary(type) -> maybe_inner_type(type) || type
      _ -> Map.get(env, :__case_subject_payload_type__)
    end
  end

  def record_container_type_for_expr(%{op: :field_access, arg: arg, field: field}, env) do
    RecordFields.field_type(env, arg, field)
  end

  def record_container_type_for_expr(%{op: :call, name: name, args: args}, env)
      when is_binary(name) do
    record_type_for_function_return(
      {Map.get(env, :__module__, "Main"), name},
      env,
      length(args || [])
    )
  end

  def record_container_type_for_expr(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    normalized = Host.normalize_special_target(target)

    case Host.special_value_from_target(normalized, args || []) do
      nil ->
        normalized
        |> Host.split_qualified_function_target()
        |> record_type_for_function_return(env, length(args || []))

      rewritten ->
        record_container_type_for_expr(rewritten, env)
    end
  end

  def record_container_type_for_expr(_expr, _env), do: nil

  @spec record_type_for_function_return(
          Types.qualified_function_target(),
          Types.compile_env(),
          non_neg_integer()
        ) :: String.t() | nil
  def record_type_for_function_return(nil, _env, _arg_count), do: nil

  def record_type_for_function_return(target_key, env, arg_count) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target_key) do
      %{type: type} ->
        if length(Host.function_arg_types(type)) == arg_count do
          return_type = Host.function_return_type(type) |> Host.normalize_type_name()

          if record_shape_for_type(return_type, env) do
            return_type
          end
        end

      _ ->
        nil
    end
  end

  @spec record_type_for_field_names([String.t()], Types.compile_env()) :: String.t() | nil
  def record_type_for_field_names(field_names, env) when is_list(field_names) do
    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    current_module = Map.get(env, :__module__, "Main")

    case record_alias_matches(field_names, alias_shapes) do
      [] ->
        nil

      matches ->
        local_matches =
          matches
          |> Enum.filter(fn {{mod, _name}, _shape} -> mod == current_module end)
          |> Enum.map(fn {{_mod, name}, _shape} -> name end)

        case local_matches do
          [single] -> single
          [_ | _] = many -> List.first(many)
          [] -> pick_global_record_type(matches)
        end
    end
  end

  @spec record_type_for_shape(Types.record_shape(), Types.compile_env()) :: String.t() | nil
  def record_type_for_shape(fields, env) when is_list(fields) do
    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    case record_alias_matches(fields, alias_shapes) do
      [] ->
        nil

      matches ->
        case Enum.map(matches, fn {{mod, name}, _shape} -> "#{mod}.#{name}" end) do
          [single] -> single
          many -> pick_global_record_type(matches) || List.first(Enum.sort(many))
        end
    end
  end

  def record_type_for_shape(_fields, _env), do: nil

  defp record_alias_matches(field_names, alias_shapes) when is_list(field_names) do
    normalized_fields = field_names |> Enum.map(&to_string/1) |> Enum.sort()

    alias_shapes
    |> Enum.filter(fn {{_mod, _name}, shape} ->
      Enum.sort(Enum.map(shape, &to_string/1)) == normalized_fields
    end)
    |> Enum.sort_by(fn {{mod, name}, _shape} -> {mod, name} end)
  end

  defp pick_global_record_type(matches) do
    matches
    |> Enum.map(fn {{mod, name}, shape} -> {"#{mod}.#{name}", shape} end)
    |> Enum.group_by(fn {_type, shape} -> shape end)
    |> Enum.sort_by(fn {shape, _entries} -> shape end)
    |> List.first()
    |> case do
      {shape, [{type, shape} | _]} -> type
      _ -> nil
    end
  end

  @spec split_qualified_type_name(String.t()) :: Types.qualified_type_target()
  def split_qualified_type_name(type_name) when is_binary(type_name) do
    case String.split(type_name, ".") do
      [_single] ->
        nil

      parts ->
        {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}
    end
  end
end
