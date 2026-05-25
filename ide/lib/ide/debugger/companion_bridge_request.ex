defmodule Ide.Debugger.CompanionBridgeRequest do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.CompanionBridgeRequest, as: BridgeRequestType

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

      companion_call_target?(normalized, "calendar") and name in ["current", "nextEvent", "upcoming"] ->
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

      true ->
        []
    end
  end

  def from_cmd_call(_row), do: []

  @spec request_meta(Types.cmd_call()) :: %{optional(:callback) => String.t() | nil}
  defp request_meta(row) when is_map(row) do
    %{callback: Map.get(row, "callback_constructor") || Map.get(row, :callback_constructor)}
  end

  defp request_meta(_row), do: %{callback: nil}

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
