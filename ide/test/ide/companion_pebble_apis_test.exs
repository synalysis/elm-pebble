defmodule Ide.CompanionPebbleApisTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger

  @root Path.expand("../../..", __DIR__)
  @bridge_schema Path.join(@root, "shared/companion-protocol/phone_bridge_v1.json")
  @core_elm_json Path.join(@root, "packages/elm-pebble-companion-core/elm.json")
  @core_src Path.join(@root, "packages/elm-pebble-companion-core/src/Pebble/Companion")
  @shared_src Path.join(@root, "shared/elm-companion/Companion")
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

  test "companion-core exposes typed contract modules and app wrappers use Result String" do
    exposed =
      @core_elm_json
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("exposed-modules")

    for module <-
          ~w(Battery Calendar Environment Locale Network Notifications Preferences Storage Timeline Weather) do
      assert "Pebble.Companion.#{module}" in exposed
      assert File.exists?(Path.join(@core_src, "#{module}.elm"))
    end

    for module <-
          ~w(Battery Calendar Environment Locale Network Notifications Preferences Storage Weather) do
      wrapper = File.read!(Path.join(@shared_src, "#{module}.elm"))
      assert String.contains?(wrapper, "Result String")
      assert String.contains?(wrapper, "Phone.sendBridgeCommand")
      assert String.contains?(wrapper, "Phone.onRawMessage")
    end
  end

  test "elm_pebble_dev package docs mirror includes companion Pebble API modules" do
    docs = @docs_json |> File.read!() |> Jason.decode!()
    documented = MapSet.new(docs, &Map.fetch!(&1, "name"))

    for module <- ~w(Battery Calendar Environment Locale Notifications Preferences Weather) do
      assert MapSet.member?(documented, "Pebble.Companion.#{module}")
    end
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

    import Companion.Preferences as Preferences
    import Companion.Storage as Storage
    import Json.Decode as Decode
    import Json.Encode as Encode

    type alias Model =
        { stored : String
        , preferenceKey : String
        }

    type Msg
        = GotStorage (Result String Storage.Value)
        | GotPreference (Result String ( String, Decode.Value ))

    init _ =
        ( { stored = "", preferenceKey = "" }
        , Cmd.batch
            [ Storage.get "theme"
            , Preferences.get "units"
            ]
        )

    update msg model =
        case msg of
            GotStorage _ ->
                ( { model | stored = "received" }, Cmd.none )

            GotPreference _ ->
                ( { model | preferenceKey = "received" }, Cmd.none )

    subscriptions _ =
        Sub.batch
            [ Storage.onStorage GotStorage
            , Preferences.onPreference GotPreference
            ]
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

    import Companion.Battery as Battery
    import Companion.Calendar as Calendar
    import Companion.Environment as Environment
    import Companion.Locale as Locale
    import Companion.Network as Network
    import Companion.Notifications as Notifications
    import Companion.Weather as Weather

    type alias Model =
        { count : Int }

    type Msg
        = GotBattery (Result String Battery.BatteryInfo)
        | GotCalendar (Result String (List Calendar.CalendarEvent))
        | GotEnvironment (Result String Environment.EnvironmentInfo)
        | GotLocale (Result String Locale.LocaleInfo)
        | GotNetwork (Result String Bool)
        | GotNotifications (Result String Notifications.NotificationStatus)
        | GotWeather (Result String (List Weather.WeatherInfo))

    init _ =
        ( { count = 0 }
        , Cmd.batch
            [ Battery.current
            , Calendar.upcoming 2
            , Environment.current
            , Locale.current
            , Network.current
            , Notifications.current
            , Weather.forecast
            ]
        )

    update msg model =
        ( { model | count = model.count + 1 }, Cmd.none )

    subscriptions _ =
        Sub.batch
            [ Battery.onBattery GotBattery
            , Calendar.onCalendar GotCalendar
            , Environment.onEnvironment GotEnvironment
            , Locale.onLocale GotLocale
            , Network.onNetwork GotNetwork
            , Notifications.onNotifications GotNotifications
            , Weather.onWeather GotWeather
            ]
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
               &(Map.get(&1, :api) == api and Map.get(&1, :result) == "Ok")
             )
    end

    assert get_in(state, [:companion, :model, "runtime_model", "count"]) >= 7
  end

  test "debugger mutates companion storage and preferences fixtures from set commands" do
    slug = "companion-api-mutating-command-results-#{System.unique_integer([:positive])}"

    source = """
    module CompanionApiMutations exposing (..)

    import Companion.Preferences as Preferences
    import Companion.Storage as Storage
    import Json.Decode as Decode
    import Json.Encode as Encode

    type alias Model =
        { count : Int }

    type Msg
        = GotStorage (Result String Storage.Value)
        | GotPreference (Result String ( String, Decode.Value ))

    init _ =
        ( { count = 0 }
        , Cmd.batch
            [ Storage.set "theme" (Storage.StringValue "light")
            , Preferences.set "units" (Encode.string "imperial")
            ]
        )

    update msg model =
        ( { model | count = model.count + 1 }, Cmd.none )

    subscriptions _ =
        Sub.batch
            [ Storage.onStorage GotStorage
            , Preferences.onPreference GotPreference
            ]
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
    assert get_in(state, [:companion, :model, "runtime_model", "count"]) >= 2
  end
end
