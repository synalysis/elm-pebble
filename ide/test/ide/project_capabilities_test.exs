defmodule Ide.ProjectCapabilitiesTest do
  use Ide.DataCase, async: false

  alias Ide.ProjectCapabilities

  @phone_geolocation """
  module CompanionApp exposing (..)

  import Pebble.Companion.Geolocation as Geolocation exposing (Location)

  type alias Model =
      { location : Maybe Location }

  type Msg
      = CurrentPosition (Result String Location)

  init _ =
      ( { location = Nothing }, Geolocation.currentPosition )

  update msg model =
      case msg of
          CurrentPosition result ->
              ( { model | location = Result.toMaybe result }, Cmd.none )

  subscriptions _ =
      Geolocation.onCurrentPosition CurrentPosition
  """

  @phone_configuration """
  module CompanionApp exposing (..)

  import Pebble.Companion.Configuration as Configuration

  type alias Model = {}

  type Msg = Closed (Maybe String)

  init _ =
      ( {}, Configuration.open "https://example.com/config" )

  update _ model =
      ( model, Cmd.none )

  subscriptions _ =
      Configuration.onClosed Closed
  """

  @phone_configuration_subscription """
  module CompanionApp exposing (..)

  import GeneratedPreferences

  type alias Model = {}

  type Msg = FromConfiguration (Result String ())

  init _ =
      ( {}, Cmd.none )

  update _ model =
      ( model, Cmd.none )

  subscriptions _ =
      GeneratedPreferences.onConfiguration FromConfiguration
  """

  @watch_health """
  module Main exposing (..)

  import Pebble.Health as Health

  type alias Model = { steps : Maybe Int }

  type Msg
      = GotSteps Int
      | HealthEvent Health.Event

  init _ =
      ( { steps = Nothing }, Health.value Health.StepCount GotSteps )

  update msg model =
      case msg of
          GotSteps steps ->
              ( { model | steps = Just steps }, Cmd.none )

          HealthEvent _ ->
              ( model, Cmd.none )

  subscriptions _ =
      Health.onEvent HealthEvent
  """

  @phone_calendar """
  module CompanionApp exposing (..)

  import Pebble.Companion.Calendar as Calendar
  import Pebble.Companion.Phone as Phone

  type alias Model = {}

  type Msg = FromWatch (Result String ())

  init _ =
      ( {}, Cmd.none )

  update _ model =
      ( model, Cmd.none )

  subscriptions _ =
      Sub.batch
          [ Phone.onWatchToPhone FromWatch
          , Calendar.onCalendar (\_ -> FromWatch (Ok ()))
          ]
  """

  test "detects companion geolocation commands and subscriptions" do
    assert {:ok, %{"debugger_contract" => introspect}} =
             Ide.Debugger.CompileContract.analyze_source(@phone_geolocation, "CompanionApp.elm")

    assert MapSet.equal?(
             ProjectCapabilities.infer_introspect(introspect, "phone"),
             MapSet.new(["location"])
           )
  end

  test "detects companion configuration commands" do
    assert {:ok, %{"debugger_contract" => introspect}} =
             Ide.Debugger.CompileContract.analyze_source(@phone_configuration, "CompanionApp.elm")

    assert MapSet.member?(
             ProjectCapabilities.infer_introspect(introspect, "phone"),
             "configurable"
           )
  end

  test "detects companion configuration subscriptions" do
    assert {:ok, %{"debugger_contract" => introspect}} =
             Ide.Debugger.CompileContract.analyze_source(
               @phone_configuration_subscription,
               "CompanionApp.elm"
             )

    assert MapSet.member?(
             ProjectCapabilities.infer_introspect(introspect, "phone"),
             "configurable"
           )
  end

  test "detects watch health commands and subscriptions" do
    assert {:ok, %{"debugger_contract" => introspect}} =
             Ide.Debugger.CompileContract.analyze_source(@watch_health, "Main.elm")

    assert MapSet.equal?(
             ProjectCapabilities.infer_introspect(introspect, "watch"),
             MapSet.new(["health"])
           )
  end

  @watch_tier1 """
  module Main exposing (..)

  import Pebble.Accel as Accel
  import Pebble.Compass as Compass
  import Pebble.Dictation as Dictation

  subscriptions _ =
      Sub.batch
          [ Accel.onData Accel.defaultConfig AccelSample
          , Compass.onChange CompassChanged
          , Dictation.onResult DictationResult
          ]
  """

  test "detects tier 1 watch project capabilities from module imports" do
    assert {:ok, %{"debugger_contract" => introspect}} =
             Ide.Debugger.CompileContract.analyze_source(@watch_tier1, "Main.elm")

    caps = ProjectCapabilities.infer_introspect(introspect, "watch")

    assert MapSet.member?(caps, "watch_accel")
    assert MapSet.member?(caps, "compass")
    assert MapSet.member?(caps, "dictation")
  end

  test "does not infer watch capabilities from phone sources" do
    assert {:ok, %{"debugger_contract" => introspect}} =
             Ide.Debugger.CompileContract.analyze_source(@phone_geolocation, "CompanionApp.elm")

    refute MapSet.member?(
             ProjectCapabilities.infer_introspect(introspect, "watch"),
             "location"
           )
  end

  test "companion_preferences? is false for calendar-only companion apps" do
    refute ProjectCapabilities.companion_preferences?("/tmp/no-such-workspace")

    tmp = System.tmp_dir!()
    workspace = Path.join(tmp, "calendar-cap-#{System.unique_integer([:positive])}")
    phone_src = Path.join(workspace, "phone/src")
    File.mkdir_p!(phone_src)
    File.write!(Path.join(workspace, "phone/elm.json"), "{}")
    File.write!(Path.join(phone_src, "CompanionApp.elm"), @phone_calendar)

    on_exit(fn -> File.rm_rf!(workspace) end)

    refute ProjectCapabilities.companion_preferences?(workspace)
  end

  test "companion_preferences? is true when preferences schema is declared" do
    alias Ide.InternalPackages

    tmp = System.tmp_dir!()
    workspace = Path.join(tmp, "prefs-cap-#{System.unique_integer([:positive])}")
    phone_root = Path.join(workspace, "phone")
    phone_src = Path.join(phone_root, "src")
    File.mkdir_p!(phone_src)

    elm_json = %{
      "type" => "application",
      "source-directories" => [
        "src",
        InternalPackages.pebble_companion_preferences_elm_src_abs()
      ],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(phone_root, "elm.json"), Jason.encode!(elm_json, pretty: true))

    File.write!(
      Path.join(phone_src, "CompanionPreferences.elm"),
      """
      module CompanionPreferences exposing (settings)

      import Pebble.Companion.Preferences as Preferences

      settings =
          Preferences.schema "Demo"
              [ Preferences.field "enabled" (Preferences.toggle "Enabled" True) ]
      """
    )

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert ProjectCapabilities.companion_preferences?(workspace)
  end

  test "companion_preferences? is true when Configuration module is used" do
    tmp = System.tmp_dir!()
    workspace = Path.join(tmp, "config-cap-#{System.unique_integer([:positive])}")
    phone_src = Path.join(workspace, "phone/src")
    File.mkdir_p!(phone_src)
    File.write!(Path.join(workspace, "phone/elm.json"), "{}")
    File.write!(Path.join(phone_src, "CompanionApp.elm"), @phone_configuration)

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert ProjectCapabilities.companion_preferences?(workspace)
  end

  test "package_capabilities returns only Pebble package metadata capabilities" do
    tmp = System.tmp_dir!()
    workspace = Path.join(tmp, "package-caps-#{System.unique_integer([:positive])}")
    watch_src = Path.join(workspace, "watch/src")
    File.mkdir_p!(watch_src)
    File.write!(Path.join(workspace, "watch/elm.json"), "{}")
    File.write!(Path.join(watch_src, "Main.elm"), @watch_health)

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert ProjectCapabilities.package_capabilities(workspace) == ["health"]
    refute "watch_accel" in ProjectCapabilities.package_capabilities(workspace)
  end

  test "sync_detected_capabilities sets inferred package capabilities from project sources" do
    slug = "project-capabilities-sync-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Ide.Projects.create_project(%{
               "name" => "Capabilities Sync",
               "slug" => slug,
               "target_type" => "app"
             })

    on_exit(fn -> Ide.Projects.delete_project(project) end)

    assert :ok =
             Ide.Projects.write_source_file(
               project,
               "phone",
               "src/CompanionApp.elm",
               @phone_geolocation
             )

    updated = Ide.Projects.get_project_by_slug(slug)
    assert updated.release_defaults["capabilities"] == ["location"]
  end

  test "sync_detected_capabilities removes stale capabilities when APIs are no longer used" do
    slug = "project-capabilities-prune-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Ide.Projects.create_project(%{
               "name" => "Capabilities Prune",
               "slug" => slug,
               "target_type" => "app"
             })

    on_exit(fn -> Ide.Projects.delete_project(project) end)

    assert {:ok, _} =
             Ide.Projects.update_project(project, %{
               "release_defaults" => %{"capabilities" => ["location", "health"]}
             })

    assert {:ok, updated} = Ide.Projects.sync_detected_capabilities(project)
    assert updated.release_defaults["capabilities"] == []
  end
end
