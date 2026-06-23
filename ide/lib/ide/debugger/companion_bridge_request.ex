defmodule Ide.Debugger.CompanionBridgeRequest do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.CompanionBridgeRequest, as: BridgeRequestType

  @spec from_bridge_command(map()) :: Types.companion_bridge_request() | nil
  def from_bridge_command(%{"api" => api, "op" => op} = command)
      when is_binary(api) and is_binary(op) do
    %{
      api: api,
      op: op,
      key: Map.get(command, "key") || Map.get(command, :key),
      value: Map.get(command, "value") || Map.get(command, :value),
      bridge_id: Map.get(command, "bridge_id") || Map.get(command, :bridge_id),
      payload: Map.get(command, "payload") || Map.get(command, :payload),
      callback:
        Map.get(command, "callback_constructor") || Map.get(command, :callback_constructor) ||
          Map.get(command, "message") || Map.get(command, :message)
    }
  end

  def from_bridge_command(%{"kind" => "cmd.companion.bridge"} = command),
    do: from_bridge_command(command)

  def from_bridge_command(_command), do: nil

  @spec from_cmd_calls([Types.cmd_call()]) :: [Types.companion_bridge_request()]
  def from_cmd_calls(calls) when is_list(calls) do
    calls
    |> Enum.flat_map(&from_cmd_call/1)
    |> Enum.uniq_by(
      &{Map.get(&1, :api), Map.get(&1, :op), Map.get(&1, :key), Map.get(&1, :callback),
       inspect(Map.get(&1, :value))}
    )
  end

  def from_cmd_calls(_calls), do: []

  @spec from_cmd_call(Types.cmd_call()) :: BridgeRequestType.from_cmd_result()
  def from_cmd_call(row) when is_map(row) do
    name = (Map.get(row, "name") || Map.get(row, :name) || "") |> to_string()
    target = (Map.get(row, "target") || Map.get(row, :target) || "") |> to_string()
    normalized = String.downcase(target)
    args = Map.get(row, "arg_values") || Map.get(row, :arg_values) || []
    meta = request_meta(row)

    cond do
      name == "subscribe" ->
        []

      companion_call_target?(normalized, "battery") and name in ["current", "status"] ->
        [Map.merge(%{api: "battery", op: "status"}, meta)]

      companion_call_target?(normalized, "locale") and name in ["current", "status"] ->
        [Map.merge(%{api: "locale", op: "status"}, meta)]

      companion_call_target?(normalized, "connectivity") and name in ["current", "status"] ->
        [Map.merge(%{api: "network", op: "status", plain_result: true}, meta)]

      companion_call_target?(normalized, "network") and name in ["current", "status"] ->
        [Map.merge(%{api: "network", op: "status", plain_result: true}, meta)]

      companion_call_target?(normalized, "notifications") and name in ["current", "status"] ->
        [Map.merge(%{api: "notifications", op: "status"}, meta)]

      companion_call_target?(normalized, "weather") and name in ["current", "forecast"] ->
        [Map.merge(%{api: "weather", op: name}, meta)]

      companion_call_target?(normalized, "calendar") and
          name in ["current", "nextEvent", "upcoming"] ->
        [
          Map.merge(
            %{api: "calendar", op: if(name == "current", do: "nextEvent", else: name)},
            meta
          )
        ]

      companion_call_target?(normalized, "environment") and name == "current" ->
        [Map.merge(%{api: "environment", op: "current"}, meta)]

      companion_call_target?(normalized, "storage") and name == "get" ->
        [
          Map.merge(
            %{
              api: "storage",
              op: "get",
              key: companion_arg_string(args, 0),
              value: Enum.at(args, 1)
            },
            meta
          )
        ]

      companion_call_target?(normalized, "storage") and name in ["set", "remove", "clear"] ->
        [
          %{
            api: "storage",
            op: name,
            key: companion_arg_string(args, 0),
            value: Enum.at(args, 1)
          }
        ]

      companion_call_target?(normalized, "preferencestore") and name == "get" ->
        [
          Map.merge(
            %{
              api: "preferences",
              op: "get",
              key: companion_arg_string(args, 0),
              value: Enum.at(args, 1)
            },
            meta
          )
        ]

      companion_call_target?(normalized, "preferencestore") and name == "set" ->
        [
          %{
            api: "preferences",
            op: "set",
            key: companion_arg_string(args, 0),
            value: Enum.at(args, 1)
          }
        ]

      companion_call_target?(normalized, "preferences") and name == "get" ->
        [
          Map.merge(
            %{
              api: "preferences",
              op: "get",
              key: companion_arg_string(args, 0),
              value: Enum.at(args, 1)
            },
            meta
          )
        ]

      companion_call_target?(normalized, "preferences") and name == "set" ->
        [
          %{
            api: "preferences",
            op: "set",
            key: companion_arg_string(args, 0),
            value: Enum.at(args, 1)
          }
        ]

      companion_call_target?(normalized, "geolocation") and
          name in ["currentPosition", "getCurrentPosition"] ->
        [Map.merge(%{api: "geolocation", op: "getCurrentPosition"}, meta)]

      companion_call_target?(normalized, "timeline") and name == "getToken" ->
        [Map.merge(%{api: "timeline", op: "getToken"}, meta)]

      companion_call_target?(normalized, "timeline") and name == "insertPin" ->
        [Map.merge(%{api: "timeline", op: "insertPin"}, meta)]

      companion_call_target?(normalized, "phone") and String.downcase(name) == "sendbridgecommand" ->
        envelope_requests_from_value(Enum.at(args, 0), meta)

      true ->
        []
    end
  end

  def from_cmd_call(_row), do: []

  @spec envelope_requests_from_value(term(), %{optional(:callback) => String.t() | nil}) ::
          BridgeRequestType.from_cmd_result()
  defp envelope_requests_from_value(value, meta) do
    case envelope_fields(value) do
      %{api: api, op: op} = fields when is_binary(api) and is_binary(op) ->
        [
          Map.merge(
            %{
              api: api,
              op: op,
              bridge_id: Map.get(fields, :id),
              payload: Map.get(fields, :payload)
            },
            meta
          )
        ]

      _ ->
        []
    end
  end

  @spec envelope_fields(term()) :: BridgeRequestType.envelope_fields() | nil
  defp envelope_fields(%{"api" => api, "op" => op} = map) when is_binary(api) and is_binary(op) do
    %{
      api: api,
      op: op,
      id: Map.get(map, "id") || Map.get(map, :id),
      payload: Map.get(map, "payload") || Map.get(map, :payload) || %{}
    }
  end

  defp envelope_fields(%{api: api, op: op} = map) when is_binary(api) and is_binary(op) do
    envelope_fields(%{
      "api" => api,
      "op" => op,
      "id" => Map.get(map, :id),
      "payload" => Map.get(map, :payload)
    })
  end

  defp envelope_fields(_), do: nil

  @spec request_meta(Types.cmd_call()) :: %{optional(:callback) => String.t() | nil}
  defp request_meta(row) when is_map(row) do
    %{callback: Map.get(row, "callback_constructor") || Map.get(row, :callback_constructor)}
  end

  @spec companion_call_target?(String.t(), String.t()) :: boolean()
  defp companion_call_target?(target, module_name)
       when is_binary(target) and is_binary(module_name) do
    String.contains?(target, module_name <> ".") or
      String.contains?(target, "companion." <> module_name) or
      String.contains?(target, "pebble.companion." <> module_name)
  end

  @spec companion_arg_string([Types.protocol_wire_arg() | String.t()], non_neg_integer()) ::
          String.t() | nil
  defp companion_arg_string(args, index) when is_list(args) do
    case Enum.at(args, index) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp companion_arg_string(_args, _index), do: nil
end
