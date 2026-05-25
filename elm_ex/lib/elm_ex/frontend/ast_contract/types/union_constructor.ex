defmodule ElmEx.Frontend.AstContract.Types.UnionConstructor do
  @moduledoc false

  @type t :: %{
          required(:name) => String.t(),
          optional(:arg) => String.t() | nil
        }
end
