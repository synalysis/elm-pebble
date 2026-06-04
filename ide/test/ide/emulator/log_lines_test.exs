defmodule Ide.Emulator.LogLinesTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PebbleProtocol.LogLines

  test "formats AppLog text payloads" do
    payload = "App fault! PC: 0 LR: 0"

    assert [line] = LogLines.format_frame(%{endpoint: 0x07D6, payload: payload})
    assert line =~ "AppLog"
    assert line =~ "App fault!"
  end

  test "detects app fault lines" do
    assert LogLines.fault_line?(
             "App fault! {52a0b461-3c46-4a63-ad92-616540a2db5d} PC: 0 LR: 0"
           )
  end

  test "formats AppRunState stop (libpebble2 opcode 0x02)" do
    uuid_bytes = Base.decode16!("52A0B4613C464A63AD92616540A2DB5D")

    assert ["AppRunState stop uuid=52a0b461-3c46-4a63-ad92-616540a2db5d"] =
             LogLines.format_frame(%{endpoint: 52, payload: <<0x02, uuid_bytes::binary>>})
  end
end
