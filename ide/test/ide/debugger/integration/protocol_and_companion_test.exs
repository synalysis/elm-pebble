defmodule Ide.Debugger.ProtocolAndCompanionIntegrationTest do
  @moduledoc false
  use Ide.DebuggerIntegrationCase, async: false

  alias Ide.DebuggerIntegrationExecutors.AccelRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.AliveGuardFrameExecutor
  alias Ide.DebuggerIntegrationExecutors.DebuggerRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.FailingExternalRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.FrameRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.HttpFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.InitNoFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.InitRandomFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.MaybeShapeRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.NilMaybeRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.StorageFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.TupleMaybeRuntimeExecutor

  test "watch init queues companion protocol until companion reload instead of bootstrapping init" do
    slug = "sim-watch-queues-companion-#{System.unique_integer([:positive])}"

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "src", "Main.elm"])
      )

    companion_source =
      File.read!(
        Path.join([
          "priv",
          "project_templates",
          "watchface_tangram_time",
          "phone",
          "src",
          "CompanionApp.elm"
        ])
      )

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, after_watch} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               reason: "watch_only",
               source_root: "watch"
             })

    assert AppMessageQueue.pending?(after_watch, :companion)

    refute Enum.any?(after_watch.debugger_timeline, fn row ->
             row.type == "init" and row.target == "phone"
           end)

    assert {:ok, after_companion} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: companion_source,
               reason: "companion_after_watch",
               source_root: "phone"
             })

    phone_inits =
      after_companion.debugger_timeline
      |> Enum.filter(&(&1.type == "init" and &1.target == "phone"))
      |> Enum.map(& &1.seq)

    assert length(phone_inits) == 1
    refute AppMessageQueue.pending?(after_companion, :companion)

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, after_drain} = Debugger.snapshot(slug, event_limit: 500)

    assert Enum.any?(after_drain.debugger_timeline, fn row ->
             row.target == "phone" and
               (row.type in ["update", "protocol_rx"] or
                  row.type == "runtime_exec_error") and
               (String.contains?(to_string(row.message || ""), "FromWatch") or
                  String.contains?(to_string(row.message || ""), "FromWatch"))
           end) or
             Enum.any?(after_drain.events, fn event ->
               event.type == "debugger.protocol_rx" and
                 String.contains?(inspect(event.payload), "FromWatch")
             end)
  end

  test "protocol matrix button select delivers watch ping to companion" do
    slug = "sim-protocol-matrix-select-#{System.unique_integer([:positive])}"

    template_root =
      Path.join(["priv", "project_templates", "companion_demo_protocol_matrix"])

    watch_source = File.read!(Path.join(template_root, "src/Main.elm"))

    companion_source =
      File.read!(Path.join(template_root, "phone/src/CompanionApp.elm"))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               reason: "protocol_matrix_watch",
               source_root: "watch"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: companion_source,
               reason: "protocol_matrix_companion",
               source_root: "phone"
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)

    assert {:ok, _} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "button_select"
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, after_select} = Debugger.snapshot(slug, event_limit: 500)

    assert Enum.any?(after_select.debugger_timeline, fn row ->
             row.target in ["phone", "companion"] and
               String.contains?(to_string(row.message || ""), "FromWatch")
           end)
  end

  test "inject_trigger applies subscription-style button trigger with deterministic events" do
    slug = "sim-trigger-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSnap exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as Platform

    type alias Model =
        { n : Int }

    type Msg
        = Inc
        | Dec
        | ButtonUp
        | ButtonDown

    init _ =
        ( { n = 0 }, Cmd.none )

    update msg model =
        case msg of
            ButtonUp ->
                ( { n = model.n + 1 }, Cmd.none )

            _ ->
                ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        []

    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSnap.elm",
        source: source,
        reason: "trigger_base"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    assert Enum.any?(trigger_rows, fn row -> is_binary(row[:trigger]) and row[:trigger] != "" end)

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "button_up"
             })

    assert get_in(triggered, [:watch, :model, "runtime_last_message"]) == "ButtonUp"
    assert get_in(triggered, [:watch, :model, "runtime_message_source"]) == "subscription_trigger"
    assert get_in(triggered, [:watch, :model, "runtime_model_source"]) == "step_message"

    assert trigger_exec =
             Enum.find(
               triggered.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) ==
                     "subscription_trigger")
             )

    assert trigger_exec.payload.message_source == "subscription_trigger"
    assert Enum.any?(triggered.events, &(&1.type == "debugger.update_in"))
    assert Enum.any?(triggered.events, &(&1.type == "debugger.view_render"))
  end

  test "inject_trigger applies structured accelerometer subscription payload" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, AccelRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-accel-trigger-#{System.unique_integer([:positive])}"

    source = """
    module AccelTrigger exposing (..)

    import Json.Decode as Decode
    import Pebble.Accel as Accel
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { x : Int
        , y : Int
        , z : Int
        }

    type Msg
        = AccelData Accel.Sample

    init _ =
        ( { x = 0, y = 0, z = 1000 }, Cmd.none )

    update msg model =
        case msg of
            AccelData sample ->
                ( { model | x = sample.x, y = sample.y, z = sample.z }, Cmd.none )

    subscriptions _ =
        Accel.onData Accel.defaultConfig AccelData

    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]

    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/AccelTrigger.elm",
        source: source,
        reason: "accel_trigger_base"
      })

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_accel",
               message: "AccelData",
               message_value: %{"x" => 120, "y" => -340, "z" => 930}
             })

    runtime_model = get_in(triggered, [:watch, :model, "runtime_model"]) || %{}
    assert runtime_model["x"] == 120
    assert runtime_model["y"] == -340
    assert runtime_model["z"] == 930
    assert get_in(triggered, [:watch, :model, "runtime_last_message"]) == "AccelData"
  end

  test "normalize_simulator_settings includes tier 1 watch sensor fields" do
    settings =
      Debugger.normalize_simulator_settings(%{
        "compass_heading_deg" => "180",
        "app_in_focus" => "false",
        "dictation_transcript" => "hello",
        "vibe_pattern_ms" => [100, 50]
      })

    assert settings["compass_heading_deg"] == 180
    assert settings["compass_valid"] == true
    assert settings["app_in_focus"] == false
    assert settings["dictation_transcript"] == "hello"
    assert settings["vibe_pattern_ms"] == [100, 50]
  end

  test "frame subscription trigger auto-fire sends frame payload" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, FrameRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-frame-trigger-#{System.unique_integer([:positive])}"

    source = """
    module FrameTrigger exposing (..)

    import Json.Decode as Decode
    import Pebble.Frame as Frame
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { frame : Int }

    type Msg
        = FrameTick Frame.Frame

    init _ =
        ( { frame = 0 }, Cmd.none )

    update msg model =
        case msg of
            FrameTick frame ->
                ( { model | frame = frame.frame }, Cmd.none )

    subscriptions _ =
        Frame.every 33 FrameTick

    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]

    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/FrameTrigger.elm",
        source: source,
        reason: "frame_trigger_base"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})

    assert frame_trigger =
             Enum.find(trigger_rows, fn row ->
               row[:message] == "FrameTick" and String.contains?(row[:trigger], "Frame")
             end)

    assert frame_trigger[:declared_interval_ms] == 33
    assert frame_trigger[:interval_ms] == 100

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               trigger: frame_trigger[:trigger],
               enabled: "true"
             })

    assert enabled.auto_tick.interval_ms == 100

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, triggered} = Debugger.stop_auto_tick(slug)

    runtime_model = get_in(triggered, [:watch, :model, "runtime_model"]) || %{}

    frame_fields =
      case Map.get(runtime_model, "frame") do
        %{} = frame -> frame
        _ -> runtime_model
      end

    assert frame_fields["frame"] >= 1
    assert frame_fields["dtMs"] == 16
    assert frame_fields["elapsedMs"] == frame_fields["frame"] * frame_fields["dtMs"]

    assert get_in(triggered, [:watch, :model, "runtime_message_source"]) ==
             "subscription_auto_fire"

    assert String.starts_with?(
             get_in(triggered, [:watch, :model, "runtime_last_message"]),
             "FrameTick "
           )

    assert Enum.any?(triggered.events, fn event ->
             message = Map.get(event.payload, :message) || Map.get(event.payload, "message") || ""

             event.seq > enabled_seq and event.type == "debugger.update_in" and
               String.starts_with?(message, "FrameTick ")
           end)
  end

  test "conditional frame subscription auto-fire respects model activation guards" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, AliveGuardFrameExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-frame-guard-#{System.unique_integer([:positive])}"

    source = """
    module FrameGuard exposing (..)

    import Json.Decode as Decode
    import Pebble.Events as Events
    import Pebble.Frame as Frame
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { alive : Bool
        , frame : Int
        }

    type Msg
        = Die
        | FrameTick Frame.Frame

    init _ =
        ( { alive = True, frame = 0 }, Cmd.none )

    update msg model =
        case msg of
            Die ->
                ( { model | alive = False }, Cmd.none )

            FrameTick frame ->
                ( { model | frame = frame.frame }, Cmd.none )

    subscriptions model =
        Events.batch
            [ if model.alive then
                  Frame.every 33 FrameTick
              else
                  Sub.none
            ]

    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]

    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/FrameGuard.elm",
        source: source,
        reason: "frame_guard_base"
      })

    assert {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Die", count: 1})

    assert {:ok, died_state} = Debugger.snapshot(slug)

    assert get_in(died_state, [:watch, :model, "runtime_model", "alive"]) == false
    assert is_boolean(get_in(died_state, [:watch, :model, "runtime_model", "alive"]))

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})

    assert frame_trigger =
             Enum.find(trigger_rows, fn row ->
               row[:message] == "FrameTick" and String.contains?(row[:trigger], "Frame")
             end)

    assert frame_trigger[:model_active] == false

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               trigger: frame_trigger[:trigger],
               enabled: "true"
             })

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    refute Enum.any?(stopped.events, fn event ->
             message = Map.get(event.payload, :message) || Map.get(event.payload, "message") || ""

             event.seq > enabled_seq and event.type == "debugger.update_in" and
               String.starts_with?(message, "FrameTick ")
           end)
  end

  test "conditional frame subscription auto-fire treats lowercase false strings as inactive" do
    source = """
    module FrameGuardString exposing (..)

    import Pebble.Events as Events
    import Pebble.Frame as Frame

    type alias Model =
        { alive : Bool
        , frame : Int
        }

    type Msg
        = FrameTick

    init _ =
        ( { alive = True, frame = 0 }, Cmd.none )

    update msg model =
        ( model, Cmd.none )

    subscriptions model =
        Events.batch
            [ if model.alive then
                  Frame.every 33 FrameTick
              else
                  Sub.none
            ]
    """

    assert {:ok, %{"debugger_contract" => ei}} =
             Ide.Debugger.CompileContract.analyze_source(source, "FrameGuardString.elm")

    state = %{
      watch: %{
        model: %{
          "runtime_model" => %{"alive" => false},
          "debugger_contract" => ei
        }
      }
    }

    row = %{trigger: "Frame.every", message: "FrameTick", target: "watch"}

    refute Debugger.subscription_model_active?(state, :watch, row)
  end

  test "disabled subscription trigger cannot be injected until re-enabled" do
    slug = "sim-disabled-subscription-#{System.unique_integer([:positive])}"

    source = """
    module DisabledSubscription exposing (..)

    import Pebble.Events as Events

    type Msg
      = Tick

    init _ =
      ( { count = 0 }, Cmd.none )

    update msg model =
      case msg of
        Tick ->
          ( { model | count = model.count + 1 }, Cmd.none )

    subscriptions _ =
      Events.onSecondChange Tick
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/DisabledSubscription.elm",
        source: source,
        reason: "disabled_subscription"
      })

    assert {:ok, disabled} =
             Debugger.set_subscription_enabled(slug, %{
               target: "watch",
               trigger: "on_second_change",
               enabled: "false"
             })

    disabled_seq = disabled.seq

    assert {:ok, blocked} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_second_change",
               message: "Tick"
             })

    refute Enum.any?(blocked.events, fn event ->
             event.seq > disabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)

    assert {:ok, enabled} =
             Debugger.set_subscription_enabled(slug, %{
               target: "watch",
               trigger: "on_second_change",
               enabled: "true"
             })

    enabled_seq = enabled.seq

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_second_change",
               message: "Tick"
             })

    assert Enum.any?(triggered.events, fn event ->
             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)
  end

  test "available_triggers prefers structured subscription callback constructors" do
    slug = "sim-trigger-subscription-callbacks-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSubscriptions exposing (..)

    type Msg
      = Tick
      | MinuteChanged Int

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Evts.batch [ Evts.onSecondChange Tick, Evts.onMinuteChange MinuteChanged ]
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSubscriptions.elm",
        source: source,
        reason: "subscription_trigger_callbacks"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})

    assert Enum.any?(trigger_rows, fn row ->
             row.trigger == "on_second_change" and row.message == "Tick"
           end)

    assert Enum.any?(trigger_rows, fn row ->
             row.trigger == "on_minute_change" and row.message == "MinuteChanged"
           end)

    assert Enum.all?(trigger_rows, &(&1.source == "subscription"))
    refute Enum.any?(trigger_rows, &(&1.trigger == "button_up"))
  end

  test "inject_trigger attaches local hour to HourChanged when trigger is on_hour_change" do
    slug = "sim-hour-change-payload-#{System.unique_integer([:positive])}"

    source = """
    module HourChangePayload exposing (..)

    import Pebble.Events as PebbleEvents
    import Pebble.Platform as PebblePlatform
    import Json.Decode as Decode

    type alias Model =
      { hour : Int }

    type Msg
      = HourChanged Int

    init _ =
      ( { hour = 0 }, Cmd.none )

    update msg model =
      case msg of
        HourChanged h ->
          ( { model | hour = h }, Cmd.none )

    subscriptions _ =
      PebbleEvents.onHourChange HourChanged

    view _ =
      []

    main : Program Decode.Value Model Msg
    main =
      PebblePlatform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/HourChangePayload.elm",
        source: source,
        reason: "hour_change_payload"
      })

    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    row = Enum.find(rows, &(&1.trigger == "on_hour_change" and &1.message == "HourChanged"))
    assert row

    assert {:ok, after_inject} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: row.trigger,
               message: row.message
             })

    msg = get_in(after_inject, [:watch, :model, "runtime_last_message"]) || ""
    assert String.match?(msg, ~r/^HourChanged [0-9]{1,2}$/)

    hour_str = String.replace_leading(msg, "HourChanged ", "")
    {hour, ""} = Integer.parse(hour_str)
    assert hour in 0..23
  end

  test "inject_trigger attaches system payloads for battery and connection subscriptions" do
    slug = "sim-system-subscription-payloads-#{System.unique_integer([:positive])}"

    source = """
    module SystemPayloadSubscriptions exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.System as PebbleSystem

    type alias Model =
      { battery : Int
      , connected : Bool
      }

    type Msg
      = BatteryChanged Int
      | ConnectionChanged Bool

    init _ =
      ( { battery = 0, connected = False }, Cmd.none )

    update msg model =
      case msg of
        BatteryChanged level ->
          ( { model | battery = level }, Cmd.none )

        ConnectionChanged connected ->
          ( { model | connected = connected }, Cmd.none )

    subscriptions _ =
      Sub.batch
        [ PebbleSystem.onBatteryChange BatteryChanged
        , PebbleSystem.onConnectionChange ConnectionChanged
        ]

    view _ =
      []

    main : Program Decode.Value Model Msg
    main =
      PebblePlatform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/SystemPayloadSubscriptions.elm",
        source: source,
        reason: "system_subscription_payloads"
      })

    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    battery_row = Enum.find(rows, &(&1.trigger == "on_battery_change"))
    connection_row = Enum.find(rows, &(&1.trigger == "on_connection_change"))

    assert battery_row.message == "BatteryChanged"
    assert connection_row.message == "ConnectionChanged"

    assert {:ok, after_battery} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: battery_row.trigger,
               message: battery_row.message
             })

    assert get_in(after_battery, [:watch, :model, "runtime_last_message"]) == "BatteryChanged 88"

    assert {:ok, after_connection} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: connection_row.trigger,
               message: connection_row.message
             })

    assert get_in(after_connection, [:watch, :model, "runtime_last_message"]) ==
             "ConnectionChanged True"
  end

  test "subscription trigger candidates ignore Sub.none" do
    slug = "sim-trigger-sub-none-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSubNone exposing (..)

    type Msg
      = Tick

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Sub.none
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSubNone.elm",
        source: source,
        reason: "subscription_trigger_sub_none"
      })

    assert {:ok, trigger_rows} = Debugger.available_triggers(slug, %{"target" => "watch"})

    refute Enum.any?(trigger_rows, &(&1.source == "subscription"))
  end

  test "elmc ingest attaches diagnostic_preview to event payload for timeline export" do
    slug = "sim-evp-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.ingest_elmc_check(slug, %{
        status: :ok,
        checked_path: ".",
        error_count: 0,
        warning_count: 0,
        diagnostics: [%{severity: "info", message: "all good", source: "elmc"}]
      })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 5)
    ev = hd(st.events)
    assert ev.type == "debugger.elmc_check"
    prev = Map.get(ev.payload, :diagnostic_preview) || Map.get(ev.payload, "diagnostic_preview")
    assert is_list(prev)
    assert hd(prev)["message"] == "all good"
  end

  test "ingest_elmc_check stores elmc_diagnostic_preview when diagnostics given" do
    slug = "sim-diag-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    diag = %{
      severity: "error",
      message: "bad type",
      file: "src/M.elm",
      line: 3,
      column: 1,
      source: "elmc",
      warning_type: "lowerer-warning",
      warning_code: "constructor_payload_arity",
      warning_constructor: "Just",
      warning_expected_kind: "single",
      warning_has_arg_pattern: false
    }

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :error,
               checked_path: "/w",
               error_count: 1,
               warning_count: 0,
               diagnostics: [diag]
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 5)
    [row] = get_in(st.watch, [:model, "elmc_diagnostic_preview"])
    assert row["message"] == "bad type"
    assert row["file"] == "src/M.elm"
    assert row["line"] == 3
    assert row["warning_type"] == "lowerer-warning"
    assert row["warning_code"] == "constructor_payload_arity"
    assert row["warning_constructor"] == "Just"
    assert row["warning_expected_kind"] == "single"
    assert row["warning_has_arg_pattern"] == false
  end

  test "ingest_elmc_check merges model fields and appends event when running" do
    slug = "sim-elmc-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :ok,
               checked_path: "/tmp/ws",
               error_count: 0,
               warning_count: 2
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    assert hd(st.events).type == "debugger.elmc_check"
    assert get_in(st.watch, [:model, "elmc_check_status"]) == "ok"
    assert get_in(st.watch, [:model, "elmc_warning_count"]) == 2
    assert get_in(st.watch, [:model, "elmc_checked_path"]) == "/tmp/ws"
  end

  test "ingest_elmc_compile merges model fields and appends event when running" do
    slug = "sim-elmc-compile-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "/tmp/compile",
               revision: "deadbeef",
               cached: true,
               error_count: 0,
               warning_count: 0
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    assert hd(st.events).type == "debugger.elmc_compile"
    assert get_in(st.watch, [:model, "elmc_compile_status"]) == "ok"
    assert get_in(st.watch, [:model, "elmc_compile_revision"]) == "deadbeef"
    assert get_in(st.watch, [:model, "elmc_compile_cached"]) == "true"
  end

  test "ingest_elmc_compile scopes elmx runtime artifacts to compiled source root" do
    slug = "sim-elmc-compile-artifacts-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "phone",
               revision: "companion",
               elmx_manifest: %{"contract" => "elmx.runtime_executor.v1"},
               elmx_revision: "companion"
             })

    assert {:ok, st_after_companion} = Debugger.snapshot(slug, event_limit: 10)
    assert get_in(st_after_companion.companion, [:shell, "elmx_revision"]) == "companion"
    refute get_in(st_after_companion.watch, [:shell, "elmx_revision"])
    refute get_in(st_after_companion.companion, [:model, "elmx_revision"])
    refute get_in(st_after_companion.watch, [:model, "elmx_revision"])

    assert {:ok, st_after_watch} =
             Debugger.ingest_elmc_compile(slug, %{
               status: :ok,
               compiled_path: "watch",
               revision: "watch",
               elmx_manifest: %{"contract" => "elmx.runtime_executor.v1"},
               elmx_revision: "watch"
             })

    assert get_in(st_after_watch.watch, [:shell, "elmx_revision"]) == "watch"
    refute get_in(st_after_watch.watch, [:model, "elmx_revision"])

    assert get_in(st_after_watch.companion, [:shell, "elmx_revision"]) ==
             get_in(st_after_companion.companion, [:shell, "elmx_revision"])
  end

  test "ingest_elmc_manifest merges model fields and appends event when running" do
    slug = "sim-elmc-manifest-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_manifest(slug, %{
               status: :ok,
               manifest_path: "/tmp/m",
               revision: "rev1",
               strict: true,
               cached: false,
               error_count: 0,
               warning_count: 0,
               schema_version: 1
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    assert hd(st.events).type == "debugger.elmc_manifest"
    assert get_in(st.watch, [:model, "elmc_manifest_status"]) == "ok"
    assert get_in(st.watch, [:model, "elmc_manifest_schema_version"]) == "1"
    assert get_in(st.watch, [:model, "elmc_manifest_strict"]) == "true"
  end

  test "ingest_elmc_check is a no-op when session is not running" do
    slug = "sim-elmc-idle-#{System.unique_integer([:positive])}"

    assert {:ok, st} =
             Debugger.ingest_elmc_check(slug, %{
               status: :ok,
               checked_path: ".",
               error_count: 0,
               warning_count: 0
             })

    assert st.running == false
    assert st.events == []
  end

  test "companion elm/http command executes and feeds structured callback message" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])
    previous_http_executor = Application.get_env(:ide, Ide.Debugger.HttpExecutor)

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_debugger_config, :runtime_executor_module, HttpFollowupRuntimeExecutor)
    )

    Application.put_env(:ide, Ide.Debugger.HttpExecutor,
      request_fun: fn _command ->
        {:ok, %{"status" => 200, "body" => "ok"}}
      end
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)

      if is_nil(previous_http_executor) do
        Application.delete_env(:ide, Ide.Debugger.HttpExecutor)
      else
        Application.put_env(:ide, Ide.Debugger.HttpExecutor, previous_http_executor)
      end
    end)

    slug = "sim-companion-http-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source: "module CompanionSnap exposing (..)",
               reason: "companion_http_followup",
               source_root: "phone"
             })

    assert {:ok, stepped} = Debugger.step(slug, %{target: "phone", message: "Tick", count: 1})

    assert get_in(reloaded, [:companion, :shell, "debugger_contract", "module"]) ==
             "CompanionSnap"

    refute get_in(reloaded, [:companion, :model, "debugger_contract"])
    assert String.starts_with?(stepped.companion.last_message, "WeatherReceived ")
    assert get_in(stepped.companion.model, ["runtime_model", "lastResponse"]) == 1

    assert get_in(stepped.companion.model, ["runtime_model", "received"]) == %{
             "ctor" => "WeatherReceived",
             "args" => [%{"ctor" => "Ok", "args" => ["ok"]}]
           }

    assert Enum.any?(stepped.events, fn event ->
             event.type == "debugger.package_cmd" and
               event.payload.target == "phone" and
               event.payload.package == "elm/http" and
               String.starts_with?(event.payload.response_message, "WeatherReceived ")
           end)
  end

  test "init runtime followups are applied and shown in debugger timeline" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(
        previous_debugger_config,
        :runtime_executor_module,
        InitRandomFollowupRuntimeExecutor
      )
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-init-random-followup-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: "module Main exposing (..)",
               reason: "init_random_followup",
               source_root: "watch"
             })

    assert get_in(reloaded.watch.model, ["runtime_model", "seed"]) == 42

    timeline =
      reloaded.debugger_timeline
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert {"watch", "init", "init"} in timeline

    assert Enum.any?(timeline, fn
             {"watch", "RandomGenerated" <> _, "runtime_followup"} -> true
             _ -> false
           end)

    assert Enum.any?(reloaded.events, fn event ->
             event.type == "debugger.package_cmd" and
               event.payload.target == "watch" and
               event.payload.package == "elm/random" and
               String.starts_with?(event.payload.response_message || "", "RandomGenerated")
           end)
  end

  test "runtime storage writes are read again after debugger restart" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(
        previous_debugger_config,
        :runtime_executor_module,
        StorageFollowupRuntimeExecutor
      )
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-storage-followup-#{System.unique_integer([:positive])}"

    source = """
    module Main exposing (..)

    type Msg
        = SaveBest
        | BestLoaded String
    """

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, loaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "storage_followup",
               source_root: "watch"
             })

    assert get_in(loaded.watch.model, ["runtime_model", "best"]) == 0

    assert {:ok, saved} = Debugger.step(slug, %{target: "watch", message: "SaveBest"})
    assert get_in(saved.watch.model, ["runtime_model", "best"]) == 9124
    assert get_in(saved, [:storage, "watch", "2048", "value"]) == "9124"

    assert {:ok, _restarted} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "storage_followup_restart",
               source_root: "watch"
             })

    assert get_in(reloaded.watch.model, ["runtime_model", "best"]) == 9124
  end

  test "runtime executor failure surfaces on debugger timeline without heuristic fallback" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_debugger_config, :runtime_executor_module, FailingExternalRuntimeExecutor)
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-runtime-exec-error-visible-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: """
               module Main exposing (..)

               init _ =
                   ( { n = 0 }, Cmd.none )
               """,
               reason: "runtime_exec_error_visible",
               source_root: "watch"
             })

    assert {:ok, stepped} = Debugger.step(slug, %{target: "watch", message: "Tick", count: 1})

    refute get_in(stepped.watch.model, ["runtime_execution", "execution_backend"]) ==
             "fallback_default"

    assert Enum.any?(stepped.debugger_timeline, fn row ->
             row.type == "runtime_exec_error" and row.target == "watch"
           end) or
             Enum.any?(stepped.events, &(&1.type == "debugger.runtime_exec_error"))
  end

  test "init commands without runtime followups are visible in debugger timeline" do
    previous_debugger_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(
        previous_debugger_config,
        :runtime_executor_module,
        InitNoFollowupRuntimeExecutor
      )
    )

    on_exit(fn ->
      Application.put_env(:ide, Debugger, previous_debugger_config)
    end)

    slug = "sim-init-no-followup-visible-#{System.unique_integer([:positive])}"

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: """
               module Main exposing (..)

               init _ =
                   ( { n = 0 }, Random.generate GotSeed (Random.int 1 10) )
               """,
               reason: "init_no_followup_visible",
               source_root: "watch"
             })

    assert Enum.any?(reloaded.debugger_timeline, fn row ->
             row.target == "watch" and row.message_source == "runtime_status" and
               row.message == "runtime no followups for 1 init cmd(s)"
           end)
  end

  test "protocol rx normalizes temperature union wire tag one into watch model updates" do
    slug = "sim-weather-temp-wire-code-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_temperature_companion"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_temperature_watch"
             })

    assert {:ok, warmed} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "phone_to_watch",
               message: "FromPhone (ProvideTemperature (Celsius 28))",
               message_value: %{
                 "ctor" => "FromPhone",
                 "args" => [
                   %{
                     "ctor" => "ProvideTemperature",
                     "args" => [%{"ctor" => "Celsius", "args" => [28]}]
                   }
                 ]
               }
             })

    assert match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [28]}]},
             get_in(warmed, [:watch, :model, "runtime_model", "temperature"])
           )
  end

  test "protocol rx normalizes clear weather condition wire code one into watch model updates" do
    slug = "sim-weather-clear-wire-code-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_condition_companion"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_condition_watch"
             })

    assert {:ok, cleared} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "phone_to_watch",
               message: "FromPhone (ProvideCondition Clear)",
               message_value: %{
                 "ctor" => "FromPhone",
                 "args" => [%{"ctor" => "ProvideCondition", "args" => [1]}]
               }
             })

    assert match?(
             %{"ctor" => "Just", "args" => [1]},
             get_in(cleared, [:watch, :model, "runtime_model", "condition"])
           )
  end

  test "protocol rx normalizes weather condition enum wire codes into watch model updates" do
    slug = "sim-weather-condition-wire-code-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_condition_companion"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_condition_watch"
             })

    assert {:ok, cloudy} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "phone_to_watch",
               message: "FromPhone (ProvideCondition Cloudy)",
               message_value: %{
                 "ctor" => "FromPhone",
                 "args" => [%{"ctor" => "ProvideCondition", "args" => [2]}]
               }
             })

    assert match?(
             %{"ctor" => "Just", "args" => [2]},
             get_in(cloudy, [:watch, :model, "runtime_model", "condition"])
           )
  end

  test "protocol rx normalizes rain weather condition wire code into watch model updates" do
    slug = "sim-weather-rain-wire-code-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_condition_companion"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_condition_watch"
             })

    assert {:ok, rained} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "phone_to_watch",
               message: "FromPhone (ProvideCondition Rain)",
               message_value: %{
                 "ctor" => "FromPhone",
                 "args" => [%{"ctor" => "ProvideCondition", "args" => [5]}]
               }
             })

    assert match?(
             %{"ctor" => "Just", "args" => [5]},
             get_in(rained, [:watch, :model, "runtime_model", "condition"])
           )
  end

  test "weather animated watchface receives drizzle temperature after companion handles RequestWeather" do
    slug = "sim-weather-bridge-drizzle-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_bridge_companion"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 26, "condition" => "drizzle"}
             })

    assert {:ok, state} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_bridge_watch"
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 500)

    runtime_model =
      state
      |> get_in([:watch, :model])
      |> case do
        %{} = model -> Ide.Debugger.RuntimeArtifacts.preview_runtime_model(model)
        _ -> %{}
      end

    assert match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [26]}]},
             runtime_model["temperature"]
           )

    assert weather_condition_matches?(runtime_model["condition"], 4, "Drizzle")

    view_tree = get_in(state, [:watch, :view_tree]) || %{}

    text_nodes =
      collect_view_text(view_tree) ++
        for(
          row <- get_in(state, [:watch, :model, "runtime_view_output"]) || [],
          row["kind"] == "text",
          is_binary(row["text"]),
          do: row["text"]
        ) ++ List.wrap(weather_preview_label(runtime_model))

    assert Enum.any?(text_nodes, &String.contains?(&1, "26C Drizzle"))
    refute Enum.any?(text_nodes, &String.contains?(&1, "Loading..."))

    timeline = state.debugger_timeline || []

    assert timeline_count(timeline, :phone, "FromWatch") == 1
    assert timeline_count(timeline, :phone, "GotWeather") >= 1
    assert timeline_count(timeline, :watch, "ProvideTemperature") >= 1
    assert timeline_count(timeline, :watch, "ProvideCondition") >= 1

    refute Enum.any?(timeline, fn row ->
             row.message_source == "runtime_status" and
               String.starts_with?(row.message || "", "runtime no followups")
           end)

    refute Enum.any?(timeline, fn row ->
             row.message_source == "runtime_followup" and String.contains?(row.message || "", "Unknown")
           end)
  end

  @tag timeout: 180_000
  test "weather animated companion reload records a single init through protocol drain" do
    slug = "sim-weather-bootstrap-single-init-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug, %{watch_profile_id: "basalt"})

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_single_init_companion"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 26, "condition" => "drizzle"}
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_single_init_watch"
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 500)

    companion_init_count =
      (state.debugger_timeline || [])
      |> Enum.count(fn row -> row.target == "phone" and row.type == "init" end)

    assert companion_init_count == 1
  end

  defp timeline_count(timeline, target, fragment) do
    target_labels = [target, Atom.to_string(target)]

    Enum.count(timeline, fn row ->
      row_target = row.target
      row_target in target_labels and is_binary(row.message) and
        String.contains?(row.message, fragment)
    end)
  end

  test "weather settings with string temperatureC deliver Celsius temperature after RequestWeather roundtrip" do
    slug = "sim-weather-string-temp-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_string_temp_companion"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => "26", "condition" => "fog"}
             })

    assert {:ok, state} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_string_temp_watch"
             })

    runtime_model_before = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    refute match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [26]}]},
             runtime_model_before["temperature"]
           )

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 500)

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [26]}]},
             runtime_model["temperature"]
           )

    assert match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Fog", "args" => []}]},
             runtime_model["condition"]
           )
  end

  test "weather condition updates apply transition animations between conditions" do
    slug = "sim-weather-transitions-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    snow_value = %{
      "ctor" => "FromPhone",
      "args" => [
        %{"ctor" => "ProvideCondition", "args" => [%{"ctor" => "Snow", "args" => []}]}
      ]
    }

    drizzle_value = %{
      "ctor" => "FromPhone",
      "args" => [
        %{"ctor" => "ProvideCondition", "args" => [%{"ctor" => "Drizzle", "args" => []}]}
      ]
    }

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_transitions_companion"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_transitions_watch"
             })

    assert {:ok, state} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 23, "condition" => "fog"}
             })

    assert {:ok, state} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "phone_to_watch",
               message: "FromPhone (ProvideCondition Snow)",
               message_value: snow_value
             })

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert match?(
             %{"ctor" => "Just", "args" => [6]},
             runtime_model["condition"]
           ) or
             match?(
               %{"ctor" => "Just", "args" => [%{"ctor" => "Snow", "args" => []}]},
               runtime_model["condition"]
             )

    assert {:ok, state} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "phone_to_watch",
               message: "FromPhone (ProvideCondition Drizzle)",
               message_value: drizzle_value
             })

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert weather_condition_matches?(runtime_model["condition"], 4, "Drizzle")

    assert weather_condition_matches?(runtime_model["displayedCondition"], 4, "Drizzle")

    newyork_watch_updates =
      (state.events || [])
      |> Enum.count(fn event ->
        event.type == "update" and
          get_in(event, [:payload, :target]) == "watch" and
          get_in(event, [:payload, :message]) == "NewYork"
      end)

    assert newyork_watch_updates == 0
  end

  test "weather simulator settings do not deliver ProvidePosition to watch" do
    slug = "sim-weather-no-position-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_no_position_phone"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_no_position_watch"
             })

    assert {:ok, state} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 21, "condition" => "clear"},
               "latitude" => 48.137154,
               "longitude" => 11.576124,
               "accuracy" => 25.0
             })

    refute Enum.any?(state.debugger_timeline, fn row ->
             row.target == "watch" and row.message_source == "simulator_settings" and
               String.contains?(row.message, "ProvidePosition")
           end)

    refute Enum.any?(state.events, fn event ->
             event.type == "runtime_exec_error" and
               get_in(event, [:payload, :target]) == "watch" and
               String.contains?(to_string(get_in(event, [:payload, :message])), "ProvidePosition")
           end)
  end

  test "weather simulator settings change delivers GotWeather to companion subscription" do
    slug = "sim-weather-settings-change-#{System.unique_integer([:positive])}"
    template_root = Path.join(["priv", "project_templates", "watchface_weather_animated"])

    watch_source = File.read!(Path.join([template_root, "src", "Main.elm"]))
    phone_source = File.read!(Path.join([template_root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug, %{watch_profile_id: "basalt"})

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_settings_change_companion"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 21, "condition" => "clear"}
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_settings_change_watch"
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 500)

    timeline = state.debugger_timeline || []
    assert timeline_count(timeline, :phone, "GotWeather") >= 1

    assert {:ok, _state} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 21, "condition" => "rain"}
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 500)

    timeline = state.debugger_timeline || []

    assert timeline_count(timeline, :phone, "GotWeather") >= 2

    companion_model = get_in(state, [:companion, :model, "runtime_model"]) || %{}

    assert match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Rain", "args" => []}]},
             companion_model["lastCondition"]
           )

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}
    assert weather_condition_matches?(runtime_model["condition"], 4, "Rain")

    assert {:ok, _state} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 21, "condition" => "cloudy"}
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 500)

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}
    assert weather_condition_matches?(runtime_model["condition"], 4, "Cloudy")
    assert runtime_model["nextAnimationId"] > 1
  end
end
