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
      assert info.app_uuid == nil
      assert "button_select" in info.controls
      assert "battery" in info.controls

      assert :ok = Emulator.kill(info.id)
    end)
  end

  test "launch stores emulator state by project and platform" do
    EmulatorSessionEnv.run(fn ->
      root =
        Path.join(
          System.tmp_dir!(),
          "elm-pebble-emulator-state-test-#{System.unique_integer([:positive])}"
        )

      previous = Application.get_env(:ide, Ide.Emulator.Session)
      Application.put_env(:ide, Ide.Emulator.Session, Keyword.put(previous, :state_root, root))

      try do
        assert {:ok, info} =
                 EmulatorLaunch.launch(
                   project_slug: "my game",
                   platform: "basalt",
                   artifact_path: nil
                 )

        assert :ok = Emulator.kill(info.id)

        assert File.exists?(Path.join(root, "my-game/basalt/qemu_spi_flash.bin"))
        assert File.dir?(Path.join(root, "my-game/basalt/pypkjs"))
      after
        Application.put_env(:ide, Ide.Emulator.Session, previous)
        File.rm_rf!(root)
      end
    end)
  end

  test "session exits when a managed emulator child exits" do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "wf-analog",
                 platform: "basalt",
                 artifact_path: nil
               )

      assert {:ok, session_pid} = Emulator.lookup(info.id)

      child =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :sys.replace_state(session_pid, fn state -> %{state | qemu_pid: child} end)
      send(session_pid, {:EXIT, child, :normal})

      assert wait_until(fn -> not Process.alive?(session_pid) end)
      assert wait_until(fn -> Emulator.lookup(info.id) == {:error, :not_found} end)
      send(child, :stop)
    end)
  end

  test "ping reports an unresponsive session without blocking the caller" do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "wf-analog",
                 platform: "basalt",
                 artifact_path: nil
               )

      assert {:ok, session_pid} = Emulator.lookup(info.id)
      :ok = :sys.suspend(session_pid)

      started_at = System.monotonic_time(:millisecond)
      assert {:error, :emulator_session_unresponsive} = Emulator.ping(info.id)
      assert System.monotonic_time(:millisecond) - started_at < 2_000

      assert :ok = Emulator.kill(info.id)
      assert wait_until(fn -> not Process.alive?(session_pid) end)
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

    assert "-pflash" in args
    assert "-L" in args
    assert "-vnc" in args
    assert ":7" in args
    refute ":7,websocket=12002" in args
    assert "tcp:127.0.0.1:12000,server=on,wait=off" in args
    assert "/tmp/spi.bin" in args
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
    assert ":7" in args
    refute ":7,websocket=12002" in args
  end

  test "emery qemu args match the SDK emulator launcher" do
    args = Session.machine_args("emery", "/tmp/spi.bin")

    assert ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4"] == Enum.take(args, 4)
    assert "-pflash" in args
    assert "/tmp/spi.bin" in args
    refute "-audio" in args
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

  test "runtime status reports disabled embedded emulator before launch" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)
    Application.put_env(:ide, Ide.Emulator.Session, enabled: false)

    try do
      status = Session.runtime_status("basalt")

      assert status.status == :warning

      assert %{id: :embedded_emulator, status: :missing, installable: false} =
               Enum.find(status.components, &(&1.id == :embedded_emulator))
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
    end
  end

  test "runtime status discovers qemu and images from sdk roots" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-sdk-root-test-#{System.unique_integer([:positive])}"
      )

    sdk_root = Path.join(root, "SDKs/current")
    qemu_bin = Path.join(sdk_root, "toolchain/bin/qemu-pebble")
    qemu_dir = Path.join(sdk_root, "sdk-core/pebble/basalt/qemu")

    File.mkdir_p!(Path.dirname(qemu_bin))
    File.mkdir_p!(qemu_dir)
    File.write!(qemu_bin, "#!/bin/sh\necho qemu-pebble test\n")
    File.chmod!(qemu_bin, 0o755)
    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [sdk_root],
      qemu_image_root: nil
    )

    try do
      status = Session.runtime_status("basalt")

      assert %{id: :qemu, status: :ok, detail: ^qemu_bin} =
               Enum.find(status.components, &(&1.id == :qemu))

      assert %{id: :qemu_micro_flash, status: :ok} =
               Enum.find(status.components, &(&1.id == :qemu_micro_flash))

      assert %{id: :qemu_spi_flash, status: :ok} =
               Enum.find(status.components, &(&1.id == :qemu_spi_flash))
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
      File.rm_rf!(root)
    end
  end

  test "runtime status reports qemu dynamic library failures" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-qemu-health-test-#{System.unique_integer([:positive])}"
      )

    sdk_root = Path.join(root, "SDKs/current")
    qemu_bin = Path.join(sdk_root, "toolchain/bin/qemu-pebble")

    File.mkdir_p!(Path.dirname(qemu_bin))

    File.write!(qemu_bin, """
    #!/bin/sh
    echo "Library not loaded: /usr/local/opt/pixman/lib/libpixman-1.0.dylib"
    exit 134
    """)

    File.chmod!(qemu_bin, 0o755)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [sdk_root],
      qemu_image_root: nil
    )

    try do
      status = Session.runtime_status("basalt")

      assert status.status == :warning

      assert %{id: :qemu, status: :missing, installable: false, detail: detail} =
               Enum.find(status.components, &(&1.id == :qemu))

      assert detail =~ "missing x86_64 Homebrew pixman"
      assert detail =~ "arch -x86_64 /usr/local/bin/brew install pixman"
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
      File.rm_rf!(root)
    end
  end

  defp wait_until(fun, attempts \\ 20)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end
end
