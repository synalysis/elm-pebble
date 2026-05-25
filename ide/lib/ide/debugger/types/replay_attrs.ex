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
          optional(:replay_rows) => [Types.replay_row()] | list(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
