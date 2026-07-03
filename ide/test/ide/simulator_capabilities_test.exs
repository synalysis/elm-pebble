defmodule Ide.SimulatorCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Ide.SimulatorCapabilities
  alias Ide.SimulatorCapabilities.Detect
  alias Ide.SimulatorSettings

  @phone_status_watch """
  module Main exposing (main)

  import Pebble.Events as Events
  import Pebble.Companion.Battery as Battery

  subscriptions _ =
      Events.batch
          [ Events.onMinuteChange MinuteChanged
          , Battery.onBattery part
          ]
  """

  @phone_status_phone """
  module CompanionApp exposing (main)

  import Pebble.Companion.Battery as Battery
  import Pebble.Companion.Locale as Locale
  import Pebble.Companion.Connectivity as Connectivity
  import Pebble.Companion.Notifications as Notifications
  import Pebble.Companion.Geolocation as Geolocation

  subscriptions _ =
      Sub.batch
          [ Battery.onBattery GotBattery
          , Locale.onLocale GotLocale
          , Connectivity.onConnectivity GotConnectivity
          , Notifications.onNotificationStatus GotNotifications
          , Geolocation.onCurrentPosition GotPosition
          ]
  """

  test "detects watch and companion simulator capabilities from Elm source" do
    {:ok, watch} = Ide.Debugger.CompileContract.analyze_source(@phone_status_watch, "Main.elm")

    {:ok, phone} =
      Ide.Debugger.CompileContract.analyze_source(@phone_status_phone, "CompanionApp.elm")

    watch_caps = Detect.watch_caps(Map.fetch!(watch, "debugger_contract"))
    phone_caps = Detect.phone_caps(Map.fetch!(phone, "debugger_contract"))

    assert MapSet.member?(watch_caps, "watch_time")
    assert MapSet.member?(phone_caps, "battery")
    assert MapSet.member?(phone_caps, "locale")
    assert MapSet.member?(phone_caps, "network")
    assert MapSet.member?(phone_caps, "notifications")
    assert MapSet.member?(phone_caps, "geolocation")
  end

  @tier1_watch """
  module Main exposing (main)

  import Pebble.Accel as Accel
  import Pebble.AppFocus as AppFocus
  import Pebble.Compass as Compass
  import Pebble.DataLog as DataLog
  import Pebble.Dictation as Dictation
  import Pebble.Vibes as Vibes

  subscriptions _ =
      Sub.batch
          [ Accel.onData Accel.defaultConfig AccelSample
          , AppFocus.onChange FocusChanged
          , Compass.onChange CompassChanged
          , Dictation.onStatus DictationStatus
          , Dictation.onResult DictationResult
          ]
  """

  test "detects tier 1 watch simulator capabilities from imports" do
    {:ok, watch} = Ide.Debugger.CompileContract.analyze_source(@tier1_watch, "Main.elm")
    caps = Detect.watch_caps(Map.fetch!(watch, "debugger_contract"))

    assert MapSet.member?(caps, "watch_accel")
    assert MapSet.member?(caps, "watch_compass")
    assert MapSet.member?(caps, "watch_app_focus")
    assert MapSet.member?(caps, "watch_dictation")
    assert MapSet.member?(caps, "watch_data_log")
    assert MapSet.member?(caps, "watch_vibes")
  end

  test "detects unobstructed area capability from UnobstructedArea subscriptions" do
    source = """
    module Main exposing (main)

    import Pebble.UnobstructedArea as UnobstructedArea

    subscriptions _ =
        Sub.batch
            [ UnobstructedArea.onWillChange WillChange
            , UnobstructedArea.onChanging Changing
            , UnobstructedArea.onDidChange DidChange
            ]
    """

    {:ok, watch} = Ide.Debugger.CompileContract.analyze_source(source, "Main.elm")
    caps = Detect.watch_caps(Map.fetch!(watch, "debugger_contract"))

    assert MapSet.member?(caps, "watch_unobstructed_area")
  end

  test "normalizes tier 1 simulator settings defaults" do
    defaults = Ide.Debugger.default_simulator_settings()

    assert defaults["compass_heading_deg"] == 0
    assert defaults["compass_valid"] == true
    assert defaults["app_in_focus"] == true
    assert defaults["dictation_transcript"] == ""
    assert defaults["dictation_error"] == ""
    assert defaults["vibe_pattern_ms"] == []
  end

  test "active groups hide unrelated companion settings for minimal watchface" do
    {:ok, watch} =
      Ide.Debugger.CompileContract.analyze_source(
        """
        module Main exposing (main)

        import Pebble.Events as Events

        subscriptions _ =
            Events.onMinuteChange MinuteChanged
        """,
        "Main.elm"
      )

    introspect = Map.fetch!(watch, "debugger_contract")
    caps = Detect.watch_caps(introspect)

    groups =
      SimulatorSettings.active_groups(
        nil,
        %{watch: %{model: %{"debugger_contract" => introspect}}},
        :debugger
      )

    titles = Enum.map(groups, fn {_id, title, _fields} -> title end)

    assert "Watch time" in titles
    refute "Notifications" in titles
    refute "Geolocation" in titles
    assert MapSet.member?(caps, "watch_time")
    refute MapSet.member?(caps, "notifications")
  end

  test "emulator mode adds timeline peek capability" do
    caps = SimulatorSettings.capabilities_for(nil, nil, :emulator)
    assert MapSet.member?(caps, "emulator_timeline_peek")
  end

  test "does not treat companion Http usage as weather simulator capability" do
    {:ok, phone} =
      Ide.Debugger.CompileContract.analyze_source(
        """
        module CompanionApp exposing (main)

        import Http
        import Json.Decode as Decode
        import Platform

        type Msg
            = CatalogReceived (Result Http.Error String)

        fetch _ =
            Http.get
                { url = "https://example.test/catalog"
                , expect = Http.expectString CatalogReceived
                }
        """,
        "CompanionApp.elm"
      )

    caps = Detect.companion_caps(Map.fetch!(phone, "debugger_contract"))
    refute MapSet.member?(caps, "weather")
  end

  test "detects weather capability from Pebble.Companion.Weather" do
    {:ok, phone} =
      Ide.Debugger.CompileContract.analyze_source(
        """
        module CompanionApp exposing (main)

        import Pebble.Companion.Weather as Weather

        subscriptions _ =
            Sub.batch
                [ Weather.onCurrent GotWeather
                , Weather.current GotWeather
                ]
        """,
        "CompanionApp.elm"
      )

    caps = Detect.companion_caps(Map.fetch!(phone, "debugger_contract"))
    assert MapSet.member?(caps, "weather")
  end

  test "infer returns empty set for missing project" do
    assert SimulatorCapabilities.infer(nil, nil) == MapSet.new()
  end

  test "detects accel tap capability from Pebble.Accel.onTap subscription" do
    {:ok, watch} =
      Ide.Debugger.CompileContract.analyze_source(
        """
        module Main exposing (main)

        import Pebble.Accel as Accel

        type Msg
            = AccelTap

        subscriptions _ =
            Accel.onTap AccelTap
        """,
        "Main.elm"
      )

    caps = Detect.watch_caps(Map.fetch!(watch, "debugger_contract"))
    assert MapSet.member?(caps, "watch_accel_tap")
  end

  test "tangram watchface hides accel tap control" do
    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "src", "Main.elm"])
      )

    {:ok, watch} = Ide.Debugger.CompileContract.analyze_source(source, "Main.elm")

    refute MapSet.member?(
             Detect.watch_caps(Map.fetch!(watch, "debugger_contract")),
             "watch_accel_tap"
           )
  end

  test "tangram companion hides weather simulator settings" do
    source =
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

    {:ok, phone} = Ide.Debugger.CompileContract.analyze_source(source, "CompanionApp.elm")
    introspect = Map.fetch!(phone, "debugger_contract")

    refute MapSet.member?(Detect.companion_caps(introspect), "weather")

    debugger_state = %{
      companion: %{
        model: %{"debugger_contract" => introspect},
        shell: %{"debugger_contract" => introspect}
      }
    }

    groups = SimulatorSettings.active_groups(nil, debugger_state, :debugger)
    titles = Enum.map(groups, fn {_id, title, _fields} -> title end)

    refute "Weather" in titles
  end

  test "emulator page exposes simulator capabilities for weather gating" do
    source = File.read!("lib/ide_web/live/workspace_live/emulator_page.ex")

    embedded_js =
      case File.read("assets/js/emulator/embedded_emulator.js") do
        {:ok, contents} -> contents
        {:error, _} -> File.read!("assets/js/emulator/embedded_emulator.ts")
      end

    vnc_js = File.read!("assets/js/emulator/emulator_vnc.ts")
    delivery_js = File.read!("assets/js/emulator/emulator_simulator_delivery.ts")

    assert source =~ "data-emulator-simulator-capabilities"
    assert source =~ "data-emulator-copy-feedback"
    assert source =~ ":if={@debug_mode}"
    assert source =~ "emulator_feedback_installation_json"
    assert source =~ "emulator_simulator_capabilities_json"
    assert embedded_js =~ "copyFeedbackReport"
    assert embedded_js =~ "downloadFeedbackReport"
    assert embedded_js =~ "writeClipboardText"
    assert embedded_js =~ "simulatorWeatherEnabled()"
    assert delivery_js =~ "emulatorSimulatorCapabilities"
    assert embedded_js =~ "readVncFramebufferSize"
    assert vnc_js =~ "clipViewport"
    assert embedded_js =~ "expectedScreenSize"
    assert embedded_js =~ "sessionTargetMismatch"
    assert embedded_js =~ "reconcileSessionWithSelectedTarget"
    assert embedded_js =~ "stopSessionForTargetChange"
    assert embedded_js =~ "acceptAppRunStateStart"
    assert embedded_js =~ "payload.length < 17"
    assert embedded_js =~ "frameUuid !== appUuid.toLowerCase()"
    assert embedded_js =~ "APP_RUN_STATE_START_DEBOUNCE_MS"
    assert delivery_js =~ "shouldPushWeatherDirectlyToWatch"
    assert delivery_js =~ "has_phone_companion !== true"
  end
end
