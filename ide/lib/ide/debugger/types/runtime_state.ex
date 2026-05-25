defmodule Ide.Debugger.Types.RuntimeState do
  @moduledoc """
  In-memory debugger session state for a project slug (`Ide.Debugger` Agent store).
  """

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{
    AutoTick,
    DebuggerTimelineRow,
    DisabledSubscription,
    LaunchContext,
    RuntimeEvent,
    SimulatorSettings,
    StorageValue
  }

  @type runtime_event :: RuntimeEvent.t()

  @type debugger_event :: DebuggerTimelineRow.t()

  @type launch_context :: LaunchContext.t() | LaunchContext.wire_map()

  @type auto_tick :: AutoTick.t() | AutoTick.wire_map()

  @type session_storage :: StorageValue.values_map()

  @type t :: %{
          required(:running) => boolean(),
          optional(:revision) => String.t() | nil,
          required(:watch_profile_id) => String.t(),
          required(:launch_context) => launch_context(),
          required(:simulator_settings) => SimulatorSettings.t(),
          required(:watch) => Surface.surface_map(),
          required(:companion) => Surface.surface_map(),
          required(:phone) => Surface.surface_map(),
          required(:storage) => session_storage(),
          required(:auto_tick) => auto_tick(),
          required(:disabled_subscriptions) => [DisabledSubscription.wire_map()],
          required(:events) => [runtime_event()],
          required(:debugger_timeline) => [debugger_event()],
          required(:debugger_seq) => non_neg_integer(),
          required(:seq) => non_neg_integer(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
