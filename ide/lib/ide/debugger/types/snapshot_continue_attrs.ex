defmodule Ide.Debugger.Types.SnapshotContinueAttrs do
  @moduledoc """
  Attributes for `Debugger.continue_from_snapshot/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:cursor_seq) => non_neg_integer() | String.t() | nil,
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
