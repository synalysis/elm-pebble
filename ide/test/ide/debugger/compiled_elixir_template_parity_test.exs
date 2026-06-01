defmodule Ide.Debugger.CompiledElixirTemplateParityTest do
  @moduledoc """
  Dual-run init parity for bootstrapped templates (optional, env-gated).

  `ELMX_TEMPLATE_CORPUS=1 mix test test/ide/debugger/compiled_elixir_template_parity_test.exs`
  """

  use Ide.DataCase, async: false

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Mcp.DebuggerTemplateCorpus

  @enabled? Corpus.corpus_enabled?()

  setup do
    old = Application.get_env(:ide, RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old)
    end)

    Corpus.ensure_compiled_elixir_backend!()
    :ok
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "starter init value parity when corpus enabled" do
    if @enabled? and "starter" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("starter", "value", 1)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-basic init y parity when corpus enabled" do
    if @enabled? and "game-basic" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("game-basic", "y", 60)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-poke-battle init animating parity when corpus enabled" do
    if @enabled? and "watchface-poke-battle" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watchface-poke-battle", "animating", false)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-poke-battle init scene ctor parity when corpus enabled" do
    if @enabled? and "watchface-poke-battle" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_union_ctor!("watchface-poke-battle", "scene", "Waiting", [])
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 init score and cells parity when corpus enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("game-2048", "score", 0)
      assert_parity_field!("game-2048", "cells", List.duplicate(0, 16))
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-analog init hour parity when corpus enabled" do
    if @enabled? and "watchface-analog" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watchface-analog", "hour", 12)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-digital init screen and time parity when corpus enabled" do
    if @enabled? and "watchface-digital" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watchface-digital", "screenW", 144)
      assert_parity_field!("watchface-digital", "timeString", "--:--")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-tiny-bird init birdY parity when corpus enabled" do
    if @enabled? and "game-tiny-bird" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("game-tiny-bird", "birdY", 60)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 RandomGenerated step seed parity when corpus enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("game-2048", "RandomGenerated 12345", "seed")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 RandomGenerated step cells parity when corpus enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("game-2048", "RandomGenerated 12345", "cells")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-tangram-time init screenW parity when corpus enabled" do
    if @enabled? and "watchface-tangram-time" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watchface-tangram-time", "screenW", 144)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run init playerY parity when corpus enabled" do
    if @enabled? and "game-jump-n-run" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("game-jump-n-run", "playerY", 84)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-accel init z parity when corpus enabled" do
    if @enabled? and "watch-demo-accel" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-accel", "z", -1000)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-light init modeIndex parity when corpus enabled" do
    if @enabled? and "watch-demo-light" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-light", "modeIndex", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-vibes init patternIndex parity when corpus enabled" do
    if @enabled? and "watch-demo-vibes" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-vibes", "patternIndex", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-app-focus init changes parity when corpus enabled" do
    if @enabled? and "watch-demo-app-focus" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-app-focus", "changes", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-watch-info init refreshes parity when corpus enabled" do
    if @enabled? and "watch-demo-watch-info" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-watch-info", "refreshes", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-compass init hasCompass parity when corpus enabled" do
    if @enabled? and "watch-demo-compass" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-compass", "hasCompass", false)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-compass GotHeading step heading parity on aplite when corpus enabled" do
    if @enabled? and "watch-demo-compass" in DebuggerTemplateCorpus.template_keys() do
      callback = %{"ctor" => "GotHeading", "args" => []}

      message_value =
        Elmx.Runtime.Pebble.runtime_dispatch("elmx_compass_peek", [callback])["message_value"]

      {:ok, %{project: project}} =
        DebuggerTemplateCorpus.bootstrap_template("watch-demo-compass", cleanup: false)

      try do
        launch_context = RuntimeSurfaces.launch_context_for("aplite", "LaunchUser")

        {elmx_value, core_value} =
          dual_steps_field_values!(
            project,
            ["GotHeading"],
            "heading",
            message_value,
            launch_context
          )

        assert parity_runtime_values_equal?(elmx_value, core_value)

        assert %{"ctor" => "Just", "args" => [heading]} = elmx_value
        assert heading["degrees"] == 180.0
        assert heading["isValid"] == true
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-compass init GotHeading followup parity on aplite when corpus enabled" do
    if @enabled? and "watch-demo-compass" in DebuggerTemplateCorpus.template_keys() do
      {:ok, %{project: project}} =
        DebuggerTemplateCorpus.bootstrap_template("watch-demo-compass", cleanup: false)

      try do
        launch_context = RuntimeSurfaces.launch_context_for("aplite", "LaunchUser")
        {elmx_followups, core_followups} = dual_init_followups!(project, launch_context)

        elmx_row = compass_got_heading_followup(elmx_followups)
        core_row = compass_got_heading_followup(core_followups)

        assert elmx_row != nil, "elmx init missing GotHeading device followup"
        assert core_row != nil, "core_ir init missing GotHeading device followup"
        assert parity_runtime_values_equal?(Map.get(elmx_row, "message_value"), Map.get(core_row, "message_value"))
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-data-log init events parity when corpus enabled" do
    if @enabled? and "watch-demo-data-log" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-data-log", "events", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-tutorial-complete init screenW parity when corpus enabled" do
    if @enabled? and "watchface-tutorial-complete" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watchface-tutorial-complete", "screenW", 144)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-health init events parity when corpus enabled" do
    if @enabled? and "watch-demo-health" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-health", "events", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-dictation init hasMicrophone parity when corpus enabled" do
    if @enabled? and "watch-demo-dictation" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watch-demo-dictation", "hasMicrophone", false)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watch-demo-dictation SelectPressed dictation followup parity on diorite when corpus enabled" do
    if @enabled? and "watch-demo-dictation" in DebuggerTemplateCorpus.template_keys() do
      {:ok, %{project: project}} =
        DebuggerTemplateCorpus.bootstrap_template("watch-demo-dictation", cleanup: false)

      try do
        # Dictation.start is guarded on `hasMicrophone`; aplite has none (see init parity test).
        launch_context = RuntimeSurfaces.launch_context_for("diorite", "LaunchUser")
        {elmx_followups, core_followups} = dual_step_followups!(project, "SelectPressed", launch_context)

        elmx_rows = dictation_runtime_followups(elmx_followups)
        core_rows = dictation_runtime_followups(core_followups)

        assert length(elmx_rows) == 4
        assert length(core_rows) == 4

        assert Enum.map(elmx_rows, & &1["message"]) ==
                 Enum.map(core_rows, & &1["message"])

        Enum.zip(elmx_rows, core_rows)
        |> Enum.each(fn {elmx_row, core_row} ->
          assert parity_runtime_values_equal?(
                   Map.get(elmx_row, "message_value"),
                   Map.get(core_row, "message_value")
                 )
        end)
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-weather-animated init suppressWeatherTransitions parity when corpus enabled" do
    if @enabled? and "watchface-weather-animated" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("watchface-weather-animated", "suppressWeatherTransitions", true)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 LeftPressed step turn parity when corpus enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("game-2048", "LeftPressed", "turn")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "starter Increment step value parity when corpus enabled" do
    if @enabled? and "starter" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("starter", "Increment", "value")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "starter Increment then Decrement value parity when corpus enabled" do
    if @enabled? and "starter" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_steps_field!("starter", ["Increment", "Decrement"], "value")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-basic UpPressed step vy parity when corpus enabled" do
    if @enabled? and "game-basic" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("game-basic", "UpPressed", "vy")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 RandomGenerated step score parity when corpus enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("game-2048", "RandomGenerated 12345", "score")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-basic FrameTick step vy parity when corpus enabled" do
    if @enabled? and "game-basic" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!(
        "game-basic",
        Ide.Debugger.CompiledElixirCorpusHelpers.frame_tick_message(),
        "vy"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-tiny-bird FrameTick step score parity when corpus enabled" do
    if @enabled? and "game-tiny-bird" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!(
        "game-tiny-bird",
        Ide.Debugger.CompiledElixirCorpusHelpers.frame_tick_message(),
        "score"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run UpPressed step velocityY parity when corpus enabled" do
    if @enabled? and "game-jump-n-run" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("game-jump-n-run", "UpPressed", "velocityY")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run FrameTick step offset parity when corpus enabled" do
    if @enabled? and "game-jump-n-run" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!(
        "game-jump-n-run",
        Corpus.frame_tick_message(),
        "offset"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-poke-battle SelectPressed step animating parity when corpus enabled" do
    if @enabled? and "watchface-poke-battle" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("watchface-poke-battle", "SelectPressed", "animating")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-2048 multi-step turn parity when corpus enabled" do
    if @enabled? and "game-2048" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_steps_field!(
        "game-2048",
        ["RandomGenerated 12345", "LeftPressed"],
        "turn"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation init latitudeE6 parity when corpus enabled" do
    if @enabled? and "companion-demo-geolocation" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("companion-demo-geolocation", "latitudeE6", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status init batteryPercent parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("companion-demo-phone-status", "batteryPercent", 0)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket init status parity when corpus enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_union_ctor!("companion-demo-websocket", "status", "Closed", [])
      assert_parity_field!("companion-demo-websocket", "statusDetail", "waiting")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline init tokenPreview parity when corpus enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("companion-demo-timeline", "tokenPreview", "loading")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env init temperatureC and condition parity when corpus enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("companion-demo-weather-env", "temperatureC", 0)
      assert_parity_union_ctor!("companion-demo-weather-env", "condition", "UnknownWeather", [])
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings init ready parity when corpus enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_field!("companion-demo-settings", "ready", false)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket FromPhone step status parity when corpus enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      message_value =
        Corpus.companion_from_phone_value("ProvideWebSocketStatus", [:Open, "connected"])

      assert_parity_step_with_value!(
        "companion-demo-websocket",
        "FromPhone (ProvideWebSocketStatus Open connected)",
        message_value,
        "status"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone Connected Ok step status parity when corpus enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_connected_ok_value()

      assert_parity_phone_step_field!(
        "companion-demo-websocket",
        "Connected",
        message_value,
        "status"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone WebSocketEvent Opened step status parity when corpus enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_websocket_event_value("Opened")

      assert_parity_phone_step_field!(
        "companion-demo-websocket",
        "WebSocketEvent",
        message_value,
        "status"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline phone PinInserted Ok step token parity when corpus enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_pin_inserted_ok_value()

      assert_parity_phone_step_field!(
        "companion-demo-timeline",
        "PinInserted",
        message_value,
        "token"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline phone GotToken step token parity when corpus enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      token = "short-timeline-token"
      message_value = Corpus.companion_got_token_ok_value(token)

      assert_parity_phone_step_with_value!(
        "companion-demo-timeline",
        "GotToken",
        message_value,
        "token",
        token
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline ProvideTimelineToken step tokenPreview parity when corpus enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      token = "short-timeline-token"
      message_value = Corpus.companion_from_phone_value("ProvideTimelineToken", [token])

      assert_parity_step_with_value!(
        "companion-demo-timeline",
        "FromPhone (ProvideTimelineToken #{token})",
        message_value,
        "tokenPreview"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "watchface-digital CurrentTimeString step timeString parity when corpus enabled" do
    if @enabled? and "watchface-digital" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_step_field!("watchface-digital", "CurrentTimeString 12:34", "timeString")
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status watch ProvideBattery step batteryPercent parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_from_phone_value("ProvideBattery", [88, true])

      assert_parity_step_with_value!(
        "companion-demo-phone-status",
        "FromPhone (ProvideBattery 88 true)",
        message_value,
        "batteryPercent"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status phone GotLocale step locale parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_got_locale_ok_value("fr-FR")

      assert_parity_phone_step_field!(
        "companion-demo-phone-status",
        "GotLocale",
        message_value,
        "locale"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage watch ProvideTheme step theme parity when corpus enabled" do
    if @enabled? and "companion-demo-storage" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_from_phone_value("ProvideTheme", [:Light, :Imperial])

      assert_parity_step_with_value!(
        "companion-demo-storage",
        "FromPhone (ProvideTheme Light Imperial)",
        message_value,
        "theme"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage phone GotStorage step theme parity when corpus enabled" do
    if @enabled? and "companion-demo-storage" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_got_storage_string_ok_value("light")

      assert_parity_phone_step_field!(
        "companion-demo-storage",
        "GotStorage",
        message_value,
        "theme"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage phone GotPreference step units parity when corpus enabled" do
    if @enabled? and "companion-demo-storage" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_got_preference_ok_value("units", "imperial")

      assert_parity_phone_step_field!(
        "companion-demo-storage",
        "GotPreference",
        message_value,
        "units"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env phone GotEnvironment step sun fields parity when corpus enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      info = Corpus.companion_environment_info(sunrise_min: 360, sunset_min: 1140, phase_e6: 750_000)
      message_value = Corpus.companion_got_environment_ok_value(info)

      assert_parity_phone_step_with_value!(
        "companion-demo-weather-env",
        "GotEnvironment",
        message_value,
        "sunriseMin",
        360
      )

      assert_parity_phone_step_with_value!(
        "companion-demo-weather-env",
        "GotEnvironment",
        message_value,
        "moonPhaseE6",
        750_000
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation phone GotPosition step coordinates parity when corpus enabled" do
    if @enabled? and "companion-demo-geolocation" in DebuggerTemplateCorpus.template_keys() do
      location = Corpus.companion_location_info(latitude: 12.345, longitude: -98.765, accuracy: 25.0)
      message_value = Corpus.companion_got_position_ok_value(location)

      assert_parity_phone_step_with_value!(
        "companion-demo-geolocation",
        "GotPosition",
        message_value,
        "latitudeE6",
        12_345_000
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env phone GotWeather step temperature parity when corpus enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      info = Corpus.companion_weather_info(temperature_c: 22, condition: "Clear")
      message_value = Corpus.companion_got_weather_current_ok_value(info)

      assert_parity_phone_step_with_value!(
        "companion-demo-weather-env",
        "GotWeather",
        message_value,
        "temperatureC",
        22
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env FromPhone ProvideWeather step parity when corpus enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_from_phone_value("ProvideWeather", [18, :Clear])

      assert_parity_watch_step_scalar!(
        "companion-demo-weather-env",
        "FromPhone (ProvideWeather 18 Clear)",
        message_value,
        "temperatureC",
        18
      )

      assert_parity_watch_step_union_ctor!(
        "companion-demo-weather-env",
        "FromPhone (ProvideWeather 18 Clear)",
        message_value,
        "condition",
        "Clear",
        []
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings phone LifecycleChanged Ready step ready parity when corpus enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_lifecycle_changed_value("Ready")

      assert_parity_phone_step_with_value!(
        "companion-demo-settings",
        "LifecycleChanged",
        message_value,
        "ready",
        true
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings phone ConfigurationClosed Saved step parity when corpus enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_configuration_closed_value("saved")

      assert_parity_phone_step_field!(
        "companion-demo-settings",
        "ConfigurationClosed",
        message_value,
        "configOutcome"
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings FromPhone SettingsReady step ready parity when corpus enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_from_phone_nullary("SettingsReady")

      assert_parity_watch_step_scalar!(
        "companion-demo-settings",
        "FromPhone SettingsReady",
        message_value,
        "ready",
        true
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status phone GotBattery step batteryPercent parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_got_battery_ok_value(77, false)

      assert_parity_phone_step_with_value!(
        "companion-demo-phone-status",
        "GotBattery",
        message_value,
        "batteryPercent",
        77
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation FromPhone ProvidePosition step latitudeE6 parity when corpus enabled" do
    if @enabled? and "companion-demo-geolocation" in DebuggerTemplateCorpus.template_keys() do
      message_value =
        Corpus.companion_from_phone_value("ProvidePosition", [12_345_000, -98_765_000, 25])

      assert_parity_geolocation_step!(message_value)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status phone GotConnectivity step online parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_got_connectivity_value("Online")

      assert_parity_phone_step_with_value!(
        "companion-demo-phone-status",
        "GotConnectivity",
        message_value,
        "online",
        true
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status watch ProvideNotifications step flags parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      assert_parity_notifications_step!(
        Corpus.companion_from_phone_value("ProvideNotifications", [true, false])
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar FromPhone ProvideNextEvent step nextEvent parity when corpus enabled" do
    if @enabled? and "companion-demo-calendar" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_from_phone_value("ProvideNextEvent", ["Standup", 9, 30])

      assert_parity_calendar_next_event_step!(message_value)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status phone GotNotifications step flags parity when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      message_value = Corpus.companion_got_notifications_ok_value(true, false)

      assert_parity_phone_step_with_value!(
        "companion-demo-phone-status",
        "GotNotifications",
        message_value,
        "notificationsEnabled",
        true
      )

      assert_parity_phone_step_with_value!(
        "companion-demo-phone-status",
        "GotNotifications",
        message_value,
        "quietHours",
        false
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar phone GotCalendar step lastTitle parity when corpus enabled" do
    if @enabled? and "companion-demo-calendar" in DebuggerTemplateCorpus.template_keys() do
      event =
        Corpus.companion_calendar_event(
          id: "standup",
          title: "Team Sync",
          start_millis: 32_400_000,
          end_millis: 32_760_000
        )

      message_value = Corpus.companion_got_calendar_ok_events([event])

      assert_parity_phone_step_with_value!(
        "companion-demo-calendar",
        "GotCalendar",
        message_value,
        "lastTitle",
        "Team Sync"
      )
    else
      assert true
    end
  end

  defp assert_parity_field!(template_key, field, expected) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} = dual_init_field_values!(project, field)
      assert parity_runtime_values_equal?(elmx_value, core_value)
      assert elmx_value == expected
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_union_ctor!(template_key, field, ctor, args) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} = dual_init_field_values!(project, field)

      assert union_ctor_wire(elmx_value) == union_ctor_wire(core_value)
      assert union_ctor_wire(elmx_value) == %{"ctor" => ctor, "args" => args}
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_step_field!(template_key, message, field) do
    assert_parity_steps_field!(template_key, [message], field)
  end

  defp assert_parity_step_with_value!(template_key, message, message_value, field) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} = dual_step_field_values!(project, message, message_value, field)
      assert parity_runtime_values_equal?(elmx_value, core_value)
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_watch_step_scalar!(template_key, message, message_value, field, expected) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} = dual_step_field_values!(project, message, message_value, field)
      assert parity_runtime_values_equal?(elmx_value, core_value)
      assert elmx_value == expected
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_watch_step_union_ctor!(template_key, message, message_value, field, ctor, args) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} = dual_step_field_values!(project, message, message_value, field)
      assert union_ctor_wire(elmx_value) == union_ctor_wire(core_value)
      assert union_ctor_wire(elmx_value) == %{"ctor" => ctor, "args" => args}
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_geolocation_step!(message_value) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template("companion-demo-geolocation", cleanup: false)

    message = "FromPhone (ProvidePosition 12345000 -98765000 25)"

    try do
      {elmx_lat, core_lat} = dual_step_field_values!(project, message, message_value, "latitudeE6")
      assert elmx_lat == core_lat
      assert elmx_lat == 12_345_000
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_notifications_step!(message_value) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template("companion-demo-phone-status", cleanup: false)

    message = "FromPhone (ProvideNotifications true false)"

    try do
      {elmx_enabled, core_enabled} =
        dual_step_field_values!(project, message, message_value, "notificationsEnabled")

      {elmx_quiet, core_quiet} =
        dual_step_field_values!(project, message, message_value, "quietHours")

      assert elmx_enabled == core_enabled
      assert elmx_quiet == core_quiet
      assert elmx_enabled == true
      assert elmx_quiet == false
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_calendar_next_event_step!(message_value) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template("companion-demo-calendar", cleanup: false)

    message = "FromPhone (ProvideNextEvent Standup 9 30)"

    try do
      {elmx_event, core_event} = dual_step_field_values!(project, message, message_value, "nextEvent")
      assert parity_runtime_values_equal?(elmx_event, core_event)
      assert elmx_event["ctor"] == "Just"

      event = hd(elmx_event["args"])
      assert event["title"] == "Standup"
      assert event["hour"] == 9
      assert event["minute"] == 30
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_phone_step_with_value!(template_key, message, message_value, field, expected, opts \\ []) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} =
        dual_phone_step_field_values!(project, message, message_value, field, opts)

      assert parity_runtime_values_equal?(elmx_value, core_value)
      assert elmx_value == expected
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_phone_step_field!(template_key, message, message_value, field, opts \\ []) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} =
        dual_phone_step_field_values!(project, message, message_value, field, opts)

      assert parity_runtime_values_equal?(elmx_value, core_value)
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp assert_parity_steps_field!(template_key, messages, field) when is_list(messages) do
    assert_parity_steps_field!(template_key, messages, field, nil)
  end

  defp assert_parity_steps_field!(template_key, messages, field, message_value)
       when is_list(messages) do
    {:ok, %{project: project}} =
      DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      {elmx_value, core_value} = dual_steps_field_values!(project, messages, field, message_value)
      assert parity_runtime_values_equal?(elmx_value, core_value)
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  defp compass_got_heading_followup(followups) when is_list(followups) do
    Enum.find(followups, fn row ->
      message = Map.get(row, "message") || Map.get(row, :message)
      source = Map.get(row, "source") || Map.get(row, :source)

      message == "GotHeading" and source == "device_command"
    end)
  end

  defp dual_init_followups!(project, launch_context) when is_map(launch_context) do
    workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

    base_request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: "",
      introspect: %{},
      current_model: %{"launch_context" => launch_context},
      current_view_tree: %{},
      message: nil
    }

    revision = "parity-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
               revision: revision,
               strip_dead_code: true
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_payload} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_payload} =
             RuntimeExecutor.execute(
               Map.merge(base_request, core_ir_attrs!(workspace))
             )

    {
      normalize_followup_rows(elmx_payload.followup_messages || []),
      normalize_followup_rows(core_payload.followup_messages || [])
    }
  end

  defp normalize_followup_rows(rows) when is_list(rows) do
    Enum.map(rows, fn row ->
      row
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
    end)
  end

  defp dictation_runtime_followups(followups) when is_list(followups) do
    Enum.filter(followups, fn row ->
      Map.get(row, "source") == "runtime_followup" and
        Map.get(row, "message") in ["DictationStatusChanged", "DictationFinished"]
    end)
  end

  defp dual_step_followups!(project, message, launch_context)
       when is_binary(message) and is_map(launch_context) do
    workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

    base_request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: "",
      introspect: %{},
      current_view_tree: %{}
    }

    revision = "parity-step-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
               revision: revision,
               strip_dead_code: true
             )

    init_model = %{"launch_context" => launch_context}

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_init} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision,
                 current_model: init_model,
                 message: nil
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_init} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 current_model: init_model,
                 message: nil
               })
               |> Map.merge(core_ir_attrs!(workspace))
             )

    elmx_step_model = %{
      "launch_context" => launch_context,
      "runtime_model" => get_in(elmx_init.model_patch, ["runtime_model"]) || %{}
    }

    core_step_model = %{
      "launch_context" => launch_context,
      "runtime_model" => get_in(core_init.model_patch, ["runtime_model"]) || %{}
    }

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_step} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision,
                 current_model: elmx_step_model,
                 message: message
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_step} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 current_model: core_step_model,
                 message: message
               })
               |> Map.merge(core_ir_attrs!(workspace))
             )

    {
      normalize_followup_rows(elmx_step.followup_messages || []),
      normalize_followup_rows(core_step.followup_messages || [])
    }
  end

  defp dual_init_field_values!(project, field) do
    workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")
    launch_context = RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

    base_request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: "",
      introspect: %{},
      current_model: %{"launch_context" => launch_context},
      current_view_tree: %{},
      message: nil
    }

    revision = "parity-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
               revision: revision,
               strip_dead_code: true
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_payload} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_payload} =
             RuntimeExecutor.execute(
               Map.merge(base_request, core_ir_attrs!(workspace))
             )

    {
      get_in(elmx_payload.model_patch, ["runtime_model", field]),
      get_in(core_payload.model_patch, ["runtime_model", field])
    }
  end

  defp dual_step_field_values!(project, message, field) do
    dual_steps_field_values!(project, [message], field, nil)
  end

  defp dual_step_field_values!(project, message, message_value, field) do
    dual_steps_field_values!(project, [message], field, message_value)
  end

  defp dual_steps_field_values!(project, messages, field, message_value, launch_context \\ nil)
       when is_list(messages) do
    workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")

    launch_context =
      launch_context || RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

    base_request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: "",
      introspect: %{},
      current_view_tree: %{}
    }

    revision = "parity-step-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
               revision: revision,
               strip_dead_code: true
             )

    init_model = %{"launch_context" => launch_context}

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_init} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision,
                 current_model: init_model,
                 message: nil
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_init} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 current_model: init_model,
                 message: nil
               })
               |> Map.merge(core_ir_attrs!(workspace))
             )

    {elmx_model, core_model} =
      Enum.reduce(messages, {elmx_init, core_init}, fn message, {elmx_acc, core_acc} ->
        elmx_step_model = %{
          "launch_context" => launch_context,
          "runtime_model" => get_in(elmx_acc.model_patch, ["runtime_model"]) || %{}
        }

        core_step_model = %{
          "launch_context" => launch_context,
          "runtime_model" => get_in(core_acc.model_patch, ["runtime_model"]) || %{}
        }

        Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

        elmx_step_request =
          Map.merge(base_request, %{
            elmx_manifest: manifest,
            elmx_revision: revision,
            current_model: elmx_step_model,
            message: message
          })

        elmx_step_request =
          if message_value,
            do: Map.put(elmx_step_request, :message_value, message_value),
            else: elmx_step_request

        {:ok, elmx_next} = RuntimeExecutor.execute(elmx_step_request)

        Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

        core_step_request =
          Map.merge(base_request, %{
            current_model: core_step_model,
            message: message
          })

        core_step_request =
          if message_value,
            do: Map.put(core_step_request, :message_value, message_value),
            else: core_step_request

        {:ok, core_next} =
          RuntimeExecutor.execute(Map.merge(core_step_request, core_ir_attrs!(workspace)))

        {elmx_next, core_next}
      end)

    {
      get_in(elmx_model.model_patch, ["runtime_model", field]),
      get_in(core_model.model_patch, ["runtime_model", field])
    }
  end

  defp parity_runtime_values_equal?(left, right) do
    case {union_ctor_wire(left), union_ctor_wire(right)} do
      {%{"ctor" => _} = normalized_left, %{"ctor" => _} = normalized_right} ->
        normalized_left == normalized_right

      _ ->
        left == right
    end
  end

  defp union_ctor_wire(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args) do
    %{"ctor" => ctor, "args" => Enum.map(args, &union_ctor_wire/1)}
  end

  defp union_ctor_wire(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args) do
    %{"ctor" => ctor, "args" => Enum.map(args, &union_ctor_wire/1)}
  end

  defp union_ctor_wire(atom) when is_atom(atom), do: %{"ctor" => Atom.to_string(atom), "args" => []}
  defp union_ctor_wire(other), do: other

  defp dual_phone_step_field_values!(project, message, message_value, field, opts \\ []) do
    phone_workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

    base_request = %{
      source_root: "phone",
      rel_path: "src/CompanionApp.elm",
      source: "",
      introspect: %{},
      current_view_tree: %{}
    }

    revision = "parity-phone-step-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(phone_workspace,
               revision: revision,
               entry_module: "CompanionApp",
               strip_dead_code: true
             )

    init_model = Keyword.get(opts, :phone_init_model, %{})

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_init} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision,
                 current_model: init_model,
                 message: nil
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_init} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 current_model: init_model,
                 message: nil
               })
               |> Map.merge(core_ir_attrs!(phone_workspace, "CompanionApp"))
             )

    elmx_step_model = %{"runtime_model" => get_in(elmx_init.model_patch, ["runtime_model"]) || %{}}
    core_step_model = %{"runtime_model" => get_in(core_init.model_patch, ["runtime_model"]) || %{}}

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    elmx_step_request =
      Map.merge(base_request, %{
        elmx_manifest: manifest,
        elmx_revision: revision,
        current_model: elmx_step_model,
        message: message,
        message_value: message_value
      })

    {:ok, elmx_step} = RuntimeExecutor.execute(elmx_step_request)

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    {:ok, core_step} =
      RuntimeExecutor.execute(
        Map.merge(base_request, %{
          current_model: core_step_model,
          message: message,
          message_value: message_value
        })
        |> Map.merge(core_ir_attrs!(phone_workspace, "CompanionApp"))
      )

    {
      get_in(elmx_step.model_patch, ["runtime_model", field]),
      get_in(core_step.model_patch, ["runtime_model", field])
    }
  end

  defp core_ir_attrs!(workspace), do: core_ir_attrs!(workspace, "Main")

  defp core_ir_attrs!(workspace, entry_module) when is_binary(entry_module) do
    {:ok, project} = Bridge.load_project(workspace)
    {:ok, ir} = Lowerer.lower_project(project)
    {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

    %{
      "elm_executor_core_ir" => core_ir,
      "elm_executor_metadata" => %{
        "compiler" => "elm_executor",
        "contract" => "elm_executor.runtime_executor.v1",
        "mode" => "ide_runtime",
        "entry_module" => entry_module,
        "core_ir_validation" => "loose"
      }
    }
  end
end
