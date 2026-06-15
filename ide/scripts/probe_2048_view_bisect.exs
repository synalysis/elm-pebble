Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, PebbleToolchain, ProjectTemplates}

defmodule Probe2048 do
  def run(label, view_source) do
    workspace = Path.join(System.tmp_dir!(), "p2048_#{label}_#{System.unique_integer([:positive])}")
    :ok = ProjectTemplates.apply_template("game-2048", workspace)
    main_path = Path.join(workspace, "watch/src/Main.elm")

    main =
      main_path
      |> File.read!()
      |> String.replace(
        ", Cmd.batch\n        [ Storage.readString 2048 BestLoaded\n        , Random.generate RandomGenerated (Random.int 1 2147483647)\n        , Light.enable\n        ]",
        ", Cmd.none"
      )
      |> String.replace(
        ~s(subscriptions model =\n    Events.onButton),
        ~s(subscriptions _ =\n    Sub.none\n\n\nsubscriptions_UNUSED model =\n    Events.onButton)
      )
      |> replace_view(view_source)

    File.write!(main_path, main)

    {:ok, pkg} =
      PebbleToolchain.package(label,
        workspace_root: workspace,
        target_type: "app",
        project_name: label,
        target_platforms: ["basalt"],
        source_roots: ["watch"],
        emulator_heap_log: false
      )

    {:ok, session} =
      Emulator.launch(project_slug: label, platform: "basalt", artifact_path: pkg.artifact_path)

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
        nil -> nil
      end)

    {:ok, ctx} = Emulator.log_capture_context(session.id)
    log_task = Task.async(fn -> LogCapture.snapshot(ctx, duration_ms: 12_000) end)
    {:ok, install} = Emulator.install(session.id)
    Process.sleep(8_000)
    snap = Task.await(log_task, 20_000)

    stopped? =
      Enum.any?(snap.lines, fn line ->
        String.contains?(line, "AppRunState stop") and
          String.contains?(line, String.downcase(install.uuid))
      end)

    Emulator.kill(session.id)
    IO.puts("#{label}: stopped=#{stopped?}")
    stopped?
  end

  defp replace_view(main, source) do
    case Regex.run(~r/view model =\n.*?\n        \|> Ui.toUiNode/s, main, return: :index) do
      [match, index] ->
        String.replace(main, match, "view model =\n    " <> source <> "\n        |> Ui.toUiNode", global: false)

      _ ->
        raise "could not locate view in Main.elm"
    end
  end
end

clear_title = """
Ui.clear Color.white
    :: [ Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = 4, y = 4, w = 132, h = 16 } "2048" ]
"""

clear_rect = """
Ui.clear Color.white
    :: [ Ui.rect { x = 10, y = 30, w = 20, h = 20 } Color.black ]
"""

clear_context_rect = """
Ui.clear Color.white
    :: [ Ui.context [ Ui.strokeColor Color.black ] [ Ui.rect { x = 10, y = 30, w = 20, h = 20 } Color.black ] ]
"""

Probe2048.run("clear_title", clear_title)
Probe2048.run("clear_rect", clear_rect)
Probe2048.run("clear_context_rect", clear_context_rect)
