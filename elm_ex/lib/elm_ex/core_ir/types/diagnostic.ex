defmodule ElmEx.CoreIR.Types.Diagnostic do
  @moduledoc false

  alias ElmEx.CoreIR.Types, as: CoreIRTypes

  @type t :: %{
          required(:severity) => String.t(),
          required(:code) => String.t(),
          optional(:module) => String.t() | nil,
          optional(:function) => String.t() | nil,
          optional(:message) => String.t()
        }

  @typedoc """
  Normalized diagnostic map from `ElmEx.CoreIR.normalize_diagnostic/1` (string keys).

  Required keys: `"severity"`, `"code"`.
  """
  @type wire_t :: CoreIRTypes.wire_map()
end
