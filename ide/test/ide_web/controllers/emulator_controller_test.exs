defmodule IdeWeb.EmulatorControllerTest do
  use IdeWeb.ConnCase, async: false

  alias Ide.Emulator
  alias Ide.Projects
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

  setup do
    previous = Application.get_env(:ide, Ide.Projects)

    root =
      Path.join(
        System.tmp_dir!(),
        "emulator-controller-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Projects, previous)
      File.rm_rf(root)
    end)
  end

  test "ping returns alive for an existing session", %{conn: conn} do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(project_slug: "wf", platform: "basalt", artifact_path: nil)

      conn = post(conn, ~p"/api/emulator/#{info.id}/ping")

      assert %{"alive" => true, "id" => id, "vnc_path" => vnc_path} = json_response(conn, 200)
      assert id == info.id
      assert vnc_path == "/api/emulator/#{info.id}/ws/vnc"

      assert :ok = Emulator.kill(info.id)
    end)
  end

  test "ping returns not alive for an unresponsive registered session", %{conn: conn} do
    id = "hung-#{System.unique_integer([:positive])}"
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _} = Registry.register(Ide.Emulator.Registry, id, nil)
        send(parent, :registered)
        Process.sleep(:infinity)
      end)

    assert_receive :registered

    assert %{"alive" => false} =
             conn
             |> post(~p"/api/emulator/#{id}/ping")
             |> json_response(200)

    Process.exit(pid, :kill)
  end

  test "kill is idempotent", %{conn: conn} do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(project_slug: "wf", platform: "basalt", artifact_path: nil)

      assert %{"status" => "ok"} =
               conn
               |> post(~p"/api/emulator/#{info.id}/kill")
               |> json_response(200)

      assert %{"status" => "ok"} =
               build_conn()
               |> post(~p"/api/emulator/#{info.id}/kill")
               |> json_response(200)
    end)
  end

  test "install reports missing protocol router in dry-run sessions", %{conn: conn} do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "wf",
                 platform: "basalt",
                 artifact_path: "/tmp/app.pbw"
               )

      assert %{"error" => "Embedded emulator protocol router is not running."} =
               conn
               |> post(~p"/api/emulator/#{info.id}/install")
               |> json_response(422)

      assert :ok = Emulator.kill(info.id)
    end)
  end

  test "launch reports missing emulator runtime before packaging", %{conn: conn} do
    previous_session_config = Application.get_env(:ide, Ide.Emulator.Session)

    slug = "controller-runtime-missing-#{System.unique_integer([:positive])}"

    runtime_root =
      Path.join(
        System.tmp_dir!(),
        "emulator-controller-runtime-test-#{System.unique_integer([:positive])}"
      )

    sdk_root = Path.join(runtime_root, "SDKs/current")
    qemu_bin = Path.join(sdk_root, "toolchain/bin/qemu-pebble")
    pypkjs_bin = Path.join(runtime_root, "bin/pypkjs")
    pebble_bin = Path.join(runtime_root, "bin/pebble")
    qemu_dir = Path.join(sdk_root, "sdk-core/pebble/basalt/qemu")

    File.mkdir_p!(Path.dirname(qemu_bin))
    File.mkdir_p!(Path.dirname(pypkjs_bin))
    File.mkdir_p!(qemu_dir)
    File.mkdir_p!(Path.join(sdk_root, ".venv/bin"))
    File.mkdir_p!(Path.join(sdk_root, "node_modules"))
    File.write!(Path.join(sdk_root, ".venv/bin/python"), "")
    File.write!(qemu_bin, "#!/bin/sh\nexit 0\n")
    File.write!(pypkjs_bin, "#!/bin/sh\nexit 0\n")
    File.write!(pebble_bin, "#!/bin/sh\necho should-not-build >&2\nexit 1\n")
    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")
    File.chmod!(qemu_bin, 0o755)
    File.chmod!(pypkjs_bin, 0o755)
    File.chmod!(pebble_bin, 0o755)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [sdk_root],
      pebble_bin: pebble_bin,
      pypkjs_bin: pypkjs_bin,
      qemu_image_root: nil
    )

    try do
      assert {:ok, _project} =
               Projects.create_project(%{
                 "name" => "Controller Runtime Missing",
                 "slug" => slug,
                 "target_type" => "app",
                 "template" => "starter"
               })

      assert %{"error" => error} =
               conn
               |> post(~p"/api/emulator/launch", %{"slug" => slug, "platform" => "basalt"})
               |> json_response(422)

      assert error =~ "Embedded emulator dependencies are missing"
      assert error =~ "Pebble ARM GCC"
      refute error =~ "should-not-build"
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous_session_config)
      File.rm_rf!(runtime_root)
    end
  end

  test "config return renders a page that can be detected by the browser hook", %{conn: conn} do
    conn = get(conn, ~p"/api/emulator/config-return?foo=bar")

    assert html_response(conn, 200) =~ "Configuration response received"
  end

  test "companion preferences renders project preference HTML", %{conn: conn} do
    slug = "controller-preferences-#{System.unique_integer([:positive])}"

    assert {:ok, _project} =
             Projects.create_project(%{
               "name" => "ControllerPreferences",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-tutorial-complete"
             })

    response =
      conn
      |> get(
        ~p"/api/projects/#{slug}/companion/preferences?return_to=/api/emulator/config-return"
      )
      |> html_response(200)

    assert response =~ "Tutorial Watchface"
    assert response =~ "showDate"
    assert response =~ "return_to"
  end
end
