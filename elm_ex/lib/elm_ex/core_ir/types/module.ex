defmodule ElmEx.CoreIR.Types.Module do
  @moduledoc false

  alias ElmEx.CoreIR.Types.Declaration
  alias ElmEx.IR.Types.UnionEntry

  @type unions :: %{String.t() => UnionEntry.t() | map()}

  @type t :: %{
          required(:name) => String.t(),
          required(:imports) => [String.t()],
          required(:unions) => unions(),
          required(:declarations) => [Declaration.t() | map()],
          optional(:ports) => [String.t()],
          optional(:port_module) => boolean()
        }
end
