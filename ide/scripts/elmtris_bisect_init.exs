# Narrow stage-02 failure: linked spawnPiece code vs freshModel at init.
Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

platform = List.first(System.argv()) || "diorite"

full_path = Path.expand("../priv/project_templates/game_elmtris/src/Main.elm", __DIR__)
full = File.read!(full_path)
lines = String.split(full, "\n")

take = fn from, to ->
  lines |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n")
end

# Through storageKey (line 115), then emptyBoard — omit Msg/init/freshModel.
core_base = take.(1, 115) <> "\n\n" <> take.(166, 168)
helpers_init = take.(391, 616)

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

init_static =
  core_base <>
    "\n\n" <>
    """
    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init context =
        ( { board = emptyBoard
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
        , Cmd.batch
            [ Storage.readString storageKey BestLoaded
            , Light.enable
            ]
        )
    """ <>
    "\n\n" <>
    stub_tail

init_fresh =
  core_base <>
    "\n\n" <>
    helpers_init <>
    "\n\n" <>
    take.(135, 163) <>
    "\n\n" <>
    take.(125, 132) <>
    "\n\n" <>
    stub_tail

init_fresh_linked_only =
  core_base <>
    "\n\n" <>
    helpers_init <>
    "\n\n" <>
    """
    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init context =
        ( { board = emptyBoard
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
        , Cmd.batch
            [ Storage.readString storageKey BestLoaded
            , Light.enable
            ]
        )
    """ <>
    "\n\n" <>
    stub_tail

stages = [
  {"static_model", init_static},
  {"fresh_linked_static_init", init_fresh_linked_only},
  {"fresh_model_init", init_fresh},
  {"spawn_only_init",
   core_base <>
     "\n\n" <>
     helpers_init <>
     "\n\n" <>
     """
     init : Platform.LaunchContext -> ( Model, Cmd Msg )
     init context =
         let
             ( board, _, nextSeed ) =
                 spawnPiece emptyBoard 1
         in
         ( { board = board
           , pieceKind = 0
           , pieceRot = 0
           , pieceX = 0
           , pieceY = 0
           , pieceSlots = []
           , lockedSlots = []
           , score = 0
           , lines = 0
           , best = 0
           , seed = nextSeed
           , tick = 0
           , dropEvery = 28
           , screenW = context.screen.width
           , screenH = context.screen.height
           , displayShape = context.screen.shape
           , gameOver = False
           }
         , Cmd.batch
             [ Storage.readString storageKey BestLoaded
             , Light.enable
             ]
         )
     """ <>
     "\n\n" <>
     stub_tail},
  {"can_place_if_init",
   core_base <>
     "\n\n" <>
     helpers_init <>
     "\n\n" <>
     """
     init : Platform.LaunchContext -> ( Model, Cmd Msg )
     init context =
         ( if canPlace 0 0 3 0 emptyBoard then
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
           else
             { board = emptyBoard
             , pieceKind = -1
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
             , gameOver = True
               }
         , Cmd.batch
             [ Storage.readString storageKey BestLoaded
             , Light.enable
             ]
         )
     """ <>
     "\n\n" <>
     stub_tail},
  {"with_piece_only_init",
   core_base <>
     "\n\n" <>
     helpers_init <>
     "\n\n" <>
     take.(85, 104) <>
     "\n\n" <>
     """
     init : Platform.LaunchContext -> ( Model, Cmd Msg )
     init context =
         ( withPiece
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
             (Just { kind = 0, rot = 0, x = 3, y = 0 })
         , Cmd.batch
             [ Storage.readString storageKey BestLoaded
             , Light.enable
             ]
         )
     """ <>
     "\n\n" <>
     stub_tail},
  {"fresh_model_no_canplace",
   core_base <>
     "\n\n" <>
     String.replace(
       helpers_init,
       """
       if canPlace kind 0 piece.x piece.y board then
           ( board, Just piece, nextSeed )

       else
           ( board, Nothing, nextSeed )
       """,
       "( board, Just piece, nextSeed )"
     ) <>
     "\n\n" <>
     take.(85, 104) <>
     "\n\n" <>
     take.(135, 163) <>
     "\n\n" <>
     take.(125, 132) <>
     "\n\n" <>
     stub_tail},
  {"fresh_model_no_slots",
   core_base <>
     "\n\n" <>
     helpers_init <>
     "\n\n" <>
     take.(85, 104) <>
     "\n\n" <>
     """
     withPiece model piece =
         case piece of
             Nothing ->
                 { model
                     | pieceKind = -1
                     , pieceRot = 0
                     , pieceX = 0
                     , pieceY = 0
                     , pieceSlots = []
                 }

             Just active ->
                 { model
                     | pieceKind = active.kind
                     , pieceRot = active.rot
                     , pieceX = active.x
                     , pieceY = active.y
                     , pieceSlots = []
                 }
     """ <>
     "\n\n" <>
     take.(135, 163) <>
     "\n\n" <>
     take.(125, 132) <>
     "\n\n" <>
     stub_tail}
]

probe = fn name, source ->
  workspace = Path.join(System.tmp_dir!(), "initbisect_#{name}")
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

IO.puts("Init narrow bisect (#{platform})\n")

results =
  Enum.map(stages, fn {name, src} ->
    try do
      probe.(name, src)
    rescue
      e -> {name, 0, false}
    catch
      :timeout -> {name, 0, false}
    end
  end)

for {n, sz, ok} <- results, do: IO.puts("#{n}: #{sz} bytes runs=#{ok}")

# Fix typo - session_id vs session.id