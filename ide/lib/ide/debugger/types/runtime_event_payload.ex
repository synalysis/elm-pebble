defmodule Ide.Debugger.Types.RuntimeEventPayload do
  @moduledoc """
  Payload shapes for `RuntimeState.events` (`append_event/3`).

  Event `type` strings discriminate usage; payloads remain maps at runtime.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{
    CompanionBridgeEventPayload,
    DeviceDataEventPayload,
    DebuggerContractEventPayload,
    ElmcEventPayload,
    GeolocationEventPayload,
    HotReloadEventPayload,
    MessageInEventPayload,
    PackageCmdErrorEventPayload,
    PackageCmdEventPayload,
    ProtocolTxRxPayload,
    ReplayEventPayload,
    ResetEventPayload,
    RuntimeExecEventPayload,
    RuntimeStatusEventPayload,
    SimulatorSettingsSetEventPayload,
    SnapshotContinueEventPayload,
    StartEventPayload,
    SubscriptionToggleEventPayload,
    TickAutoEventPayload,
    TickEventPayload,
    ViewRenderEventPayload,
    WatchProfileSetEventPayload
  }

  @known_event_types %{
    "debugger.start" => :start,
    "debugger.reset" => :reset,
    "debugger.watch_profile_set" => :watch_profile_set,
    "debugger.simulator_settings_set" => :simulator_settings_set,
    "debugger.init_in" => :init_in,
    "debugger.update_in" => :update_in,
    "debugger.view_render" => :view_render,
    "debugger.device_data" => :device_data,
    "debugger.companion_bridge" => :companion_bridge,
    "debugger.geolocation" => :geolocation,
    "debugger.tick" => :tick,
    "debugger.tick_auto" => :tick_auto,
    "debugger.subscription_toggle" => :subscription_toggle,
    "debugger.package_cmd" => :package_cmd,
    "debugger.package_cmd_error" => :package_cmd_error,
    "debugger.protocol_tx" => :protocol_tx_rx,
    "debugger.protocol_rx" => :protocol_tx_rx,
    "debugger.reload" => :hot_reload,
    "debugger.runtime_exec" => :runtime_exec,
    "debugger.runtime_status" => :runtime_status,
    "debugger.contract" => :contract,
    "debugger.elm_introspect" => :elm_introspect,
    "debugger.replay" => :replay,
    "debugger.snapshot_continue" => :snapshot_continue,
    "debugger.elmc_check" => :elmc,
    "debugger.elmc_compile" => :elmc,
    "debugger.elmc_manifest" => :elmc
  }

  @payload_modules %{
    start: StartEventPayload,
    reset: ResetEventPayload,
    watch_profile_set: WatchProfileSetEventPayload,
    simulator_settings_set: SimulatorSettingsSetEventPayload,
    init_in: MessageInEventPayload,
    update_in: MessageInEventPayload,
    view_render: ViewRenderEventPayload,
    device_data: DeviceDataEventPayload,
    companion_bridge: CompanionBridgeEventPayload,
    geolocation: GeolocationEventPayload,
    tick: TickEventPayload,
    tick_auto: TickAutoEventPayload,
    subscription_toggle: SubscriptionToggleEventPayload,
    package_cmd: PackageCmdEventPayload,
    package_cmd_error: PackageCmdErrorEventPayload,
    protocol_tx_rx: ProtocolTxRxPayload,
    hot_reload: HotReloadEventPayload,
    runtime_exec: RuntimeExecEventPayload,
    runtime_status: RuntimeStatusEventPayload,
    contract: DebuggerContractEventPayload,
    elm_introspect: DebuggerContractEventPayload,
    replay: ReplayEventPayload,
    snapshot_continue: SnapshotContinueEventPayload,
    elmc: ElmcEventPayload
  }

  @type event_kind ::
          :start
          | :reset
          | :watch_profile_set
          | :simulator_settings_set
          | :init_in
          | :update_in
          | :view_render
          | :device_data
          | :companion_bridge
          | :geolocation
          | :tick
          | :tick_auto
          | :subscription_toggle
          | :package_cmd
          | :package_cmd_error
          | :protocol_tx_rx
          | :hot_reload
          | :runtime_exec
          | :runtime_status
          | :contract
          | :elm_introspect
          | :replay
          | :snapshot_continue
          | :elmc
          | :generic

  @type event_type :: String.t()

  @spec known_event_types() :: %{event_type() => event_kind()}
  def known_event_types, do: @known_event_types

  @spec kind_for(event_type()) :: event_kind()
  def kind_for(type) when is_binary(type) do
    Map.get(@known_event_types, type, :generic)
  end

  @spec known_event_type?(event_type()) :: boolean()
  def known_event_type?(type) when is_binary(type), do: Map.has_key?(@known_event_types, type)

  @spec payload_module_for(event_kind()) :: module() | nil
  def payload_module_for(kind) when is_atom(kind), do: Map.get(@payload_modules, kind)

  @spec payload_module_for_type(event_type()) :: module() | nil
  def payload_module_for_type(type) when is_binary(type) do
    type |> kind_for() |> payload_module_for()
  end

  @spec contract_kinds() :: [event_kind()]
  def contract_kinds, do: Map.keys(@payload_modules)

  @spec contract_complete?() :: boolean()
  def contract_complete? do
    @known_event_types
    |> Map.values()
    |> Enum.uniq()
    |> Enum.reject(&(&1 == :generic))
    |> Enum.all?(&(payload_module_for(&1) != nil))
  end

  @type surface_label :: String.t()

  @type start :: StartEventPayload.t()
  @type reset :: ResetEventPayload.t()
  @type watch_profile_set :: WatchProfileSetEventPayload.t()
  @type simulator_settings_set :: SimulatorSettingsSetEventPayload.t()
  @type init_in :: MessageInEventPayload.t()
  @type update_in :: MessageInEventPayload.t()
  @type view_render :: ViewRenderEventPayload.t()
  @type device_data :: DeviceDataEventPayload.t()
  @type companion_bridge :: CompanionBridgeEventPayload.t()
  @type geolocation :: GeolocationEventPayload.t()
  @type tick :: TickEventPayload.t()
  @type tick_auto :: TickAutoEventPayload.t()
  @type subscription_toggle :: SubscriptionToggleEventPayload.t()

  @type package_cmd :: PackageCmdEventPayload.t()

  @type package_cmd_error :: PackageCmdErrorEventPayload.t()

  @type protocol_tx_rx :: ProtocolTxRxPayload.t()

  @type hot_reload :: HotReloadEventPayload.t()

  @type runtime_exec :: RuntimeExecEventPayload.t()

  @type runtime_status :: RuntimeStatusEventPayload.t()

  @type contract :: DebuggerContractEventPayload.t()
  @type elm_introspect :: DebuggerContractEventPayload.t()

  @type protocol_reload :: ProtocolTxRxPayload.t()

  @type replay :: ReplayEventPayload.t()
  @type snapshot_continue :: SnapshotContinueEventPayload.t()

  @type elmc :: ElmcEventPayload.t()

  @type generic :: %{optional(atom()) => Types.wire_input(), optional(String.t()) => Types.wire_input()}

  @type t ::
          start()
          | reset()
          | watch_profile_set()
          | simulator_settings_set()
          | update_in()
          | view_render()
          | device_data()
          | companion_bridge()
          | geolocation()
          | tick()
          | tick_auto()
          | subscription_toggle()
          | init_in()
          | package_cmd()
          | package_cmd_error()
          | protocol_tx_rx()
          | protocol_reload()
          | hot_reload()
          | runtime_exec()
          | runtime_status()
          | elm_introspect()
          | replay()
          | snapshot_continue()
          | elmc()
          | generic()
end
