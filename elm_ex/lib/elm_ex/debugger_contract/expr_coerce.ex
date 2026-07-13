defmodule ElmEx.DebuggerContract.ExprCoerce do
  @moduledoc false

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes

  @known_ops ~w(
    call qualified_call qualified_call1 constructor_call list_literal
    let_in case if var expr int_literal string_literal float_literal bool_literal char_literal
    lambda tuple2 tuple_expr field_access record_literal record_update
    add_const sub_const add_vars compare unsupported
    tuple_first_expr tuple_second_expr if_expr
  )a

  @field_keys ~w(
    name target args items subject branches pattern expr cond then_expr else_expr
    in_expr value_expr left right kind fields bind arg_pattern constructors type elements
    module as exposing
  )

  @string_keys Map.new(@field_keys, fn k -> {k, String.to_atom(k)} end)

  @spec to_ast(AstTypes.invalid_input()) :: AstTypes.expr() | AstTypes.invalid_input()
  @spec to_ast(list()) :: list()
  def to_ast(%{} = map), do: coerce_map(map)
  def to_ast(list) when is_list(list), do: Enum.map(list, &to_ast/1)
  def to_ast(other), do: other

  @spec coerce_map(AstTypes.invalid_input()) :: AstTypes.expr()
  defp coerce_map(map) do
    Map.new(map, fn {k, v} ->
      key = coerce_key(k)
      {key, if(key == :op, do: coerce_op(v), else: to_ast(v))}
    end)
  end

  @spec coerce_key(String.t() | atom()) :: atom() | String.t()
  defp coerce_key("op"), do: :op
  defp coerce_key(k) when is_binary(k), do: Map.get(@string_keys, k, k)

  defp coerce_key(k) when is_atom(k), do: k

  @spec coerce_op(String.t() | atom()) :: atom()
  defp coerce_op(v) when is_binary(v) do
    op = String.to_atom(v)

    if op in @known_ops do
      op
    else
      :unsupported
    end
  end

  defp coerce_op(v) when is_atom(v), do: v
  defp coerce_op(_), do: :unsupported
end
