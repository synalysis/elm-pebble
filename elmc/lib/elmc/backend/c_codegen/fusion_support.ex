defmodule Elmc.Backend.CCodegen.FusionSupport do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type callee_key :: {String.t(), String.t()}
  @type callee_key_set :: MapSet.t(callee_key())
  @type var_name_set :: MapSet.t(String.t())

  @type fusion_tree_expr ::
          Types.ir_expr()
          | %{optional(atom()) => term()}
          | [fusion_tree_expr()]

  @spec ok(String.t(), [callee_key()]) :: {:ok, String.t(), [callee_key()]}
  def ok(code, runtime_callees \\ []), do: {:ok, code, runtime_callees}

  @spec ok_rc(String.t(), [callee_key()]) :: {:ok, String.t(), [callee_key()], :rc_native}
  def ok_rc(code, runtime_callees \\ []), do: {:ok, code, runtime_callees, :rc_native}

  @spec field_macro(String.t(), String.t(), String.t()) :: String.t() | nil
  def field_macro(module_name, type_name, field) do
    case Map.get(Process.get(:elmc_record_field_macros, %{}), {module_name, type_name, field}) do
      macro when is_binary(macro) ->
        macro

      _ ->
        field_macro_fallback(module_name, type_name, field)
    end
  end

  defp field_macro_fallback(module_name, type_name, field) do
    shapes = record_alias_shapes()

    case Map.get(shapes, {module_name, type_name}) do
      fields when is_list(fields) ->
        case Enum.find_index(fields, &(&1 == field)) do
          nil -> nil
          index -> Integer.to_string(index)
        end

      _ ->
        nil
    end
  end

  defp record_alias_shapes do
    case Process.get(:elmc_record_alias_shapes) do
      %{} = shapes when map_size(shapes) > 0 ->
        shapes

      _ ->
        Process.get(:elmc_record_field_types, %{})
        |> Enum.map(fn {{mod, record}, fields} ->
          field_names =
            Enum.map(fields, fn
              {name, _type} when is_binary(name) -> name
              name when is_binary(name) -> name
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)

          {{mod, record}, field_names}
        end)
        |> Map.new()
    end
  end

  @spec superseded_fusion_callee?({String.t(), String.t()}, {String.t(), String.t()}, map()) :: boolean()
  def superseded_fusion_callee?({caller_mod, caller_fun}, {callee_mod, callee_fun}, decl_map) do
    with %{expr: expr} <- Map.get(decl_map, {caller_mod, caller_fun}),
         callees when is_list(callees) <-
           Elmc.Backend.CCodegen.Fusion.runtime_callees(caller_mod, caller_fun, expr, decl_map) do
      {callee_mod, callee_fun} in callees
    else
      _ -> false
    end
  end

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

  @spec resolve_cell_count(map(), String.t(), String.t()) :: {:ok, integer()} | :error
  def resolve_cell_count(decl_map, module_name, size_var) when is_binary(size_var) do
    case Map.get(decl_map, {module_name, size_var}) do
      %{expr: %{op: :int_literal, value: value}} when is_integer(value) ->
        {:ok, value}

      %{expr: %{op: :call, name: mul, args: [%{op: :var, name: a}, %{op: :var, name: b}]}}
      when mul in ["*", "__mul__"] ->
        resolve_product(decl_map, module_name, a, b)

      %{
        expr: %{
          op: :qualified_call,
          target: "Basics.mul",
          args: [%{op: :var, name: a}, %{op: :var, name: b}]
        }
      } ->
        resolve_product(decl_map, module_name, a, b)

      _ ->
        :error
    end
  end

  @spec resolve_product(map(), String.t(), String.t(), String.t()) :: {:ok, integer()} | :error
  defp resolve_product(decl_map, module_name, a, b) do
    with {:ok, ac} <- resolve_int_constant(decl_map, module_name, a),
         {:ok, bc} <- resolve_int_constant(decl_map, module_name, b) do
      {:ok, ac * bc}
    else
      _ -> :error
    end
  end

  @spec flat_list_cell_reader?(map(), String.t(), String.t(), String.t()) :: boolean()
  def flat_list_cell_reader?(decl_map, module_name, cell_reader, cols_var) do
    case Map.get(decl_map, callee_key(module_name, cell_reader)) do
      %{expr: %{op: :if, else_expr: else_expr}} ->
        flat_list_index_uses_cols?(else_expr, cols_var)

      _ ->
        false
    end
  end

  @spec flat_list_index_uses_cols?(Types.ir_expr() | map(), String.t()) :: boolean()
  defp flat_list_index_uses_cols?(expr, cols_var) do
    case expr do
      %{op: :qualified_call, target: "Maybe.withDefault", args: [_default, index_expr]} ->
        flat_list_index_uses_cols?(index_expr, cols_var)

      %{op: :qualified_call, target: list_at, args: [index_expr, _board]}
      when is_binary(list_at) and list_at != "Maybe.withDefault" ->
        flat_list_index_uses_cols?(index_expr, cols_var)

      other ->
        case cols_from_y_mul_plus_x(other) do
          {:ok, resolved} -> resolved == cols_var
          _ -> false
        end
    end
  end

  @spec indexed_list_at_reader?(map(), String.t(), String.t()) :: boolean()
  def indexed_list_at_reader?(decl_map, module_name, list_at_target) do
    case Map.get(decl_map, callee_key(module_name, list_at_target)) do
      %{expr: %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}} ->
        index_lt_zero?(cond) and maybe_nothing?(then_expr) and nth_maybe_body?(else_expr)

      _ ->
        false
    end
  end

  @spec index_lt_zero?(Types.ir_expr() | map()) :: boolean()
  defp index_lt_zero?(%{
         op: :compare,
         left: %{op: :var, name: "index"},
         right: %{op: :int_literal, value: 0},
         kind: :lt
       }),
       do: true

  defp index_lt_zero?(%{op: :call, name: op, args: [%{op: :var, name: "index"}, %{op: :int_literal, value: 0}]})
       when op in ["__lt__", "<"],
       do: true

  defp index_lt_zero?(%{
         op: :qualified_call,
         target: op,
         args: [%{op: :var, name: "index"}, %{op: :int_literal, value: 0}]
       })
       when op in ["Basics.lt", "<"],
       do: true

  defp index_lt_zero?(_), do: false

  @spec maybe_nothing?(Types.ir_expr() | map()) :: boolean()
  defp maybe_nothing?(%{union_ctor: "Maybe.Nothing"}), do: true
  defp maybe_nothing?(%{op: :int_literal, union_ctor: "Maybe.Nothing"}), do: true
  defp maybe_nothing?(_), do: false

  @spec nth_maybe_body?(Types.ir_expr() | map()) :: boolean()
  defp nth_maybe_body?(%{
         op: :runtime_call,
         function: "elmc_list_nth_maybe",
         args: [%{op: :var, name: _list}, %{op: :var, name: _index}]
       }),
       do: true

  defp nth_maybe_body?(%{op: :qualified_call, target: "List.head", args: [drop_expr]}),
    do: list_drop_index_values?(drop_expr)

  defp nth_maybe_body?(_), do: false

  @spec list_drop_index_values?(Types.ir_expr() | map()) :: boolean()
  defp list_drop_index_values?(%{
         op: :qualified_call,
         target: target,
         args: [%{op: :var, name: _index}, %{op: :var, name: _list}]
       })
       when target in ["List.drop", "drop"],
       do: true

  defp list_drop_index_values?(%{
         op: :call,
         target: {_, "drop"},
         args: [%{op: :var, name: _index}, %{op: :var, name: _list}]
       }),
       do: true

  defp list_drop_index_values?(_), do: false

  @spec int_constant_c(map(), String.t(), String.t()) :: String.t()
  def int_constant_c(decl_map, module_name, var_name) do
    case resolve_int_constant(decl_map, module_name, var_name) do
      {:ok, value} -> "#{value} /* #{Util.escape_c_comment(var_name)} */"
      :error -> "elmc_as_int(#{Util.module_fn_name(module_name, var_name)}(NULL, 0))"
    end
  end

  @spec find_tuple2_table(map(), String.t()) :: {:ok, String.t()} | :error
  def find_tuple2_table(decl_map, module_name) do
    decl_map
    |> Enum.find_value(fn
      {{^module_name, name}, %{expr: expr}} ->
        case Tuple2CaseTable.try_emit(module_name, name, expr) do
          {:ok, _, _, _} -> name
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

  @spec cols_from_mul_cols_var(Types.ir_expr() | map()) :: {:ok, String.t()} | :error
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

  @spec board_size_expr(map(), String.t(), String.t(), String.t(), String.t()) :: String.t()
  def board_size_expr(decl_map, module_name, size_var, cols_var, rows_var) do
    case Map.get(decl_map, {module_name, size_var}) do
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

  @spec board_var?(Types.ir_expr() | map(), String.t()) :: boolean()
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

  @spec expr_var_names(fusion_tree_expr()) :: [String.t()]
  def expr_var_names(expr), do: expr_var_names(expr, MapSet.new()) |> MapSet.to_list()

  @spec sub_one_dim_vars(fusion_tree_expr()) :: [String.t()]
  def sub_one_dim_vars(expr), do: sub_one_dim_vars(expr, []) |> Enum.uniq()

  @spec sub_one_dim_vars(fusion_tree_expr(), [String.t()]) :: [String.t()]
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

  @spec grid_dim_constants(fusion_tree_expr(), map(), String.t()) ::
          {:ok, String.t(), String.t()} | :error
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

  @spec expr_var_names(fusion_tree_expr(), var_name_set()) :: var_name_set()
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

  @spec collect_call_keys(fusion_tree_expr(), String.t(), callee_key_set()) :: callee_key_set()
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
