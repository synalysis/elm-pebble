defmodule ElmEx.Frontend.AstContract.Types.RecordField do
  @moduledoc false

  alias ElmEx.Frontend.AstContract.Types.Expr

  @type t :: %{
          required(:name) => String.t(),
          required(:expr) => Expr.t()
        }
end
