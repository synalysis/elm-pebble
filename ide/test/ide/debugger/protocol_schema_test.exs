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

    [msg | _] = schema.watch_to_phone
    assert %{name: "Ping", tag: tag, fields: fields} = msg
    assert is_integer(tag) and tag > 0
    assert [%{name: "field1", wire_type: :int, key: key} | _] = fields
    assert is_binary(key) and key != ""
  end
end
