defmodule Ide.Debugger.ProtocolSchemaTest do
  use ExUnit.Case, async: true

  alias Ide.CompanionProtocolGenerator

  @types """
  module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

  type WatchToPhone
      = Ping Int

  type PhoneToWatch
      = Pong Int
  """

  test "schema_from_source matches declared Schema.t shape" do
    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(@types)
    assert is_map(schema.enums)
    assert is_list(schema.watch_to_phone)
    assert is_list(schema.phone_to_watch)
    assert is_map(schema.key_ids)
    assert is_map(schema.type_aliases)
    assert is_list(schema.wire_slots)

    [msg | _] = schema.watch_to_phone
    assert %{name: "Ping", tag: tag, fields: fields} = msg
    assert is_integer(tag) and tag > 0
    assert [%{name: "field1", wire_type: :int, key: key} | _] = fields
    assert is_binary(key) and key != ""
  end

  test "schema exposes type aliases and flattened wire slots" do
    types = """
    module Companion.Types exposing (PhoneToWatch(..), Point, WatchToPhone(..))

    type alias Point =
        { x : Int, y : Int }

    type WatchToPhone
        = Ping Int

    type PhoneToWatch
        = SetOrigin Point
    """

    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(types)

    assert [%{name: "x", type: "Int"}, %{name: "y", type: "Int"}] = schema.type_aliases["Point"]
    assert Enum.any?(schema.wire_slots, &(&1.key == "set_origin_field1_x"))
    assert Enum.any?(schema.wire_slots, &(&1.key == "set_origin_field1_y"))
  end
end
