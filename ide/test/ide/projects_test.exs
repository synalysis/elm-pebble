defmodule Ide.ProjectsTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Projects

  setup do
    root = Path.join(System.tmp_dir!(), "ide_projects_test_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "create/list/activate project" do
    assert {:ok, first} =
             Projects.create_project(%{
               "name" => "Alpha",
               "slug" => "alpha",
               "target_type" => "app"
             })

    assert first.active

    assert {:ok, second} =
             Projects.create_project(%{
               "name" => "Beta",
               "slug" => "beta",
               "target_type" => "watchface"
             })

    refute second.active
    assert Enum.map(Projects.list_projects(), & &1.slug) == ["alpha", "beta"]

    assert {:ok, _} = Projects.activate_project(second)
    assert Projects.active_project().slug == "beta"
  end

  test "source file operations across roots" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Ops",
               "slug" => "ops",
               "target_type" => "app",
               "source_roots" => ["watch", "protocol", "phone"]
             })

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "src/Main.elm",
               "module Main exposing (main)"
             )

    assert {:ok, "module Main exposing (main)"} =
             Projects.read_source_file(project, "watch", "src/Main.elm")

    assert :ok = Projects.rename_source_path(project, "watch", "src/Main.elm", "src/App.elm")
    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/App.elm")

    assert :ok = Projects.delete_source_path(project, "watch", "src/App.elm")
    assert {:error, :enoent} = Projects.read_source_file(project, "watch", "src/App.elm")
  end

  test "delete project clears debugger state for reusable slug" do
    slug = "delete-clears-debugger-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "DeleteClearsDebugger",
               "slug" => slug,
               "target_type" => "app"
             })

    assert {:ok, started} = Debugger.start_session(slug)
    assert started.running == true
    assert started.events != []

    assert {:ok, _deleted} = Projects.delete_project(project)

    assert {:ok, snapshot} = Debugger.snapshot(slug, event_limit: 10)
    assert snapshot.running == false
    assert snapshot.events == []
    assert snapshot.debugger_timeline == []
  end

  test "bitmap/font resource import generates read-only resources module" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "BitmapOps",
               "slug" => "bitmap-ops-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "release_defaults" => %{"target_platforms" => ["basalt", "chalk"]}
             })

    tmp_png =
      Path.join(System.tmp_dir!(), "bitmap_upload_#{System.unique_integer([:positive])}.png")

    File.write!(tmp_png, <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>)
    on_exit(fn -> File.rm(tmp_png) end)

    tmp_ttf =
      Path.join(System.tmp_dir!(), "font_upload_#{System.unique_integer([:positive])}.ttf")

    File.write!(tmp_ttf, <<0, 1, 0, 0, 0, 14, 0, 128>>)
    on_exit(fn -> File.rm(tmp_ttf) end)

    assert {:ok, _} = Projects.import_bitmap_resource(project, tmp_png, "logo.png")
    assert {:ok, _} = Projects.import_font_resource(project, tmp_ttf, "menu.ttf")

    assert {:ok, %{duplicate: true}} =
             Projects.import_bitmap_resource(project, tmp_png, "logo-copy.png")

    assert {:ok, %{duplicate: true}} =
             Projects.import_font_resource(project, tmp_ttf, "menu-copy.ttf")

    assert {:ok, entries} = Projects.list_bitmap_resources(project)
    assert [%{ctor: "Logo"}] = entries
    assert {:ok, font_sources} = Projects.list_font_sources(project)
    assert [%{id: source_id, filename: "menu.ttf"}] = font_sources

    source_font_path =
      Path.join(Projects.project_workspace_path(project), "watch/resources/fonts/menu.ttf")

    assert File.exists?(source_font_path)

    assert {:ok, _} =
             Projects.add_font_variant(project, %{
               "source_id" => source_id,
               "ctor" => "MenuDigits28",
               "name" => "Menu Digits 28",
               "height" => "28",
               "characters" => "[0-9:.]",
               "tracking_adjust" => "1",
               "compatibility" => "2.7",
               "target_platforms" => "basalt chalk"
             })

    assert {:ok, _} =
             Projects.add_font_variant(project, %{
               "source_id" => source_id,
               "ctor" => "MenuText18",
               "name" => "Menu Text 18",
               "height" => "18",
               "characters" => "[A-Za-z ]",
               "tracking_adjust" => "0",
               "compatibility" => "3.0"
             })

    assert {:ok, font_entries} = Projects.list_font_resources(project)
    assert Enum.map(font_entries, & &1.ctor) == ["MenuDigits28", "MenuText18"]

    assert {:ok, _} = Projects.add_font_variant(project, %{"source_id" => source_id})
    assert {:ok, font_entries} = Projects.list_font_resources(project)
    auto_entry = Enum.find(font_entries, &(&1.ctor == "Menu"))
    assert auto_entry.height == 29
    assert auto_entry.compatibility == "latest"
    assert auto_entry.target_platforms == ["basalt", "chalk"]

    generated =
      Path.join(Projects.project_workspace_path(project), "watch/src/Pebble/Ui/Resources.elm")

    assert {:ok, source} = File.read(generated)
    assert String.contains?(source, "Generated from the resources configured")
    assert String.contains?(source, "project settings Resources page")
    assert String.contains?(source, "type Bitmap")
    assert String.contains?(source, "Logo")
    assert String.contains?(source, "type alias BitmapInfo")
    assert String.contains?(source, "bitmapInfo")
    assert String.contains?(source, "type Font")
    assert String.contains?(source, "Menu")
    assert String.contains?(source, "MenuDigits28")
    assert String.contains?(source, "MenuText18")
    assert String.contains?(source, "height = 28")
    assert String.contains?(source, "height = 18")
    assert String.contains?(source, "type alias FontInfo")
    assert String.contains?(source, "fontInfo")
    refute String.contains?(source, "toResourceId")

    assert {:ok, _} = Projects.delete_bitmap_resource(project, "Logo")
    assert {:ok, []} = Projects.list_bitmap_resources(project)
    assert {:ok, _} = Projects.delete_font_resource(project, "MenuDigits28")
    assert File.exists?(source_font_path)
    assert {:ok, remaining_fonts} = Projects.list_font_resources(project)
    assert Enum.map(remaining_fonts, & &1.ctor) == ["Menu", "MenuText18"]
    assert {:ok, _} = Projects.delete_font_source(project, source_id)
    refute File.exists?(source_font_path)
    assert {:ok, []} = Projects.list_font_resources(project)
    assert {:ok, []} = Projects.list_font_sources(project)
  end

  test "game templates seed app projects with Elm game APIs" do
    for template <- ["game-basic", "game-tiny-bird", "game-greeneys-run", "game-2048"] do
      slug = "#{template}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => template,
                 "slug" => slug,
                 "target_type" => "watchface",
                 "template" => template
               })

      assert project.target_type == "app"
      base = Projects.project_workspace_path(project)
      assert File.exists?(Path.join(base, "watch/src/Main.elm"))
      assert {:ok, main} = File.read(Path.join(base, "watch/src/Main.elm"))
      assert String.contains?(main, "Pebble.Frame") or String.contains?(main, "Pebble.Button")
    end
  end

  test "starter watch template only places user sources under watch/src" do
    slug = "starter-clean-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "StarterClean",
               "slug" => slug,
               "target_type" => "app",
               "template" => "starter"
             })

    base = Projects.project_workspace_path(project)
    watch_src = Path.join(base, "watch/src")

    assert File.exists?(Path.join(watch_src, "Main.elm"))
    refute File.exists?(Path.join(watch_src, "CoreCompliance.elm"))
    assert File.exists?(Path.join(watch_src, "Pebble/Ui/Resources.elm"))

    assert {:ok, elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, decoded} = Jason.decode(elm_json_raw)
    dirs = Map.fetch!(decoded, "source-directories")
    direct = get_in(decoded, ["dependencies", "direct"]) || %{}
    assert "src" in dirs
    assert Enum.any?(dirs, &String.ends_with?(&1, "packages/elm-pebble/elm-watch/src"))

    assert "../protocol/src" in dirs

    refute Map.has_key?(direct, "elm-pebble/elm-watch")
    assert Map.fetch!(direct, "elm/json") == "1.1.3"

    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "phone/elm.json"))

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    phone_direct = get_in(phone_decoded, ["dependencies", "direct"]) || %{}
    assert phone_direct["elm/http"] == "2.0.0"
    refute Map.has_key?(phone_direct, "elm/random")

    refute Map.has_key?(
             phone_direct,
             "elm-pebble/elm-phone"
           )

    phone_dirs = Map.fetch!(phone_decoded, "source-directories")
    assert "../protocol/src" in phone_dirs
    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "phone-pebble-stubs/src"))
    assert Enum.any?(phone_dirs, &String.ends_with?(&1, "shared/elm-companion"))
    assert Enum.any?(phone_dirs, &String.ends_with?(&1, "packages/elm-pebble-companion-core/src"))

    assert Enum.any?(
             phone_dirs,
             &String.ends_with?(&1, "packages/elm-pebble-companion-preferences/src")
           )

    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "internal_packages/elm-random/src"))

    assert {:ok, protocol_types} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert String.contains?(protocol_types, "module Companion.Types")

    assert {:ok, phone_engine} = Projects.read_source_file(project, "phone", "src/Engine.elm")
    assert String.contains?(phone_engine, "module Engine")
  end

  test "phone tree hides platform bridge modules that should be browsed through docs" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PhoneTreeDocs",
               "slug" => "phone-tree-docs-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "starter"
             })

    assert {:error, _} =
             Projects.read_source_file(project, "phone", "src/Pebble/Companion/AppMessage.elm")

    phone_tree =
      project
      |> Projects.list_source_tree()
      |> Enum.find(&(&1.source_root == "phone"))

    refute "src/Pebble/Companion/AppMessage.elm" in tree_rel_paths(phone_tree.nodes)
    refute "src/Companion/Internal.elm" in tree_rel_paths(phone_tree.nodes)
    refute "src/Engine.elm" in tree_rel_paths(phone_tree.nodes)
  end

  test "protocol tree hides platform bridge modules that should be browsed through docs" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ProtocolTreeDocs",
               "slug" => "protocol-tree-docs-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "starter"
             })

    assert {:ok, watch_bridge} =
             Projects.read_source_file(project, "protocol", "src/Companion/Watch.elm")

    assert String.contains?(watch_bridge, "module Companion.Watch")

    protocol_tree =
      project
      |> Projects.list_source_tree()
      |> Enum.find(&(&1.source_root == "protocol"))

    refute "src/Companion/Watch.elm" in tree_rel_paths(protocol_tree.nodes)
    refute "src/Companion/Internal.elm" in tree_rel_paths(protocol_tree.nodes)
    assert "src/Companion/Types.elm" in tree_rel_paths(protocol_tree.nodes)
  end

  test "listing a companion project restores missing default protocol files" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ProtocolInvariant",
               "slug" => "protocol-invariant-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "starter"
             })

    base = Projects.project_workspace_path(project)
    File.rm_rf!(Path.join(base, "protocol"))

    refute File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))

    protocol_tree =
      project
      |> Projects.list_source_tree()
      |> Enum.find(&(&1.source_root == "protocol"))

    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert "src/Companion/Types.elm" in tree_rel_paths(protocol_tree.nodes)
  end

  test "watchface templates seed watch-only starter apps" do
    for {template, expected_line} <- [
          {"watchface-digital", "timeString"},
          {"watchface-analog", "handEnd"}
        ] do
      slug =
        "watchface-template-#{String.replace(template, "-", "_")}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => "WatchfaceTemplate",
                 "slug" => slug,
                 "target_type" => "app",
                 "template" => template
               })

      base = Projects.project_workspace_path(project)
      assert project.target_type == "watchface"
      assert File.exists?(Path.join(base, "watch/src/Main.elm"))
      assert File.exists?(Path.join(base, "watch/index.html"))
      refute File.exists?(Path.join(base, "protocol/elm.json"))
      refute File.exists?(Path.join(base, "phone/elm.json"))
      refute File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
      refute File.exists?(Path.join(base, "phone/src/Engine.elm"))

      assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
      assert String.contains?(watch_main, expected_line)
      refute String.contains?(watch_main, "Companion")

      assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
      assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
      watch_direct = get_in(watch_decoded, ["dependencies", "direct"]) || %{}
      assert Map.fetch!(watch_direct, "elm/json") == "1.1.3"
    end
  end

  test "add_companion_app scaffolds phone and protocol for watch-only projects" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "AddCompanion",
               "slug" => "add-companion-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "watchface-digital"
             })

    base = Projects.project_workspace_path(project)
    refute Projects.companion_app_present?(project)
    refute File.exists?(Path.join(base, "phone/elm.json"))
    refute File.exists?(Path.join(base, "protocol/elm.json"))

    assert :ok = Projects.add_companion_app(project)

    assert Projects.companion_app_present?(project)
    assert File.exists?(Path.join(base, "phone/elm.json"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))

    assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
    assert "../protocol/src" in Map.fetch!(watch_decoded, "source-directories")

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    phone_dirs = Map.fetch!(phone_decoded, "source-directories")
    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "phone-pebble-stubs/src"))
    assert Enum.any?(phone_dirs, &String.ends_with?(&1, "shared/elm-companion"))
    assert Enum.any?(phone_dirs, &String.ends_with?(&1, "packages/elm-pebble-companion-core/src"))

    assert Enum.any?(
             phone_dirs,
             &String.ends_with?(&1, "packages/elm-pebble-companion-preferences/src")
           )

    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "internal_packages/elm-random/src"))
    refute Map.has_key?(get_in(phone_decoded, ["dependencies", "direct"]) || %{}, "elm/random")
  end

  test "complete watchface tutorial template seeds sources and resources" do
    slug = "watchface-tutorial-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WatchfaceTutorial",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-tutorial-complete"
             })

    base = Projects.project_workspace_path(project)
    assert project.target_type == "watchface"
    assert File.exists?(Path.join(base, "watch/src/Main.elm"))
    assert File.exists?(Path.join(base, "watch/resources/bitmaps/BtIcon.png"))
    assert File.exists?(Path.join(base, "watch/resources/fonts/Jersey.ttf"))
    assert File.exists?(Path.join(base, "watch/resources/bitmaps.json"))
    assert File.exists?(Path.join(base, "watch/resources/fonts.json"))
    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert File.exists?(Path.join(base, "phone/elm.json"))
    assert File.exists?(Path.join(base, "phone/src/Engine.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionPreferences.elm"))
    assert File.exists?(Path.join(base, "phone/src/Companion/GeneratedPreferences.elm"))
    refute File.exists?(Path.join(base, "phone/src/Pebble/Companion/AppMessage.elm"))
    refute File.exists?(Path.join(base, "phone/src/Companion/Internal.elm"))
    refute File.exists?(Path.join(base, "phone/src/Companion/Http.elm"))

    assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert String.contains?(watch_main, "RequestWeather CurrentLocation")
    assert String.contains?(watch_main, "PebbleSystem.batteryLevel")
    assert String.contains?(watch_main, "PebbleUi.text")
    assert String.contains?(watch_main, "currentDateTime : Maybe PebbleTime.CurrentDateTime")
    assert String.contains?(watch_main, "temperature : Maybe Temperature")
    assert String.contains?(watch_main, "condition : Maybe WeatherCondition")
    refute String.contains?(watch_main, ", hour : Int")
    refute String.contains?(watch_main, ", dayOfWeek : PebbleTime.DayOfWeek")
    refute String.contains?(watch_main, "conditionCode")
    refute String.contains?(watch_main, "SetTemperatureUnit")
    refute String.contains?(watch_main, "| ProvideTemperature")
    refute String.contains?(watch_main, "| SetBackgroundColor")
    assert String.contains?(watch_main, "FromPhone PhoneToWatch")
    assert String.contains?(watch_main, "CompanionWatch.onPhoneToWatch FromPhone")

    assert {:ok, protocol_internal} =
             Projects.read_source_file(project, "protocol", "src/Companion/Internal.elm")

    assert String.contains?(protocol_internal, "Generated wire encoding and decoding helpers")
    assert String.contains?(protocol_internal, "encodeTemperatureTag")
    assert String.contains?(protocol_internal, "encodeTemperatureValue")
    assert String.contains?(protocol_internal, "encodeWeatherConditionCode")
    assert String.contains?(protocol_internal, "encodeTutorialColorCode")
    refute String.contains?(protocol_internal, "locationWeatherQuery")

    assert {:ok, resources} =
             Projects.read_source_file(project, "watch", "src/Pebble/Ui/Resources.elm")

    assert String.contains?(resources, "BtIcon")
    assert String.contains?(resources, "Jersey")

    assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
    assert get_in(watch_decoded, ["dependencies", "direct", "elm/json"]) == "1.1.3"

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    assert get_in(phone_decoded, ["dependencies", "direct", "elm/http"]) == "2.0.0"

    assert {:ok, companion_app} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert String.contains?(companion_app, "import Http")
    assert String.contains?(companion_app, "CompanionPhone.onWatchToPhone FromWatch")
    assert String.contains?(companion_app, "GeneratedPreferences.onConfiguration FromBridge")
    assert String.contains?(companion_app, "type alias Flags =")
    assert String.contains?(companion_app, "init : Flags -> ( Model, Cmd Msg )")
    assert String.contains?(companion_app, "GeneratedPreferences.decodeConfigurationFlags flags")
    assert String.contains?(companion_app, "sendSettings settings")

    assert String.contains?(
             companion_app,
             "FromBridge (Result String CompanionPreferences.Settings)"
           )

    assert String.contains?(companion_app, "FromBridge (Ok settings)")
    assert String.contains?(companion_app, "FromBridge (Err error)")
    assert String.contains?(companion_app, "errors : List String")
    assert String.contains?(companion_app, "addError")
    assert String.contains?(companion_app, "httpErrorToString")
    refute String.contains?(companion_app, "decodeConfigurationSaved")

    assert String.contains?(companion_app, "SetBackgroundColor settings.backgroundColor")
    assert String.contains?(companion_app, "SetTextColor settings.textColor")
    assert String.contains?(companion_app, "SetShowDate settings.showDate")
    assert String.contains?(companion_app, "FromWatch (Result String WatchToPhone)")
    assert String.contains?(companion_app, "conditionFromCode")
    assert String.contains?(companion_app, "ProvideCondition weather.condition")
    refute String.contains?(companion_app, "Companion.Http")
    refute String.contains?(companion_app, "port module")
    refute String.contains?(companion_app, "port incoming")
    refute String.contains?(companion_app, "port outgoing")
    refute String.contains?(companion_app, "port httpRequest")
    refute String.contains?(companion_app, "port httpResponse")

    assert {:ok, companion_preferences} =
             Projects.read_source_file(project, "phone", "src/CompanionPreferences.elm")

    assert String.contains?(companion_preferences, "Preferences.schema \"Tutorial Watchface\"")
    assert String.contains?(companion_preferences, "Preferences.field \"backgroundColor\"")
    assert String.contains?(companion_preferences, "Preferences.field \"textColor\"")
    assert String.contains?(companion_preferences, "Preferences.field \"showDate\"")

    assert {:ok, generated_preferences} =
             Projects.read_source_file(project, "phone", "src/Companion/GeneratedPreferences.elm")

    assert String.contains?(generated_preferences, "Subscribe to configuration responses")
    assert String.contains?(generated_preferences, "decodeConfigurationFlags flags")
    assert String.contains?(generated_preferences, "decodeConfigurationSaved")
    assert String.contains?(generated_preferences, "decodeConfigurationFlags")
    assert String.contains?(generated_preferences, "configurationFlagsDecoder")
    assert String.contains?(generated_preferences, "configurationResponseDecoder")
    assert String.contains?(generated_preferences, "preferencesErrorToString")

    assert String.contains?(
             generated_preferences,
             "Preferences.decodeResponse PreferencesSchema.settings"
           )

    assert {:ok, preferences_schema} = Ide.PebblePreferences.extract(Path.join(base, "phone"))
    assert preferences_schema.title == "Tutorial Watchface"

    assert Enum.flat_map(preferences_schema.sections, & &1.fields) |> Enum.map(& &1.id) == [
             "backgroundColor",
             "textColor",
             "showDate"
           ]
  end

  test "yes watchface template seeds watch protocol phone and preferences" do
    slug = "watchface-yes-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES Watchface",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    base = Projects.project_workspace_path(project)
    assert project.target_type == "watchface"
    assert File.exists?(Path.join(base, "watch/src/Main.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionPreferences.elm"))
    assert File.exists?(Path.join(base, "phone/src/Companion/GeneratedPreferences.elm"))

    assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert String.contains?(watch_main, "RequestUpdate")
    assert String.contains?(watch_main, "ProvideSun")
    assert String.contains?(watch_main, "ProvideWeather")
    assert String.contains?(watch_main, "ProvideWind")
    assert String.contains?(watch_main, "ProvideTide")
    assert String.contains?(watch_main, "Button.onRelease Button.Down RequestRefresh")
    assert String.contains?(watch_main, "model.isRound")

    assert {:ok, protocol_types} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert String.contains?(protocol_types, "type WeatherCondition")
    assert String.contains?(protocol_types, "ProvideLocation Int Int Int")
    assert String.contains?(protocol_types, "type InternetMode")

    assert String.contains?(
             protocol_types,
             "ProvideWeather Int WeatherCondition Int Int Int TemperatureUnit"
           )

    assert String.contains?(protocol_types, "ProvideWind Int Int WindUnit")
    assert String.contains?(protocol_types, "SetUseInternet InternetMode")
    assert String.contains?(protocol_types, "SetUnits TemperatureUnit WindUnit")

    assert {:ok, companion_app} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert String.contains?(companion_app, "Http.get")
    assert String.contains?(companion_app, "GeneratedPreferences.onConfiguration FromBridge")
    assert String.contains?(companion_app, "CompanionPhone.onWatchToPhone FromWatch")
    assert String.contains?(companion_app, "ProvideAltitude")

    assert {:ok, companion_preferences} =
             Projects.read_source_file(project, "phone", "src/CompanionPreferences.elm")

    assert String.contains?(companion_preferences, "Preferences.schema \"YES Watchface\"")
    assert String.contains?(companion_preferences, "Preferences.field \"homeLatitude\"")
    assert String.contains?(companion_preferences, "Preferences.field \"internetMode\"")
    assert String.contains?(companion_preferences, "Preferences.choiceOption Fahrenheit")
    assert String.contains?(companion_preferences, "Preferences.choiceOption MilesPerHour")

    assert {:ok, preferences_schema} = Ide.PebblePreferences.extract(Path.join(base, "phone"))

    assert Enum.flat_map(preferences_schema.sections, & &1.fields) |> Enum.map(& &1.id) == [
             "homeLatitude",
             "homeLongitude",
             "homeTzOffsetMinutes",
             "internetMode",
             "showTide",
             "temperatureUnit",
             "windUnit"
           ]
  end

  test "import project maps watch/protocol/phone directories" do
    source_root =
      Path.join(System.tmp_dir!(), "ide_import_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(source_root, "watch/src"))
    File.mkdir_p!(Path.join(source_root, "protocol/src/Companion"))
    File.mkdir_p!(Path.join(source_root, "phone/src"))
    File.write!(Path.join(source_root, "watch/src/Main.elm"), "module Main exposing (main)")

    File.write!(
      Path.join(source_root, "protocol/src/Companion/Types.elm"),
      "module Companion.Types exposing (..)"
    )

    File.write!(Path.join(source_root, "phone/src/Engine.elm"), "module Engine exposing (..)")

    on_exit(fn -> File.rm_rf(source_root) end)

    assert {:ok, project} =
             Projects.import_project(
               %{
                 "name" => "ImportedMulti",
                 "slug" => "imported-multi",
                 "target_type" => "app"
               },
               source_root
             )

    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")

    assert {:ok, _} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert {:ok, _} = Projects.read_source_file(project, "phone", "src/Engine.elm")
  end

  test "import project without roots falls back to watch root" do
    source_root =
      Path.join(System.tmp_dir!(), "ide_import_watch_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(source_root, "src"))
    File.write!(Path.join(source_root, "elm.json"), "{\"type\":\"application\"}")
    File.write!(Path.join(source_root, "src/Main.elm"), "module Main exposing (main)")

    on_exit(fn -> File.rm_rf(source_root) end)

    assert {:ok, project} =
             Projects.import_project(
               %{
                 "name" => "ImportedWatchOnly",
                 "slug" => "imported-watch-only",
                 "target_type" => "app"
               },
               source_root
             )

    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")

    assert {:error, :enoent} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")
  end

  test "create project writes bundle metadata manifest" do
    slug = "manifest-create-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ManifestCreate",
               "slug" => slug,
               "target_type" => "app"
             })

    manifest_path = Path.join(Projects.project_workspace_path(project), "elm-pebble.project.json")
    assert {:ok, raw} = File.read(manifest_path)
    assert {:ok, decoded} = Jason.decode(raw)
    assert decoded["name"] == "ManifestCreate"
    assert decoded["slug"] == slug
    assert decoded["target_type"] == "app"
    assert decoded["import_path"] == "."
    assert Enum.sort(decoded["source_roots"]) == ["phone", "protocol", "watch"]
    assert decoded["debugger_settings"] == %{}
  end

  test "import project reads bundle metadata and nested import path" do
    source_root =
      Path.join(
        System.tmp_dir!(),
        "ide_import_manifest_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(source_root, "bundle/watch/src"))

    File.write!(
      Path.join(source_root, "bundle/watch/src/Main.elm"),
      "module Main exposing (main)"
    )

    File.write!(
      Path.join(source_root, "elm-pebble.project.json"),
      Jason.encode!(%{
        "schema_version" => 1,
        "name" => "Bundled Import",
        "slug" => "bundled-import",
        "target_type" => "watchface",
        "source_roots" => ["watch", "protocol", "phone"],
        "import_path" => "bundle",
        "debugger_settings" => %{"auto_fire" => %{"watch" => true}}
      })
    )

    on_exit(fn -> File.rm_rf(source_root) end)

    assert {:ok, project} = Projects.import_project(%{}, source_root)
    assert project.name == "Bundled Import"
    assert project.slug == "bundled-import"
    assert project.target_type == "watchface"
    assert project.debugger_settings == %{"auto_fire" => %{"watch" => true}}
    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")
  end

  test "export project creates zip with manifest and sources" do
    slug = "export-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Exportable",
               "slug" => slug,
               "target_type" => "app"
             })

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "src/Main.elm",
               "module Main exposing (main)"
             )

    hidden_build_dir = Path.join(Projects.project_workspace_path(project), "watch/.elmc-build")
    File.mkdir_p!(hidden_build_dir)
    File.write!(Path.join(hidden_build_dir, "generated.c"), "/* generated */")

    assert {:ok, zip_path} = Projects.export_project(project)
    assert File.exists?(zip_path)

    assert {:ok, zip_entries} = :zip.table(String.to_charlist(zip_path))

    file_names =
      zip_entries
      |> Enum.flat_map(fn
        {:zip_file, name, _info, _comment, _offset, _size} ->
          [to_string(name)]

        {:zip_file, name, _info, _comment, _offset, _comp_size, _uncomp_size} ->
          [to_string(name)]

        _other ->
          []
      end)

    assert "elm-pebble.project.json" in file_names
    assert "watch/src/Main.elm" in file_names
    refute "watch/.elmc-build/generated.c" in file_names
  end

  test "debugger lazily boots phone companion when watch sends protocol message" do
    slug = "lazy-companion-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Lazy Companion",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-yes"
             })

    assert {:ok, watch_source} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: watch_source,
               reason: "lazy_companion_boot",
               source_root: "watch"
             })

    companion_model = get_in(reloaded, [:companion, :model]) || %{}
    companion_runtime = Map.get(companion_model, "runtime_model") || %{}

    assert get_in(companion_model, ["elm_introspect", "module"]) == "CompanionApp"
    assert %{"ctor" => "Just", "args" => [settings]} = companion_runtime["settings"]
    assert is_map(settings)
    refute Map.has_key?(settings, "$var")
    assert companion_runtime["errors"] == []
    assert companion_runtime["protocol_message_count"] >= 1
    refute st_has_internal_text_tuple?(reloaded.watch.view_tree)
  end

  defp st_has_internal_text_tuple?(value) do
    value
    |> inspect()
    |> String.contains?("{3, {1")
  end

  defp tree_rel_paths(nodes) do
    Enum.flat_map(nodes, fn node ->
      [node.rel_path | tree_rel_paths(Map.get(node, :children, []))]
    end)
  end
end
