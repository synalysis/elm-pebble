defmodule IdeWeb.EmulatorControllerTest do
  use IdeWeb.ConnCase, async: false

  alias Ide.Emulator
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

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
end
