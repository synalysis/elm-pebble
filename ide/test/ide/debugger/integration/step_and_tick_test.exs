defmodule Ide.Debugger.StepAndTickIntegrationTest do
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

  test "step emits deterministic runtime timeline events without heuristic mutation" do
    slug = "sim-step-#{System.unique_integer([:positive])}"

    source = """
    module Main exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as Ui

    type alias Model =
        { n : Int, enabled : Bool }

    type Msg
        = Inc
        | Dec

    init _ =
        ( { n = 1, enabled = false }, Cmd.none )

    update msg model =
        case msg of
            Inc ->
                ( { n = model.n + 1, enabled = model.enabled }, Cmd.none )

            Dec ->
                ( { n = model.n - 1, enabled = model.enabled }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.root []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "step_base"
      })

    assert {:ok, stepped} =
             Debugger.step(slug, %{
               target: "watch",
               message: "inc",
               count: 2
             })

    assert Ide.Debugger.RuntimeArtifacts.versioned_elmx_artifacts?(
             Ide.Debugger.RuntimeArtifacts.execution_model(stepped.watch)
           )

    assert get_in(stepped, [:watch, :model, "runtime_last_message"]) == "Inc"
    assert get_in(stepped, [:watch, :model, "runtime_message_source"]) == "provided"
    assert get_in(stepped, [:watch, :model, "runtime_model_source"]) == "step_message"
    assert get_in(stepped, [:watch, :model, "runtime_model", "n"]) == 3
    assert get_in(stepped, [:watch, :model, "runtime_model", "last_operation"]) == "Inc"

    refute get_in(stepped, [:watch, :model, "runtime_execution", "heuristic_fallback_used"])

    assert get_in(stepped, [:watch, :model, "runtime_model_sha256"]) !=
             get_in(reloaded, [:watch, :model, "runtime_model_sha256"])

    assert get_in(stepped, [:watch, :model, "runtime_view_tree_sha256"]) !=
             get_in(reloaded, [:watch, :model, "runtime_view_tree_sha256"])

    assert get_in(stepped, [:watch, :model, "runtime_execution", "runtime_model_sha256"]) ==
             get_in(stepped, [:watch, :model, "runtime_model_sha256"])

    assert is_integer(
             get_in(stepped, [:watch, :model, "runtime_execution", "runtime_model_entry_count"])
           )

    assert is_integer(
             get_in(stepped, [:watch, :model, "runtime_execution", "view_tree_node_count"])
           )

    assert get_in(stepped, [:watch, :model, "runtime_known_messages"]) == ["Inc", "Dec"]
    assert get_in(stepped, [:watch, :model, "_debugger_steps"]) >= 2

    assert runtime_exec =
             Enum.find(
               stepped.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) == "step")
             )

    assert runtime_exec.payload.runtime_model_source == "step_message"
    assert runtime_exec.payload.view_tree_source == "step_derived_view_tree"
    assert runtime_exec.payload.trigger == "step"
    assert runtime_exec.payload.message == "Inc"
    assert runtime_exec.payload.message_source == "provided"

    refute Enum.any?(stepped.events, &synthetic_step_protocol_event?/1)

    refute Enum.any?(stepped.events, fn event ->
             event.type == "debugger.update_in" and
               (Map.get(event.payload, :target) || Map.get(event.payload, "target")) == "protocol" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "Step:"
               )
           end)

    assert Enum.count(stepped.events, &(&1.type == "debugger.update_in")) >= 1
    assert Enum.count(stepped.events, &(&1.type == "debugger.view_render")) >= 1

    assert {:ok, unfiltered_snapshot} = Debugger.snapshot(slug, types: [])
    assert Enum.any?(unfiltered_snapshot.events, &(&1.type == "debugger.update_in"))
  end

  test "step without explicit message cycles msg constructors deterministically" do
    slug = "sim-step-cycle-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "StepCycle",
        """
        type alias Model = { n : Int }

        type Msg
            = Inc
            | Dec

        init _ =
            ( { n = 1 }, Cmd.none )

        update msg model =
            case msg of
                Inc ->
                    ( { n = model.n + 1 }, Cmd.none )

                Dec ->
                    ( { n = model.n - 1 }, Cmd.none )

        view _ =
            Ui.root []
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/StepCycle.elm",
        source: source,
        reason: "step_cycle_base"
      })

    assert {:ok, stepped} = Debugger.step(slug, %{target: "watch", count: 2})
    assert get_in(stepped, [:watch, :model, "runtime_message_source"]) == "auto_cycle"
    assert get_in(stepped, [:watch, :model, "runtime_last_message"]) == "Dec"
    assert get_in(stepped, [:watch, :model, "runtime_model", "n"]) == 1
  end

  test "companion step does not synthesize watch protocol inbox state" do
    slug = "sim-proto-watch-#{System.unique_integer([:positive])}"

    source = """
    module ProtoStep exposing (..)

    type Msg
        = Ping

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "protocol/ProtoStep.elm",
        source: source,
        reason: "proto_step_base",
        source_root: "protocol"
      })

    assert {:ok, stepped} =
             Debugger.step(slug, %{
               target: "companion",
               message: "Ping",
               count: 1
             })

    refute get_in(stepped, [:watch, :model, "protocol_last_inbound_message"]) == "Step:Ping"

    refute get_in(stepped, [:watch, :model, "runtime_model", "protocol_last_inbound_message"]) ==
             "Step:Ping"

    refute Enum.any?(stepped.events, &synthetic_step_protocol_event?/1)
  end

  test "tick injects subscription-style ingress with deterministic message source" do
    slug = "sim-tick-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "TickSnap",
        """
        import Time

        type alias Model = { n : Int }

        type Msg
            = Tick
            | Inc

        init _ =
            ( { n = 1 }, Cmd.none )

        update msg model =
            case msg of
                Tick ->
                    ( model, Cmd.none )

                Inc ->
                    ( { n = model.n + 1 }, Cmd.none )

        subscriptions _ =
            Time.every 1000 Tick

        view _ =
            Ui.root []
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TickSnap.elm",
        source: source,
        reason: "tick_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 2})
    assert get_in(ticked, [:watch, :model, "runtime_last_message"]) == "Tick"
    assert get_in(ticked, [:watch, :model, "runtime_message_source"]) == "subscription_tick"
    assert get_in(ticked, [:watch, :model, "runtime_model_source"]) == "step_message"

    assert tick_exec =
             Enum.find(
               ticked.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) == "tick")
             )

    assert tick_exec.payload.trigger == "tick"

    assert Enum.count(ticked.events, &(&1.type == "debugger.tick")) >= 1

    refute Enum.any?(ticked.events, &synthetic_step_protocol_event?/1)

    assert Enum.count(ticked.events, &(&1.type == "debugger.update_in")) >= 1
    assert Enum.count(ticked.events, &(&1.type == "debugger.view_render")) >= 1
    assert is_map(get_in(ticked, [:watch, :view_tree]))
    assert is_binary(get_in(ticked, [:watch, :view_tree, "type"]))
    assert is_list(get_in(ticked, [:watch, :model, "runtime_view_output"]))

    assert Enum.any?(get_in(ticked, [:watch, :view_tree, "children"]) || [], fn child ->
             is_map(child) and Map.get(child, "type") == "debuggerRenderStep"
           end)
  end

  test "tick synthesizes realistic current time device response when command requests it" do
    slug = "sim-device-time-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "DeviceTimeSnap",
        """
        import Pebble.Cmd as PebbleCmd

        type alias Model = { hhmm : Int }

        type Msg
            = Tick
            | CurrentTime String

        init _ =
            ( { hhmm = 0 }, Cmd.none )

        update msg model =
            case msg of
                Tick ->
                    ( model, PebbleCmd.getCurrentTimeString CurrentTime )

                CurrentTime _ ->
                    ( model, Cmd.none )

        view _ =
            Ui.root []
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/DeviceTimeSnap.elm",
        source: source,
        reason: "device_time_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})

    assert is_integer(get_in(ticked, [:watch, :model, "runtime_model", "hhmm"]))
    assert get_in(ticked, [:watch, :model, "runtime_model", "hhmm"]) > 0
    assert is_map(get_in(ticked, [:watch, :model, "debugger_device_current_time_string"]))

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.device_data" and
               (Map.get(event.payload, :request) || Map.get(event.payload, "request")) ==
                 "current_time_string"
           end)

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.update_in" and
               String.starts_with?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "CurrentTime"
               )
           end)
  end

  test "step message matrix surfaces strict no-heuristic behavior" do
    slug = "sim-msg-matrix-#{System.unique_integer([:positive])}"

    source = """
    module Main exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as Ui

    type alias Model =
        { count : Int
        , enabled : Bool
        , title : String
        }

    type Msg
        = Tick
        | SetCount Int
        | SetEnabled Bool
        | SetTitle String
        | SetCountIgnored Int

    init _ =
        ( { count = 0, enabled = true, title = "--" }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, Cmd.none )

            SetCount value ->
                ( { model | count = value }, Cmd.none )

            SetEnabled value ->
                ( { model | enabled = value }, Cmd.none )

            SetTitle value ->
                ( { model | title = value }, Cmd.none )

            SetCountIgnored _ ->
                ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.root []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "message_matrix_base"
      })

    assert {:ok, after_title} =
             Debugger.step(slug, %{target: "watch", message: "SetTitle \"HELLO\"", count: 1})

    assert get_in(after_title, [:watch, :model, "runtime_last_message"]) =~ "SetTitle"
    enabled_baseline = get_in(after_title, [:watch, :model, "runtime_model", "enabled"])
    title_baseline = get_in(after_title, [:watch, :model, "runtime_model", "title"])
    count_baseline = get_in(after_title, [:watch, :model, "runtime_model", "count"]) || 0

    refute get_in(after_title, [:watch, :model, "runtime_execution", "heuristic_fallback_used"])

    assert {:ok, after_count} =
             Debugger.step(slug, %{target: "watch", message: "SetCount 42", count: 1})

    assert {:ok, _after_count} =
             Debugger.step(slug, %{target: "watch", message: "SetCount 42", count: 1})

    assert {:ok, _after_bool} =
             Debugger.step(slug, %{target: "watch", message: "SetEnabled false", count: 1})

    assert {:ok, after_wildcard} =
             Debugger.step(slug, %{target: "watch", message: "SetCountIgnored 99", count: 1})

    refute get_in(after_wildcard, [:watch, :model, "runtime_execution", "heuristic_fallback_used"])

    assert {:ok, after_unmapped} =
             Debugger.step(slug, %{target: "watch", message: "Ping 7", count: 1})

    assert get_in(after_unmapped, [:watch, :model, "runtime_execution", "operation_source"]) ==
             "unmapped_message"

    _ = {title_baseline, enabled_baseline, count_baseline}
  end

  test "strict full-stack flow keeps protocol/device/replay deterministic without hidden mutation" do
    slug = "sim-strict-fullstack-#{System.unique_integer([:positive])}"

    source = """
    module Main exposing (..)

    import Json.Decode as Decode
    import Pebble.Cmd as PebbleCmd
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as Ui

    type alias Model =
        { count : Int
        , timeString : String
        }

    type Msg
        = Tick
        | SetCount Int
        | CurrentTimeString String

    init _ =
        ( { count = 1, timeString = "--:--" }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, PebbleCmd.getCurrentTimeString CurrentTimeString )

            SetCount value ->
                ( { model | count = value }, Cmd.none )

            CurrentTimeString value ->
                ( { model | timeString = value }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.root []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "strict_fullstack_base"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    preview = get_in(ticked, [:watch, :model, "debugger_device_current_time_string"]) || %{}

    assert is_binary(get_in(ticked, [:watch, :model, "runtime_model", "timeString"]))
    assert get_in(ticked, [:watch, :model, "runtime_model", "timeString"]) == preview["string"]
    assert is_map(preview)

    assert get_in(ticked, [:watch, :model, "runtime_execution", "runtime_model_source"]) ==
             "step_message"

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.device_data" and
               (Map.get(event.payload, :request) || Map.get(event.payload, "request")) ==
                 "current_time_string"
           end)

    refute Enum.any?(ticked.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               (Map.get(event.payload, :trigger) || Map.get(event.payload, "trigger")) == "tick"
           end)

    assert {:ok, stepped} =
             Debugger.step(slug, %{target: "watch", message: "SetCount 9", count: 1})

    stepped_count = get_in(stepped, [:watch, :model, "runtime_model", "count"])

    assert get_in(stepped, [:watch, :model, "runtime_last_message"]) =~ "SetCount"

    refute get_in(stepped, [:watch, :model, "runtime_execution", "heuristic_fallback_used"])

    seq_before_replay = stepped.seq
    assert {:ok, _} = Debugger.step(slug, %{target: "watch", message: "SetCount 11", count: 1})

    assert {:ok, replayed} =
             Debugger.replay_recent(slug, %{
               target: "watch",
               count: 1,
               cursor_seq: seq_before_replay
             })

    assert get_in(replayed, [:watch, :model, "runtime_model", "count"]) == stepped_count

    assert Enum.any?(replayed.events, fn event ->
             event.type == "debugger.runtime_exec" and
               (Map.get(event.payload, :trigger) || Map.get(event.payload, "trigger")) == "replay"
           end)
  end

  test "tick synthesizes structured current date/time device response with UTC offset" do
    slug = "sim-device-datetime-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "DeviceDateTimeSnap",
        """
        import Pebble.Cmd as PebbleCmd
        import Time

        type alias Model =
            { year : Int
            , month : Int
            , day : Int
            , dayOfWeek : Time.Weekday
            , hour : Int
            , minute : Int
            , second : Int
            , utcOffsetMinutes : Int
            }

        type Msg
            = Tick
            | CurrentDateTime PebbleCmd.CurrentDateTime

        init _ =
            ( { year = 0
              , month = 0
              , day = 0
              , dayOfWeek = Time.Mon
              , hour = 0
              , minute = 0
              , second = 0
              , utcOffsetMinutes = 0
              }
            , Cmd.none
            )

        update msg model =
            case msg of
                Tick ->
                    ( model, PebbleCmd.getCurrentDateTime CurrentDateTime )

                CurrentDateTime value ->
                    ( { model
                        | year = value.year
                        , month = value.month
                        , day = value.day
                        , dayOfWeek = value.dayOfWeek
                        , hour = value.hour
                        , minute = value.minute
                        , second = value.second
                        , utcOffsetMinutes = value.utcOffsetMinutes
                      }
                    , Cmd.none
                    )

        view _ =
            Ui.root []
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/DeviceDateTimeSnap.elm",
        source: source,
        reason: "device_datetime_base"
      })

    {:ok, _} =
      Debugger.set_simulator_settings(slug, %{
        "use_simulated_time" => true,
        "simulated_date" => "2026-05-19",
        "simulated_time" => "07:08:09",
        "timezone_offset_min" => 120
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})

    runtime_model = get_in(ticked, [:watch, :model, "runtime_model"]) || %{}
    device_preview = get_in(ticked, [:watch, :model, "debugger_device_current_date_time"]) || %{}

    assert runtime_model["year"] == 2026
    assert runtime_model["month"] == 5
    assert runtime_model["day"] == 19
    assert runtime_model["hour"] == 7
    assert runtime_model["minute"] == 8
    assert runtime_model["second"] == 9
    assert runtime_model["utcOffsetMinutes"] == 120
    assert is_map(runtime_model["dayOfWeek"])
    assert runtime_model["dayOfWeek"]["ctor"] == "Tuesday"
    assert is_map(device_preview)
    assert device_preview["utcOffsetMinutes"] == runtime_model["utcOffsetMinutes"]
    assert device_preview["dayOfWeek"] == runtime_model["dayOfWeek"]["ctor"]

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.device_data" and
               (Map.get(event.payload, :request) || Map.get(event.payload, "request")) ==
                 "current_date_time"
           end)

    assert Enum.any?(ticked.events, fn event ->
             event.type == "debugger.update_in" and
               String.contains?(
                 Map.get(event.payload, :message) || Map.get(event.payload, "message") || "",
                 "CurrentDateTime"
               )
           end)
  end

  test "tick resolves minute-change subscription trigger message" do
    slug = "sim-minute-change-#{System.unique_integer([:positive])}"

    source = """
    module MinuteChangeSnap exposing (..)

    import Pebble.Events as PebbleEvents

    type Msg
        = MinuteChanged Int
        | Tick

    init _ =
        ( { count = 0 }, Cmd.none )

    update msg model =
        case msg of
            MinuteChanged minute ->
                ( { model | count = minute }, Cmd.none )

            Tick ->
                ( model, Cmd.none )

    subscriptions _ =
        PebbleEvents.onMinuteChange MinuteChanged
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/MinuteChangeSnap.elm",
        source: source,
        reason: "minute_change_sub"
      })

    {:ok, _} =
      Debugger.set_simulator_settings(slug, %{
        "use_simulated_time" => true,
        "simulated_time" => "07:34"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    message = get_in(ticked, [:watch, :model, "runtime_last_message"]) || ""
    assert message == "MinuteChanged 34"
  end

  test "tick prefers minute subscription payload over hour when both are present" do
    slug = "sim-minute-over-hour-#{System.unique_integer([:positive])}"

    source = """
    module MinuteOverHour exposing (..)

    import Pebble.Events as PebbleEvents
    import Pebble.Platform as PebblePlatform
    import Json.Decode as Decode

    type alias Model =
      { value : Int }

    type Msg
      = HourChanged Int
      | MinuteChanged Int

    init _ =
      ( { value = 0 }, Cmd.none )

    update msg model =
      case msg of
        HourChanged h ->
          ( { model | value = h }, Cmd.none )

        MinuteChanged m ->
          ( { model | value = m }, Cmd.none )

    subscriptions _ =
      PebbleEvents.batch
        [ PebbleEvents.onHourChange HourChanged
        , PebbleEvents.onMinuteChange MinuteChanged
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
        rel_path: "watch/MinuteOverHour.elm",
        source: source,
        reason: "minute_over_hour"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    message = get_in(ticked, [:watch, :model, "runtime_last_message"]) || ""
    assert String.starts_with?(message, "MinuteChanged ")
  end

  test "tangram minute change applies structured current date time follow-up" do
    slug = "sim-tangram-minute-datetime-#{System.unique_integer([:positive])}"

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "src/Main.elm",
        source: watch_source,
        reason: "tangram_minute_datetime",
        source_root: "watch"
      })

    assert {:ok, configured} =
             Debugger.set_simulator_settings(slug, %{
               "use_simulated_time" => true,
               "simulated_date" => "2026-05-27",
               "simulated_time" => "23:42:00",
               "timezone_offset_min" => 120
             })

    baseline_seq = configured.seq

    assert {:ok, triggered} =
             Debugger.step(slug, %{
               target: "watch",
               message: "MinuteChanged 42",
               count: 1
             })

    new_rows =
      triggered.debugger_timeline
      |> Enum.filter(&(&1.raw_seq > baseline_seq))
      |> Enum.sort_by(& &1.seq, :asc)

    assert Enum.any?(new_rows, fn row ->
             row.type == "update" and row.target == "watch" and
               (String.starts_with?(row.message, "MinuteChanged 42") or
                  row.message == "MinuteChanged" or
                  String.starts_with?(row.message, "MinuteChanged "))
           end)

    assert Enum.any?(new_rows, fn row ->
             row.type == "update" and row.target == "watch" and
               String.starts_with?(row.message, "CurrentDateTime ") and
               String.contains?(row.message, "\"minute\":42")
           end)

    minute_seq =
      new_rows
      |> Enum.find_value(fn row ->
        if row.type == "update" and String.starts_with?(row.message, "MinuteChanged "),
          do: row.seq
      end)

    datetime_seq =
      new_rows
      |> Enum.find_value(fn row ->
        if row.type == "update" and String.starts_with?(row.message, "CurrentDateTime "),
          do: row.seq
      end)

    assert is_integer(minute_seq)
    assert is_integer(datetime_seq)
    assert minute_seq < datetime_seq

    now =
      get_in(triggered, [:watch, :model, "now", "args", Access.at(0)]) ||
        get_in(triggered, [:watch, :model, "runtime_model", "now", "args", Access.at(0)])

    if is_map(now) do
      assert now["minute"] == 42
      assert now["hour"] == 23
    end
  end

  test "watch demo health template returns simulated step counts in debugger" do
    slug = "sim-watch-demo-health-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watch_demo_health", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "health_steps" => 5123,
               "health_steps_today" => 9876
             })

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "watch_demo_health",
               source_root: "watch"
             })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    if get_in(runtime_model, ["supported", "ctor"]) == "Just" do
      assert get_in(runtime_model, ["supported", "args", Access.at(0)]) == true
      assert get_in(runtime_model, ["stepsNow", "ctor"]) == "Just"
      assert get_in(runtime_model, ["stepsNow", "args", Access.at(0)]) == 5123
      assert get_in(runtime_model, ["stepsToday", "ctor"]) == "Just"
      assert get_in(runtime_model, ["stepsToday", "args", Access.at(0)]) == 9876
    end

    assert Enum.any?(reloaded.debugger_timeline, fn row ->
             row.target == "watch" and
               (row.message == "GotSupported" or String.starts_with?(row.message, "GotSupported "))
           end)

    assert {:ok, compiled} =
             compile_health_template_preview(slug, source, reloaded.revision)

    view_output = get_in(compiled, [:watch, :model, "runtime_view_output"]) || []
    texts = for row <- view_output, row["kind"] == "text", do: row["text"]

    assert "Health demo" in texts
    assert Enum.any?(texts, &String.starts_with?(&1, "Now: "))
    assert Enum.any?(texts, &String.starts_with?(&1, "Today: "))
  end

  test "inject_trigger prefers non-tick message for button triggers when available" do
    slug = "sim-trigger-prefer-button-#{System.unique_integer([:positive])}"

    source = """
    module Main exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as Ui

    type alias Model =
        { n : Int }

    type Msg
        = Tick
        | ButtonPressed

    init _ =
        ( { n = 0 }, Cmd.none )

    update msg model =
        case msg of
            Tick ->
                ( model, Cmd.none )

            ButtonPressed ->
                ( { n = model.n + 1 }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.root []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "trigger_prefer_button_base"
      })

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "button_up"
             })

    assert get_in(triggered, [:watch, :model, "runtime_last_message"]) == "ButtonPressed"
  end

  test "start_auto_tick and stop_auto_tick drive periodic ingress events" do
    slug = "sim-auto-tick-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, started} =
             Debugger.start_auto_tick(slug, %{
               target: "watch",
               interval_ms: 120,
               count: 1
             })

    assert started.auto_tick.enabled == true
    assert started.auto_tick.interval_ms == 120
    assert started.auto_tick.target == "watch"

    Process.sleep(280)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)
    assert stopped.auto_tick.enabled == false

    assert Enum.any?(stopped.events, &(&1.type == "debugger.tick_auto"))
    assert Enum.any?(stopped.events, &(&1.type == "debugger.tick"))
  end

  test "set_auto_fire toggles natural watch and companion ingress targets" do
    slug = "sim-auto-fire-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, watch_on} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               enabled: "true"
             })

    assert watch_on.auto_tick.enabled == true
    assert watch_on.auto_tick.targets == ["watch"]

    assert {:ok, both_on} =
             Debugger.set_auto_fire(slug, %{
               target: "protocol",
               enabled: "true"
             })

    assert both_on.auto_tick.enabled == true
    assert both_on.auto_tick.targets == ["watch", "phone"]

    assert {:ok, companion_only} =
             Debugger.set_auto_fire(slug, %{
               target: "watch"
             })

    assert companion_only.auto_tick.enabled == true
    assert companion_only.auto_tick.targets == ["phone"]

    assert {:ok, all_off} =
             Debugger.set_auto_fire(slug, %{
               target: "protocol"
             })

    assert all_off.auto_tick.enabled == false
    assert all_off.auto_tick.targets == []

    assert Enum.any?(all_off.events, fn event ->
             event.type == "debugger.tick_auto" and
               (Map.get(event.payload, :action) || Map.get(event.payload, "action")) ==
                 "set_auto_fire"
           end)
  end

  test "set_auto_fire can enable one subscription trigger without firing siblings" do
    slug = "sim-auto-fire-single-subscription-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "AutoFireSingleSubscription",
        """
        import Pebble.Events as Evts

        type alias Model = {}

        type Msg
            = Tick
            | MinuteChanged Int

        init _ =
            ( {}, Cmd.none )

        update _ model =
            ( model, Cmd.none )

        subscriptions _ =
            Evts.batch [ Evts.onSecondChange Tick, Evts.onMinuteChange MinuteChanged ]
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/AutoFireSingleSubscription.elm",
        source: source,
        reason: "auto_fire_single_subscription"
      })

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               trigger: "on_second_change",
               enabled: "true"
             })

    assert enabled.auto_tick.enabled == true
    assert enabled.auto_tick.targets == ["watch"]

    assert enabled.auto_tick.subscriptions == [
             %{"target" => "watch", "trigger" => "on_second_change"}
           ]

    enabled_seq = enabled.seq
    Process.sleep(2_100)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    assert Enum.any?(stopped.events, fn event ->
             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)

    refute Enum.any?(stopped.events, fn event ->
             message = Map.get(event.payload, :message) || Map.get(event.payload, "message") || ""

             event.seq > enabled_seq and event.type == "debugger.update_in" and
               String.starts_with?(message, "MinuteChanged ")
           end)
  end

  test "set_auto_fire does not synthesize Tick when target has no parsed subscriptions" do
    slug = "sim-auto-fire-no-subscriptions-#{System.unique_integer([:positive])}"

    source = """
    module AutoFireSubNone exposing (..)

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
        rel_path: "watch/AutoFireSubNone.elm",
        source: source,
        reason: "auto_fire_sub_none"
      })

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               enabled: "true"
             })

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    refute Enum.any?(stopped.events, fn event ->
             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (Map.get(event.payload, :message) || Map.get(event.payload, "message")) == "Tick"
           end)
  end

  test "set_auto_fire does not fire minute or hour change subscriptions immediately" do
    wait_until_stable_minute()

    slug = "sim-auto-fire-clock-change-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_analog", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "auto_fire_clock_change",
        source_root: "watch"
      })

    assert {:ok, enabled} =
             Debugger.set_auto_fire(slug, %{
               target: "watch",
               enabled: "true"
             })

    enabled_seq = enabled.seq
    Process.sleep(1_150)

    assert {:ok, stopped} = Debugger.stop_auto_tick(slug)

    refute Enum.any?(stopped.events, fn event ->
             message = Map.get(event.payload, :message) || Map.get(event.payload, "message") || ""

             event.seq > enabled_seq and event.type == "debugger.update_in" and
               (String.starts_with?(message, "MinuteChanged ") or
                  String.starts_with?(message, "HourChanged "))
           end)
  end

  test "replay_recent reapplies recent update messages oldest-to-newest" do
    slug = "sim-replay-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "ReplaySnap",
        """
        type alias Model = { n : Int }

        type Msg
            = Inc
            | Dec

        init _ =
            ( { n = 1 }, Cmd.none )

        update msg model =
            case msg of
                Inc ->
                    ( { n = model.n + 1 }, Cmd.none )

                Dec ->
                    ( { n = model.n - 1 }, Cmd.none )

        view _ =
            Ui.root []
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/ReplaySnap.elm",
        source: source,
        reason: "replay_base"
      })

    {:ok, after_inc} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})
    assert get_in(after_inc, [:watch, :model, "runtime_model", "n"]) == 2

    {:ok, stepped0} = Debugger.step(slug, %{target: "watch", message: "Dec", count: 1})
    assert get_in(stepped0, [:watch, :model, "runtime_model", "n"]) == 1
    seq_before_latest_step = stepped0.seq

    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})

    assert {:ok, replayed} =
             Debugger.replay_recent(slug, %{
               target: "watch",
               count: 1,
               cursor_seq: seq_before_latest_step
             })

    assert get_in(replayed, [:watch, :model, "runtime_model", "n"]) == 1
    assert get_in(replayed, [:watch, :model, "runtime_last_message"]) == "Dec"

    assert replay_exec =
             Enum.find(
               replayed.events,
               &(&1.type == "debugger.runtime_exec" and
                   (Map.get(&1.payload, :trigger) || Map.get(&1.payload, "trigger")) == "replay")
             )

    assert replay_exec.payload.trigger == "replay"

    refute Enum.any?(replayed.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               (Map.get(event.payload, :trigger) || Map.get(event.payload, "trigger")) == "replay"
           end)

    replay_event = Enum.find(replayed.events, &(&1.type == "debugger.replay"))
    assert is_map(replay_event)
    assert Map.get(replay_event.payload, :target) == "watch"
    assert Map.get(replay_event.payload, :replayed_count) == 1
    assert Map.get(replay_event.payload, :cursor_seq) == seq_before_latest_step
    assert Map.get(replay_event.payload, :replay_target_counts) == %{"watch" => 1}
    assert Map.get(replay_event.payload, :replay_message_counts) == %{"Dec" => 1}

    assert_replay_telemetry(replay_event.payload, %{
      mode: "unknown",
      source: "recent_query",
      drift_seq: 0,
      drift_band: "none",
      used_live_query: true,
      used_frozen_preview: false
    })

    assert [%{seq: preview_seq, target: "watch", message: "Dec"}] =
             Map.get(replay_event.payload, :replay_preview)

    assert is_integer(preview_seq)
    assert preview_seq <= seq_before_latest_step
  end

  test "replay_recent can apply exact frozen preview rows" do
    slug = "sim-replay-frozen-#{System.unique_integer([:positive])}"

    source =
      watchface_module(
        "ReplayFrozen",
        """
        type alias Model = { n : Int }

        type Msg
            = Inc
            | Dec

        init _ =
            ( { n = 1 }, Cmd.none )

        update msg model =
            case msg of
                Inc ->
                    ( { n = model.n + 1 }, Cmd.none )

                Dec ->
                    ( { n = model.n - 1 }, Cmd.none )

        view _ =
            Ui.root []
        """
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/ReplayFrozen.elm",
        source: source,
        reason: "replay_frozen_base"
      })

    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})
    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Dec", count: 1})
    {:ok, _} = Debugger.step(slug, %{target: "watch", message: "Inc", count: 1})

    assert {:ok, replayed} =
             Debugger.replay_recent(slug, %{
               count: 50,
               replay_rows: [%{seq: 123, target: "watch", message: "Dec"}]
             })

    assert get_in(replayed, [:watch, :model, "runtime_model", "n"]) == 1
    replay_event = Enum.find(replayed.events, &(&1.type == "debugger.replay"))
    assert replay_event.payload.replay_source == "frozen_preview"

    assert_replay_telemetry(replay_event.payload, %{
      mode: "unknown",
      source: "frozen_preview",
      drift_seq: 0,
      drift_band: "none",
      used_live_query: false,
      used_frozen_preview: true
    })

    assert replay_event.payload.requested_count == 1
    assert replay_event.payload.replayed_count == 1
    assert replay_event.payload.replay_message_counts == %{"Dec" => 1}
  end

  test "weather bridge delivers simulator settings without stepping companion GotWeather" do
    slug = "sim-weather-bridge-direct-#{System.unique_integer([:positive])}"
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
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_bridge_watch"
             })

    assert {:ok, state} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 26, "condition" => "drizzle"}
             })

    assert {:ok, state} = Debugger.tick(slug)

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert match?(
             %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [26]}]},
             runtime_model["temperature"]
           )

    assert weather_condition_matches?(runtime_model["condition"], 4, "Drizzle")

    companion_got_weather_updates =
      (state.events || [])
      |> Enum.count(fn event ->
        event.type == "update" and
          get_in(event, [:payload, :target]) == "companion" and
          String.starts_with?(get_in(event, [:payload, :message]) || "", "GotWeather")
      end)

    assert companion_got_weather_updates == 0
  end
end
