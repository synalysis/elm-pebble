defmodule Ide.Debugger.Types.AutoTick do
  @moduledoc """
  Auto tick / auto-fire worker state on `RuntimeState.auto_tick`.
  """

  alias Ide.Debugger.Types.DisabledSubscription

  @type t :: %{
          optional(:enabled) => boolean(),
          optional(:interval_ms) => pos_integer() | nil,
          optional(:target) => String.t(),
          optional(:targets) => [String.t()],
          optional(:count) => pos_integer() | nil,
          optional(:worker_pid) => pid() | nil,
          optional(:subscriptions) => [DisabledSubscription.wire_map()],
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
