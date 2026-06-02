defmodule Ide.Debugger.CompanionBridge.SimulatorStore do
  @moduledoc false

  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types

  @spec storage_result(Types.simulator_settings(), Types.wire_map()) ::
          {Types.simulator_settings(), {:ok, Types.protocol_ctor_value()} | {:error, String.t()}}
  def storage_result(settings, request) when is_map(settings) and is_map(request) do
    values = Map.get(settings, "storage_values", %{})
    key = Map.get(request, :key)

    case Map.get(request, :op) do
      "get" ->
        case key && Map.get(values, key) do
          nil -> {settings, {:error, "Storage key not found"}}
          value -> {settings, {:ok, storage_value_to_elm_value(value)}}
        end

      "set" ->
        stored = command_value_to_storage_value(Map.get(request, :value))

        {put_nested(settings, "storage_values", key, stored),
         {:ok, storage_value_to_elm_value(stored)}}

      "remove" ->
        {put_nested(settings, "storage_values", key, nil),
         {:ok, %{"ctor" => "JsonValue", "args" => [%{}]}}}

      "clear" ->
        {Map.put(settings, "storage_values", %{}),
         {:ok, %{"ctor" => "JsonValue", "args" => [%{}]}}}

      _ ->
        {settings, {:error, "Unsupported storage operation"}}
    end
  end

  @spec preferences_result(Types.simulator_settings(), Types.wire_map()) ::
          {Types.simulator_settings(),
           {:ok, {String.t(), Types.wire_input()}} | {:error, String.t()}}
  def preferences_result(settings, request) when is_map(settings) and is_map(request) do
    values = Map.get(settings, "preferences", %{})
    key = Map.get(request, :key)

    case Map.get(request, :op) do
      "get" ->
        value = if key, do: Map.get(values, key), else: nil
        {settings, {:ok, {key || "", value}}}

      "set" ->
        value = command_json_value(Map.get(request, :value))
        pref_key = if is_binary(key), do: key, else: ""

        {put_nested(settings, "preferences", pref_key, value), {:ok, {pref_key, value}}}

      "subscribe" ->
        {settings, {:ok, {"", values}}}

      _ ->
        {settings, {:error, "Unsupported preferences operation"}}
    end
  end

  @spec normalize_settings(Types.SimulatorSettings.wire_map()) :: Types.simulator_settings()
  def normalize_settings(settings), do: DebuggerSimulatorSettings.normalize(settings)

  @spec storage_value_to_elm_value(Types.wire_map()) :: Types.protocol_ctor_value()
  def storage_value_to_elm_value(%{"kind" => "string", "value" => value}) when is_binary(value),
    do: %{"ctor" => "StringValue", "args" => [value]}

  def storage_value_to_elm_value(%{"kind" => "int", "value" => value}) when is_integer(value),
    do: %{"ctor" => "IntValue", "args" => [value]}

  def storage_value_to_elm_value(%{"kind" => "bool", "value" => value}) when is_boolean(value),
    do: %{"ctor" => "BoolValue", "args" => [value]}

  def storage_value_to_elm_value(%{"kind" => "json", "value" => value}),
    do: %{"ctor" => "JsonValue", "args" => [value]}

  def storage_value_to_elm_value(value), do: %{"ctor" => "JsonValue", "args" => [value]}

  @spec command_value_to_storage_value(Types.simulator_command_input()) :: Types.StorageValue.t()
  def command_value_to_storage_value(%{"$ctor" => ctor, "$args" => [value | _]})
      when ctor in ["StringValue", "Storage.StringValue"] and is_binary(value),
      do: %{"kind" => "string", "value" => value}

  def command_value_to_storage_value(%{"$ctor" => ctor, "$args" => [value | _]})
      when ctor in ["IntValue", "Storage.IntValue"] and is_integer(value),
      do: %{"kind" => "int", "value" => value}

  def command_value_to_storage_value(%{"$ctor" => ctor, "$args" => [value | _]})
      when ctor in ["BoolValue", "Storage.BoolValue"] and is_boolean(value),
      do: %{"kind" => "bool", "value" => value}

  def command_value_to_storage_value(%{"$ctor" => _ctor, "$args" => [value | _]}),
    do: %{"kind" => "json", "value" => value}

  def command_value_to_storage_value(value), do: %{"kind" => "json", "value" => value}

  @spec command_json_value(Types.simulator_command_input()) ::
          Types.wire_scalar() | Types.elmc_wire_ctor_call() | map()
  def command_json_value(%{"$call" => target, "$args" => [value | _]}) when is_binary(target) do
    cond do
      String.ends_with?(target, ".string") and is_binary(value) -> value
      String.ends_with?(target, ".int") and is_integer(value) -> value
      String.ends_with?(target, ".bool") and is_boolean(value) -> value
      true -> %{"$call" => target, "$args" => [value]}
    end
  end

  def command_json_value(value), do: value

  defp put_nested(settings, key, child_key, nil)
       when is_map(settings) and is_binary(key) and is_binary(child_key) do
    values =
      settings
      |> Map.get(key, %{})
      |> Map.delete(child_key)

    normalize_settings(Map.put(settings, key, values))
  end

  defp put_nested(settings, key, child_key, value)
       when is_map(settings) and is_binary(key) and is_binary(child_key) do
    values =
      settings
      |> Map.get(key, %{})
      |> Map.put(child_key, value)

    normalize_settings(Map.put(settings, key, values))
  end
end
