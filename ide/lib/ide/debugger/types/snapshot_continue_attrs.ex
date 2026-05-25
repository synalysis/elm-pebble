defmodule Ide.Debugger.Types.SnapshotContinueAttrs do
  @moduledoc """
  Attributes for `Debugger.continue_from_snapshot/2`.
  """

  @type t :: %{
          optional(:cursor_seq) => non_neg_integer() | String.t() | nil,
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
