defmodule Ide.CompanionPebbleApisTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger

  @root Path.expand("../../..", __DIR__)
  @bridge_schema Path.join(@root, "shared/companion-protocol/phone_bridge_v1.json")
  @core_elm_json Path.join(@root, "packages/elm-pebble-companion-core/elm.json")
  @core_src Path.join(@root, "packages/elm-pebble-companion-core/src/Pebble/Companion")
  @docs_json Path.join(
               @root,
               "elm_pebble_dev/public/package-docs/packages/elm-pebble/companion-core/0.1.0/docs.json"
             )

  test "phone bridge schema declares companion Pebble API operations" do
    schema = @bridge_schema |> File.read!() |> Jason.decode!()

    apis =
      schema
      |> Map.fetch!("apis")
      |> Map.new(&{Map.fetch!(&1, "name"), Map.fetch!(&1, "ops")})

    assert apis["battery"] == ["status", "subscribe"]
    assert apis["locale"] == ["status", "subscribe"]
    assert apis["calendar"] == ["nextEvent", "upcoming", "subscribe"]
    assert apis["weather"] == ["current", "forecast", "subscribe"]
    assert apis["network"] == ["status", "subscribe"]
    assert apis["notifications"] == ["status", "subscribe"]
    assert apis["preferences"] == ["get", "set", "subscribe"]
    assert apis["environment"] == ["current", "subscribe"]
    assert apis["storage"] == ["set", "get", "remove", "clear"]
  end

  test "companion-core exposes developer-facing Pebble.Companion modules" do
    exposed =
      @core_elm_json
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("exposed-modules")

    for module <-
          ~w(Battery Calendar Connectivity Environment Geolocation Locale Notifications PreferenceStore Storage Weather Phone Platform) do
      assert "Pebble.Companion.#{module}" in exposed
      assert File.exists?(Path.join(@core_src, "#{module}.elm"))
    end

    refute "Pebble.Companion" in exposed
    refute File.exists?(Path.join(@root, "packages/elm-pebble-companion-core/src/Pebble/Companion.elm"))

    lifecycle = File.read!(Path.join(@core_src, "Lifecycle.elm"))
    assert String.contains?(lifecycle, "onLifecycle : (Event -> msg) -> Sub msg")
    refute String.contains?(lifecycle, "decode : BridgeEvent")

    configuration = File.read!(Path.join(@core_src, "Configuration.elm"))
    assert String.contains?(configuration, "open : String -> Cmd msg")
    assert String.contains?(configuration, "onClosed : (Maybe String -> msg) -> Sub msg")

    platform = File.read!(Path.join(@core_src, "Platform.elm"))
    assert String.contains?(platform, "subscribe : Handler msg -> Sub msg")
    assert String.contains?(platform, "setup : Interest -> Cmd msg")
    assert String.contains?(platform, "@docs Interest, Handler")
    assert String.contains?(platform, "handler,")

    weather = File.read!(Path.join(@core_src, "Weather.elm"))
    assert String.contains?(weather, "(Result String WeatherInfo -> msg) -> Cmd msg")
    assert String.contains?(weather, "type WeatherUpdate")
    assert String.contains?(weather, "Platform.subscribe")
    assert String.contains?(weather, "onWeather")
    assert String.contains?(weather, "onCurrent :")
    assert String.contains?(weather, "onForecast :")
    refute String.contains?(weather, "part :")

    connectivity = File.read!(Path.join(@core_src, "Connectivity.elm"))
    assert String.contains?(connectivity, "type Connectivity")
    assert String.contains?(connectivity, "(Connectivity -> msg) -> Cmd msg")
  end

  test "elm_pebble_dev package docs mirror includes companion Pebble API modules" do
    docs = @docs_json |> File.read!() |> Jason.decode!()
    documented = MapSet.new(docs, &Map.fetch!(&1, "name"))

    for module <-
          ~w(Battery Calendar Connectivity Environment Geolocation Locale Notifications PreferenceStore Storage Weather) do
      assert MapSet.member?(documented, "Pebble.Companion.#{module}")
    end

    refute MapSet.member?(documented, "Pebble.Companion")

    phone = File.read!(Path.join(@core_src, "Phone.elm"))
    refute String.contains?(phone, "@docs Request")
    refute String.contains?(phone, "@docs send")
    assert String.contains?(phone, "onWatchToPhone")
    assert String.contains?(phone, "sendPhoneToWatch")
    assert String.contains?(phone, "platformIncomingFor")
    assert String.contains?(phone, "batteryPlatformIncoming")

    battery = File.read!(Path.join(@core_src, "Battery.elm"))
    refute String.contains?(battery, ", handler")
    assert String.contains?(battery, "onBattery : (Result String BatteryInfo -> msg) -> Sub msg")
    refute String.contains?(battery, "part :")
  end

  test "debugger simulator settings persist typed phone context fields" do
    {:ok, _state} = Debugger.start_session("companion-api-settings-test")

    {:ok, state} =
      Debugger.set_simulator_settings("companion-api-settings-test", %{
        "battery_percent" => 67,
        "charging" => true,
        "timezone_id" => "Europe/London",
        "timezone_offset_min" => 60,
        "locale" => "en-GB",
        "language" => "en",
        "region" => "GB",
        "network_online" => false,
        "notifications_enabled" => false,
        "quiet_hours" => true,
        "weather" => %{"temperatureC" => 13, "condition" => "rain"},
        "calendar_events" => [
          %{
            "id" => "meeting",
            "title" => "Meeting",
            "startMillis" => 1,
            "endMillis" => 2,
            "allDay" => false
          }
        ],
        "storage_values" => %{"theme" => %{"kind" => "string", "value" => "dark"}},
        "preferences" => %{"units" => "metric"},
        "environment" => %{
          "sun" => %{"sunriseMin" => 400, "sunsetMin" => 1210, "polarDay" => false}
        }
      })

    settings = state.simulator_settings

    assert settings["battery_percent"] == 67
    assert settings["timezone_id"] == "Europe/London"
    assert settings["timezone_offset_min"] == 60
    assert settings["locale"] == "en-GB"
    assert settings["network_online"] == false
    assert settings["notifications_enabled"] == false
    assert settings["quiet_hours"] == true
    assert settings["weather"]["condition"] == "rain"
    assert [%{"id" => "meeting"} = _event] = settings["calendar_events"]
    assert settings["storage_values"]["theme"]["value"] == "dark"
    assert settings["preferences"]["units"] == "metric"
    assert settings["environment"]["sun"]["sunriseMin"] == 400
  end

  test "debugger simulates companion storage and preferences command results" do
    slug = "companion-api-command-results-#{System.unique_integer([:positive])}"

    source = """
    module CompanionApiCommands exposing (..)

    import Json.Decode as Decode
    import Json.Encode as Encode
    import Pebble.Companion.PreferenceStore as PreferenceStore
    import Pebble.Companion.Storage as Storage

    type alias Model =
        { stored : String
        , preferenceKey : String
        }

    type Msg
        = GotStorage (Result Storage.Error Storage.Value)
        | GotPreference (Result String ( String, Decode.Value ))

    init _ =
        ( { stored = "", preferenceKey = "" }
        , Cmd.batch
            [ Storage.get "theme" GotStorage
            , PreferenceStore.get "units" GotPreference
            ]
        )

    update msg model =
        case msg of
            GotStorage _ ->
                ( { model | stored = "received" }, Cmd.none )

            GotPreference _ ->
                ( { model | preferenceKey = "received" }, Cmd.none )

    subscriptions _ =
        Sub.none
    """

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, _state} =
      Debugger.set_simulator_settings(slug, %{
        "storage_values" => %{"theme" => %{"kind" => "string", "value" => "dark"}},
        "preferences" => %{"units" => "metric"}
      })

    {:ok, state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApiCommands.elm",
        source_root: "phone",
        source: source,
        reason: "companion_api_commands"
      })

    runtime_model = get_in(state, [:companion, :model, "runtime_model"])

    assert runtime_model["stored"] == "received"
    assert runtime_model["preferenceKey"] == "received"

    assert Enum.any?(state.events, fn event ->
             event.type == "debugger.companion_bridge" and
               Map.get(event.payload, :api) == "storage" and
               Map.get(event.payload, :op) == "get" and
               get_in(event.payload, [:response_value, "ctor"]) == "StringValue"
           end)

    assert Enum.any?(state.events, fn event ->
             event.type == "debugger.companion_bridge" and
               Map.get(event.payload, :api) == "preferences" and
               Map.get(event.payload, :op) == "get" and
               elem(Map.get(event.payload, :response_value), 0) == "units"
           end)
  end

  test "debugger simulates command requests for all companion data APIs" do
    slug = "companion-api-all-command-results-#{System.unique_integer([:positive])}"

    source = """
    module CompanionApiAllCommands exposing (..)

    import Pebble.Companion.Battery as Battery
    import Pebble.Companion.Calendar as Calendar
    import Pebble.Companion.Connectivity as Connectivity
    import Pebble.Companion.Environment as Environment
    import Pebble.Companion.Locale as Locale
    import Pebble.Companion.Notifications as Notifications
    import Pebble.Companion.Weather as Weather

    type alias Model =
        { count : Int }

    type Msg
        = GotBattery (Result String Battery.BatteryInfo)
        | GotCalendar (Result String (List Calendar.CalendarEvent))
        | GotEnvironment (Result String Environment.EnvironmentInfo)
        | GotLocale (Result String Locale.LocaleInfo)
        | GotConnectivity Connectivity.Connectivity
        | GotNotifications (Result String Notifications.NotificationStatus)
        | GotWeather (Result String (List Weather.WeatherInfo))

    init _ =
        ( { count = 0 }
        , Cmd.batch
            [ Battery.current GotBattery
            , Calendar.upcoming 2 GotCalendar
            , Environment.current GotEnvironment
            , Locale.current GotLocale
            , Connectivity.current GotConnectivity
            , Notifications.current GotNotifications
            , Weather.forecast GotWeather
            ]
        )

    update msg model =
        ( { model | count = model.count + 1 }, Cmd.none )

    subscriptions _ =
        Sub.none
    """

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApiAllCommands.elm",
        source_root: "phone",
        source: source,
        reason: "companion_api_all_commands"
      })

    bridge_events =
      state.events
      |> Enum.filter(&(&1.type == "debugger.companion_bridge"))
      |> Enum.map(& &1.payload)

    for api <- ~w(battery calendar environment locale network notifications weather) do
      assert Enum.any?(
               bridge_events,
               &(Map.get(&1, :api) == api and Map.get(&1, :result) in ["Ok", "plain"])
             )
    end

    assert get_in(state, [:companion, :model, "runtime_model", "count"]) >= 7
  end

  test "debugger mutates companion storage and preferences fixtures from set commands" do
    slug = "companion-api-mutating-command-results-#{System.unique_integer([:positive])}"

    source = """
    module CompanionApiMutations exposing (..)

    import Json.Decode as Decode
    import Json.Encode as Encode
    import Pebble.Companion.PreferenceStore as PreferenceStore
    import Pebble.Companion.Storage as Storage

    type alias Model =
        { count : Int }

    type Msg
        = GotStorage (Result Storage.Error Storage.Value)
        | GotPreference (Result String ( String, Decode.Value ))

    init _ =
        ( { count = 0 }
        , Cmd.batch
            [ Storage.set "theme" (Storage.StringValue "light")
            , PreferenceStore.set "units" (Encode.string "imperial")
            ]
        )

    update msg model =
        ( { model | count = model.count + 1 }, Cmd.none )

    subscriptions _ =
        Sub.none
    """

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApiMutations.elm",
        source_root: "phone",
        source: source,
        reason: "companion_api_mutations"
      })

    assert get_in(state, [:simulator_settings, "storage_values", "theme"]) == %{
             "kind" => "string",
             "value" => "light"
           }

    assert get_in(state, [:simulator_settings, "preferences", "units"]) == "imperial"
  end

  test "debugger simulates phone status demo battery from init helper and simulator settings" do
    slug = "companion-phone-status-#{System.unique_integer([:positive])}"

    template_root =
      Path.expand(
        "../../priv/project_templates/companion_demo_phone_status",
        __DIR__
      )

    source = File.read!(Path.join(template_root, "phone/src/CompanionApp.elm"))

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: source,
        reason: "companion_phone_status_init"
      })

    assert Enum.any?(state.events, fn event ->
             event.type == "debugger.companion_bridge" and
               Map.get(event.payload, :api) == "battery" and
               Map.get(event.payload, :response_message) == "GotBattery" and
               get_in(event.payload, [:response_value, "percent"]) == 88
           end)

    {:ok, updated} =
      Debugger.set_simulator_settings(slug, %{
        "battery_percent" => 42,
        "charging" => true,
        "locale" => "de-DE"
      })

    assert Enum.any?(updated.events, fn event ->
             event.type == "debugger.companion_bridge" and
               Map.get(event.payload, :api) == "battery" and
               Map.get(event.payload, :response_message) == "GotBattery" and
               get_in(event.payload, [:response_value, "percent"]) == 42
           end)
  end

  test "subscription trigger rows expose documentation-style display ids" do
    slug = "companion-trigger-display-#{System.unique_integer([:positive])}"

    template_root =
      Path.expand(
        "../../priv/project_templates/companion_demo_phone_status",
        __DIR__
      )

    source = File.read!(Path.join(template_root, "phone/src/CompanionApp.elm"))

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: source,
        reason: "companion_trigger_display"
      })

    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "phone"})
    battery = Enum.find(rows, &(&1.trigger == "on_battery"))
    assert battery.trigger_display == "Battery.onBattery"
    assert Debugger.subscription_trigger_display_for(state, "on_battery", "phone") == "Battery.onBattery"
  end

  test "inject_trigger applies companion onBattery payload from structured message_value" do
    slug = "companion-phone-status-inject-#{System.unique_integer([:positive])}"

    template_root =
      Path.expand(
        "../../priv/project_templates/companion_demo_phone_status",
        __DIR__
      )

    source = File.read!(Path.join(template_root, "phone/src/CompanionApp.elm"))

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, _state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: source,
        reason: "companion_phone_status_inject"
      })

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "phone",
               trigger: "Battery.onBattery",
               message: "GotBattery",
               message_value: %{
                 "ctor" => "GotBattery",
                 "args" => [
                   %{
                     "ctor" => "Ok",
                     "args" => [%{"percent" => 55, "charging" => true}]
                   }
                 ]
               }
             })

    runtime_model = get_in(triggered, [:companion, :model, "runtime_model"]) || %{}
    assert runtime_model["batteryPercent"] == 55
    assert runtime_model["charging"] == true
  end

  test "debugger forwards phone status protocol values to the watch surface" do
    slug = "companion-phone-status-watch-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Ide.Projects.create_project(%{
               "name" => "Phone Status Demo",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "companion-demo-phone-status"
             })

    workspace = Ide.Projects.project_workspace_path(project)

    phone_source = File.read!(Path.join(workspace, "phone/src/CompanionApp.elm"))
    watch_source = File.read!(Path.join(workspace, "watch/src/Main.elm"))

    {:ok, _state} = Debugger.start_session(slug)

    {:ok, _state} =
      Debugger.set_simulator_settings(slug, %{
        "battery_percent" => 42,
        "charging" => true,
        "locale" => "de-DE"
      })

    {:ok, _state} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: phone_source,
        reason: "companion_phone_status_phone"
      })

    {:ok, watch_state} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source_root: "watch",
        source: watch_source,
        reason: "companion_phone_status_watch"
      })

    watch_model = get_in(watch_state, [:watch, :model, "runtime_model"])

    assert watch_model["locale"] == "de-DE"
    refute watch_model["locale"] == "debugger response"

    assert Enum.any?(watch_state.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               match?(
                 "ProvideBattery 42" <> _,
                 to_string(Map.get(event.payload, :message) || "")
               )
           end)

    assert get_in(watch_state, [:watch, :model, "runtime_model", "charging"]) == true
  end

  test "debugger forwards phone status connectivity from simulator settings to watch" do
    slug = "companion-phone-status-network-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Ide.Projects.create_project(%{
               "name" => "Phone Status Network",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "companion-demo-phone-status"
             })

    workspace = Ide.Projects.project_workspace_path(project)
    phone_source = File.read!(Path.join(workspace, "phone/src/CompanionApp.elm"))
    watch_source = File.read!(Path.join(workspace, "watch/src/Main.elm"))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.set_simulator_settings(slug, %{
        "network_online" => false,
        "battery_percent" => 42,
        "charging" => false
      })

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: phone_source,
        reason: "companion_phone_status_phone_network"
      })

    {:ok, watch_state} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source_root: "watch",
        source: watch_source,
        reason: "companion_phone_status_watch_network"
      })

    watch_model = get_in(watch_state, [:watch, :model, "runtime_model"])
    assert watch_model["online"] == false

    assert Enum.any?(watch_state.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               match?(
                 "ProvideConnectivity false" <> _,
                 to_string(Map.get(event.payload, :message) || "")
               )
           end)

    {:ok, updated} = Debugger.set_simulator_settings(slug, %{"network_online" => true})

    assert Enum.any?(updated.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and
               match?(
                 "ProvideConnectivity true" <> _,
                 to_string(Map.get(event.payload, :message) || "")
               )
           end)
  end

  test "debugger resolves phone status watch time string when model has multiple string fields" do
    slug = "companion-phone-status-time-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Ide.Projects.create_project(%{
               "name" => "Phone Status Time",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "companion-demo-phone-status"
             })

    workspace = Ide.Projects.project_workspace_path(project)
    watch_source = File.read!(Path.join(workspace, "watch/src/Main.elm"))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, watch_state} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source_root: "watch",
        source: watch_source,
        reason: "companion_phone_status_watch_time"
      })

    preview = get_in(watch_state, [:watch, :model, "debugger_device_current_time_string"]) || %{}
    time_string = get_in(watch_state, [:watch, :model, "runtime_model", "timeString"])

    assert is_binary(preview["string"])
    assert time_string == preview["string"]
    refute is_map(time_string)

    assert Enum.any?(watch_state.events, fn event ->
             event.type == "debugger.update_in" and
               match?(
                 "CurrentTimeString \"" <> _,
                 to_string(Map.get(event.payload, :message) || Map.get(event.payload, "message") || "")
               )
           end)

    assert watch_state.watch.view_tree
           |> collect_view_nodes()
           |> Enum.any?(fn node ->
             node["type"] == "text" and node["text"] == preview["string"]
           end)
  end

  defp collect_view_nodes(%{"children" => children}) when is_list(children) do
    Enum.flat_map(children, fn child ->
      if is_map(child) do
        [child | collect_view_nodes(child)]
      else
        []
      end
    end)
  end

  defp collect_view_nodes(%{children: children}) when is_list(children) do
    Enum.flat_map(children, fn child ->
      if is_map(child) do
        [child | collect_view_nodes(child)]
      else
        []
      end
    end)
  end

  defp collect_view_nodes(_node), do: []
end
