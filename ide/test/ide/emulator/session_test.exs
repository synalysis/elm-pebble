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

  test "launch refreshes existing spi flash from sdk image" do
    EmulatorSessionEnv.run(fn ->
      root =
        Path.join(
          System.tmp_dir!(),
          "elm-pebble-emulator-state-test-#{System.unique_integer([:positive])}"
        )

      image_root =
        Path.join(
          System.tmp_dir!(),
          "elm-pebble-emulator-images-test-#{System.unique_integer([:positive])}"
        )

      qemu_dir = Path.join([image_root, "basalt", "qemu"])
      state_image = Path.join(root, "my-game/basalt/qemu_spi_flash.bin")

      File.mkdir_p!(qemu_dir)
      File.mkdir_p!(Path.dirname(state_image))
      File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
      File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin"), "fresh sdk image")
      File.write!(state_image, "stale installed app")

      previous = Application.get_env(:ide, Ide.Emulator.Session)

      Application.put_env(
        :ide,
        Ide.Emulator.Session,
        Keyword.merge(previous, state_root: root, qemu_image_root: image_root)
      )

      try do
        assert {:ok, info} =
                 EmulatorLaunch.launch(
                   project_slug: "my game",
                   platform: "basalt",
                   artifact_path: nil
                 )

        assert :ok = Emulator.kill(info.id)
        refute File.read!(state_image) == "stale installed app"
      after
        Application.put_env(:ide, Ide.Emulator.Session, previous)
        File.rm_rf!(root)
        File.rm_rf!(image_root)
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

  test "runtime status reports Linux missing shared library failures with OS hints" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-qemu-linux-library-test-#{System.unique_integer([:positive])}"
      )

    sdk_root = Path.join(root, "SDKs/current")
    qemu_bin = Path.join(sdk_root, "toolchain/bin/qemu-pebble")

    File.mkdir_p!(Path.dirname(qemu_bin))

    File.write!(qemu_bin, """
    #!/bin/sh
    echo "#{qemu_bin}: error while loading shared libraries: libsndio.so.7: cannot open shared object file: No such file or directory"
    exit 127
    """)

    File.chmod!(qemu_bin, 0o755)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [sdk_root],
      qemu_image_root: nil
    )

    try do
      status = Session.runtime_status("basalt")

      assert %{id: :qemu, status: :missing, installable: false, detail: detail} =
               Enum.find(status.components, &(&1.id == :qemu))

      assert detail =~ "missing Linux shared library libsndio.so.7"
      assert detail =~ "Debian/Ubuntu"
      assert detail =~ "Fedora"
      assert detail =~ "standard Fedora repositories"
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
      File.rm_rf!(root)
    end
  end

  test "runtime status reports missing SDK Python env as installable" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-sdk-python-env-test-#{System.unique_integer([:positive])}"
      )

    sdk_root = Path.join(root, "SDKs/current")
    requirements = Path.join(sdk_root, "sdk-core/requirements.txt")

    File.mkdir_p!(Path.dirname(requirements))
    File.write!(requirements, "pypng>=0.20220715.0\n")

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [sdk_root],
      qemu_image_root: nil
    )

    try do
      status = Session.runtime_status("basalt")

      assert %{id: :pebble_sdk_python_env, status: :missing, installable: true} =
               Enum.find(status.components, &(&1.id == :pebble_sdk_python_env))

      assert status.installable
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
      File.rm_rf!(root)
    end
  end

  test "runtime status reports missing SDK JS dependencies as installable" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-sdk-node-env-test-#{System.unique_integer([:positive])}"
      )

    sdk_root = Path.join(root, "SDKs/current")
    package_json = Path.join(sdk_root, "sdk-core/package.json")

    File.mkdir_p!(Path.dirname(package_json))
    File.write!(package_json, ~s({"dependencies":{}}))

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [sdk_root],
      qemu_image_root: nil
    )

    try do
      status = Session.runtime_status("basalt")

      assert %{id: :pebble_sdk_node_modules, status: :missing, installable: true} =
               Enum.find(status.components, &(&1.id == :pebble_sdk_node_modules))

      assert status.installable
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
      File.rm_rf!(root)
    end
  end

  test "runtime status checks ARM GCC in versioned SDK root used by pebble build" do
    previous = Application.get_env(:ide, Ide.Emulator.Session)

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-versioned-gcc-test-#{System.unique_integer([:positive])}"
      )

    current_root = Path.join(root, "SDKs/current")
    current_gcc = Path.join(current_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-gcc")

    File.mkdir_p!(Path.dirname(current_gcc))
    File.write!(current_gcc, "#!/bin/sh\n")

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [current_root],
      sdk_core_version: "4.9.169",
      qemu_image_root: nil
    )

    try do
      status = Session.runtime_status("basalt")
      expected = Path.join(root, "SDKs/4.9.169/toolchain/arm-none-eabi/bin/arm-none-eabi-gcc")

      assert %{id: :pebble_arm_gcc, status: :missing, installable: true, detail: ^expected} =
               Enum.find(status.components, &(&1.id == :pebble_arm_gcc))
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous)
      File.rm_rf!(root)
    end
  end

  test "runtime dependency install refreshes pebble-tool with supported Python before SDK install" do
    previous_config = Application.get_env(:ide, Ide.Emulator.Session)
    previous_path = System.get_env("PATH")
    previous_command_log = System.get_env("COMMAND_LOG")

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-install-python-test-#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    log_path = Path.join(root, "commands.log")
    image_root = Path.join(root, "images")
    qemu_dir = Path.join([image_root, "basalt", "qemu"])
    pebble_bin = Path.join(bin_dir, "pebble")
    pypkjs_bin = Path.join(bin_dir, "pypkjs")
    uv_bin = Path.join(bin_dir, "uv")
    sdk_archive_path = write_sdk_core_archive!(root)
    toolchain_archive_path = write_toolchain_archive!(root)

    File.mkdir_p!(bin_dir)
    File.mkdir_p!(qemu_dir)
    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")

    write_command_logger!(uv_bin, "uv")
    write_command_logger!(pebble_bin, "pebble")
    write_command_logger!(pypkjs_bin, "pypkjs")

    path = if previous_path in [nil, ""], do: bin_dir, else: "#{bin_dir}:#{previous_path}"

    System.put_env("PATH", path)
    System.put_env("COMMAND_LOG", log_path)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      pebble_bin: pebble_bin,
      pypkjs_bin: pypkjs_bin,
      qemu_image_root: image_root,
      sdk_roots: [Path.join(root, "SDKs/current")],
      sdk_core_version: "4.9.169",
      sdk_core_archive_path: sdk_archive_path,
      sdk_toolchain_archive_path: toolchain_archive_path,
      pebble_tool_python: "3.13"
    )

    try do
      assert {:ok, result} = Session.install_runtime_dependencies("basalt")

      assert Enum.map(result.results, & &1.name) == [
               :pebble_tool,
               :pebble_sdk,
               :qemu_images
             ]

      log = File.read!(log_path)
      assert log =~ "uv tool install --force --python 3.13 pebble-tool"
      refute log =~ "pebble sdk install"
      assert File.exists?(Path.join(root, "SDKs/current/toolchain/bin/qemu-pebble"))
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous_config)
      restore_env("PATH", previous_path)
      restore_env("COMMAND_LOG", previous_command_log)
      File.rm_rf!(root)
    end
  end

  test "runtime dependency install asks uv to install missing managed Python and retries" do
    previous_config = Application.get_env(:ide, Ide.Emulator.Session)
    previous_path = System.get_env("PATH")
    previous_command_log = System.get_env("COMMAND_LOG")

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-install-managed-python-test-#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    log_path = Path.join(root, "commands.log")
    image_root = Path.join(root, "images")
    qemu_dir = Path.join([image_root, "basalt", "qemu"])
    pebble_bin = Path.join(bin_dir, "pebble")
    pypkjs_bin = Path.join(bin_dir, "pypkjs")
    uv_bin = Path.join(bin_dir, "uv")
    sdk_archive_path = write_sdk_core_archive!(root)
    toolchain_archive_path = write_toolchain_archive!(root)

    File.mkdir_p!(bin_dir)
    File.mkdir_p!(qemu_dir)
    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")

    write_uv_requiring_python_install!(uv_bin)
    write_command_logger!(pebble_bin, "pebble")
    write_command_logger!(pypkjs_bin, "pypkjs")

    path = if previous_path in [nil, ""], do: bin_dir, else: "#{bin_dir}:#{previous_path}"

    System.put_env("PATH", path)
    System.put_env("COMMAND_LOG", log_path)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      pebble_bin: pebble_bin,
      pypkjs_bin: pypkjs_bin,
      qemu_image_root: image_root,
      sdk_roots: [Path.join(root, "SDKs/current")],
      sdk_core_version: "4.9.169",
      sdk_core_archive_path: sdk_archive_path,
      sdk_toolchain_archive_path: toolchain_archive_path,
      pebble_tool_python: "3.13"
    )

    try do
      assert {:ok, result} = Session.install_runtime_dependencies("basalt")

      assert Enum.map(result.results, & &1.name) == [
               :pebble_tool,
               :pebble_sdk,
               :qemu_images
             ]

      log = File.read!(log_path)
      assert log =~ "uv tool install --force --python 3.13 pebble-tool"
      assert log =~ "uv python install 3.13"
      refute log =~ "pebble sdk install"
      assert File.exists?(Path.join(root, "SDKs/current/toolchain/bin/qemu-pebble"))
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous_config)
      restore_env("PATH", previous_path)
      restore_env("COMMAND_LOG", previous_command_log)
      File.rm_rf!(root)
    end
  end

  test "runtime dependency install stops when pebble-tool cannot be refreshed" do
    previous_config = Application.get_env(:ide, Ide.Emulator.Session)
    previous_path = System.get_env("PATH")
    previous_command_log = System.get_env("COMMAND_LOG")

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-runtime-install-stop-test-#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    log_path = Path.join(root, "commands.log")
    image_root = Path.join(root, "images")
    qemu_dir = Path.join([image_root, "basalt", "qemu"])

    File.mkdir_p!(bin_dir)
    File.mkdir_p!(qemu_dir)
    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")

    write_failing_command_logger!(Path.join(bin_dir, "uv"), "uv")
    write_command_logger!(Path.join(bin_dir, "pebble"), "pebble")
    write_command_logger!(Path.join(bin_dir, "pypkjs"), "pypkjs")

    path = if previous_path in [nil, ""], do: bin_dir, else: "#{bin_dir}:#{previous_path}"

    System.put_env("PATH", path)
    System.put_env("COMMAND_LOG", log_path)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      qemu_image_root: image_root,
      sdk_roots: [Path.join(root, "SDKs/current")],
      sdk_core_version: "4.9.169",
      pebble_tool_python: "3.13"
    )

    try do
      assert {:ok, result} = Session.install_runtime_dependencies("basalt")

      assert [%{name: :pebble_tool, status: :error}] = result.results

      log = File.read!(log_path)
      assert log =~ "uv tool install --force --python 3.13 pebble-tool"
      refute log =~ "pebble sdk install"
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous_config)
      restore_env("PATH", previous_path)
      restore_env("COMMAND_LOG", previous_command_log)
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

  defp write_command_logger!(path, name) do
    File.write!(path, """
    #!/bin/sh
    echo "#{name} $*" >> "$COMMAND_LOG"
    exit 0
    """)

    File.chmod!(path, 0o755)
  end

  defp write_failing_command_logger!(path, name) do
    File.write!(path, """
    #!/bin/sh
    echo "#{name} $*" >> "$COMMAND_LOG"
    echo "failed"
    exit 1
    """)

    File.chmod!(path, 0o755)
  end

  defp write_uv_requiring_python_install!(path) do
    File.write!(path, """
    #!/bin/sh
    echo "uv $*" >> "$COMMAND_LOG"

    if [ "$1 $2" = "python install" ]; then
      touch "$(dirname "$COMMAND_LOG")/managed-python-installed"
      exit 0
    fi

    if [ "$1 $2" = "tool install" ] && [ ! -f "$(dirname "$COMMAND_LOG")/managed-python-installed" ]; then
      echo "error: No interpreter found for Python 3.13 in search path or managed installations"
      echo ""
      echo "hint: A managed Python download is available for Python 3.13, but Python downloads are set to 'manual', use \\`uv python install 3.13\\` to install the required version"
      exit 2
    fi

    exit 0
    """)

    File.chmod!(path, 0o755)
  end

  defp write_sdk_core_archive!(root) do
    archive_path = Path.join(root, "sdk-core-test.tar.gz")
    source_root = Path.join(root, "sdk-core-archive")
    pebble_root = Path.join(source_root, "sdk-core/pebble")

    File.mkdir_p!(pebble_root)
    File.write!(Path.join(source_root, "sdk-core/manifest.json"), ~s({"version":"4.9.169"}))

    {_, 0} = System.cmd("tar", ["czf", archive_path, "-C", source_root, "."])

    archive_path
  end

  defp write_toolchain_archive!(root) do
    archive_path = Path.join(root, "toolchain-test.tar.gz")
    source_root = Path.join(root, "toolchain-archive")
    qemu_bin = Path.join(source_root, "toolchain-linux-x86_64/bin/qemu-pebble")
    gcc_bin = Path.join(source_root, "toolchain-linux-x86_64/arm-none-eabi/bin/arm-none-eabi-gcc")

    File.mkdir_p!(Path.dirname(qemu_bin))
    File.mkdir_p!(Path.dirname(gcc_bin))

    File.write!(qemu_bin, """
    #!/bin/sh
    echo qemu-pebble test
    """)

    File.chmod!(qemu_bin, 0o755)
    File.write!(gcc_bin, "#!/bin/sh\n")
    File.chmod!(gcc_bin, 0o755)

    {_, 0} = System.cmd("tar", ["czf", archive_path, "-C", source_root, "."])

    archive_path
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
