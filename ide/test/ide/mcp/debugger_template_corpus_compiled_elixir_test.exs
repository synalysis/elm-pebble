defmodule Ide.Mcp.DebuggerTemplateCorpusCompiledElixirTest do
  @moduledoc """
  Optional template corpus gate for `:compiled_elixir` backend.

  Run with `ELMX_TEMPLATE_CORPUS=1 mix test --only compiled_elixir_corpus`.
  """

  use Ide.DataCase, async: false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Mcp.DebuggerTemplateCorpus

  @enabled? Corpus.corpus_enabled?()

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "minimal template compiles in memory when enabled" do
    if @enabled? do
      project_dir = Path.expand("../../../../elmx/test/fixtures/minimal", __DIR__)
      revision = "corpus-minimal-" <> Integer.to_string(:erlang.unique_integer([:positive]))

      assert {:ok, %{elmx_manifest: manifest}} =
               Ide.Compiler.build_elmx_artifacts_in_memory(project_dir, revision: revision)

      assert manifest["contract"] == "elmx.runtime_executor.v1"
      assert Elmx.module_for_revision(revision)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run compiles and executes init when enabled" do
    if @enabled? and "game-jump-n-run" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("game-jump-n-run", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        assert {:ok, _manifest, runtime_model} =
                 Corpus.corpus_compile_and_execute_init!(workspace,
                   revision:
                     "corpus-jump-" <> Integer.to_string(:erlang.unique_integer([:positive]))
                 )

        assert Map.has_key?(runtime_model, "alive")
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-basic template compiles and executes init when enabled" do
    if @enabled? and "game-basic" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("game-basic", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_init!(workspace,
               revision: "corpus-basic-" <> Integer.to_string(:erlang.unique_integer([:positive]))
             ) do
          {:ok, manifest, runtime_model} ->
            assert manifest["contract"] == "elmx.runtime_executor.v1"
            assert runtime_model["y"] == 60
            assert runtime_model["x"] == 18

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "starter template compiles and executes init when enabled" do
    if @enabled? and "starter" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("starter", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_init!(workspace,
               revision:
                 "corpus-starter-" <> Integer.to_string(:erlang.unique_integer([:positive]))
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["value"] == 1

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-digital compiles and executes init when enabled" do
    if @enabled? and "watchface-digital" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("watchface-digital", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_init!(workspace,
               revision:
                 "corpus-digital-" <> Integer.to_string(:erlang.unique_integer([:positive]))
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["screenW"] == 144
            assert runtime_model["screenH"] == 168
            assert runtime_model["timeString"] == "--:--"

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-analog compiles and executes init when enabled" do
    corpus_init_execute!("watchface-analog", "corpus-analog-init-", fn model ->
      assert model["hour"] == 12
      assert model["minute"] == 0
      assert model["screenW"] == 144
      assert model["screenH"] == 168
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-tutorial-complete compiles and executes init when enabled" do
    corpus_init_execute!("watchface-tutorial-complete", "corpus-tutorial-init-", fn model ->
      assert model["screenW"] == 144
      assert model["screenH"] == 168
      assert model["batteryLevel"] == %{"ctor" => "Nothing", "args" => []}
      assert model["connected"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-health compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-health", "corpus-health-init-", fn model ->
      assert model["events"] == 0
      assert model["refreshes"] == 0
      assert model["lastEvent"] == "Waiting"
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-poke-battle compiles and executes init when enabled" do
    corpus_init_execute!("watchface-poke-battle", "corpus-poke-init-", fn model ->
      assert model["animating"] == false
      assert model["scene"]["ctor"] == "Waiting"
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-data-log compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-data-log", "corpus-datalog-", fn model ->
      assert model["events"] == 0
      assert model["lastValue"] == 0
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-dictation compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-dictation", "corpus-dictation-", fn model ->
      assert model["hasMicrophone"] == false

      assert model["status"] == %{
               "ctor" => "Just",
               "args" => [%{"ctor" => "Finished", "args" => []}]
             }

      assert model["result"] == %{
               "ctor" => "Err",
               "args" => [%{"ctor" => "NoMicrophone", "args" => []}]
             }
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 compiles and executes init when enabled" do
    corpus_init_execute!("game-2048", "corpus-2048-init-", fn model ->
      assert is_list(model["cells"])
      assert is_integer(model["score"])
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 gabbro init keeps round screen fields" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("game-2048", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        revision = "corpus-2048-gabbro-" <> Integer.to_string(:erlang.unique_integer([:positive]))

        assert {:ok, manifest, runtime_model} =
                 Corpus.corpus_compile_and_execute_init!(workspace,
                   revision: revision,
                   watch_profile_id: "gabbro"
                 )

        assert runtime_model["screenW"] == 260
        assert runtime_model["screenH"] == 260
        assert runtime_model["displayShape"] == %{"ctor" => "Round", "args" => []}

        {:ok, view_payload} =
          Ide.Debugger.RuntimeExecutor.execute(%{
            elmx_manifest: manifest,
            elmx_revision: revision,
            current_model: %{
              "launch_context" => Corpus.corpus_launch_context_for("gabbro"),
              "runtime_model" => runtime_model
            },
            message: nil,
            introspect: %{},
            source: "",
            source_root: "watch",
            rel_path: "src/Main.elm",
            current_view_tree: %{}
          })

        rows = Map.get(view_payload, :view_output) || Map.get(view_payload, "view_output") || []
        rect = Enum.find(rows, &(Map.get(&1, "kind") == "rect"))

        assert rect,
               "expected rect draw op in gabbro view_output, got #{inspect(Enum.map(rows, &Map.get(&1, "kind")))}"

        refute rect["x"] == 15 and rect["y"] == 26 and rect["w"] == 55,
               "expected round board layout, got rectangular basalt-style rect #{inspect(rect)}"
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-tangram-time compiles and executes init when enabled" do
    corpus_init_execute!("watchface-tangram-time", "corpus-tangram-init-", fn model ->
      assert model["screenW"] == 144
      assert model["screenH"] == 168
      assert model["downloadedPieces"] == []
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-weather-animated compiles and executes init when enabled" do
    corpus_init_execute!("watchface-weather-animated", "corpus-weather-init-", fn model ->
      assert model["screenW"] == 144
      assert model["screenH"] == 168
      assert model["displayedCondition"] == %{"$ctor" => "Nothing", "$args" => []} or
               model["displayedCondition"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-tiny-bird compiles and executes init when enabled" do
    corpus_init_execute!("game-tiny-bird", "corpus-tiny-bird-init-", fn model ->
      assert model["birdY"] == 60
      assert model["alive"] == true
      assert is_integer(model["score"])
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-compass compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-compass", "corpus-compass-init-", fn model ->
      assert is_boolean(model["hasCompass"])
      assert model["refreshes"] == 0
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-compass init hasCompass true on aplite profile when enabled" do
    if @enabled? and "watch-demo-compass" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("watch-demo-compass", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_init!(workspace,
               revision:
                 "corpus-compass-aplite-" <>
                   Integer.to_string(:erlang.unique_integer([:positive])),
               watch_profile_id: "aplite"
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["hasCompass"] == true
            assert runtime_model["refreshes"] == 0

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-accel compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-accel", "corpus-accel-init-", fn model ->
      assert model["z"] == -1000
      assert model["taps"] == 0
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-light compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-light", "corpus-light-init-", fn model ->
      assert model["modeIndex"] == 0
      assert model["applies"] == 0
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-vibes compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-vibes", "corpus-vibes-init-", fn model ->
      assert model["patternIndex"] == 0
      assert model["presses"] == 0
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-app-focus compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-app-focus", "corpus-app-focus-init-", fn model ->
      assert model["changes"] == 0
      assert model["focus"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-watch-info compiles and executes init when enabled" do
    corpus_init_execute!("watch-demo-watch-info", "corpus-watch-info-init-", fn model ->
      assert model["refreshes"] == 0
      assert model["model"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-yes compiles and executes init when enabled" do
    corpus_init_execute!("watchface-yes", "corpus-yes-init-", fn model ->
      assert is_integer(model["screenW"])
      assert model["screenW"] == 144
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "starter Increment step increments value when enabled" do
    corpus_step_execute!("starter", "Increment", "corpus-starter-inc-", fn model ->
      assert model["value"] == 2
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-basic UpPressed step sets vy when enabled" do
    corpus_step_execute!("game-basic", "UpPressed", "corpus-basic-up-", fn model ->
      assert model["vy"] == -7
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 RandomGenerated step keeps score at zero when enabled" do
    corpus_step_execute!("game-2048", "RandomGenerated 12345", "corpus-2048-rand-", fn model ->
      assert model["score"] == 0
      assert is_integer(model["seed"])
      assert length(model["cells"]) == 16
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-basic FrameTick step advances vy when enabled" do
    corpus_step_execute!(
      "game-basic",
      Corpus.frame_tick_message(),
      "corpus-basic-frame-",
      fn model ->
        assert model["vy"] == 1
        assert model["y"] == 60
      end
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-tiny-bird FrameTick step advances score when enabled" do
    corpus_step_execute!(
      "game-tiny-bird",
      Corpus.frame_tick_message(),
      "corpus-tiny-frame-",
      fn model ->
        assert model["score"] == 1
        assert model["birdY"] == 60
        assert model["velocity"] == 1
        assert model["alive"] == true
      end
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run UpPressed step sets velocityY when enabled" do
    corpus_step_execute!("game-jump-n-run", "UpPressed", "corpus-jump-up-", fn model ->
      assert model["velocityY"] == -9
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-poke-battle SelectPressed step sets animating when enabled" do
    corpus_step_execute!(
      "watchface-poke-battle",
      "SelectPressed",
      "corpus-poke-select-",
      fn model ->
        assert model["animating"] == true
        assert model["scene"]["ctor"] == "Waiting"
      end
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-light SelectPressed step increments applies when enabled" do
    corpus_step_execute!("watch-demo-light", "SelectPressed", "corpus-light-select-", fn model ->
      assert model["applies"] == 1
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 RandomGenerated then LeftPressed advances turn when enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("game-2048", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_steps!(
               workspace,
               ["RandomGenerated 12345", "LeftPressed"],
               revision:
                 "corpus-2048-steps-" <> Integer.to_string(:erlang.unique_integer([:positive]))
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["turn"] == 1
            assert Enum.count(runtime_model["cells"], &(&1 != 0)) >= 2

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-geolocation", "corpus-geo-init-", fn model ->
      assert model["timeString"] == "--:--"
      assert model["latitudeE6"] == 0
      assert model["screenW"] == 144
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-phone-status", "corpus-phone-status-init-", fn model ->
      assert model["timeString"] == "--:--"
      assert model["batteryPercent"] == 0
      assert model["screenW"] == 144
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-weather-env", "corpus-weather-env-init-", fn model ->
      assert model["timeString"] == "--:--"
      assert model["temperatureC"] == 0
      assert model["condition"]["ctor"] == "UnknownWeather"
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-storage", "corpus-storage-init-", fn model ->
      assert model["theme"] == %{"ctor" => "Nothing", "args" => []}
      assert model["screenW"] == 144
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-calendar", "corpus-calendar-init-", fn model ->
      assert model["timeString"] == "--:--"
      assert model["nextEvent"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-settings", "corpus-settings-init-", fn model ->
      assert model["ready"] == false
      assert model["configOutcome"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-websocket", "corpus-websocket-init-", fn model ->
      assert model["statusDetail"] == "waiting"
      assert model["status"]["ctor"] == "Closed"
      assert model["screenW"] == 144
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline compiles and executes init when enabled" do
    corpus_init_execute!("companion-demo-timeline", "corpus-timeline-init-", fn model ->
      assert model["tokenPreview"] == "loading"
      assert model["pinStatus"] == %{"ctor" => "Nothing", "args" => []}
    end)
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "starter Increment then Decrement restores value when enabled" do
    if @enabled? and "starter" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("starter", cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_steps!(workspace, ["Increment", "Decrement"],
               revision:
                 "corpus-starter-id-" <> Integer.to_string(:erlang.unique_integer([:positive]))
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["value"] == 1

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run FrameTick step advances offset when enabled" do
    corpus_step_execute!(
      "game-jump-n-run",
      Corpus.frame_tick_message(),
      "corpus-jump-frame-",
      fn model ->
        assert model["alive"] == true
        assert is_integer(model["offset"])
      end
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-digital CurrentTimeString step updates timeString when enabled" do
    corpus_step_execute!(
      "watchface-digital",
      "CurrentTimeString 12:34",
      "corpus-digital-time-",
      fn model ->
        assert model["timeString"] == "12:34"
      end
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone Connected Ok step updates status when enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-websocket",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_connected_ok_value()

        case Corpus.corpus_phone_step_execute!(phone_workspace, "Connected",
               revision:
                 "corpus-ws-connected-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["status"]["ctor"] == "Open"

          {:compile_error, reason} ->
            flunk("companion-demo-websocket Connected step failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone WebSocketEvent Opened step updates status when enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-websocket",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_websocket_event_value("Opened")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "WebSocketEvent",
               revision:
                 "corpus-ws-event-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["status"]["ctor"] == "Open"
            assert runtime_model["statusDetail"] == "open"

          {:compile_error, reason} ->
            flunk("companion-demo-websocket WebSocketEvent Opened failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket FromPhone step updates status when enabled" do
    message_value =
      Corpus.companion_from_phone_value("ProvideWebSocketStatus", [:Open, "connected"])

    corpus_step_execute!(
      "companion-demo-websocket",
      "FromPhone (ProvideWebSocketStatus Open connected)",
      "corpus-websocket-step-",
      fn model ->
        assert model["status"]["ctor"] == "Open"
        assert model["statusDetail"] == "connected"
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status FromPhone ProvideBattery step updates model when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideBattery", [88, true])

    corpus_step_execute!(
      "companion-demo-phone-status",
      "FromPhone (ProvideBattery 88 true)",
      "corpus-phone-bat-",
      fn model ->
        assert model["batteryPercent"] == 88
        assert model["charging"] == true
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status GotBattery step updates model when enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-phone-status",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_got_battery_ok_value(55, true)

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotBattery",
               revision:
                 "corpus-phone-got-bat-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["batteryPercent"] == 55
            assert runtime_model["charging"] == true

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status GotLocale step updates locale when enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-phone-status",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_got_locale_ok_value("de-DE")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotLocale",
               revision:
                 "corpus-phone-locale-step-" <>
                   Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["locale"] == "de-DE"

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status GotConnectivity step updates online when enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-phone-status",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_got_connectivity_value("Online")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotConnectivity",
               revision:
                 "corpus-phone-net-step-" <>
                   Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["online"] == true

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status FromPhone ProvideNotifications step updates flags when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideNotifications", [true, false])

    corpus_step_execute!(
      "companion-demo-phone-status",
      "FromPhone (ProvideNotifications true false)",
      "corpus-phone-notif-",
      fn model ->
        assert model["notificationsEnabled"] == true
        assert model["quietHours"] == false
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status FromPhone ProvideLocale step updates locale when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideLocale", ["en-US"])

    corpus_step_execute!(
      "companion-demo-phone-status",
      "FromPhone (ProvideLocale en-US)",
      "corpus-phone-locale-",
      fn model ->
        assert model["locale"] == "en-US"
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation phone GotPosition step updates coordinates when enabled" do
    if @enabled? and "companion-demo-geolocation" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-geolocation",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        location =
          Corpus.companion_location_info(latitude: 12.345, longitude: -98.765, accuracy: 25.0)

        message_value = Corpus.companion_got_position_ok_value(location)

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotPosition",
               revision:
                 "corpus-geo-got-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["latitudeE6"] == 12_345_000
            assert runtime_model["longitudeE6"] == -98_765_000
            assert runtime_model["accuracyM"] == 25

          {:compile_error, reason} ->
            flunk("companion-demo-geolocation GotPosition step failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation FromPhone step updates position when enabled" do
    message_value =
      Corpus.companion_from_phone_value("ProvidePosition", [12_345_000, -98_765_000, 25])

    corpus_step_execute!(
      "companion-demo-geolocation",
      "FromPhone (ProvidePosition 12345000 -98765000 25)",
      "corpus-geo-step-",
      fn model ->
        assert model["latitudeE6"] == 12_345_000
        assert model["longitudeE6"] == -98_765_000
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage FromPhone ProvideTheme step updates theme and units when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideTheme", [:Dark, :Metric])

    corpus_step_execute!(
      "companion-demo-storage",
      "FromPhone (ProvideTheme Dark Metric)",
      "corpus-storage-theme-",
      fn model ->
        assert model["theme"]["ctor"] == "Just"
        assert hd(model["theme"]["args"])["ctor"] == "Dark"
        assert model["units"]["ctor"] == "Just"
        assert hd(model["units"]["args"])["ctor"] == "Metric"
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar FromPhone ProvideNextEvent step updates nextEvent when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideNextEvent", ["Standup", 9, 30])

    corpus_step_execute!(
      "companion-demo-calendar",
      "FromPhone (ProvideNextEvent Standup 9 30)",
      "corpus-calendar-event-",
      fn model ->
        assert model["nextEvent"]["ctor"] == "Just"

        event = hd(model["nextEvent"]["args"])
        assert event["title"] == "Standup"
        assert event["hour"] == 9
        assert event["minute"] == 30
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar FromPhone NoUpcomingEvents clears nextEvent when enabled" do
    message_value = Corpus.companion_from_phone_nullary("NoUpcomingEvents")

    corpus_step_execute!(
      "companion-demo-calendar",
      "FromPhone NoUpcomingEvents",
      "corpus-calendar-none-",
      fn model ->
        assert model["nextEvent"]["ctor"] == "Nothing"
        assert model["nextEvent"]["args"] == []
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings FromPhone SettingsReady step sets ready when enabled" do
    message_value = Corpus.companion_from_phone_nullary("SettingsReady")

    corpus_step_execute!(
      "companion-demo-settings",
      "FromPhone SettingsReady",
      "corpus-settings-ready-",
      fn model ->
        assert model["ready"] == true
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings FromPhone SettingsClosed step records outcome when enabled" do
    message_value = Corpus.companion_from_phone_value("SettingsClosed", [:Dismissed])

    corpus_step_execute!(
      "companion-demo-settings",
      "FromPhone (SettingsClosed Dismissed)",
      "corpus-settings-closed-",
      fn model ->
        assert model["configOutcome"]["ctor"] == "Just"
        assert hd(model["configOutcome"]["args"])["ctor"] == "Dismissed"
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings phone LifecycleChanged Ready step sets ready when enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-settings",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_lifecycle_changed_value("Ready")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "LifecycleChanged",
               revision:
                 "corpus-settings-lifecycle-" <>
                   Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["ready"] == true

          {:compile_error, reason} ->
            flunk("companion-demo-settings LifecycleChanged Ready failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings phone ConfigurationClosed step records Saved when enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-settings",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_configuration_closed_value("saved")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "ConfigurationClosed",
               revision:
                 "corpus-settings-config-" <>
                   Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["configOutcome"]["ctor"] == "Just"
            assert hd(runtime_model["configOutcome"]["args"])["ctor"] == "Saved"

          {:compile_error, reason} ->
            flunk("companion-demo-settings ConfigurationClosed failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage phone GotStorage step updates theme when enabled" do
    if @enabled? and "companion-demo-storage" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-storage", cleanup: false)

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_got_storage_string_ok_value("light")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotStorage",
               revision:
                 "corpus-storage-got-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["theme"]["ctor"] == "Light"

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage phone GotPreference step updates units when enabled" do
    if @enabled? and "companion-demo-storage" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-storage", cleanup: false)

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        message_value = Corpus.companion_got_preference_ok_value("units", "imperial")

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotPreference",
               revision:
                 "corpus-storage-pref-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["units"]["ctor"] == "Imperial"

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env phone GotWeather step updates temperature when enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-weather-env",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        info = Corpus.companion_weather_info(temperature_c: 22, condition: "Rain")
        message_value = Corpus.companion_got_weather_current_ok_value(info)

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotWeather",
               revision:
                 "corpus-weather-got-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["temperatureC"] == 22
            assert runtime_model["condition"]["ctor"] == "Rain"

          {:compile_error, reason} ->
            flunk("companion-demo-weather-env GotWeather step failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env phone GotEnvironment step updates sun and moon when enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-weather-env",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        info =
          Corpus.companion_environment_info(sunrise_min: 360, sunset_min: 1140, phase_e6: 750_000)

        message_value = Corpus.companion_got_environment_ok_value(info)

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotEnvironment",
               revision:
                 "corpus-env-got-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["sunriseMin"] == 360
            assert runtime_model["sunsetMin"] == 1140
            assert runtime_model["moonPhaseE6"] == 750_000

          {:compile_error, reason} ->
            flunk("companion-demo-weather-env GotEnvironment step failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar phone GotCalendar step updates lastTitle when enabled" do
    if @enabled? and "companion-demo-calendar" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-calendar",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        event =
          Corpus.companion_calendar_event(
            id: "standup",
            title: "Team Sync",
            start_millis: 32_400_000,
            end_millis: 32_760_000
          )

        message_value = Corpus.companion_got_calendar_ok_events([event])

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotCalendar",
               revision:
                 "corpus-calendar-phone-" <>
                   Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["lastTitle"] == "Team Sync"

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env FromPhone ProvideWeather step updates temperature when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideWeather", [18, :Clear])

    corpus_step_execute!(
      "companion-demo-weather-env",
      "FromPhone (ProvideWeather 18 Clear)",
      "corpus-weather-temp-",
      fn model ->
        assert model["temperatureC"] == 18
        assert model["condition"]["ctor"] == "Clear"
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env FromPhone ProvideEnvironment step updates sun fields when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideEnvironment", [360, 1080, 500_000])

    corpus_step_execute!(
      "companion-demo-weather-env",
      "FromPhone (ProvideEnvironment 360 1080 500000)",
      "corpus-weather-env-",
      fn model ->
        assert model["sunriseMin"] == 360
        assert model["sunsetMin"] == 1080
        assert model["moonPhaseE6"] == 500_000
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline phone GotToken step updates token when enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-timeline",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        token = "short-timeline-token"
        message_value = Corpus.companion_got_token_ok_value(token)

        case Corpus.corpus_phone_step_execute!(phone_workspace, "GotToken",
               revision:
                 "corpus-timeline-got-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["token"] == token

          {:compile_error, reason} ->
            flunk("companion-demo-timeline GotToken step failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline phone PinInserted Ok step keeps token when enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-timeline",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        token = "seed-token"
        message_value = Corpus.companion_pin_inserted_ok_value()

        case Corpus.corpus_phone_step_execute!(phone_workspace, "PinInserted",
               revision:
                 "corpus-timeline-pin-" <> Integer.to_string(:erlang.unique_integer([:positive])),
               message_value: message_value,
               current_runtime_model: %{"token" => token}
             ) do
          {:ok, _manifest, runtime_model} ->
            assert runtime_model["token"] == token

          {:compile_error, reason} ->
            flunk("companion-demo-timeline PinInserted step failed: #{inspect(reason)}")
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline ProvideTimelineToken step updates tokenPreview when enabled" do
    token = "short-timeline-token"
    message_value = Corpus.companion_from_phone_value("ProvideTimelineToken", [token])

    corpus_step_execute!(
      "companion-demo-timeline",
      "FromPhone (ProvideTimelineToken #{token})",
      "corpus-timeline-token-",
      fn model ->
        assert model["tokenPreview"] == token
      end,
      message_value: message_value
    )
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline ProvideTimelineStatus step updates pinStatus when enabled" do
    message_value = Corpus.companion_from_phone_value("ProvideTimelineStatus", [:PinOk])

    corpus_step_execute!(
      "companion-demo-timeline",
      "FromPhone (ProvideTimelineStatus PinOk)",
      "corpus-timeline-pin-",
      fn model ->
        assert model["pinStatus"]["ctor"] == "Just"
        assert hd(model["pinStatus"]["args"])["ctor"] == "PinOk"
      end,
      message_value: message_value
    )
  end

  defp corpus_step_execute!(template_key, message, revision_prefix, assert_model, step_opts \\ [])
       when is_function(assert_model, 1) do
    if @enabled? and template_key in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_step!(
               workspace,
               message,
               Keyword.merge(step_opts,
                 revision:
                   revision_prefix <> Integer.to_string(:erlang.unique_integer([:positive]))
               )
             ) do
          {:ok, _manifest, runtime_model} ->
            assert_model.(runtime_model)

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  defp corpus_init_execute!(template_key, revision_prefix, assert_model)
       when is_function(assert_model, 1) do
    if @enabled? and template_key in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

        case Corpus.corpus_compile_and_execute_init!(workspace,
               revision: revision_prefix <> Integer.to_string(:erlang.unique_integer([:positive]))
             ) do
          {:ok, _manifest, runtime_model} ->
            assert_model.(runtime_model)

          {:compile_error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  defp corpus_compile_smoke!(template_key, revision_prefix) do
    if @enabled? and template_key in DebuggerTemplateCorpus.template_keys() do
      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

      try do
        workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")
        revision = revision_prefix <> Integer.to_string(:erlang.unique_integer([:positive]))

        case Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
               revision: revision,
               strip_dead_code: true
             ) do
          {:ok, %{elmx_manifest: manifest}} ->
            assert manifest["contract"] == "elmx.runtime_executor.v1"

          {:error, reason} ->
            Corpus.refute_compile_gap!(reason)
        end
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
