defmodule Ide.Debugger.Types.AutoTick do
  @moduledoc """
  Auto tick / auto-fire worker state on `RuntimeState.auto_tick`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:enabled) => boolean(),
          optional(:interval_ms) => pos_integer() | nil,
          optional(:target) => String.t(),
          optional(:targets) => [String.t()],
          optional(:count) => pos_integer() | nil,
          optional(:worker_pid) => pid() | nil,
          optional(:subscriptions) => [Types.disabled_subscription()]
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
