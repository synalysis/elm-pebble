defmodule Ide.Debugger.Types.ReplayAttrs do
  @moduledoc """
  Attributes for `Debugger.replay_recent/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:count) => pos_integer() | non_neg_integer() | String.t() | nil,
          optional(:target) => Types.surface_target() | String.t() | atom() | nil,
          optional(:cursor_seq) => non_neg_integer() | String.t() | nil,
          optional(:replay_mode) => String.t() | nil,
          optional(:replay_drift_seq) => non_neg_integer() | String.t() | nil,
          optional(:replay_rows) => [Types.replay_row()],
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
