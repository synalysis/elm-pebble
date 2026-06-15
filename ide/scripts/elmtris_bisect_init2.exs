# Finer split: emptyBoard only vs spawnPiece at init vs full freshModel.
Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

platform = List.first(System.argv()) || "diorite"

full_path = Path.expand("../priv/project_templates/game_elmtris/src/Main.elm", __DIR__)
full = File.read!(full_path)
lines = String.split(full, "\n")

take = fn from, to ->
  lines |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n")
end

core = take.(1, 168)
helpers_init = take.(391, 616)
with_piece = take.(85, 104)

stub_tail = """
type Msg
    = BestLoaded String

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        BestLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )

        _ ->
            ( model, Cmd.none )

view : Model -> Ui.UiNode
view _ =
    Ui.toUiNode [ Ui.clear Color.white ]

subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch []

main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
"""

cmds = """
        , Cmd.batch
            [ Storage.readString storageKey BestLoaded
            , Light.enable
            ]
"""

base_fields = """
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
"""

wrap = fn body ->
  core <>
    "\n\n" <>
    body <>
    "\n\n" <>
    stub_tail
end

stages = [
  {"empty_board_only",
   wrap.(
     """
     init : Platform.LaunchContext -> ( Model, Cmd Msg )
     init context =
         ( { board = emptyBoard
     """ <> base_fields <> "\n         }\n" <> cmds <> "\n         )\n"
   )},
  {"spawn_at_init",
   wrap.(
     helpers_init <>
       "\n\n" <>
       with_piece <>
       "\n\n" <>
       """
       init : Platform.LaunchContext -> ( Model, Cmd Msg )
       init context =
           let
               ( board, piece, nextSeed ) =
                   spawnPiece emptyBoard 1
           in
           ( withPiece
                 { board = board
     """ <> base_fields <> """
                 , seed = nextSeed
                 }
                 piece
     """ <> cmds <> "\n           )\n"
   )},
  {"fresh_model",
   wrap.(
     helpers_init <>
       "\n\n" <>
       take.(135, 163) <>
       "\n\n" <>
       take.(125, 132)
   )}
]

probe = fn name, source ->
  workspace = Path.join(System.tmp_dir!(), "init2_#{name}")
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

IO.puts("Init2 bisect (#{platform})\n")

for {name, src} <- stages do
  {n, sz, ok} =
    try do
      probe.(name, src)
    catch
      :timeout -> {name, 0, false}
    end

  IO.puts("#{n}: #{sz} bytes runs=#{ok}")
end
