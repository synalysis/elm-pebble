defmodule Ide.Emulator.PebbleProtocol.RouterTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PebbleProtocol.Frame
  alias Ide.Emulator.PebbleProtocol.Router

  test "proxies QEMU frames to pypkjs clients" do
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)
    {:ok, pypkjs} = :gen_tcp.connect(~c"127.0.0.1", proxy_port, [:binary, active: false])
    Process.sleep(150)

    raw = qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, 0, 0, 0, 7>>))
    :ok = :gen_tcp.send(qemu, raw)

    assert {:ok, ^raw} = :gen_tcp.recv(pypkjs, byte_size(raw), 1_000)

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
    :gen_tcp.close(pypkjs)
  end

  test "sends internal requests and awaits matching responses" do
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)

    task =
      Task.async(fn ->
        Router.send_and_await(router, 0xBEEF, <<0x05, 0, 0, 0, 1>>, fn frame ->
          frame.endpoint == 0xBEEF and frame.payload == <<0x01, 0, 0, 0, 1>>
        end)
      end)

    assert {:ok, request} = :gen_tcp.recv(qemu, 0, 1_000)
    assert request == qemu_spp_packet(Frame.encode(0xBEEF, <<0x05, 0, 0, 0, 1>>))

    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, 0, 0, 0, 1>>)))
    assert {:ok, %{payload: <<0x01, 0, 0, 0, 1>>}} = Task.await(task, 1_000)

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
  end

  test "returns observed non-matching frames on waiter timeout" do
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)

    task =
      Task.async(fn ->
        Router.send_and_await(
          router,
          0x0034,
          <<0x01>>,
          fn frame -> frame.endpoint == 0x1771 end,
          100
        )
      end)

    assert {:ok, _request} = :gen_tcp.recv(qemu, 0, 1_000)
    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0x1A7A, <<0x07, 0x34>>)))

    assert {:error, {:timeout, [%{endpoint: 0x1A7A, payload_prefix: "0734"}]}} =
             Task.await(task, 1_000)

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
  end

  test "writes protocol trace when enabled" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-trace-#{System.unique_integer([:positive])}.log"
      )

    previous_enabled = System.get_env("ELM_PEBBLE_PROTOCOL_TRACE")
    previous_file = System.get_env("ELM_PEBBLE_PROTOCOL_TRACE_FILE")

    System.put_env("ELM_PEBBLE_PROTOCOL_TRACE", "1")
    System.put_env("ELM_PEBBLE_PROTOCOL_TRACE_FILE", tmp)

    try do
      {:ok, server, qemu_port} = listen()
      {:ok, proxy_port} = free_port()
      {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
      {:ok, qemu} = :gen_tcp.accept(server, 1_000)

      task =
        Task.async(fn ->
          Router.send_and_await(router, 0x0034, <<0x01>>, fn frame ->
            frame.endpoint == 0x1A7A
          end)
        end)

      assert {:ok, _request} = :gen_tcp.recv(qemu, 0, 1_000)
      :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0x1A7A, <<0x07, 0x34>>)))
      assert {:ok, %{endpoint: 0x1A7A}} = Task.await(task, 1_000)

      trace = File.read!(tmp)
      assert trace =~ "pebble-protocol host->watch endpoint=52 name=AppRunState"
      assert trace =~ "pebble-protocol watch->host endpoint=6778 name=DataLogging"

      GenServer.stop(router)
      :gen_tcp.close(qemu)
      :gen_tcp.close(server)
    after
      restore_env("ELM_PEBBLE_PROTOCOL_TRACE", previous_enabled)
      restore_env("ELM_PEBBLE_PROTOCOL_TRACE_FILE", previous_file)
      File.rm(tmp)
    end
  end

  test "queues pypkjs outbound frames while locked" do
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)
    {:ok, pypkjs} = :gen_tcp.connect(~c"127.0.0.1", proxy_port, [:binary, active: false])

    assert :ok = Router.acquire(router)
    :ok = :gen_tcp.send(pypkjs, qemu_spp_packet(Frame.encode(0xBEEF, <<0x02>>)))
    assert {:error, :timeout} = :gen_tcp.recv(qemu, 0, 100)

    assert :ok = Router.release(router)
    assert {:ok, data} = :gen_tcp.recv(qemu, 0, 1_000)
    assert data == qemu_spp_packet(Frame.encode(0xBEEF, <<0x02>>))

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
    :gen_tcp.close(pypkjs)
  end

  defp listen do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(socket)
    {:ok, socket, port}
  end

  defp free_port do
    {:ok, socket, port} = listen()
    :gen_tcp.close(socket)
    {:ok, port}
  end

  defp qemu_spp_packet(payload), do: qemu_packet(1, payload)

  defp qemu_packet(protocol, payload) do
    <<0xFEED::16, protocol::16, byte_size(payload)::16, payload::binary, 0xBEEF::16>>
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
