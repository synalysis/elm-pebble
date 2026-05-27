defmodule Ide.Emulator.Session.InfoTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Session.Info

  test "display_ready?/1 is false without qemu and vnc banner" do
    state = %{
      id: "sess",
      token: "tok",
      project_slug: "demo",
      platform: "chalk",
      qemu_pid: nil,
      pypkjs_pid: nil,
      phone_ws_port: 0,
      vnc_banner_ready: false
    }

    refute Info.display_ready?(state)
  end

  test "public_info/1 includes api paths and platform" do
    state = %{
      id: "abc",
      token: "secret",
      project_slug: "demo",
      platform: "chalk",
      artifact_path: "/tmp/x.pbw",
      app_uuid: nil,
      has_phone_companion: false,
      has_companion_preferences: false,
      qemu_pid: nil,
      pypkjs_pid: nil,
      phone_ws_port: 0,
      vnc_banner_ready: false
    }

    info = Info.public_info(state)

    assert info.id == "abc"
    assert info.platform == "chalk"
    assert info.artifact_path == "/api/emulator/abc/artifact"
    assert info.ping_path == "/api/emulator/abc/ping"
    assert is_map(info.screen)
    assert is_list(info.controls)
  end
end
