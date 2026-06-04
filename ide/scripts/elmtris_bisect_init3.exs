# Replace template init; single init definition, view reads pieceKind to keep spawn live.
Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

platform = List.first(System.argv()) || "diorite"

full_path = Path.expand("../priv/project_templates/game_elmtris/src/Main.elm", __DIR__)
lines = String.split(File.read!(full_path), "\n")

take = fn from, to ->
  lines |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n")
end

core = take.(1, 124) <> "\n\n" <> take.(169, length(lines))
helpers = take.(391, 616)
with_piece = take.(85, 104)
fresh_model = take.(135, 163)

tail = """
type Msg = BestLoaded String
update msg model = case msg of BestLoaded v -> ({ model | best = Maybe.withDefault 0 (String.toInt v) }, Cmd.none) ; _ -> (model, Cmd.none)
view model = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt model.pieceKind) ]
subscriptions _ = Events.batch []
main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
"""

static_rec = """
{ board = emptyBoard
, pieceKind = 0
, pieceRot = 0
, pieceX = 0
, pieceY = 0
, pieceSlots = []
, lockedSlots = []
, score = 0
, lines = 0
, best = 0
, seed = 1
, tick = 0
, dropEvery = 28
, screenW = context.screen.width
, screenH = context.screen.height
, displayShape = context.screen.shape
, gameOver = False
}
"""

cmds = "Cmd.batch [ Storage.readString storageKey BestLoaded, Light.enable ]"

static_inner =
  static_rec
  |> String.trim()
  |> String.trim_leading("{")
  |> String.trim_trailing("}")

stages = [
  {"spawn_discard", helpers,
   "let\n    _ =\n        spawnPiece emptyBoard 1\nin\n( " <> static_rec <> "\n, " <> cmds <> "\n)"},
  {"spawn_use_board", helpers,
   "let\n    ( board, _, nextSeed ) =\n        spawnPiece emptyBoard 1\nin\n( { " <> static_inner <>
     "\n  , board = board\n  , seed = nextSeed\n  }\n, " <> cmds <> "\n)"},
  {"with_piece_spawn", helpers <> "\n\n" <> with_piece,
   "let\n    ( board, piece, nextSeed ) =\n        spawnPiece emptyBoard 1\nin\n( withPiece { " <>
     static_inner <> "\n  , board = board\n  , seed = nextSeed\n  }\n    piece\n, " <> cmds <> "\n)"},
  {"with_piece_static", helpers <> "\n\n" <> with_piece,
   "( withPiece " <> static_rec <> "\n    (Just { kind = 0, rot = 0, x = 3, y = 0 })\n, " <> cmds <> "\n)"},
  {"fresh_model", helpers <> "\n\n" <> with_piece <> "\n\n" <> fresh_model,
   "( freshModel 0 1 context.screen.width context.screen.height context.screen.shape\n, " <> cmds <> "\n)"}
]

probe = fn name, extra, init_body ->
  source = core <> "\n\n" <> extra <> "\n\ninit context =\n    " <> init_body <> "\n\n" <> tail
  workspace = Path.join(System.tmp_dir!(), "init3_#{name}")
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

  gen = Path.join(workspace, "watch/.elmc-build/c/elmc_generated.c")
  gen_ok = File.exists?(gen) and File.read!(gen) =~ "spawnPiece"

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

  {name, File.stat!(pkg.artifact_path).size, not stopped?, gen_ok}
end

IO.puts("Init3 bisect (#{platform})\n")

for {name, extra, init_body} <- stages do
  {n, sz, ok, gen_ok} =
    try do
      probe.(name, extra, init_body)
    catch
      :timeout -> {name, 0, false, false}
    end

  IO.puts("#{n}: #{sz} bytes runs=#{ok} has_spawn=#{gen_ok}")
end
