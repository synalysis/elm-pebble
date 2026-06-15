# Force spawnPiece / withPiece results to stay live.
Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

platform = List.first(System.argv()) || "diorite"

full_path = Path.expand("../priv/project_templates/game_elmtris/src/Main.elm", __DIR__)
lines = String.split(File.read!(full_path), "\n")
take = fn from, to -> lines |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n") end

core = take.(1, 168)
helpers = take.(391, 616)
with_piece = take.(85, 104)
piece_slots = take.(107, 113)

tail = """
type Msg = BestLoaded String
update msg model = case msg of BestLoaded v -> ({ model | best = Maybe.withDefault 0 (String.toInt v) }, Cmd.none) ; _ -> (model, Cmd.none)
view _ = Ui.toUiNode [ Ui.clear Color.white ]
subscriptions _ = Events.batch []
main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
"""

base_fields = """
pieceKind = 0, pieceRot = 0, pieceX = 0, pieceY = 0, pieceSlots = [], lockedSlots = [], score = 0, lines = 0, best = 0, seed = 1, tick = 0, dropEvery = 28, screenW = context.screen.width, screenH = context.screen.height, displayShape = context.screen.shape, gameOver = False
"""

cmds = "Cmd.batch [ Storage.readString storageKey BestLoaded, Light.enable ]"

stages = [
  {"use_board_from_spawn",
   core <> "\n\n" <> helpers <> "\n\ninit context =\n    let\n        ( board, _, nextSeed ) =\n            spawnPiece emptyBoard 1\n    in\n    ( { board = board, " <> base_fields <> ", seed = nextSeed }\n    , " <> cmds <> "\n    )\n\n" <> tail},
  {"with_piece_after_spawn",
   core <> "\n\n" <> helpers <> "\n\n" <> with_piece <> "\n\ninit context =\n    let\n        ( board, piece, nextSeed ) =\n            spawnPiece emptyBoard 1\n    in\n    ( withPiece { board = board, " <> base_fields <> ", seed = nextSeed } piece\n    , " <> cmds <> "\n    )\n\n" <> tail},
  {"piece_slots_only",
   core <> "\n\n" <> take.(514, 602) <> "\n\n" <> piece_slots <> "\n\ninit context =\n    let\n        slots =\n            pieceSlots { kind = 0, rot = 0, x = 3, y = 0 }\n    in\n    ( { board = emptyBoard, " <> base_fields <> ", pieceSlots = slots }\n    , " <> cmds <> "\n    )\n\n" <> tail}
]

probe = fn name, source ->
  workspace = Path.join(System.tmp_dir!(), "spawn2_#{name}")
  File.mkdir_p!(workspace)
  :ok = ProjectTemplates.apply_template("game-elmtris", workspace)
  File.write!(Path.join(workspace, "watch/src/Main.elm"), source)

  {:ok, pkg} =
    PebbleToolchain.package("b",
      workspace_root: workspace,
      target_type: "app",
      project_name: "B",
      target_platforms: [platform],
      source_roots: ["watch", "protocol", "phone"],
      emulator_storage_logs: true
    )

  {:ok, session} = Emulator.launch(project_slug: "b", platform: platform, artifact_path: pkg.artifact_path)

  deadline = System.monotonic_time(:millisecond) + 90_000

  :ok =
    Stream.repeatedly(fn ->
      case Emulator.ping(session.id) do
        {:ok, %{display_ready: true}} -> :ok
        _ -> :wait
      end
    end)
    |> Enum.find_value(fn
      :ok -> :ok
      :wait ->
        if System.monotonic_time(:millisecond) >= deadline, do: :timeout
        Process.sleep(200)
        nil
    end)
    |> case do
      :ok -> :ok
      _ -> throw(:timeout)
    end

  {:ok, ctx} = Emulator.log_capture_context(session.id)
  log_task = Task.async(fn -> LogCapture.snapshot(ctx, duration_ms: 10_000) end)
  {:ok, install} = Emulator.install(session.id)
  Process.sleep(7_000)
  snap = Task.await(log_task, 15_000)
  Emulator.kill(session.id)

  stopped? =
    Enum.any?(snap.lines, fn line ->
      String.contains?(line, "AppRunState stop") and
        String.contains?(line, String.downcase(install.uuid))
    end)

  {name, File.stat!(pkg.artifact_path).size, not stopped?}
end

IO.puts("Spawn2 bisect (#{platform})\n")

for {name, src} <- stages do
  {n, sz, ok} =
    try do
      probe.(name, src)
    catch
      :timeout -> {name, 0, false}
    end

  IO.puts("#{n}: #{sz} bytes runs=#{ok}")
end
