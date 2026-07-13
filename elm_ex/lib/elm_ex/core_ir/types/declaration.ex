defmodule ElmEx.CoreIR.Types.Declaration do
  @moduledoc false

  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmEx.CoreIR.Types.Expr

  @type wire_t :: CoreIRTypes.wire_map()

  @type t :: %{
          required(:kind) => String.t(),
          required(:name) => String.t(),
          optional(:type) => String.t() | nil,
          required(:args) => [String.t()],
          required(:ownership) => [String.t()],
          optional(:expr) => Expr.t() | Expr.wire_expr() | nil
        }
end
