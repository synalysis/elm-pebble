Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

workspace = Path.join(System.tmp_dir!(), "initonly_#{System.unique_integer([:positive])}")
:ok = ProjectTemplates.apply_template("game-elmtris", workspace)
main_path = Path.join(workspace, "watch/src/Main.elm")
main = File.read!(main_path)

main =
  main
  |> String.replace("Frame.every 33 FrameTick\n        , ", "")
  |> String.replace(
    "update : Msg -> Model -> ( Model, Cmd Msg )\nupdate msg model =\n    case msg of",
    "update : Msg -> Model -> ( Model, Cmd Msg )\nupdate msg model =\n    case msg of\n        BestLoaded value ->\n            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )\n\n        _ ->\n            ( model, Cmd.none )\n\n\nupdate_UNUSED msg model =\n    case msg of"
  )
  |> String.split("update_UNUSED msg model =")
  |> hd()
  |> String.replace(
    "view : Model -> Ui.UiNode\nview model =",
    "view : Model -> Ui.UiNode\nview _ =\n    Ui.toUiNode [ Ui.clear Color.white ]\n\n\nview_UNUSED model ="
  )
  |> String.split("view_UNUSED model =")
  |> hd()

File.write!(main_path, main)

{:ok, pkg} =
  PebbleToolchain.package("p",
    workspace_root: workspace,
    target_type: "app",
    project_name: "P",
    target_platforms: ["diorite"],
    source_roots: ["watch", "protocol", "phone"],
    emulator_storage_logs: true
  )

{:ok, session} =
  Emulator.launch(project_slug: "p", platform: "diorite", artifact_path: pkg.artifact_path)

:ok =
  Stream.repeatedly(fn ->
    case Emulator.ping(session.id) do
      {:ok, %{display_ready: true}} -> :ok
      _ -> :wait
    end
  end)
  |> Enum.find_value(fn
    :ok -> :ok
    :wait -> Process.sleep(250)
    nil
  end)

{:ok, ctx} = Emulator.log_capture_context(session.id)
log_task = Task.async(fn -> LogCapture.snapshot(ctx, duration_ms: 20_000) end)
{:ok, install} = Emulator.install(session.id)
Process.sleep(12_000)
snap = Task.await(log_task, 30_000)

stopped? =
  Enum.any?(snap.lines, fn line ->
    String.contains?(line, "AppRunState stop") and
      String.contains?(line, String.downcase(install.uuid))
  end)

IO.puts(
  "pbw=#{File.stat!(pkg.artifact_path).size} stopped=#{stopped?} has_log=#{snap.output =~ "AppLog"}"
)

Emulator.kill(session.id)
System.halt(if stopped?, do: 2, else: 0)
