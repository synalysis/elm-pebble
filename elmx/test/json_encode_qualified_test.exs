defmodule Elmx.JsonEncodeQualifiedTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Stdlib

  test "Json.Encode.string compiles via stdlib qualified dispatch" do
    assert {:ok, code} = Stdlib.qualified_call("Json.Encode.string", ~s("metric"))
    assert code == "(Elmx.Runtime.Json.Encode.string(\"metric\"))"
  end

  test "runtime Json.Encode.string returns plain string values" do
    assert Elmx.Runtime.Json.Encode.string("imperial") == "imperial"
  end

  test "Json.Encode.int compiles and returns integers" do
    assert {:ok, code} = Stdlib.qualified_call("Json.Encode.int", "42")
    assert code == "(Elmx.Runtime.Json.Encode.int(42))"
    assert Elmx.Runtime.Json.Encode.int(42) == 42
  end

  test "Json.Decode.string and decodeValue compile via qualified dispatch" do
    assert {:ok, "Elmx.Runtime.Json.Decode.string()"} =
             Stdlib.qualified_call("Json.Decode.string", "")

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.decodeValue", "decoder, value")
    assert code == "Elmx.Runtime.Json.Decode.decode_value(decoder, value)"
  end

  test "runtime decode_value decodes plain strings" do
    assert {:Ok, "metric"} =
             Elmx.Runtime.Json.Decode.decode_value(Elmx.Runtime.Json.Decode.string(), "metric")
  end

  test "Json.Encode.object and list via special values and runtime" do
    pairs = [
      {"kind", "string"},
      {"value", "dark"}
    ]

    assert {:ok, %{op: :runtime_call, function: "elmx_json_encode_object", args: [^pairs]}} =
             SpecialValues.rewrite("Json.Encode.object", [pairs])

    assert ~s({"kind":"string","value":"dark"}) =
             Pebble.runtime_dispatch("elmx_json_encode_encode", [
               0,
               Pebble.runtime_dispatch("elmx_json_encode_object", [pairs])
             ])

    assert {:ok, code} = Stdlib.qualified_call("Json.Encode.null", "")
    assert code == "Elmx.Runtime.Json.Encode.null()"
    assert nil == Elmx.Runtime.Json.Encode.null()

    items = ["a", "b"]

    assert ["A", "B"] =
             Elmx.Runtime.Json.Encode.list(fn s -> String.upcase(s) end, items)

    assert {:ok, code} = Stdlib.qualified_call("Json.Encode.encode", "0, payload")
    assert code == "Elmx.Runtime.Json.Encode.encode(0, payload)"

    assert ~s({"k":1}) = Elmx.Runtime.Json.Encode.encode(0, %{"k" => 1})
  end
end
