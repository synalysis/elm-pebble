defmodule Ide.Emulator.VncReadyTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.VncReady

  test "wait_banner succeeds when server sends RFB version line" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])

    try do
      {:ok, port} = :inet.port(listen)
      parent = self()

      acceptor =
        spawn(fn ->
          {:ok, socket} = :gen_tcp.accept(listen)
          :gen_tcp.send(socket, "RFB 003.008\n")
          send(parent, :sent)
          Process.sleep(:infinity)
        end)

      assert :ok = VncReady.wait_banner(port, 2_000)
      assert_receive :sent, 1_000
      Process.exit(acceptor, :kill)
    after
      :gen_tcp.close(listen)
    end
  end

  test "wait_banner times out when port accepts but never sends RFB banner" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])

    try do
      {:ok, port} = :inet.port(listen)

      acceptor =
        spawn(fn ->
          {:ok, _socket} = :gen_tcp.accept(listen)
          Process.sleep(:infinity)
        end)

      assert {:error, :vnc_banner_timeout} = VncReady.wait_banner(port, 300)
      Process.exit(acceptor, :kill)
    after
      :gen_tcp.close(listen)
    end
  end

  test "banner_ready? is false for closed port" do
    refute VncReady.banner_ready?(59_999)
  end

  test "version_line_complete? requires a full RFB version line" do
    refute VncReady.version_line_complete?("RFB ")
    refute VncReady.version_line_complete?("RFB 003")
    assert VncReady.version_line_complete?("RFB 003.008\n")
  end

  test "wait_banner does not succeed on a partial RFB prefix" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])

    try do
      {:ok, port} = :inet.port(listen)

      acceptor =
        spawn(fn ->
          {:ok, socket} = :gen_tcp.accept(listen)
          :gen_tcp.send(socket, "RFB ")
          Process.sleep(:infinity)
        end)

      assert {:error, :vnc_banner_timeout} = VncReady.wait_banner(port, 300)
      Process.exit(acceptor, :kill)
    after
      :gen_tcp.close(listen)
    end
  end
end
