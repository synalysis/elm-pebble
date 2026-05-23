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

  test "detects companion geolocation commands and subscriptions" do
    assert {:ok, %{"elm_introspect" => introspect}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@phone_geolocation, "CompanionApp.elm")

    assert MapSet.equal?(
             ProjectCapabilities.infer_introspect(introspect, "phone"),
             MapSet.new(["location"])
           )
  end

  test "detects companion configuration commands" do
    assert {:ok, %{"elm_introspect" => introspect}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@phone_configuration, "CompanionApp.elm")

    assert MapSet.member?(
             ProjectCapabilities.infer_introspect(introspect, "phone"),
             "configurable"
           )
  end

  test "detects companion configuration subscriptions" do
    assert {:ok, %{"elm_introspect" => introspect}} =
             Ide.Debugger.ElmIntrospect.analyze_source(
               @phone_configuration_subscription,
               "CompanionApp.elm"
             )

    assert MapSet.member?(
             ProjectCapabilities.infer_introspect(introspect, "phone"),
             "configurable"
           )
  end

  test "detects watch health commands and subscriptions" do
    assert {:ok, %{"elm_introspect" => introspect}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@watch_health, "Main.elm")

    assert MapSet.equal?(
             ProjectCapabilities.infer_introspect(introspect, "watch"),
             MapSet.new(["health"])
           )
  end

  test "does not infer watch capabilities from phone sources" do
    assert {:ok, %{"elm_introspect" => introspect}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@phone_geolocation, "CompanionApp.elm")

    refute MapSet.member?(
             ProjectCapabilities.infer_introspect(introspect, "watch"),
             "location"
           )
  end

  test "sync_detected_capabilities merges inferred capabilities into project settings" do
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
    assert "location" in (updated.release_defaults["capabilities"] || [])
  end
end
