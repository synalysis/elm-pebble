defmodule Ide.Debugger.Types.SnapshotContinueAttrs do
  @moduledoc """
  Attributes for `Debugger.continue_from_snapshot/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:cursor_seq) => non_neg_integer() | String.t() | nil,
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
