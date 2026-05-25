defmodule ElmEx.CoreIR.Types.Declaration do
  @moduledoc false

  alias ElmEx.CoreIR.Types.Expr

  @type t :: %{
          required(:kind) => String.t(),
          required(:name) => String.t(),
          optional(:type) => String.t() | nil,
          required(:args) => [String.t()],
          required(:ownership) => [String.t()],
          optional(:expr) => Expr.t() | map() | nil
        }
end
