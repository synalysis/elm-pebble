defmodule Ide.Debugger.Geolocation do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.ProtocolResolutionCtx
  alias Ide.Debugger.Types
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.SimulatorSettings

  @spec contract() :: Types.api_suffix_contract()
  def contract, do: CompanionBridge.geolocation_contract()

  @spec location_payload(Types.simulator_settings()) :: Types.wire_map()
  def location_payload(settings) when is_map(settings) do
    normalized = DebuggerSimulatorSettings.normalize(settings)
    {lat, lon, accuracy} = SimulatorSettings.geolocation(normalized)

    %{
      "latitude" => lat,
      "longitude" => lon,
      "accuracy" => accuracy
    }
  end

  @spec location_from_state(Types.runtime_state()) :: Types.wire_map()
  def location_from_state(state) when is_map(state) do
    state
    |> Map.get(:simulator_settings)
    |> DebuggerSimulatorSettings.normalize()
    |> location_payload()
  end

  @spec wire_triplet(Types.simulator_settings()) :: {integer(), integer(), integer()}
  def wire_triplet(settings) when is_map(settings) do
    {lat, lon, accuracy} = SimulatorSettings.geolocation(settings)

    {
      position_microdegrees(lat),
      position_microdegrees(lon),
      round_number(accuracy) || 0
    }
  end

  @spec watch_from_phone_message_value(Types.simulator_settings()) ::
          Types.phone_to_watch_message_value()
  def watch_from_phone_message_value(settings) when is_map(settings) do
    {lat_e6, lon_e6, accuracy_m} = wire_triplet(settings)

    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvidePosition",
          "args" => [lat_e6, lon_e6, accuracy_m]
        }
      ]
    }
  end

  @spec simulator_wire_int(Types.eval_context() | ProtocolResolutionCtx.t()) :: integer() | nil
  def simulator_wire_int(ctx) when is_map(ctx) do
    with %{} = settings <- Map.get(ctx, :simulator_settings),
         index when is_integer(index) <- Map.get(ctx, :arg_index) do
      {lat, lon, accuracy} = SimulatorSettings.geolocation(settings)

      case index do
        0 -> micro_degrees_from_float(lat)
        1 -> micro_degrees_from_float(lon)
        2 -> round_number(accuracy)
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  @spec init_requested?([Types.cmd_call()], String.t() | nil) :: boolean()
  def init_requested?(init_cmd_calls, subscription_callback) when is_list(init_cmd_calls) do
    init_requested? =
      Enum.any?(init_cmd_calls, fn row ->
        CmdCall.name?(row, "currentPosition") or
          CmdCall.target_ends_with?(row, ".currentPosition")
      end)

    init_requested? or is_binary(subscription_callback)
  end

  def init_requested?(_init_cmd_calls, subscription_callback),
    do: is_binary(subscription_callback)

  @spec update_branch_requests_command?([Types.cmd_call()], Types.elm_introspect()) :: boolean()
  def update_branch_requests_command?(update_cmd_calls, ei)
      when is_list(update_cmd_calls) and is_map(ei) do
    Enum.any?(update_cmd_calls, &CmdCall.requests_current_position?(ei, &1))
  end

  def update_branch_requests_command?(_update_cmd_calls, _ei), do: false

  @spec init_requested_from_introspect?(Types.elm_introspect()) :: boolean()
  def init_requested_from_introspect?(ei) when is_map(ei) do
    init_cmd_calls =
      ei
      |> IntrospectAccess.cmd_calls("init_cmd_calls")
      |> CmdCall.expand_helpers(ei)

    init_requested?(init_cmd_calls, subscription_callback_from_introspect(ei))
  end

  def init_requested_from_introspect?(_ei), do: false

  @spec subscription_callback_from_introspect(Types.elm_introspect()) :: String.t() | nil
  def subscription_callback_from_introspect(ei) when is_map(ei) do
    subscription_callback(
      IntrospectAccess.cmd_calls(ei, "subscription_calls"),
      contract()
    )
  end

  def subscription_callback_from_introspect(_ei), do: nil

  @spec subscription_callback([Types.cmd_call()], Types.api_suffix_contract()) :: String.t() | nil
  def subscription_callback(subscription_calls, contract)
      when is_list(subscription_calls) and is_map(contract) do
    target_suffixes = Map.get(contract, :target_suffixes, []) |> List.wrap()

    Enum.find_value(subscription_calls, fn row ->
      if CmdCall.subscription_call_matches?(row, target_suffixes) do
        callback = Map.get(row, "callback_constructor")
        if is_binary(callback) and callback != "", do: callback, else: nil
      end
    end)
  end

  def subscription_callback(_subscription_calls, _contract), do: nil

  @spec position_microdegrees(number()) :: integer()
  def position_microdegrees(value) when is_integer(value) and abs(value) > 1_000_000, do: value

  def position_microdegrees(value) when is_integer(value), do: round(value * 1_000_000)

  def position_microdegrees(value) when is_float(value), do: round(value * 1_000_000)

  @spec micro_degrees_from_float(number()) :: integer() | nil
  def micro_degrees_from_float(value) when is_number(value), do: round(value * 1_000_000)
  def micro_degrees_from_float(_value), do: nil

  @spec round_number(number()) :: integer() | nil
  def round_number(value) when is_integer(value), do: value
  def round_number(value) when is_float(value), do: round(value)
  def round_number(_value), do: nil
end
