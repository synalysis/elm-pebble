defmodule ElmEx.CoreIR.Types.Module do
  @moduledoc false

  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmEx.CoreIR.Types.Declaration
  alias ElmEx.CoreIR.Types.UnionEntry

  @type unions :: %{String.t() => UnionEntry.t() | UnionEntry.wire_map()}

  @typedoc """
  Normalized module map from `ElmEx.CoreIR.normalize_module/1` (string keys at runtime).

  Required keys: `"name"`, `"imports"`, `"unions"`, `"declarations"`.
  """
  @type wire_t :: CoreIRTypes.wire_map()

  @typedoc "Normalized declaration entry inside `wire_t` declarations list."
  @type wire_declaration :: CoreIRTypes.wire_map()

  @type t :: %{
          required(:name) => String.t(),
          required(:imports) => [String.t()],
          required(:unions) => unions(),
          required(:declarations) => [Declaration.t() | wire_declaration()],
          optional(:ports) => [String.t()],
          optional(:port_module) => boolean()
        }
end
