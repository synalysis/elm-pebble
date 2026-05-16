defmodule Ide.Emulator.PebbleProtocol.TraceTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PebbleProtocol.Trace

  test "formats named endpoints with payload preview" do
    assert Trace.format("host->watch", 0x0034, <<1, 2, 3>>) ==
             "pebble-protocol host->watch endpoint=52 name=AppRunState len=3 payload=010203"
  end

  test "truncates long payloads" do
    payload = :binary.copy(<<0xAA>>, 25)

    assert Trace.format("watch->host", 0xBEEF, payload) ==
             "pebble-protocol watch->host endpoint=48879 name=PutBytes len=25 payload=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..."
  end
end
