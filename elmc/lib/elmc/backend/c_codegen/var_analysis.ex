defmodule Elmc.Backend.CCodegen.VarAnalysis do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.Types

  @call_operator_names ~w(
    __add__ __sub__ __mul__ __idiv__ __fdiv__ __pow__
    __eq__ __neq__ __lt__ __lte__ __gt__ __gte__ __append__
    __apply__
    max min modBy remainderBy
  )

  @spec used_vars(Types.ir_expr() | nil) :: Types.var_name_set()
  def used_vars(nil), do: MapSet.new()

  def used_vars(%{op: :var, name: name}), do: MapSet.new([name])
  def used_vars(%{op: :float_literal}), do: MapSet.new()
  def used_vars(%{op: :field_access, arg: arg}) when is_binary(arg), do: MapSet.new([arg])
  def used_vars(%{op: :field_access, arg: arg}) when is_map(arg), do: used_vars(arg)

  def used_vars(%{op: :qualified_ref, target: target}) when is_binary(target) do
    case dotted_var_ref_root(target) do
      root when is_binary(root) -> MapSet.new([root])
      _ -> MapSet.new()
    end
  end

  def used_vars(%{op: :compose_left, f: f, g: g}), do: compose_used_vars(f, g)
  def used_vars(%{op: :compose_right, f: f, g: g}), do: compose_used_vars(f, g)
  def used_vars(%{op: :add_const, var: name}), do: MapSet.new([name])
  def used_vars(%{op: :sub_const, var: name}), do: MapSet.new([name])
  def used_vars(%{op: :add_vars, left: left, right: right}), do: MapSet.new([left, right])
  def used_vars(%{op: :sub_vars, left: left, right: right}), do: MapSet.new([left, right])
  def used_vars(%{op: :tuple_second, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :tuple_first, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :string_length, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :char_from_code, arg: arg}), do: MapSet.new([arg])
  def used_vars(%{op: :tuple_second_expr, arg: arg}), do: used_vars(arg)
  def used_vars(%{op: :tuple_first_expr, arg: arg}), do: used_vars(arg)
  def used_vars(%{op: :string_length_expr, arg: arg}), do: used_vars(arg)
  def used_vars(%{op: :char_from_code_expr, arg: arg}), do: used_vars(arg)

  def used_vars(%{op: :runtime_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :qualified_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :constructor_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :list_literal, items: items}) do
    Enum.reduce(items, MapSet.new(), fn item, acc -> MapSet.union(acc, used_vars(item)) end)
  end

  def used_vars(%{op: :call, name: "__apply__", args: args}) when is_list(args) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :call, name: name, args: args}) when is_binary(name) do
    acc = if call_name_is_var_ref?(name), do: MapSet.new([name]), else: MapSet.new()

    Enum.reduce(args, acc, fn arg, acc2 ->
      MapSet.union(acc2, used_vars(arg))
    end)
  end

  def used_vars(%{op: :call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :field_call, arg: arg, args: args}) do
    Enum.reduce(args, field_arg_vars(arg), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  def used_vars(%{op: :lambda, body: body}) do
    used_vars(body)
  end

  def used_vars(%{op: :record_literal, fields: fields}) do
    Enum.reduce(fields, MapSet.new(), fn
      %{expr: expr}, acc -> MapSet.union(acc, used_vars(expr))
      _other, acc -> acc
    end)
  end

  def used_vars(%{op: :record_update, base: base, fields: fields}) do
    Enum.reduce(fields, used_vars(base), fn
      %{expr: expr}, acc -> MapSet.union(acc, used_vars(expr))
      _other, acc -> acc
    end)
  end

  def used_vars(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}) do
    MapSet.union(used_vars(value_expr), used_vars(in_expr))
  end

  def used_vars(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}) do
    used_vars(cond_expr)
    |> MapSet.union(used_vars(then_expr))
    |> MapSet.union(used_vars(else_expr))
  end

  def used_vars(%{op: :compare, left: left, right: right}) do
    MapSet.union(used_vars(left), used_vars(right))
  end

  def used_vars(%{op: :tuple2, left: left, right: right}) do
    MapSet.union(used_vars(left), used_vars(right))
  end

  def used_vars(%{op: :case, subject: subject, branches: branches}) do
    branch_vars =
      branches
      |> Enum.map(&used_vars(&1.expr))
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    MapSet.put(branch_vars, subject)
  end

  def used_vars(%{op: op, params: params})
      when op in [:bytes_cmd, :html_cmd, :dom_sub, :browser_cmd, :json_cmd, :parser_cmd] and is_list(params) do
    Enum.reduce(params, MapSet.new(), fn param, acc ->
      MapSet.union(acc, used_vars(param))
    end)
  end

  def used_vars(_), do: MapSet.new()

  @doc """
  Free variables referenced by `body` that must be captured when lowering a
  lambda with parameters `lambda_args`.

  Unlike `used_vars/1`, respects nested-lambda boundaries (inner closures capture
  their own free vars) and case/let pattern bindings.
  """
  @spec lambda_capture_free_vars(Types.ir_expr() | nil, [String.t()]) :: Types.var_name_set()
  def lambda_capture_free_vars(body, lambda_args) do
    free_vars(body, MapSet.new(lambda_args || []), true)
  end

  @doc """
  Names referenced by `expr` that are not bound by nested `let` / `case` / lambda
  binders inside `expr`. Prefer this over `used_vars/1` for dependency analysis.
  """
  @spec free_vars(Types.ir_expr() | nil) :: Types.var_name_set()
  def free_vars(expr), do: free_vars(expr, MapSet.new(), false)

  @spec free_vars(Types.ir_expr() | nil, Types.var_name_set(), boolean()) :: Types.var_name_set()
  defp free_vars(nil, _bound, _stop_at_nested?), do: MapSet.new()

  defp free_vars(%{op: :var, name: name}, bound, _stop_at_nested?) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  # Nested closure definitions in the current lambda body capture on their own.
  # Peel curried `\a -> \b -> …` chains so let-bound locals referenced only in
  # the innermost body are still captured, but do not descend into lambdas nested
  # inside the peeled tail (if branches, call-arg closures, etc.).
  defp free_vars(%{op: :lambda, args: args, body: body}, bound, true) do
    inner_bound = MapSet.union(bound, MapSet.new(args || []))
    free_vars_peel_curried_lambda(body, inner_bound)
  end

  defp free_vars(%{op: :lambda, args: args, body: body}, bound, stop_at_nested?) do
    inner_bound = MapSet.union(bound, MapSet.new(args || []))
    free_vars(body, inner_bound, stop_at_nested?)
  end

  defp free_vars(%{op: :add_const, var: name}, bound, _stop_at_nested?) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp free_vars(%{op: :sub_const, var: name}, bound, _stop_at_nested?) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp free_vars(%{op: :add_vars, left: left, right: right}, bound, _stop_at_nested?) do
    MapSet.new([left, right])
    |> MapSet.reject(&MapSet.member?(bound, &1))
  end

  defp free_vars(%{op: :sub_vars, left: left, right: right}, bound, _stop_at_nested?) do
    MapSet.new([left, right])
    |> MapSet.reject(&MapSet.member?(bound, &1))
  end

  defp free_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound, stop_at_nested?) do
    MapSet.union(
      free_vars(value_expr, bound, stop_at_nested?),
      free_vars(in_expr, MapSet.put(bound, name), stop_at_nested?)
    )
  end

  defp free_vars(%{op: :case, subject: subject, branches: branches}, bound, stop_at_nested?) do
    subject_free = free_vars_subject(subject, bound, stop_at_nested?)

    branch_free =
      Enum.reduce(branches, MapSet.new(), fn branch, acc ->
        pattern = Map.get(branch, :pattern, %{})
        arm_bound = MapSet.union(bound, MapSet.new(pattern_bound_names(pattern)))
        MapSet.union(acc, free_vars(Map.get(branch, :expr), arm_bound, stop_at_nested?))
      end)

    MapSet.union(subject_free, branch_free)
  end

  defp free_vars(%{op: :field_access, arg: arg}, bound, stop_at_nested?) do
    free_vars_value(arg, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :qualified_ref, target: target}, bound, stop_at_nested?) when is_binary(target) do
    case dotted_var_ref_root(target) do
      root when is_binary(root) -> free_vars_subject(root, bound, stop_at_nested?)
      _ -> MapSet.new()
    end
  end

  defp free_vars(%{op: :qualified_call, args: args}, bound, stop_at_nested?) when is_list(args) do
    free_vars_args(args, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :constructor_call, args: args}, bound, stop_at_nested?) when is_list(args) do
    free_vars_args(args, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :partial_constructor, args: args}, bound, stop_at_nested?) when is_list(args) do
    free_vars_args(args, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :runtime_call, args: args}, bound, stop_at_nested?) when is_list(args) do
    free_vars_args(args, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :list_literal, items: items}, bound, stop_at_nested?) when is_list(items) do
    free_vars_args(items, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :call, name: name, args: args}, bound, stop_at_nested?)
       when is_binary(name) and is_list(args) do
    name_free =
      if call_name_is_var_ref?(name) do
        free_vars_subject(name, bound, stop_at_nested?)
      else
        MapSet.new()
      end

    MapSet.union(name_free, free_vars_args(args, bound, stop_at_nested?))
  end

  defp free_vars(%{op: :call, args: args}, bound, stop_at_nested?) when is_list(args) do
    free_vars_args(args, bound, stop_at_nested?)
  end

  defp free_vars(%{op: :field_call, arg: arg, args: args}, bound, stop_at_nested?) when is_list(args) do
    MapSet.union(free_vars_value(arg, bound, stop_at_nested?), free_vars_args(args, bound, stop_at_nested?))
  end

  defp free_vars(%{op: :record_literal, fields: fields}, bound, stop_at_nested?) when is_list(fields) do
    Enum.reduce(fields, MapSet.new(), fn
      %{expr: expr}, acc -> MapSet.union(acc, free_vars(expr, bound, stop_at_nested?))
      _other, acc -> acc
    end)
  end

  defp free_vars(%{op: :record_update, base: base, fields: fields}, bound, stop_at_nested?) do
    Enum.reduce(fields || [], free_vars_value(base, bound, stop_at_nested?), fn
      %{expr: expr}, acc -> MapSet.union(acc, free_vars(expr, bound, stop_at_nested?))
      _other, acc -> acc
    end)
  end

  defp free_vars(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}, bound, stop_at_nested?) do
    free_vars(cond_expr, bound, stop_at_nested?)
    |> MapSet.union(free_vars(then_expr, bound, stop_at_nested?))
    |> MapSet.union(free_vars(else_expr, bound, stop_at_nested?))
  end

  defp free_vars(%{op: :compare, left: left, right: right}, bound, stop_at_nested?) do
    MapSet.union(free_vars(left, bound, stop_at_nested?), free_vars(right, bound, stop_at_nested?))
  end

  defp free_vars(%{op: :tuple2, left: left, right: right}, bound, stop_at_nested?) do
    MapSet.union(free_vars(left, bound, stop_at_nested?), free_vars(right, bound, stop_at_nested?))
  end

  defp free_vars(%{op: op, params: params}, bound, stop_at_nested?)
       when op in [:bytes_cmd, :html_cmd, :dom_sub, :browser_cmd, :json_cmd, :parser_cmd] and
              is_list(params) do
    free_vars_args(params, bound, stop_at_nested?)
  end

  defp free_vars(%{op: _op}, _bound, _stop_at_nested?), do: MapSet.new()

  defp free_vars(expr, bound, stop_at_nested?) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn value, acc ->
      MapSet.union(acc, free_vars_value(value, bound, stop_at_nested?))
    end)
  end

  defp free_vars(_, _bound, _stop_at_nested?), do: MapSet.new()

  @spec free_vars_subject(String.t() | map() | term(), Types.var_name_set(), boolean()) ::
          Types.var_name_set()
  defp free_vars_subject(name, bound, _stop_at_nested?) when is_binary(name) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp free_vars_subject(expr, bound, stop_at_nested?) when is_map(expr),
    do: free_vars(expr, bound, stop_at_nested?)

  defp free_vars_subject(_, _, _stop_at_nested?), do: MapSet.new()

  @spec free_vars_value(map() | String.t() | list() | term(), Types.var_name_set(), boolean()) ::
          Types.var_name_set()
  defp free_vars_value(value, bound, stop_at_nested?) when is_map(value),
    do: free_vars(value, bound, stop_at_nested?)

  defp free_vars_value(value, bound, stop_at_nested?) when is_binary(value),
    do: free_vars_subject(value, bound, stop_at_nested?)

  defp free_vars_value(values, bound, stop_at_nested?) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, free_vars_value(value, bound, stop_at_nested?))
    end)
  end

  defp free_vars_value(_, _, _stop_at_nested?), do: MapSet.new()

  @spec free_vars_args([term()], Types.var_name_set(), boolean()) :: Types.var_name_set()
  defp free_vars_args(args, bound, stop_at_nested?) when is_list(args) do
    free_vars_call_args(args, bound, stop_at_nested?)
  end

  @spec free_vars_call_args([term()], Types.var_name_set(), boolean()) :: Types.var_name_set()
  defp free_vars_call_args(args, bound, stop_at_nested?) when is_list(args) do
    Enum.reduce(args, MapSet.new(), fn arg, acc ->
      MapSet.union(acc, free_vars_call_arg(arg, bound, stop_at_nested?))
    end)
  end

  @spec free_vars_call_arg(term(), Types.var_name_set(), boolean()) :: Types.var_name_set()
  defp free_vars_call_arg(%{op: :lambda, args: inner_args, body: body}, bound, _stop_at_nested?) do
    inner_bound = MapSet.union(bound, MapSet.new(inner_args || []))
    free_vars(body, inner_bound, true)
  end

  defp free_vars_call_arg(expr, bound, stop_at_nested?) do
    free_vars(expr, bound, stop_at_nested?)
  end

  @spec free_vars_peel_curried_lambda(term(), Types.var_name_set()) :: Types.var_name_set()
  defp free_vars_peel_curried_lambda(%{op: :lambda, args: args, body: body}, bound) do
    inner_bound = MapSet.union(bound, MapSet.new(args || []))
    free_vars_peel_curried_lambda(body, inner_bound)
  end

  defp free_vars_peel_curried_lambda(expr, bound) when is_map(expr) do
    free_vars(expr, bound, true)
  end

  defp free_vars_peel_curried_lambda(_, _bound), do: MapSet.new()

  @spec pattern_bound_names(term()) :: [String.t()]
  defp pattern_bound_names(%{kind: :var, name: name}) when is_binary(name), do: [name]

  defp pattern_bound_names(%{kind: :constructor, bind: bind}) when is_binary(bind), do: [bind]

  defp pattern_bound_names(%{kind: :constructor, arg_pattern: arg_pattern}) when is_map(arg_pattern),
    do: pattern_bound_names(arg_pattern)

  defp pattern_bound_names(%{kind: :tuple, elements: elements}) when is_list(elements),
    do: Enum.flat_map(elements, &pattern_bound_names/1)

  defp pattern_bound_names(%{kind: :record, fields: fields, bind: bind}) when is_list(fields) do
    field_names = Enum.flat_map(fields, &pattern_bound_names/1)
    if is_binary(bind), do: [bind | field_names], else: field_names
  end

  defp pattern_bound_names(_), do: []

  @spec field_arg_vars(Types.ir_expr() | String.t()) :: Types.var_name_set()
  defp field_arg_vars(arg) when is_binary(arg), do: MapSet.new([arg])
  defp field_arg_vars(arg) when is_map(arg), do: used_vars(arg)
  defp field_arg_vars(_arg), do: MapSet.new()

  @spec compose_used_vars(Types.ir_expr() | String.t(), Types.ir_expr() | String.t()) ::
          Types.var_name_set()
  defp compose_used_vars(f, g) do
    MapSet.union(compose_side_vars(f), compose_side_vars(g))
  end

  @spec compose_side_vars(Types.ir_expr() | String.t()) :: Types.var_name_set()
  defp compose_side_vars(name) when is_binary(name), do: MapSet.new([name])
  defp compose_side_vars(expr) when is_map(expr), do: used_vars(expr)
  defp compose_side_vars(_), do: MapSet.new()

  @spec call_name_is_var_ref?(String.t()) :: boolean()
  defp call_name_is_var_ref?(name) when is_binary(name) do
    name not in @call_operator_names and not String.starts_with?(name, "__")
  end

  # Record field chains lowered to qualified_ref (e.g. hull.lo.x) are not module paths.
  @spec dotted_var_ref_root(String.t()) :: String.t() | nil
  defp dotted_var_ref_root(target) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [root, _rest] when root != "" -> if var_like_root?(root), do: root, else: nil
      _ -> nil
    end
  end

  @spec var_like_root?(String.t()) :: boolean()
  defp var_like_root?(root) when is_binary(root) do
    case root do
      <<first::utf8, _::binary>> -> first in ?a..?z or first in ?_..?_
      _ -> false
    end
  end
end
