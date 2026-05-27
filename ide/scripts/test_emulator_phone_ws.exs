# Usage: mix run scripts/test_emulator_phone_ws.exs
# Verifies embedded emulator launch + phone websocket (direct and via EmulatorProxyClient).

defmodule EmulatorPhoneWsScript.Probe do
  use WebSockex

  def handle_connect(_conn, %{owner: owner}) do
    send(owner, :ws_open)
    {:ok, %{}}
  end

  def handle_frame(_frame, state), do: {:ok, state}
end

Application.ensure_all_started(:ide)

{:ok, info} =
  Ide.Emulator.launch(
    project_slug: "phone-ws-script",
    platform: "basalt",
    artifact_path: nil,
    has_phone_companion: false,
    has_companion_preferences: false
  )

{:ok, pid} = Ide.Emulator.lookup(info.id)
port = Ide.Emulator.Session.local_port(pid, :phone)

IO.puts("session=#{info.id} phone_port=#{port} bridge_ready=#{info.phone_bridge_ready}")

owner = self()

t0 = System.monotonic_time(:millisecond)

{:ok, direct} =
  WebSockex.start_link(
    "ws://127.0.0.1:#{port}/",
    EmulatorPhoneWsScript.Probe,
    %{owner: owner},
    async_connect: true
  )

receive do
  :ws_open -> IO.puts("direct pypkjs websocket: ok in #{System.monotonic_time(:millisecond) - t0}ms")
after
  5_000 -> IO.puts("direct pypkjs websocket: TIMEOUT"); System.halt(1)
end

Process.exit(direct, :normal)

t1 = System.monotonic_time(:millisecond)

{:ok, proxy} = IdeWeb.EmulatorProxyClient.start_link("ws://127.0.0.1:#{port}/", owner)

receive do
  :emulator_proxy_upstream_connected ->
    IO.puts("proxy client (async_connect): ok in #{System.monotonic_time(:millisecond) - t1}ms")
after
  5_000 -> IO.puts("proxy client: TIMEOUT"); System.halt(1)
end

Process.exit(proxy, :normal)
Ide.Emulator.kill(info.id)
IO.puts("done")
