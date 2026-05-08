defmodule Ide.CompanionProtocolGeneratorTest do
  use ExUnit.Case, async: true

  alias Ide.CompanionProtocolGenerator

  @types """
  module Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), TutorialColor(..), WatchToPhone(..))

  type Location
      = CurrentLocation
      | Berlin
      | Zurich

  type Temperature
      = Celsius Int
      | Fahrenheit Int

  type TutorialColor
      = Black
      | White

  type WatchToPhone
      = RequestWeather Location

  type PhoneToWatch
      = ProvideTemperature Temperature
      | SetBackgroundColor TutorialColor
      | SetShowDate Bool
      | SetLabel String
  """

  test "extracts generic ADT schema without app-specific query data" do
    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(@types)

    assert schema.enums == %{
             "Location" => ["CurrentLocation", "Berlin", "Zurich"],
             "TutorialColor" => ["Black", "White"]
           }

    assert Enum.map(schema.payload_unions["Temperature"], & &1.name) == ["Celsius", "Fahrenheit"]

    assert [%{name: "RequestWeather", tag: 2, fields: [request_field]}] = schema.watch_to_phone
    assert request_field.wire_type == {:enum, "Location"}

    assert Enum.map(schema.phone_to_watch, & &1.name) == [
             "ProvideTemperature",
             "SetBackgroundColor",
             "SetShowDate",
             "SetLabel"
           ]

    refute inspect(schema) =~ "latitude"
  end

  test "generates C and JS from the extracted schema" do
    tmp =
      Path.join(System.tmp_dir!(), "elm-pebble-protocol-#{System.unique_integer([:positive])}")

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.write!(types, @types)

      assert :ok =
               CompanionProtocolGenerator.generate(types, header, source, js,
                 runtime_tags: %{
                   "Temperature" => %{"Celsius" => 41, "Fahrenheit" => 42},
                   "TutorialColor" => %{"Black" => 51, "White" => 52}
                 }
               )

      assert File.read!(header) =~ "COMPANION_PROTOCOL_ENUM_LOCATION_CURRENT_LOCATION 0"
      assert File.read!(header) =~ "COMPANION_PROTOCOL_TAG_REQUEST_WEATHER 2"
      assert File.read!(source) =~ "companion_protocol_dispatch_phone_to_watch"
      assert File.read!(source) =~ "ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET"
      assert File.read!(source) =~ "companion_protocol_new_union_value"
      assert File.read!(source) =~ "companion_protocol_new_phone_to_watch_message"
      assert File.read!(source) =~ "case 0: return 41;"
      assert File.read!(source) =~ "case 1: return 52;"
      refute File.read!(source) =~ "tag + 1"
      assert File.read!(header) =~ "COMPANION_PROTOCOL_KEY_PROVIDE_TEMPERATURE_FIELD1_TAG"
      assert File.read!(header) =~ "COMPANION_PROTOCOL_KEY_PROVIDE_TEMPERATURE_FIELD1_VALUE"
      assert File.read!(js) =~ "decodeWatchToPhonePayload"
      assert File.read!(js) =~ "locationNameForCode"
    after
      File.rm_rf(tmp)
    end
  end

  test "generates Elm internal helpers from the extracted schema" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-elm-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.write!(types, @types)

      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)
      generated = File.read!(internal)

      assert generated =~ "Generated wire encoding and decoding helpers"
      assert generated =~ "encodeLocationCode : Location -> Int"
      assert generated =~ "decodeLocationCode : Int -> Maybe Location"
      assert generated =~ "encodeTemperatureTag : Temperature -> Int"
      assert generated =~ "encodeTemperatureValue : Temperature -> Int"
      assert generated =~ "decodeTemperature : Int -> Int -> Maybe Temperature"
      assert generated =~ "encodeTutorialColorCode : TutorialColor -> Int"
      assert generated =~ "( \"set_show_date_field1\", Encode.int (if field1 then 1 else 0) )"
      assert generated =~ "watchToPhoneTag : WatchToPhone -> Int"
      refute generated =~ "locationWeatherQuery"
      refute generated =~ ", location"
    after
      File.rm_rf(tmp)
    end
  end
end
