defmodule Ide.Emulator.PBWInstaller.PutbytesTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBWInstaller.Putbytes
  alias Ide.Emulator.PebbleProtocol.Packets

  test "chunks/2 splits binary into fixed-size segments" do
    assert Putbytes.chunks(<<1, 2, 3, 4, 5>>, 2) == [<<1, 2>>, <<3, 4>>, <<5>>]
  end

  test "chunks/2 returns a single segment when data fits chunk_size" do
    assert Putbytes.chunks(<<10, 20>>, 8) == [<<10, 20>>]
  end

  test "chunks/2 returns empty list for empty input" do
    assert Putbytes.chunks(<<>>, 4) == []
  end

  test "putbytes ack helpers accept matching cookie lists" do
    response = %{ack?: true, result: :ack, cookie: 42}

    assert :ok = Packets.putbytes_ack?(response, [42, 0])
    assert {:error, {:wrong_cookie, [1], 42}} = Packets.putbytes_ack?(response, [1])
    assert {:error, {:nack, 7}} = Packets.putbytes_ack?(%{ack?: false, result: :nack, cookie: 7}, nil)
  end
end
