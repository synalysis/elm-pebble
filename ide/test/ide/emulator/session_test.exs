defmodule Ide.Emulator.SessionTest do
  use ExUnit.Case, async: false

  alias Ide.Emulator
  alias Ide.Emulator.Session
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

  test "launch creates an unguessable session with websocket paths and controls" do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "wf-analog",
                 platform: "flint",
                 artifact_path: "/tmp/app.pbw"
               )

      assert is_binary(info.id)
      assert byte_size(info.id) > 16
      assert info.project_slug == "wf-analog"
      assert info.platform == "flint"
      assert info.vnc_path == "/api/emulator/#{info.id}/ws/vnc"
      assert info.phone_path == "/api/emulator/#{info.id}/ws/phone"
      assert info.install_path == "/api/emulator/#{info.id}/install"
      assert "button_select" in info.controls
      assert "battery" in info.controls

      assert :ok = Emulator.kill(info.id)
    end)
  end

  test "qemu arguments declare platform-specific machine and local websocket vnc" do
    state = %{
      platform: "basalt",
      bt_port: 12_000,
      console_port: 12_001,
      vnc_display: 7,
      vnc_ws_port: 12_002,
      spi_image_path: "/tmp/spi.bin"
    }

    args = Session.qemu_args(state)

    assert ["-machine", "pebble-snowy-bb", "-cpu", "cortex-m4"] ==
             Enum.take(Session.machine_args("basalt", "/tmp/spi.bin"), 4)

    assert "-kernel" in args
    assert "-L" in args
    assert "-vnc" in args
    assert ":7,websocket=12002" in args
    assert "tcp:127.0.0.1:12000,server=on,wait=off" in args
    assert "if=none,id=spi-flash,file=/tmp/spi.bin,format=raw" in args
  end

  test "qemu readiness uses vnc websocket port and leaves bluetooth port for pypkjs" do
    state = %{
      platform: "basalt",
      bt_port: 12_000,
      console_port: 12_001,
      vnc_display: 7,
      vnc_ws_port: 12_002,
      spi_image_path: "/tmp/spi.bin"
    }

    args = Session.qemu_args(state)

    assert "tcp:127.0.0.1:12000,server=on,wait=off" in args
    assert ":7,websocket=12002" in args
  end

  test "modern qemu-pebble models use mtd flash for newer platforms" do
    args = Session.machine_args("emery", "/tmp/spi.bin")

    assert ["-machine", "pebble-emery", "-cpu", "cortex-m33"] == Enum.take(args, 4)
    assert "-drive" in args
    assert "if=mtd,format=raw,file=/tmp/spi.bin" in args
    assert "driver=none,id=audio0" in args
  end

  test "pypkjs arguments include qemu bridge, websocket port, and persist dir" do
    args =
      Session.pypkjs_args(%{
        platform: "basalt",
        bt_port: 12_000,
        phone_ws_port: 12_001,
        token: "secret",
        persist_dir: "/tmp/persist"
      })

    prefix = ["--qemu", "127.0.0.1:12000", "--port", "12001", "--persist", "/tmp/persist"]

    assert List.starts_with?(args, prefix)

    case Enum.drop(args, length(prefix)) do
      [] ->
        :ok

      ["--layout", path] ->
        assert is_binary(path) and String.ends_with?(path, "layouts.json")

      other ->
        flunk("unexpected pypkjs args tail: #{inspect(other)}")
    end
  end

  test "pypkjs arguments use protocol proxy port when present" do
    args =
      Session.pypkjs_args(%{
        platform: "basalt",
        bt_port: 12_000,
        protocol_proxy_port: 12_099,
        phone_ws_port: 12_001,
        token: "secret",
        persist_dir: "/tmp/persist"
      })

    assert Enum.take(args, 2) == ["--qemu", "127.0.0.1:12099"]
  end

  test "pypkjs command uses the pypkjs interpreter for the embedded wrapper" do
    script = Path.join(System.tmp_dir!(), "pypkjs-test-#{System.unique_integer([:positive])}")
    python = System.find_executable("sh") || "/bin/sh"

    File.write!(script, "#!#{python}\n")

    assert {:ok, ^python, [wrapper]} = Session.pypkjs_command(script)
    assert String.ends_with?(wrapper, "priv/python/embedded_pypkjs.py")

    File.rm(script)
  end
end
