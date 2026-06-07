defmodule Ide.PebbleToolchainTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias Ide.PebbleToolchain

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_pebble_toolchain_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "template_app_root_path resolves bundled priv template when config path is stale" do
    original = Application.get_env(:ide, Ide.PebbleToolchain, [])

    Application.put_env(
      :ide,
      Ide.PebbleToolchain,
      Keyword.put(original, :template_app_root, "/nonexistent/build-time/pebble_app_template")
    )

    on_exit(fn -> Application.put_env(:ide, Ide.PebbleToolchain, original) end)

    assert {:ok, path} = PebbleToolchain.template_app_root_path()
    assert File.dir?(path)
    assert String.ends_with?(Path.expand(path), "pebble_app_template")
  end

  test "publish passes app description for non-interactive new app creation" do
    root = Path.join(System.tmp_dir!(), "ide_publish_test_#{System.unique_integer([:positive])}")
    app_root = Path.join(root, "app")
    File.mkdir_p!(app_root)

    pebble_bin = Path.join(root, "pebble")

    File.write!(pebble_bin, """
    #!/bin/sh
    printf '%s\\n' "$@"
    """)

    File.chmod!(pebble_bin, 0o755)

    original = Application.get_env(:ide, Ide.PebbleToolchain, [])
    Application.put_env(:ide, Ide.PebbleToolchain, Keyword.put(original, :pebble_bin, pebble_bin))

    on_exit(fn ->
      Application.put_env(:ide, Ide.PebbleToolchain, original)
      File.rm_rf(root)
    end)

    assert {:ok, result} =
             PebbleToolchain.publish("demo",
               app_root: app_root,
               release_notes: "First release",
               version: "1.0.1",
               description: "Tangram watchface for Pebble",
               screenshots: [
                 Path.join(app_root, "emery_1.png"),
                 Path.join(app_root, "chalk_1.png")
               ]
             )

    assert result.status == :ok
    assert result.output =~ "--version"
    assert result.output =~ "1.0.1"
    assert result.output =~ "--description"
    assert result.output =~ "Tangram watchface for Pebble"
    assert result.output =~ "--screenshots"
    assert result.output =~ "emery_1.png"
    assert result.output =~ "chalk_1.png"
  end

  test "package metadata uses configured release version" do
    source = File.read!("lib/ide/pebble_toolchain.ex")

    assert source =~ "version = package_version(Keyword.get(opts, :version))"
    assert source =~ ~s("version" => version)
    assert source =~ ~s(args ++ ["--version", trimmed])
  end

  test "toolchain stages animation raw resources and resource id header" do
    source = File.read!("lib/ide/pebble_toolchain.ex")
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert source =~ "stage_animation_resources"
    assert source =~ "elm_pebble_animation_resource_id"
    assert template =~ "ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT"
    assert template =~ "ELMC_PEBBLE_DRAW_BITMAP_SEQUENCE_AT"
    assert template =~ "gbitmap_sequence_create_with_resource"
    assert template =~ "bitmap_sequence_normalize_play_count"
    assert template =~ "bitmap_sequence_advance_playback"
    assert template =~ "gbitmap_sequence_update_bitmap_next_frame"
    assert source =~ "ApngPatch.pebble_stage_bytes"
    assert template =~ "PLAY_COUNT_INFINITE"
    assert template =~ "vector_sequence_playable_duration_ms"
    assert template =~ "vector_sequence_frame_at_elapsed"
    assert template =~ "elmc_pebble_invalidate_scene"
    refute template =~ "s_vector_sequence_anim_origin_seq"
    assert template =~ "gdraw_command_frame_get_duration"
  end

  test "emulator packaging writes storage log build flags header" do
    source = File.read!("lib/ide/pebble_toolchain.ex")
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert source =~ "write_emulator_build_flags"
    assert source =~ "elmc_emulator_build_flags.h"
    assert source =~ "ELMC_PEBBLE_EMULATOR_STORAGE_LOGS 1"
    refute source =~ "#define ELMC_PEBBLE_RUNTIME_LOGS 1"
    assert source =~ "emulator_agent_probes"
    assert source =~ "#define ELMC_AGENT_PROBES 0"
    assert source =~ "maybe_build_env_agent_probes"
    assert template =~ ~s(#include "elmc_emulator_build_flags.h")
    assert template =~ "emulator_storage_snapshot_callback"
    assert template =~ "companion_inbox_log"
    assert template =~ "ELMC_DEBUG_STORAGE_OP_SNAPSHOT"
  end

  test "infer_package_target_type follows Pebble.Platform watchface entrypoint" do
    slug = "toolchain-watchface-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Toolchain Watchface",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-digital"
             })

    project_root = Path.join(Projects.project_workspace_path(project), "watch")

    on_exit(fn -> Projects.delete_project(project) end)

    assert PebbleToolchain.infer_package_target_type(project_root, "app") == "watchface"
  end

  test "infer_package_target_type follows Pebble.Platform application entrypoint" do
    slug = "toolchain-application-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Toolchain Application",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "starter"
             })

    project_root = Path.join(Projects.project_workspace_path(project), "watch")

    on_exit(fn -> Projects.delete_project(project) end)

    assert PebbleToolchain.infer_package_target_type(project_root, "watchface") == "app"
  end

  test "generated resource bridge does not reserve Pebble resource id zero" do
    source = File.read!("lib/ide/pebble_toolchain.ex")
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert source =~ "elm_pebble_dev/node_modules/.bin/elm"
    assert source =~ "Enum.with_index(1)"
    assert source =~ "#define ELM_PEBBLE_RESOURCE_ID_MISSING UINT32_MAX"
    assert source =~ "default: return ELM_PEBBLE_RESOURCE_ID_MISSING;"
    assert source =~ "elm_pebble_font_resource_height"
    assert source =~ "\"characterRegex\""
    assert source =~ "\"trackingAdjust\""
    assert source =~ "\"targetPlatforms\""
    assert source =~ "maybe_put_compatibility"
    assert source =~ "maybe_put_capabilities"
    assert source =~ ~s(["location", "configurable", "health"])
    assert template =~ "resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING"
    assert template =~ "font_from_id_for_height"
    refute template =~ "resource_height > requested_height"
    assert template =~ "s_draw_cmd"
    assert template =~ "s_draw_update_active"
    assert template =~ "elmc-draw text pre seq=%d #%d font=%p"
    assert template =~ "elmc-draw text post seq=%d #%d ok"
    assert template =~ "elmc_pebble_scene_commands_next(&s_elm_app, &s_draw_cmd, 1)"
    refute template =~ "malloc(sizeof(ElmcPebbleDrawCmd)"
    assert template =~ "elmc_pebble_scene_reset_draw_cursor"
    assert template =~ "elmc_pebble_scene_commands_next"
    refute template =~ "realloc(s_draw_cmds"
    refute template =~ "resource_id == 0"
  end

  test "Elm companion index queues early appmessages until incoming port is ready" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "var pendingIncoming = [];"
    assert source =~ "function deliverIncoming(payload)"
    assert source =~ "deliverIncoming(normalizeIncomingAppMessage(event.payload));"
    assert source =~ "while (pendingIncoming.length > 0)"
    assert source =~ "incomingPort.send(pendingIncoming.shift());"
    assert source =~ "normalizeIncomingAppMessage(event.payload)"
  end

  test "Elm companion index supports generated configuration pages" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "generatedConfigurationUrl"
    assert source =~ "showConfiguration"
    assert source =~ "webviewclosed"
    assert source =~ "configuration.closed"
    assert source =~ "openConfigurationUrl"
    assert source =~ "configurationStorageKey"
    assert source =~ "readStoredConfigurationResponse"
    assert source =~ "writeStoredConfigurationResponse"
    assert source =~ "configurationResponse: readStoredConfigurationResponse()"
    assert source =~ "elmRoot.CompanionApp.init({ flags: companionFlags() })"
  end

  test "Elm companion index shims PebbleKit XMLHttpRequest for elm/http" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "installXmlHttpRequestCompatibility"
    assert source =~ "proto.addEventListener"
    assert source =~ "this.response = this.responseText"
    assert source =~ "this.response === null"
    assert source =~ "proto.getAllResponseHeaders"
  end

  test "Elm companion index normalizes AppMessage keys in both directions" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "require(\"./companion-protocol.js\")"
    assert source =~ "appMessageKeyNamesById"
    assert source =~ "normalizeIncomingAppMessage"
    assert source =~ "normalizeOutgoingAppMessage"
  end

  test "Elm companion index serializes outgoing AppMessages" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "appMessageOutbox"
    assert source =~ "appMessageSending"
    assert source =~ "sendQueuedAppMessage"
    assert source =~ "drainAppMessageOutbox"
    assert source =~ "Pebble.sendAppMessage = function"
    assert source =~ "setTimeout(drainAppMessageOutbox, 250)"
    refute source =~ "Pebble.sendAppMessage(normalizeOutgoingAppMessage"
  end

  test "Elm companion index serves calendar bridge data from simulator settings" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "companionSimulatorSettings"
    assert source =~ "function companionApplySimulatorSettings(settings)"
    assert source =~ "function handleCalendarCommand(request)"
    assert source =~ ~S/deliverCalendarNext(requestId, events.length > 0 ? events[0] : null)/
    refute source =~ "Calendar data unavailable from this Pebble companion runtime"
  end

  test "Elm companion index serves weather bridge and Http simulator data from settings" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "function handleWeatherCommand(request)"
    assert source =~ "function fetchWeatherFromGeolocation"
    assert source =~ "function companionSupportsWeatherPlatform"
    assert source =~ "function companionSupportsCalendarPlatform"
    assert source =~ "companionSupportsWeatherPlatform() && shouldUseSimulatorWeather()"
    assert source =~ "function weatherFromSettings()"
    assert source =~ "function normalizeCompanionSimulatorSettings("
    assert source =~ "function deliverWeatherToWatch()"
    assert source =~ "function simulatedHttpResponse(method"
    assert source =~ "deliverWeatherCurrent"
    assert source =~ "applyPendingCompanionSimulatorSettings();"
    refute source =~ "deliverWeatherToWatchWithRetry();"
    refute source =~ "if (!applyPendingCompanionSimulatorSettings())"
    assert source =~ "function syncCompanionSimulatorSettingsFromGlobal()"
    assert source =~ "function currentCompanionSimulatorSettings()"
    assert source =~ "__elmPebbleCompanionSimulatorSettings"
    assert source =~ "function applyPendingCompanionSimulatorSettings()"
    assert source =~ "function companionGlobalRoot()"

    assert source =~
             "companionGlobalRoot().companionApplySimulatorSettings = companionApplySimulatorSettings"

    assert source =~ "companionSimulatorSettingsReady"
    assert source =~ "function bootElmCompanionWhenReady"
    assert source =~ "lastDeliveredCompanionWeatherSignature"
    assert source =~ "function deliverWeatherToWatch()"
    assert source =~ "function sendImmediateAppMessage"
    assert source =~ "deliverWeatherToWatch = deliverWeatherToWatch"
    refute source =~ "deliverWeatherToWatch();\n        lastDeliveredCompanionWeatherSignature"
    refute source =~ "requestCompanionWeatherRefresh();"
    refute source =~ "Weather data unavailable from this Pebble companion runtime"
  end

  test "companion build copies full pkjs template with calendar support" do
    source = Ide.PebbleToolchain.companion_index_js_for_preferences(nil)

    assert source =~ "function handleCalendarCommand(request)"
    assert source =~ "function companionApplySimulatorSettings(settings)"
    assert source =~ "var generatedConfigurationUrl = null;"
  end

  test "companion index emits JavaScript null for absent preferences URL" do
    source = Ide.PebbleToolchain.companion_index_js_for_preferences(nil)

    assert source =~ "var generatedConfigurationUrl = null;"
    refute source =~ "generatedConfigurationUrl = undefined"
  end

  test "Platform.setup registers bridge handlers before subscribe commands" do
    source =
      File.read!("priv/bundled_elm/pebble-companion-core-src/Pebble/Companion/Platform.elm")

    {register_at, _} = :binary.match(source, "Phone.registerHandler")
    {subscribe_at, _} = :binary.match(source, "Phone.sendBridgeCommand")
    assert register_at < subscribe_at
  end

  test "companion pkjs routes bridge results before clearing pending ids" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    {deliver_at, _} = :binary.match(source, "deliverPlatformIncoming(envelope);")
    {delete_at, _} = :binary.match(source, "delete pendingBridgeResponseIds[id];")
    assert deliver_at < delete_at
  end

  test "companion pkjs queues platform bridge messages until handlers register" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "pendingUnhandledPlatformMessages"
    assert source =~ "function flushUnhandledPlatformIncoming()"
    assert source =~ "flushUnhandledPlatformIncoming();"
    assert source =~ "function finishCompanionBoot()"
    assert source =~ "setTimeout(function () {"
    assert source =~ "finishCompanionBoot();"
  end

  test "Calendar bridge routes one-shot responses through onCalendar" do
    source =
      File.read!("priv/bundled_elm/pebble-companion-core-src/Pebble/Companion/Calendar.elm")

    assert source =~ ~s/resultIdPrefixes = [ "calendar-" ]/
    assert source =~ ~s/String.startsWith "calendar-next" envelope.id/
    assert source =~ "Cmd.batch"
    assert source =~ "setup"
  end

  test "Pebble bundle includes JavaScript only when PKJS exists" do
    wscript = File.read!("priv/pebble_app_template/wscript")
    app_template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert wscript =~ "if os.path.exists('src/pkjs/index.js')"
    assert wscript =~ "ctx.pbl_bundle(**bundle_args)"

    assert app_template =~
             "#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND || ELMC_PEBBLE_FEATURE_INBOX_EVENTS"
  end

  test "pebble app template initializes Elm after pushing the window once" do
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    init_body =
      case Regex.run(~r/static void init\(void\) \{(.*?)^\}/ms, template) do
        [_, body] -> body
        _ -> flunk("init() body not found in pebble app template")
      end

    push_idx = :binary.match(init_body, "window_stack_push(s_main_window, true);") |> elem(0)
    init_call_idx = :binary.match(init_body, "complete_elm_init();") |> elem(0)

    assert push_idx < init_call_idx

    refute template =~
             ~s/} else {\n    APP_LOG(APP_LOG_LEVEL_ERROR, "elmc_pebble_init failed: %d", rc);\n  }\n\n  window_stack_push(s_main_window, true);/

    assert template =~ "display_bounds"
  end

  test "emulator install wipes before installing" do
    source = File.read!("lib/ide/pebble_toolchain.ex")

    assert source =~ ~S|run_pebble_with_timeout(["wipe"], timeout_seconds, cwd: cwd)|
    assert source =~ "emulator_install_args(emulator_target, package_path)"
    assert source =~ ~S|["install", "--emulator", emulator_target]|
    assert source =~ ~S|--throttle=#{throttle}|
    assert source =~ "ensure_successful_wipe"
  end

  test "external emulator controls dispatch Pebble SDK emu commands" do
    previous_config = Application.get_env(:ide, Ide.PebbleToolchain, [])

    root =
      Path.join(
        System.tmp_dir!(),
        "ide_pebble_toolchain_controls_test_#{System.unique_integer([:positive])}"
      )

    fake_pebble = Path.join(root, "fake_pebble.sh")
    output = Path.join(root, "args.txt")

    File.mkdir_p!(root)

    File.write!(fake_pebble, """
    #!/usr/bin/env bash
    printf '%s\n' "$@" >> #{output}
    """)

    File.chmod!(fake_pebble, 0o755)

    Application.put_env(
      :ide,
      Ide.PebbleToolchain,
      Keyword.put(previous_config, :pebble_bin, fake_pebble)
    )

    on_exit(fn ->
      Application.put_env(:ide, Ide.PebbleToolchain, previous_config)
      File.rm_rf(root)
    end)

    assert {:ok, %{status: :ok}} =
             PebbleToolchain.run_emulator_control("test", "chalk", %{
               "control" => "battery",
               "percent" => "87",
               "charging" => "true"
             })

    assert File.read!(output) =~ "emu-battery\n--emulator\nchalk\n--percent\n87\n--charging\n"
  end

  test "emulator commands expose Linux bzip2 compatibility library path" do
    previous_config = Application.get_env(:ide, Ide.PebbleToolchain, [])

    root =
      Path.join(
        System.tmp_dir!(),
        "ide_pebble_toolchain_compat_test_#{System.unique_integer([:positive])}"
      )

    fake_pebble = Path.join(root, "fake_pebble.sh")
    compat_dir = Path.join(root, "compat")
    host_bzip2 = Path.join(root, "libbz2.so.1")

    File.mkdir_p!(root)
    File.write!(host_bzip2, "")

    File.write!(fake_pebble, """
    #!/usr/bin/env bash
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    """)

    File.chmod!(fake_pebble, 0o755)

    Application.put_env(
      :ide,
      Ide.PebbleToolchain,
      previous_config
      |> Keyword.put(:pebble_bin, fake_pebble)
      |> Keyword.put(:pebble_toolchain_compat_dir, compat_dir)
      |> Keyword.put(:legacy_bzip2_candidates, [Path.join(root, "libbz2.so.1.0")])
      |> Keyword.put(:bzip2_soname_alias_candidates, [host_bzip2])
    )

    on_exit(fn ->
      Application.put_env(:ide, Ide.PebbleToolchain, previous_config)
      File.rm_rf(root)
    end)

    assert {:ok, result} =
             PebbleToolchain.run_screenshot("test", Path.join(root, "screen.png"), "flint")

    assert result.status == :ok
    assert result.output =~ "LD_LIBRARY_PATH=#{compat_dir}"
    assert File.exists?(Path.join(compat_dir, "libbz2.so.1.0"))
  end

  test "deterministic package UUIDs set RFC4122 version and variant bits" do
    source = File.read!("lib/ide/pebble_toolchain.ex")

    assert source =~ "List.update_at(6, &((&1 &&& 0x0F) ||| 0x40))"
    assert source =~ "List.update_at(8, &((&1 &&& 0x3F) ||| 0x80))"
  end

  test "watch-only watchfaces package without a companion protocol schema" do
    slug = "toolchain-analog-watchface-#{System.unique_integer([:positive])}"

    previous_config = Application.get_env(:ide, Ide.PebbleToolchain, [])

    pebble_bin =
      Path.join(
        System.tmp_dir!(),
        "fake_pebble_#{System.unique_integer([:positive])}.sh"
      )

    File.write!(pebble_bin, """
    #!/usr/bin/env bash
    set -e
    if [ "$1" = "build" ]; then
      mkdir -p build
      python3 -c 'import zipfile; z=zipfile.ZipFile("build/app.pbw", "w"); z.writestr("appinfo.json", "{}"); z.close()'
    fi
    """)

    File.chmod!(pebble_bin, 0o755)

    Application.put_env(
      :ide,
      Ide.PebbleToolchain,
      Keyword.put(previous_config, :pebble_bin, pebble_bin)
    )

    on_exit(fn ->
      Application.put_env(:ide, Ide.PebbleToolchain, previous_config)
      File.rm(pebble_bin)
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Toolchain Analog Watchface",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-analog"
             })

    workspace_root = Projects.project_workspace_path(project)
    on_exit(fn -> Projects.delete_project(project) end)

    refute File.exists?(Path.join(workspace_root, "protocol/src/Companion/Types.elm"))
    refute File.exists?(Path.join(workspace_root, "phone/elm.json"))

    assert {:ok, package} =
             PebbleToolchain.package(slug,
               workspace_root: workspace_root,
               target_type: project.target_type,
               project_name: project.name,
               target_platforms: ["chalk"]
             )

    refute package.has_phone_companion

    assert {:ok, package_json} =
             package.app_root
             |> Path.join("package.json")
             |> File.read!()
             |> Jason.decode()

    refute get_in(package_json, ["pebble", "enableMultiJS"])
    refute get_in(package_json, ["pebble", "messageKeys"])
    refute File.exists?(Path.join(package.app_root, "src/pkjs/index.js"))
    refute File.exists?(Path.join(package.app_root, "src/pkjs/companion-protocol.js"))
    refute File.exists?(Path.join(package.app_root, "src/c/generated/companion_protocol.h"))
    refute File.exists?(Path.join(package.app_root, "src/c/generated/companion_protocol.c"))
  end

  test "package falls back to generic renderer for unsupported direct render views" do
    slug = "toolchain-unsupported-direct-render-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Unsupported Direct Render",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-digital"
             })

    workspace_root = Projects.project_workspace_path(project)
    on_exit(fn -> Projects.delete_project(project) end)

    unsupported_main = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        {}


    type Msg
        = NoOp


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( {}, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    view : Model -> Ui.UiNode
    view _ =
        List.filterMap keepCommand [ Ui.clear Color.black ]
            |> Ui.toUiNode


    keepCommand : Ui.RenderOp -> Maybe Ui.RenderOp
    keepCommand command =
        Just command


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    main : Program Decode.Value Model Msg
    main =
        Platform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    assert :ok = Projects.write_source_file(project, "watch", "src/Main.elm", unsupported_main)

    assert {:ok, package} =
             PebbleToolchain.package(slug,
               workspace_root: workspace_root,
               target_type: project.target_type,
               project_name: project.name,
               target_platforms: ["chalk"]
             )

    generated_h = File.read!(Path.join(package.app_root, "src/c/elmc/c/elmc_generated.h"))
    refute generated_h =~ "ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW"
  end

  test "vector resource staging preserves manifest order for elm constructor tags" do
    source = File.read!("lib/ide/pebble_toolchain.ex")

    vector_section =
      source
      |> String.split("defp stage_vector_resources")
      |> Enum.at(1)
      |> String.split("defp stage_")
      |> hd()

    refute vector_section =~ ~s/Enum.sort_by(&to_string(Map.get(&1, "ctor", "")))/
  end

  test "package rejects watch Elm roots with compiler check failures" do
    alias Ide.ProjectTemplates

    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "ide_pebble_toolchain_check_gate_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(workspace_root) end)

    assert :ok = ProjectTemplates.apply_template("watch-demo-health", workspace_root)

    source_path = Path.join([workspace_root, "watch", "src", "Main.elm"])

    source =
      source_path
      |> File.read!()
      |> String.replace(
        "Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 96, w = 136, h = 20 } (String.fromInt model.events)",
        "Ui.textInt Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 96, w = 136, h = 20 } model.events"
      )

    File.write!(source_path, source)

    assert {:error, {:compiler_check_failed, "watch", check_result}} =
             PebbleToolchain.package("watch-demo-health-check-gate",
               workspace_root: workspace_root,
               target_type: "app",
               project_name: "Health Check Gate",
               target_platforms: ["basalt"],
               source_roots: ["watch"]
             )

    assert check_result.status == :error
    assert check_result.error_count >= 1
  end
end
