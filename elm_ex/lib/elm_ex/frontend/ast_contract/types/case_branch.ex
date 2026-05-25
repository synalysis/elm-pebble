defmodule ElmEx.Frontend.AstContract.Types.CaseBranch do
  @moduledoc false

  alias ElmEx.Frontend.AstContract.Types.{Expr, Pattern}

  @type t :: %{
          required(:pattern) => Pattern.t(),
          required(:expr) => Expr.t()
        }
end
