# Usage: cd ide && mix run scripts/elmtris_bisect.exs [diorite]
#
# Systematically grows Elmtris Main.elm from a known-good minimal app and
# probes the embedded emulator after each stage.

Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

platform =
  case System.argv() do
    [p] -> p
    _ -> "diorite"
  end

unless Emulator.runtime_status(platform).missing == [] do
  IO.puts("emulator not ready: #{inspect(Emulator.runtime_status(platform).missing)}")
  System.halt(1)
end

full_path = Path.expand("../priv/project_templates/game_elmtris/src/Main.elm", __DIR__)
full = File.read!(full_path)
lines = String.split(full, "\n")

take_lines = fn from, to ->
  lines
  |> Enum.slice((from - 1)..(to - 1))
  |> Enum.join("\n")
end

stub_update_best_only = """
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        BestLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )

        _ ->
            ( model, Cmd.none )
"""

stub_view_clear = """
view : Model -> Ui.UiNode
view _ =
    Ui.toUiNode [ Ui.clear Color.white ]
"""

stub_view_hud = """
view : Model -> Ui.UiNode
view model =
    Ui.toUiNode (Ui.clear Color.white :: hudOps model)
"""

stub_view_full = take_lines.(630, 649)

stub_subs_none = """
subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch []
"""

stub_subs_buttons = """
subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Back LeftPressed
        , Button.onPress Button.Select RightPressed
        , Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        ]
"""

stub_subs_full = take_lines.(619, 627)

stub_main = """
main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
"""

# Shared prefix: imports through emptyBoard (line 168)
core = take_lines.(1, 168)

# Init-time board/piece helpers (spawnPiece, canPlace, pieceOffsets, …)
helpers_init = take_lines.(391, 616)

# lockPiece path (frame tick → dropStep → lockPiece)
helpers_lock =
  take_lines.(312, 372) <>
    "\n\n" <>
    take_lines.(375, 388) <>
    "\n\n" <>
    take_lines.(722, 733)

# Msg variants added per stage
msg_minimal = """
type Msg
    = BestLoaded String
"""

msg_buttons = """
type Msg
    = LeftPressed
    | RightPressed
    | UpPressed
    | DownPressed
    | BestLoaded String
"""

msg_frame = """
type Msg
    = FrameTick Frame.Frame
    | LeftPressed
    | RightPressed
    | UpPressed
    | DownPressed
    | BestLoaded String
"""

# Update bodies pulled from full file when needed
update_tick_only = """
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FrameTick _ ->
            if model.gameOver then
                ( model, Cmd.none )

            else
                tickGravity model

        BestLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )

        _ ->
            ( model, Cmd.none )
"""

update_full = take_lines.(171, 210)

# Helpers only referenced from later stages (append in order)
helpers_tick =
  take_lines.(222, 233) <>
    "\n\n" <>
    take_lines.(235, 246)

helpers_buttons =
  "\n\n" <>
    take_lines.(249, 309) <>
    "\n\n" <>
    take_lines.(213, 219)

helpers_view =
  "\n\n" <>
    take_lines.(652, 855)

stages = [
  {"01_minimal", fn ->
     File.read!(Path.join(__DIR__, "fixtures/elmtris_minimal_main.elm"))
   end},
  {"02_model_init", fn ->
     core <>
       "\n\n" <>
       helpers_init <>
       "\n\n" <>
       msg_minimal <>
       "\n\n" <>
       stub_update_best_only <>
       "\n\n" <>
       stub_view_clear <>
       "\n\n" <>
       stub_subs_none <>
       "\n\n" <>
       stub_main
   end},
  {"03_view_hud", fn ->
     core <>
       "\n\n" <>
       helpers_init <>
       "\n\n" <>
       msg_minimal <>
       "\n\n" <>
       take_lines.(798, 828) <>
       "\n\n" <>
       stub_update_best_only <>
       "\n\n" <>
       stub_view_hud <>
       "\n\n" <>
       stub_subs_none <>
       "\n\n" <>
       stub_main
   end},
  {"04_view_full", fn ->
     core <>
       "\n\n" <>
       helpers_init <>
       "\n\n" <>
       msg_minimal <>
       "\n\n" <>
       helpers_view <>
       "\n\n" <>
       stub_update_best_only <>
       "\n\n" <>
       stub_view_full <>
       "\n\n" <>
       stub_subs_none <>
       "\n\n" <>
       stub_main
   end},
  {"05_subs_frame", fn ->
     core <>
       "\n\n" <>
       helpers_init <>
       "\n\n" <>
       msg_frame <>
       "\n\n" <>
       helpers_lock <>
       "\n\n" <>
       helpers_view <>
       "\n\n" <>
       helpers_tick <>
       "\n\n" <>
       update_tick_only <>
       "\n\n" <>
       stub_view_full <>
       "\n\n" <>
       stub_subs_full <>
       "\n\n" <>
       stub_main
   end},
  {"06_update_buttons", fn ->
     core <>
       "\n\n" <>
       helpers_init <>
       "\n\n" <>
       msg_frame <>
       "\n\n" <>
       helpers_lock <>
       "\n\n" <>
       helpers_view <>
       "\n\n" <>
       helpers_tick <>
       "\n\n" <>
       helpers_buttons <>
       "\n\n" <>
       take_lines.(171, 210) <>
       "\n\n" <>
       stub_view_full <>
       "\n\n" <>
       stub_subs_full <>
       "\n\n" <>
       stub_main
   end},
  {"07_full", fn -> full end}
]

IO.puts("Elmtris bisect on #{platform}\n")
IO.puts(String.pad_trailing("stage", 22) <> String.pad_trailing("pbw", 8) <> "runs  compile")

probe_stage = fn name, source ->
  workspace = Path.join(System.tmp_dir!(), "bisect_#{name}_#{System.unique_integer([:positive])}")

  compile_result =
    try do
      File.mkdir_p!(workspace)
      :ok = ProjectTemplates.apply_template("game-elmtris", workspace)
      main_path = Path.join(workspace, "watch/src/Main.elm")
      File.write!(main_path, source)

      case PebbleToolchain.package("bisect",
             workspace_root: workspace,
             target_type: "app",
             project_name: "Bisect",
             target_platforms: [platform],
             source_roots: ["watch", "protocol", "phone"],
             emulator_storage_logs: true
           ) do
        {:ok, pkg} ->
          {:ok, pkg, workspace}

        {:error, reason} ->
          {:compile_error, reason}
      end
    rescue
      e -> {:compile_error, Exception.message(e)}
    end

  case compile_result do
    {:compile_error, reason} ->
      {name, :compile_fail, 0, false, inspect(reason) |> String.slice(0, 80)}

    {:ok, pkg, _workspace} ->
      runs? =
        try do
          {:ok, session} =
            Emulator.launch(
              project_slug: "bisect",
              platform: platform,
              artifact_path: pkg.artifact_path
            )

          deadline = System.monotonic_time(:millisecond) + 120_000

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
                if System.monotonic_time(:millisecond) >= deadline do
                  :timeout
                else
                  Process.sleep(200)
                  nil
                end
            end)
            |> case do
              :ok -> :ok
              _ -> throw(:display_timeout)
            end

          {:ok, ctx} = Emulator.log_capture_context(session.id)

          log_task =
            Task.async(fn ->
              LogCapture.snapshot(ctx, duration_ms: 12_000)
            end)

          {:ok, install} = Emulator.install(session.id)
          Process.sleep(8_000)
          snap = Task.await(log_task, 20_000)
          Emulator.kill(session.id)

          stopped? =
            Enum.any?(snap.lines, fn line ->
              String.contains?(line, "AppRunState stop") and
                String.contains?(line, String.downcase(install.uuid))
            end)

          not stopped?
        catch
          :display_timeout -> false
        end

      pbw = File.stat!(pkg.artifact_path).size
      {name, :ok, pbw, runs?, ""}
  end
end

results = Enum.map(stages, fn {name, source_fn} -> probe_stage.(name, source_fn.()) end)

first_fail =
  results
  |> Enum.find(fn
    {_, :compile_fail, _, _, _} -> true
    {_, :ok, _, false, _} -> true
    _ -> false
  end)

for {name, status, pbw, runs?, note} <- results do
  runs_txt =
    case status do
      :compile_fail -> "FAIL "
      :ok -> if runs?, do: "yes  ", else: "NO   "
    end

  compile_txt = if status == :compile_fail, do: "no ", else: "yes"

  IO.puts(
    String.pad_trailing(name, 22) <>
      String.pad_trailing(Integer.to_string(pbw), 8) <>
      runs_txt <>
      compile_txt <>
      note
  )
end

IO.puts("")

case first_fail do
  {name, :compile_fail, _, _, _} ->
    IO.puts("First compile failure: #{name}")

  {name, :ok, pbw, false, _} ->
    IO.puts("First runtime stop after compile: #{name} (#{pbw} bytes)")

    prev =
      results
      |> Enum.take_while(fn {n, _, _, _, _} -> n != name end)
      |> List.last()

    case prev do
      {pname, :ok, pbw_prev, true, _} ->
        IO.puts("Last good stage: #{pname} (#{pbw_prev} bytes)")

      _ ->
        IO.puts("No prior running stage (check 01_minimal)")
    end

  nil ->
    IO.puts("All stages ran on emulator.")
end

if Enum.any?(results, fn {_, :ok, _, false, _} -> true end), do: System.halt(2)
