defmodule IdeWeb.EmulatorVncChannelTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  alias Ide.Emulator
  alias Ide.Emulator.VncReady
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

  @endpoint IdeWeb.Endpoint
  @handshake_timeout_ms 30_000

  test "join pushes RFB banner on frame events" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-channel-banner-test")

      try do
        assert info.display_ready == true

        assert {:ok, socket} = connect(IdeWeb.UserSocket, %{}, endpoint: @endpoint)
        assert {:ok, reply, _socket} = subscribe_and_join(socket, "emulator_vnc:#{info.id}", %{})

        encoded = Map.get(reply, "initial") || Map.get(reply, :initial)

        banner =
          if is_binary(encoded) do
            Base.decode64!(encoded)
          else
            assert_push "frame", {:binary, pushed}, @handshake_timeout_ms
            pushed
          end

        assert is_binary(banner)
        assert VncReady.version_line_complete?(banner)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  defp launch_diorite(slug) do
    EmulatorLaunch.launch(
      project_slug: slug,
      platform: "diorite",
      artifact_path: nil,
      has_phone_companion: false,
      has_companion_preferences: false
    )
  end
end
