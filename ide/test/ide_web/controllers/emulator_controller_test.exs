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
