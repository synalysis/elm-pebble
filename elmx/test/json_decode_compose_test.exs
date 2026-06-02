defmodule Elmx.JsonDecodeComposeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Json.Decode
  alias Elmx.Runtime.Stdlib

  test "field float int map2 decodes nested weather JSON" do
    decoder =
      Decode.field(
        "current",
        Decode.map2(
          fn temp, code -> %{temperature: temp, code: code} end,
          Decode.field("temperature_2m", Decode.float()),
          Decode.field("weather_code", Decode.int())
        )
      )

    json = ~s({"current":{"temperature_2m":18.5,"weather_code":0}})

    assert {:Ok, %{temperature: 18.5, code: 0}} = Decode.decode_value(decoder, json)
  end

  test "qualified dispatch compiles decoder builders" do
    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.field", "\"current\", inner")
    assert code == "Elmx.Runtime.Json.Decode.field(\"current\", inner)"

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.optionalField", "\"name\", inner")
    assert code == "Elmx.Runtime.Json.Decode.optional_field(\"name\", inner)"

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.map2", "f, d1, d2")
    assert code == "Elmx.Runtime.Json.Decode.map2(f, d1, d2)"

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.map5", "f, d1, d2, d3, d4, d5")
    assert code == "Elmx.Runtime.Json.Decode.map5(f, d1, d2, d3, d4, d5)"
  end

  test "list and nullable decoders" do
    events_decoder =
      Decode.list(
        Decode.map6(
          fn id, title, location, start_ms, end_ms, all_day ->
            %{id: id, title: title, location: location, start: start_ms, end: end_ms, all_day: all_day}
          end,
          Decode.field("id", Decode.string()),
          Decode.field("title", Decode.string()),
          Decode.maybe(Decode.field("location", Decode.string())),
          Decode.field("startMillis", Decode.int()),
          Decode.field("endMillis", Decode.int()),
          Decode.field("allDay", Decode.bool())
        )
      )

    json = ~s({
      "events":[
        {"id":"e1","title":"Standup","startMillis":1000,"endMillis":2000,"allDay":false}
      ]
    })

    assert {:Ok, [event]} = Decode.decode_value(Decode.field("events", events_decoder), json)
    assert event.title == "Standup"
    assert event.location == :Nothing

    assert {:Ok, :Nothing} = Decode.decode_value(Decode.nullable(Decode.string()), nil)
    assert {:Ok, {:Just, "Hi"}} = Decode.decode_value(Decode.nullable(Decode.string()), "Hi")
  end

  test "andThen decodes storage value kinds" do
    storage_decoder =
      Decode.and_then(
        fn
          "string" ->
            Decode.map(
              fn text -> {:StringValue, text} end,
              Decode.field("value", Decode.string())
            )

          "int" ->
            Decode.map(fn n -> {:IntValue, n} end, Decode.field("value", Decode.int()))

          _ ->
            Decode.fail("unknown")
        end,
        Decode.field("kind", Decode.string())
      )

    assert {:Ok, {:StringValue, "dark"}} =
             Decode.decode_value(storage_decoder, ~s({"kind":"string","value":"dark"}))

    assert {:Ok, {:IntValue, 42}} =
             Decode.decode_value(storage_decoder, ~s({"kind":"int","value":42}))
  end

  test "oneOf and succeed implement field-with-default pattern" do
    decode_field_with_default = fn name, inner, fallback ->
      Decode.one_of([
        Decode.field(name, inner),
        Decode.succeed(fallback)
      ])
    end

    width_decoder = decode_field_with_default.("width", Decode.int(), 144)

    assert {:Ok, 200} = Decode.decode_value(width_decoder, ~s({"width":200}))
    assert {:Ok, 144} = Decode.decode_value(width_decoder, ~s({"other":1}))
  end

  test "oneOf picks first matching primitive decoder" do
    decoder = Decode.one_of([Decode.int(), Decode.string()])

    assert {:Ok, 7} = Decode.decode_value(decoder, "7")
    assert {:Ok, "hi"} = Decode.decode_value(decoder, "\"hi\"")
    assert {:Err, _} = Decode.decode_value(decoder, "true")
  end

  test "decodeString parses JSON document" do
    theme_decoder =
      Decode.one_of([
        Decode.map(fn s -> String.to_atom(s) end, Decode.field("theme", Decode.string())),
        Decode.succeed(:Light)
      ])

    assert {:Ok, :Dark} =
             Decode.decode_string(theme_decoder, ~s({"theme":"Dark"}))

    assert {:Ok, :Light} = Decode.decode_string(theme_decoder, ~s({}))
  end

  test "map7 decodes launch-context shaped object" do
    decoder =
      Decode.map7(
        fn reason, model, profile, screen, mic, compass, health ->
          %{
            reason: reason,
            watchModel: model,
            watchProfileId: profile,
            screen: screen,
            hasMicrophone: mic,
            hasCompass: compass,
            supportsHealth: health
          }
        end,
        Decode.field("reason", Decode.string()),
        Decode.field("watchModel", Decode.string()),
        Decode.field("watchProfileId", Decode.string()),
        Decode.field("screen", Decode.field("width", Decode.int())),
        Decode.field("hasMicrophone", Decode.bool()),
        Decode.field("hasCompass", Decode.bool()),
        Decode.field("supportsHealth", Decode.bool())
      )

    json = ~s({
      "reason":"user",
      "watchModel":"Pebble Time",
      "watchProfileId":"basalt",
      "screen":{"width":144},
      "hasMicrophone":false,
      "hasCompass":true,
      "supportsHealth":true
    })

    assert {:Ok, ctx} = Decode.decode_value(decoder, json)
    assert ctx.watchModel == "Pebble Time"
    assert ctx.screen == 144
  end

  test "at index array and null decoders" do
    at_decoder = Decode.at(["payload", "response"], Decode.nullable(Decode.string()))

    assert {:Ok, :Nothing} =
             Decode.decode_value(at_decoder, %{"payload" => %{"response" => nil}})

    assert {:Ok, {:Just, "saved"}} =
             Decode.decode_value(at_decoder, %{"payload" => %{"response" => "saved"}})

    assert {:Ok, 5} = Decode.decode_value(Decode.index(1, Decode.int()), [4, 5, 6])

    assert {:Ok, [1, 2]} =
             Decode.decode_value(Decode.array(Decode.int()), [1, 2])

    assert {:Ok, "fallback"} = Decode.decode_value(Decode.null("fallback"), nil)
  end

  test "storage bool and json value kinds decode" do
    bool_decoder =
      Decode.and_then(
        fn
          "bool" ->
            Decode.map(fn flag -> {:BoolValue, flag} end, Decode.field("value", Decode.bool()))

          "json" ->
            Decode.map(fn json -> {:JsonValue, json} end, Decode.field("value", Decode.value()))

          _ ->
            Decode.fail("unknown")
        end,
        Decode.field("kind", Decode.string())
      )

    assert {:Ok, {:BoolValue, true}} =
             Decode.decode_value(bool_decoder, ~s({"kind":"bool","value":true}))

    assert {:Ok, {:JsonValue, %{"x" => 1}}} =
             Decode.decode_value(bool_decoder, ~s({"kind":"json","value":{"x":1}}))
  end

  test "dict and keyValuePairs decode objects" do
    assert {:Ok, %{"a" => 1, "b" => 2}} =
             Decode.decode_value(Decode.dict(Decode.int()), %{"a" => 1, "b" => 2})

    assert {:Ok, pairs} =
             Decode.decode_value(Decode.key_value_pairs(Decode.string()), %{"x" => "1", "y" => "2"})

    assert pairs == [{"x", "1"}, {"y", "2"}] or pairs == [{"y", "2"}, {"x", "1"}]
    assert length(pairs) == 2
  end

  test "lazy defers decoder construction" do
    decoder =
      Decode.lazy(fn ->
        Decode.field("name", Decode.string())
      end)

    assert {:Ok, "Ada"} = Decode.decode_value(decoder, ~s({"name":"Ada"}))
  end

  test "qualified dispatch for oneOf succeed decodeString map7" do
    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.oneOf", "decoders")
    assert code == "(Elmx.Runtime.Json.Decode.one_of(decoders))"

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.succeed", "42")
    assert code == "(Elmx.Runtime.Json.Decode.succeed(42))"

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.decodeString", "decoder, json")
    assert code == "Elmx.Runtime.Json.Decode.decode_string(decoder, json)"
  end
end
