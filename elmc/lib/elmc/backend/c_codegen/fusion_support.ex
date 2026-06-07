defmodule Elmc.Backend.CCodegen.FusionSupport do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Util

  @type callee_key :: {String.t(), String.t()}

  @spec ok(String.t(), [callee_key()]) :: {:ok, String.t(), [callee_key()]}
  def ok(code, runtime_callees \\ []), do: {:ok, code, runtime_callees}

  @spec local_name(String.t()) :: String.t()
  def local_name(target) when is_binary(target) do
    case String.split(target, ".") do
      [single] -> single
      parts -> List.last(parts)
    end
  end

  @spec callee_key(String.t(), String.t() | map()) :: callee_key()
  def callee_key(module_name, target) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [^module_name, name] -> {module_name, name}
      [_other, name] -> {module_name, name}
      [name] -> {module_name, name}
    end
  end

  def callee_key(module_name, %{op: :qualified_call, target: target}),
    do: callee_key(module_name, target)

  def callee_key(module_name, %{op: :call, name: name}), do: {module_name, name}

  @spec resolve_int_constant(map(), String.t(), String.t()) :: {:ok, integer()} | :error
  def resolve_int_constant(decl_map, module_name, var_name) when is_binary(var_name) do
    case Map.get(decl_map, {module_name, var_name}) do
      %{expr: %{op: :int_literal, value: value}} when is_integer(value) -> {:ok, value}
      _ -> :error
    end
  end

  @spec int_constant_c(map(), String.t(), String.t()) :: String.t()
  def int_constant_c(decl_map, module_name, var_name) do
    case resolve_int_constant(decl_map, module_name, var_name) do
      {:ok, value} -> Integer.to_string(value)
      :error -> "elmc_as_int(#{Util.module_fn_name(module_name, var_name)}(NULL, 0))"
    end
  end

  @spec find_tuple2_table(map(), String.t()) :: {:ok, String.t()} | :error
  def find_tuple2_table(decl_map, module_name) do
    decl_map
    |> Enum.find_value(fn
      {{^module_name, name}, %{expr: expr}} ->
        case Tuple2CaseTable.try_emit(module_name, name, expr) do
          {:ok, _, _} -> name
          _ -> nil
        end

      _ ->
        nil
    end)
    |> case do
      nil -> :error
      name -> {:ok, name}
    end
  end

  @spec table_suffix(String.t()) :: String.t()
  def table_suffix(fn_name), do: Util.safe_c_suffix(fn_name)

  @spec table_type(String.t()) :: String.t()
  def table_type(fn_name), do: "#{table_suffix(fn_name)}_entry_t"

  @spec table_ref(String.t()) :: String.t()
  def table_ref(fn_name), do: "#{table_suffix(fn_name)}_table"

  @spec cols_from_y_mul_plus_x(map()) :: {:ok, String.t()} | :error
  def cols_from_y_mul_plus_x(%{
        op: :call,
        name: mul,
        args: [
          %{op: :call, name: inner_mul, args: [%{op: :var, name: "y"}, %{op: :var, name: cols_var}]},
          _x
        ]
      })
      when mul in ["__add__", "__iadd__"] and inner_mul in ["__mul__", "__imul__"] and
             is_binary(cols_var),
      do: {:ok, cols_var}

  def cols_from_y_mul_plus_x(%{
        op: :qualified_call,
        target: add,
        args: [
          %{op: :qualified_call, target: mul, args: [%{op: :var, name: "y"}, %{op: :var, name: cols_var}]},
          _x
        ]
      })
      when add in ["Basics.add", "+"] and mul in ["Basics.mul", "*"] and is_binary(cols_var),
      do: {:ok, cols_var}

  def cols_from_y_mul_plus_x(_), do: :error

  @add_ops ["__add__", "__iadd__", "+", "Basics.add"]
  @mul_ops ["__mul__", "__imul__", "*", "Basics.mul"]

  @spec cols_from_row_mul_plus_col(map()) :: {:ok, String.t()} | :error
  def cols_from_row_mul_plus_col(%{op: :call, name: add, args: [mul_expr, _right]})
      when add in @add_ops,
      do: cols_from_mul_cols_var(mul_expr)

  def cols_from_row_mul_plus_col(%{
        op: :qualified_call,
        target: add,
        args: [mul_expr, _right]
      })
      when add in ["Basics.add", "+"],
      do: cols_from_mul_cols_var(mul_expr)

  def cols_from_row_mul_plus_col(_), do: :error

  defp cols_from_mul_cols_var(%{op: :call, name: mul, args: [_row, %{op: :var, name: cols_var}]})
       when mul in @mul_ops and is_binary(cols_var),
       do: {:ok, cols_var}

  defp cols_from_mul_cols_var(%{
         op: :qualified_call,
         target: mul,
         args: [_row, %{op: :var, name: cols_var}]
       })
       when mul in ["Basics.mul", "*"] and is_binary(cols_var),
       do: {:ok, cols_var}

  defp cols_from_mul_cols_var(_), do: :error

  @spec rows_from_sub_one(map()) :: {:ok, String.t()} | :error
  def rows_from_sub_one(%{op: :sub_const, var: var, value: 1}) when is_binary(var), do: {:ok, var}
  def rows_from_sub_one(%{op: :add_const, var: var, value: -1}) when is_binary(var), do: {:ok, var}
  def rows_from_sub_one(_), do: :error

  @spec cols_from_sub_one(map()) :: {:ok, String.t()} | :error
  def cols_from_sub_one(%{op: :sub_const, var: var, value: 1}) when is_binary(var), do: {:ok, var}
  def cols_from_sub_one(%{op: :add_const, var: var, value: -1}) when is_binary(var), do: :error
  def cols_from_sub_one(_), do: :error

  @spec board_size_expr(map(), String.t(), String.t(), String.t()) :: String.t()
  def board_size_expr(decl_map, module_name, cols_var, rows_var) do
    case Map.get(decl_map, {module_name, "boardSize"}) do
      %{expr: %{op: :int_literal, value: value}} when is_integer(value) ->
        Integer.to_string(value)

      %{expr: %{op: :call, name: "*", args: [%{op: :var, name: ^cols_var}, %{op: :var, name: ^rows_var}]}} ->
        int_constant_c(decl_map, module_name, cols_var) <>
          " * " <> int_constant_c(decl_map, module_name, rows_var)

      %{expr: %{op: :call, name: "__mul__", args: [%{op: :var, name: ^cols_var}, %{op: :var, name: ^rows_var}]}} ->
        int_constant_c(decl_map, module_name, cols_var) <>
          " * " <> int_constant_c(decl_map, module_name, rows_var)

      _ ->
        int_constant_c(decl_map, module_name, cols_var) <>
          " * " <> int_constant_c(decl_map, module_name, rows_var)
    end
  end

  @spec five_arg_xy_board_call?(map()) :: boolean()
  def five_arg_xy_board_call?(%{op: :qualified_call, args: [x, y, _dx, _dy, board]}) do
    match?(%{op: :var, name: "x"}, x) and match?(%{op: :var, name: "y"}, y) and
      match?(%{op: :var, name: "board"}, board)
  end

  def five_arg_xy_board_call?(%{op: :call, args: [x, y, _dx, _dy, board]}) do
    match?(%{op: :var, name: "x"}, x) and match?(%{op: :var, name: "y"}, y) and
      match?(%{op: :var, name: "board"}, board)
  end

  def five_arg_xy_board_call?(_), do: false

  @spec two_arg_row_board_call?(map(), String.t()) :: boolean()
  def two_arg_row_board_call?(%{op: :qualified_call, args: [row, board]}, board_var) do
    match?(%{op: :var, name: "row"}, row) and board_var?(board, board_var)
  end

  def two_arg_row_board_call?(%{op: :call, args: [row, board]}, board_var) do
    match?(%{op: :var, name: "row"}, row) and board_var?(board, board_var)
  end

  def two_arg_row_board_call?(_, _), do: false

  defp board_var?(%{op: :var, name: name}, board_var), do: name == board_var
  defp board_var?(_, _), do: false

  @spec dim_vars_from_comparisons(map(), map(), String.t()) :: {String.t() | nil, String.t() | nil}
  def dim_vars_from_comparisons(expr, decl_map, module_name) do
    int_constants =
      expr
      |> expr_var_names()
      |> Enum.filter(fn var ->
        match?({:ok, _}, resolve_int_constant(decl_map, module_name, var))
      end)
      |> Enum.sort()

    case int_constants do
      [cols, rows | _] -> {cols, rows}
      [cols] -> {cols, nil}
      _ -> {nil, nil}
    end
  end

  @spec expr_var_names(map() | list() | any()) :: [String.t()]
  def expr_var_names(expr), do: expr_var_names(expr, MapSet.new()) |> MapSet.to_list()

  @spec sub_one_dim_vars(map() | list() | any()) :: [String.t()]
  def sub_one_dim_vars(expr), do: sub_one_dim_vars(expr, []) |> Enum.uniq()

  defp sub_one_dim_vars(%{op: :sub_const, var: var, value: 1}, acc) when is_binary(var),
    do: [var | acc]

  defp sub_one_dim_vars(%{op: :add_const, var: var, value: -1}, acc) when is_binary(var),
    do: [var | acc]

  defp sub_one_dim_vars(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn
      {key, _value}, inner_acc when key in [:span, :meta, :kind, :union_ctor] -> inner_acc
      {_key, value}, inner_acc -> sub_one_dim_vars(value, inner_acc)
    end)
  end

  defp sub_one_dim_vars(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &sub_one_dim_vars/2)

  defp sub_one_dim_vars(_other, acc), do: acc

  @spec grid_dim_constants(map(), map(), String.t()) :: {:ok, String.t(), String.t()} | :error
  def grid_dim_constants(expr, decl_map, module_name) do
    int_dims =
      expr
      |> sub_one_dim_vars()
      |> Enum.filter(fn var -> match?({:ok, _}, resolve_int_constant(decl_map, module_name, var)) end)

    case int_dims do
      [cols_var, rows_var | _] -> {:ok, cols_var, rows_var}
      _ -> :error
    end
  end

  defp expr_var_names(%{op: :var, name: name}, acc) when is_binary(name), do: MapSet.put(acc, name)

  defp expr_var_names(%{op: :call, name: name, args: []}, acc) when is_binary(name),
    do: MapSet.put(acc, name)

  defp expr_var_names(%{op: :qualified_call, target: target, args: []}, acc) when is_binary(target),
    do: MapSet.put(acc, local_name(target))

  defp expr_var_names(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn
      {key, _value}, inner_acc when key in [:span, :meta, :kind, :union_ctor] ->
        inner_acc

      {_key, value}, inner_acc ->
        expr_var_names(value, inner_acc)
    end)
  end

  defp expr_var_names(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &expr_var_names/2)

  defp expr_var_names(_other, acc), do: acc

  @spec call_name(map()) :: String.t() | nil
  def call_name(%{op: :qualified_call, target: target}), do: local_name(target)
  def call_name(%{op: :call, name: name}), do: name
  def call_name(_), do: nil

  @spec same_module_callees(map() | list() | any(), String.t()) :: [callee_key()]
  def same_module_callees(expr, module_name) do
    expr
    |> collect_call_keys(module_name, MapSet.new())
    |> MapSet.to_list()
  end

  defp collect_call_keys(%{op: :qualified_call, target: target, args: args}, module_name, acc) do
    acc = MapSet.put(acc, callee_key(module_name, target))
    Enum.reduce(args || [], acc, &collect_call_keys(&1, module_name, &2))
  end

  defp collect_call_keys(%{op: :call, name: name, args: args}, module_name, acc) when is_binary(name) do
    acc = MapSet.put(acc, {module_name, name})
    Enum.reduce(args || [], acc, &collect_call_keys(&1, module_name, &2))
  end

  defp collect_call_keys(map, module_name, acc) when is_map(map) do
    Enum.reduce(map, acc, fn
      {key, _value}, inner_acc when key in [:span, :meta, :kind, :union_ctor] -> inner_acc
      {_key, value}, inner_acc -> collect_call_keys(value, module_name, inner_acc)
    end)
  end

  defp collect_call_keys(list, module_name, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect_call_keys(&1, module_name, &2))

  defp collect_call_keys(_other, _module_name, acc), do: acc
end
