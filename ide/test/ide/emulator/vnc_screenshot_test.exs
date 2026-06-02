defmodule Ide.Emulator.VncScreenshotTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.VncScreenshot
  alias Ide.Png

  test "capture reads framebuffer update without consuming an extra protocol byte" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen, 5_000)
        :gen_tcp.send(socket, "RFB 003.008\n")
        assert {:ok, _client} = recv_until_newline(socket)
        :gen_tcp.send(socket, <<1, 1>>)
        assert {:ok, <<1>>} = :gen_tcp.recv(socket, 1, 5_000)
        :gen_tcp.send(socket, <<0, 0, 0, 0>>)
        assert {:ok, <<1>>} = :gen_tcp.recv(socket, 1, 5_000)

        name = "test"
        pixel_format = <<32, 24, 0, 1, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0, 0>>

        :gen_tcp.send(
          socket,
          <<2::unsigned-big-16, 2::unsigned-big-16>> <>
            pixel_format <>
            <<byte_size(name)::unsigned-big-32>> <>
            name
        )

        assert {:ok, <<3, 0, 0, 0, 0, 0, 0, 144, 0, 168>>} = :gen_tcp.recv(socket, 10, 5_000)

        :gen_tcp.send(socket, <<0, 0, 0, 1>>)

        :gen_tcp.send(
          socket,
          <<0, 0, 144::unsigned-big-16, 168::unsigned-big-16, 0::signed-big-32>>
        )

        pixels = :binary.copy(<<0, 0, 255, 255>>, 144 * 168)
        :gen_tcp.send(socket, pixels)

        socket
      end)

    assert {:ok, png} = VncScreenshot.capture(port, platform: "basalt", timeout: 5_000)
    assert {:ok, 144, 168} = Png.dimensions(png)

    socket = Task.await(server, 5_000)
    :gen_tcp.close(socket)
    :gen_tcp.close(listen)
  end

  defp recv_until_newline(socket, acc \\ <<>>) do
    case :gen_tcp.recv(socket, 1, 5_000) do
      {:ok, <<?\n>>} -> {:ok, acc}
      {:ok, byte} -> recv_until_newline(socket, acc <> byte)
      other -> other
    end
  end
end
