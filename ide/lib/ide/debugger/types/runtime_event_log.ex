defmodule Ide.Debugger.Types.RuntimeEventLog do
  @moduledoc """
  Typed pairings between `RuntimeEventPayload.event_kind/0` and payload modules.

  Runtime history stores wire `type` strings (for example `"debugger.start"`); use
  `event_type/1` to map kinds back to those strings.
  """

  alias Ide.Debugger.Types.RuntimeEventPayload, as: Payload

  @typedoc "Discriminated payload by internal event kind (not the wire string)."
  @type kind_payload ::
          {:start, Payload.start()}
          | {:reset, Payload.reset()}
          | {:watch_profile_set, Payload.watch_profile_set()}
          | {:simulator_settings_set, Payload.simulator_settings_set()}
          | {:init_in, Payload.init_in()}
          | {:update_in, Payload.update_in()}
          | {:view_render, Payload.view_render()}
          | {:device_data, Payload.device_data()}
          | {:companion_bridge, Payload.companion_bridge()}
          | {:geolocation, Payload.geolocation()}
          | {:tick, Payload.tick()}
          | {:tick_auto, Payload.tick_auto()}
          | {:subscription_toggle, Payload.subscription_toggle()}
          | {:package_cmd, Payload.package_cmd()}
          | {:package_cmd_error, Payload.package_cmd_error()}
          | {:protocol_tx_rx, Payload.protocol_tx_rx()}
          | {:hot_reload, Payload.hot_reload()}
          | {:runtime_exec, Payload.runtime_exec()}
          | {:runtime_status, Payload.runtime_status()}
          | {:contract, Payload.contract()}
          | {:elm_introspect, Payload.elm_introspect()}
          | {:replay, Payload.replay()}
          | {:snapshot_continue, Payload.snapshot_continue()}
          | {:elmc, Payload.elmc()}

  @spec event_type(Payload.event_kind()) :: String.t() | nil
  def event_type(kind) when is_atom(kind) do
    Payload.known_event_types()
    |> Enum.find_value(fn {type, mapped} -> if mapped == kind, do: type end)
  end

  @spec payload_module(Payload.event_kind()) :: module() | nil
  def payload_module(kind) when is_atom(kind), do: Payload.payload_module_for(kind)

  @spec wire_type?(String.t()) :: boolean()
  def wire_type?(type) when is_binary(type), do: Payload.known_event_type?(type)

  @type kind :: Payload.event_kind()

  @spec known_wire_types() :: %{String.t() => kind()}
  def known_wire_types, do: Payload.known_event_types()
end
