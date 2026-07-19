defmodule ElmEx.Test.LetExprHelpers do
  @moduledoc false

  @spec let_expr?(map()) :: boolean()
  def let_expr?(%{op: op}) when op in [:let_in, :let_bindings], do: true
  def let_expr?(_), do: false

  @spec nested_let_expr?(map()) :: boolean()
  def nested_let_expr?(%{expr: expr}), do: let_expr?(expr)
  def nested_let_expr?(_), do: false

  @spec first_binding_name(map()) :: String.t() | nil
  def first_binding_name(%{op: :let_in, name: name}), do: name

  def first_binding_name(%{op: :let_bindings, bindings: [%{kind: :name, name: name} | _]}), do: name

  def first_binding_name(%{op: :let_bindings, bindings: [%{kind: :discard} | _]}), do: "_"

  def first_binding_name(_), do: nil
end
