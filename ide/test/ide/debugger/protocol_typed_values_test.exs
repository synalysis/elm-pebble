defmodule Ide.Debugger.ProtocolTypedValuesTest do
  use ExUnit.Case, async: true

  alias Ide.CompanionProtocolGenerator
  alias Ide.Debugger.ProtocolEvents.CmdCall

  @types File.read!("priv/project_templates/watchface_yes/protocol/src/Companion/Types.elm")

  setup do
    {:ok, schema} = CompanionProtocolGenerator.schema_from_source(@types)
    {:ok, schema: schema}
  end

  test "normalize ProvideWeather preserves typed Celsius temperature", %{schema: schema} do
    wire = %{
      "ctor" => "ProvideWeather",
      "args" => [
        %{"ctor" => "Celsius", "args" => [210]},
        %{"ctor" => "Clear", "args" => []},
        0,
        0,
        1013
      ]
    }

    {message, normalized} =
      CmdCall.normalize_protocol_message_value_from_schema(schema, :phone_to_watch, wire, "ProvideWeather")

    assert message == "ProvideWeather Celsius 210 Clear 0 0 1013"

    assert %{"ctor" => "Celsius", "args" => [210]} = Enum.at(normalized["args"], 0)
    assert Enum.at(normalized["args"], 1)["ctor"] == "Clear"
  end

  test "normalize ProvideWind preserves typed wind direction and speed", %{schema: schema} do
    wire = %{
      "ctor" => "ProvideWind",
      "args" => [
        %{"ctor" => "NorthEast", "args" => []},
        %{"ctor" => "MetersPerSecond", "args" => [4]}
      ]
    }

    {message, normalized} =
      CmdCall.normalize_protocol_message_value_from_schema(schema, :phone_to_watch, wire, "ProvideWind")

    assert message == "ProvideWind NorthEast MetersPerSecond 4"
    assert Enum.at(normalized["args"], 0)["ctor"] == "NorthEast"
    assert %{"ctor" => "MetersPerSecond", "args" => [4]} = Enum.at(normalized["args"], 1)
  end
end
