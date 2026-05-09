defmodule Ide.Emulator.PBWInstallerTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBWInstaller
  alias Ide.Emulator.PebbleProtocol.Frame
  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router

  @uuid "3278ae24-9885-427f-90e7-791ac2450e78"
  @uuid_bytes Base.decode16!("3278AE249885427F90E7791AC2450E78")

  test "runs AppFetch and PutBytes sequence for binary and resources" do
    path = tmp_pbw()
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)

    task =
      Task.async(fn ->
        PBWInstaller.install(router, path, "emery", chunk_size: 2, timeout_ms: 1_000)
      end)

    assert {:ok, %{endpoint: 0xB1DB, payload: <<0x01, token::little-16, 0x02, _rest::binary>>}} =
             recv_frame(qemu)

    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xB1DB, <<token::little-16, 0x01>>)))

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    :ok =
      :gen_tcp.send(
        qemu,
        qemu_spp_packet(Frame.encode(6001, <<0x01, @uuid_bytes::binary, 0x11223344::little-32>>))
      )

    assert_putbytes_part(qemu, 0x11223344, 0x85, <<1, 2, 3>>, 0xABCDEF01)
    assert_putbytes_part(qemu, 0x11223344, 0x84, <<4, 5>>, 0xABCDEF02)

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    assert {:ok, result} = Task.await(task, 1_000)
    assert result.uuid == @uuid
    assert Enum.map(result.parts, & &1.kind) == [:binary, :resources]

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
  end

  test "retries transient PutBytes chunk NACKs" do
    path = tmp_pbw()
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)

    task =
      Task.async(fn ->
        PBWInstaller.install(router, path, "emery",
          chunk_size: 2,
          timeout_ms: 1_000,
          putbytes_retries: 1
        )
      end)

    assert {:ok, %{endpoint: 0xB1DB, payload: <<0x01, token::little-16, 0x02, _rest::binary>>}} =
             recv_frame(qemu)

    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xB1DB, <<token::little-16, 0x01>>)))

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    :ok =
      :gen_tcp.send(
        qemu,
        qemu_spp_packet(Frame.encode(6001, <<0x01, @uuid_bytes::binary, 0x11223344::little-32>>))
      )

    assert_putbytes_part(qemu, 0x11223344, 0x85, <<1, 2, 3>>, 0xABCDEF01,
      nack_first_chunk?: true
    )

    assert_putbytes_part(qemu, 0x11223344, 0x84, <<4, 5>>, 0xABCDEF02)

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    assert {:ok, result} = Task.await(task, 1_000)
    assert Enum.map(result.parts, & &1.kind) == [:binary, :resources]

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
  end

  test "resends whole part after commit NACK" do
    path = tmp_pbw()
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)

    task =
      Task.async(fn ->
        PBWInstaller.install(router, path, "emery",
          chunk_size: 2,
          timeout_ms: 1_000,
          chunk_delay_ms: 0,
          part_retries: 1
        )
      end)

    assert {:ok, %{endpoint: 0xB1DB, payload: <<0x01, token::little-16, 0x02, _rest::binary>>}} =
             recv_frame(qemu)

    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xB1DB, <<token::little-16, 0x01>>)))

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    :ok =
      :gen_tcp.send(
        qemu,
        qemu_spp_packet(Frame.encode(6001, <<0x01, @uuid_bytes::binary, 0x11223344::little-32>>))
      )

    assert_putbytes_part(qemu, 0x11223344, 0x85, <<1, 2, 3>>, 0xABCDEF01,
      nack_commit?: true
    )

    assert {:ok, %{endpoint: 0xBEEF, payload: <<0x04, 0xABCDEF01::32>>}} = recv_frame(qemu)
    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, 0xABCDEF01::32>>)))

    assert_putbytes_part(qemu, 0x11223344, 0x85, <<1, 2, 3>>, 0xABCDEF03)
    assert_putbytes_part(qemu, 0x11223344, 0x84, <<4, 5>>, 0xABCDEF02)

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    assert {:ok, result} = Task.await(task, 1_000)
    assert Enum.map(result.parts, & &1.kind) == [:binary, :resources]

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
  end

  test "retries full install handshake after binary commit NACK" do
    path = tmp_pbw()
    {:ok, server, qemu_port} = listen()
    {:ok, proxy_port} = free_port()
    {:ok, router} = Router.start_link(qemu_port: qemu_port, proxy_port: proxy_port)
    {:ok, qemu} = :gen_tcp.accept(server, 1_000)

    task =
      Task.async(fn ->
        PBWInstaller.install(router, path, "emery",
          chunk_size: 2,
          timeout_ms: 1_000,
          part_retries: 0,
          install_retries: 1,
          install_retry_delay_ms: 0
        )
      end)

    acknowledge_blob_insert(qemu)
    request_app_fetch(qemu, 0x11223344)

    assert_putbytes_part(qemu, 0x11223344, 0x85, <<1, 2, 3>>, 0xABCDEF01,
      nack_commit?: true
    )

    acknowledge_blob_insert(qemu)
    request_app_fetch(qemu, 0x55667788)

    assert_putbytes_part(qemu, 0x55667788, 0x85, <<1, 2, 3>>, 0xABCDEF02)
    assert_putbytes_part(qemu, 0x55667788, 0x84, <<4, 5>>, 0xABCDEF03)

    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    assert {:ok, result} = Task.await(task, 1_000)
    assert result.app_id == 0x55667788
    assert Enum.map(result.parts, & &1.kind) == [:binary, :resources]

    GenServer.stop(router)
    :gen_tcp.close(qemu)
    :gen_tcp.close(server)
  end

  defp assert_putbytes_part(qemu, app_id, object_type, data, cookie, opts \\ []) do
    data_size = byte_size(data)
    nack_first_chunk? = Keyword.get(opts, :nack_first_chunk?, false)
    nack_commit? = Keyword.get(opts, :nack_commit?, false)

    assert {:ok,
            %{endpoint: 0xBEEF, payload: <<0x01, ^data_size::32, ^object_type, ^app_id::32>>}} =
             recv_frame(qemu)

    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, cookie::32>>)))

    chunks(data, 2)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, index} ->
      chunk_size = byte_size(chunk)

      assert {:ok,
              %{endpoint: 0xBEEF, payload: <<0x02, ^cookie::32, ^chunk_size::32, ^chunk::binary>>}} =
               recv_frame(qemu)

      if nack_first_chunk? and index == 0 do
        :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x02, cookie::32>>)))

        assert {:ok,
                %{endpoint: 0xBEEF, payload: <<0x02, ^cookie::32, ^chunk_size::32, ^chunk::binary>>}} =
                 recv_frame(qemu)
      end

      :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, cookie::32>>)))
    end)

    assert {:ok, %{endpoint: 0xBEEF, payload: <<0x03, ^cookie::32, _crc::32>>}} = recv_frame(qemu)
    if nack_commit? do
      :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x02, cookie::32>>)))
      :ok
    else
      :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, cookie::32>>)))

      assert {:ok, %{endpoint: 0xBEEF, payload: <<0x05, ^cookie::32>>}} = recv_frame(qemu)
      :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xBEEF, <<0x01, cookie::32>>)))
    end
  end

  defp assert_recv_frame(socket, endpoint, payload) do
    assert {:ok, %{endpoint: ^endpoint, payload: ^payload}} = recv_frame(socket)
  end

  defp acknowledge_blob_insert(qemu) do
    assert {:ok, %{endpoint: 0xB1DB, payload: <<0x01, token::little-16, 0x02, _rest::binary>>}} =
             recv_frame(qemu)

    :ok = :gen_tcp.send(qemu, qemu_spp_packet(Frame.encode(0xB1DB, <<token::little-16, 0x01>>)))
  end

  defp request_app_fetch(qemu, app_id) do
    assert_recv_frame(qemu, 52, elem(Packets.app_run_state_start(@uuid), 1))

    :ok =
      :gen_tcp.send(
        qemu,
        qemu_spp_packet(Frame.encode(6001, <<0x01, @uuid_bytes::binary, app_id::little-32>>))
      )
  end

  defp recv_frame(socket) do
    with {:ok, <<0xFEED::16, 1::16, qemu_length::16>>} <- :gen_tcp.recv(socket, 6, 1_000),
         {:ok, data} <- :gen_tcp.recv(socket, qemu_length + 2, 1_000),
         <<length::16, endpoint::16, payload::binary-size(length), 0xBEEF::16>> <- data do
      {:ok, %{endpoint: endpoint, payload: payload}}
    end
  end

  defp qemu_spp_packet(payload), do: qemu_packet(1, payload)

  defp qemu_packet(protocol, payload) do
    <<0xFEED::16, protocol::16, byte_size(payload)::16, payload::binary, 0xBEEF::16>>
  end

  defp chunks(data, size) when byte_size(data) <= size, do: [data]

  defp chunks(data, size) do
    chunk = binary_part(data, 0, size)
    rest = binary_part(data, size, byte_size(data) - size)
    [chunk | chunks(rest, size)]
  end

  defp tmp_pbw do
    path =
      Path.join(System.tmp_dir!(), "installer-pbw-test-#{System.unique_integer([:positive])}.pbw")

    appinfo =
      Jason.encode!(%{
        "uuid" => @uuid,
        "targetPlatforms" => ["emery"],
        "watchapp" => %{"watchface" => true}
      })

    manifest =
      Jason.encode!(%{
        "manifestVersion" => 2,
        "application" => %{"name" => "pebble-app.bin", "size" => 3},
        "resources" => %{"name" => "app_resources.pbpack", "size" => 2}
      })

    {:ok, _path} =
      :zip.create(
        String.to_charlist(path),
        [
          {~c"appinfo.json", appinfo},
          {~c"emery/manifest.json", manifest},
          {~c"emery/pebble-app.bin", <<1, 2, 3>>},
          {~c"emery/app_resources.pbpack", <<4, 5>>}
        ]
      )

    path
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
end
