defmodule ElmEx.CoreIR.Types.Module do
  @moduledoc false

  alias ElmEx.CoreIR.Types.Declaration

  @type unions :: %{String.t() => map()}

  @type t :: %{
          required(:name) => String.t(),
          required(:imports) => [String.t()],
          required(:unions) => unions(),
          required(:declarations) => [Declaration.t() | map()]
        }
end
