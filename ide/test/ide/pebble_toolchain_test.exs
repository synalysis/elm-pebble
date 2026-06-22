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

  defp toolchain_impl_source do
    [
      Ide.PebbleToolchain.Package,
      Ide.PebbleToolchain.Build,
      Ide.PebbleToolchain.Command,
      Ide.PebbleToolchain.Companion,
      Ide.PebbleToolchain.Elmc,
      Ide.PebbleToolchain.Emulator,
      Ide.PebbleToolchain.Prepare
    ]
    |> Enum.map_join("\n", fn module ->
      module.module_info(:compile)
      |> Keyword.fetch!(:source)
      |> to_string()
      |> File.read!()
    end)
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
    source = toolchain_impl_source()

    assert source =~ "version = package_version(Keyword.get(opts, :version))"
    assert source =~ ~s("version" => version)
    assert source =~ ~s(args ++ ["--version", trimmed])
  end

  test "toolchain stages animation raw resources and resource id header" do
    source = toolchain_impl_source()
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
    source = toolchain_impl_source()
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert source =~ "write_emulator_build_flags"
    assert source =~ "elmc_emulator_build_flags.h"
    assert source =~ "ELMC_PEBBLE_EMULATOR_STORAGE_LOGS 1"
    assert source =~ "emulator_heap_log"
    assert source =~ "ELMC_PEBBLE_HEAP_LOG 1"
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
    source = toolchain_impl_source()
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
    assert source =~ "companionWatchAppReady"
    assert source =~ "markCompanionWatchAppReady"
    assert source =~ "APP_MESSAGE_MAX_RETRIES"
    assert source =~ "sendQueuedAppMessage"
    assert source =~ "drainAppMessageOutbox"
    assert source =~ "Pebble.sendAppMessage = function"
    assert source =~ "setTimeout(drainAppMessageOutbox, 250)"
    assert source =~ "sendAppMessage giving up after retries"
    refute source =~ "setTimeout(drainAppMessageOutbox, 150)"
    refute source =~ "Pebble.sendAppMessage(normalizeOutgoingAppMessage"
  end

  test "Elm companion index defers phone-to-watch AppMessages until watch app is ready" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "settings.watchAppRunning === true"
    assert source =~ "Object.keys(settings).length === 1"
    assert source =~ ~S/markCompanionWatchAppReady("simulator_settings")/
    refute source =~ "requestCompanionWeatherRefresh();"
    assert source =~ ~S/markCompanionWatchAppReady("watch_appmessage")/
    assert source =~ "scheduleCompanionWatchReadyBootTimeout"
    assert source =~ "COMPANION_WATCH_READY_BOOT_TIMEOUT_MS"
    assert source =~ "wirePhoneToWatchFromElmPayload"
  end

  test "watch companion resync retries cover phone companion reload window" do
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert template =~ "companion_resync_delays_ms"
    assert template =~ "3000"
    assert template =~ "10000"
    assert template =~ "companion_resync_callback"
    assert template =~ "s_inbox_snapshot_count >= 1"
  end

  test "weather animated companion subscribes to weather bridge responses" do
    companion =
      File.read!("priv/project_templates/watchface_weather_animated/phone/src/CompanionApp.elm")

    assert companion =~ "Weather.onCurrent"
    assert companion =~ "Weather.current"
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
    assert source =~ "function companionSupportsWeatherPlatform()"
    assert source =~ "function shouldUseSimulatorWeather()"
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
    assert source =~ "function deliverWeatherToWatch()"
    assert source =~ "function sendImmediateAppMessage"
    assert source =~ "deliverWeatherToWatch = deliverWeatherToWatch"
    refute source =~ "companion weather apply"
    refute source =~ "deliverWeatherToWatch();"
    refute source =~ "finishCompanionBoot();\n    requestCompanionWeatherRefresh"
    refute source =~ "function requestCompanionWeatherRefresh"
    refute source =~ "Weather data unavailable from this Pebble companion runtime"
  end

  test "Elm companion index queues deferred weather AppMessages until simulator settings ready" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "Elm companion weather AppMessage deferred until simulator settings ready"
    assert source =~ "appMessageOutbox.push(companionPhoneToWatchWirePayload(payload || {}));"
    assert source =~ "markCompanionSimulatorSettingsReady"
    assert source =~ "drainAppMessageOutbox();"
  end

  test "Elm companion index only defers weather AppMessages by payload shape, not wire tag" do
    source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    assert source =~ "function isCompanionWeatherAppMessage(payload)"
    assert source =~ "provide_temperature_field1_tag"
    assert source =~ "provide_temperature_field1_value"
    assert source =~ "provide_condition_field1"
    refute source =~ "return tag === 201 || tag === 202;"
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

  test "pebble app template runs startup cmds after init completes" do
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

    assert template =~ "s_startup_cmds_ready = true;"
    assert template =~ "if (!s_startup_cmds_ready)"
    refute template =~ "complete_elm_init();\n    apply_pending_cmd();"
    refute template =~ "drain_startup_init_cmds"

    startup_body =
      case Regex.run(~r/static void startup_cmd_callback\(void \*data\) \{(.*?)^\}/ms, template) do
        [_, body] -> body
        _ -> flunk("startup_cmd_callback body not found")
      end

    assert startup_body =~ "apply_pending_cmd();"
    refute startup_body =~ "elmc_pebble_ensure_scene(&s_elm_app);"
    assert startup_body =~ "s_startup_cmds_ready = true;"
    assert startup_body =~ "startup_render_callback"
    refute startup_body =~ "render_model();"
    refute template =~ "startup_build_scene"
    refute template =~ "elmc_pebble_reserve_startup_scene"
    assert template =~ "static ElmcPebbleCmd cmd;"

    draw_body =
      case Regex.run(
             ~r/static void draw_update_proc\(Layer \*layer, GContext \*ctx\) \{(.*?)^\}/ms,
             template
           ) do
        [_, body] -> body
        _ -> flunk("draw_update_proc body not found")
      end

    refute draw_body =~ "elmc_pebble_ensure_scene(&s_elm_app);"
    assert template =~ "schedule_scene_prep"
    assert template =~ "scene_prep_timer_callback"
    assert template =~ "app_timer_register(100, scene_prep_timer_callback, NULL)"
    assert template =~ "if (s_elm_app.scene.dirty)"

    assert draw_body =~ "bounds.size.w < compile.size.w || bounds.size.h < compile.size.h"
    assert template =~ "startup_cmd_callback(NULL);"

    complete_elm_init_body =
      case Regex.run(~r/static void complete_elm_init\(void\) \{(.*?)^\}/ms, template) do
        [_, body] -> body
        _ -> flunk("complete_elm_init() body not found in pebble app template")
      end

    assert complete_elm_init_body =~ "startup_cmd_callback(NULL);"
    refute complete_elm_init_body =~ "app_timer_register(1, startup_cmd_callback, NULL);"
  end

  test "pebble app template applies antialiased style and disables mono stroke dither" do
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert template =~ "graphics_context_set_antialiased(ctx, style->antialiased);"

    assert template =~
             "#ifndef PBL_COLOR\n          graphics_context_set_antialiased(ctx, false);\n          rect_sw = 2;\n          graphics_context_set_stroke_width(ctx, rect_sw);\n#endif\n          graphics_context_set_stroke_color(ctx, color_from_code(cmd->p4));\n          graphics_draw_rect(ctx, stroke_outline_rect_bounds(x, y, w, h, rect_sw));"

    assert template =~
             "#ifndef PBL_COLOR\n        graphics_context_set_antialiased(ctx, false);\n#endif\n        graphics_draw_text(ctx, cmd->text, font, text_rect, overflow, align, NULL);"
  end

  test "pebble app template mono color_from_code uses luminance not GColor8 ordinals" do
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert template =~ "int luminance = (red * 30 + green * 59 + blue * 11) / 100;"
    refute template =~ "GColor8DarkGray"
    refute template =~ "code <= 0x55"
  end

  test "pebble app template launch context uses compile display bounds" do
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    launch_body =
      case Regex.run(
             ~r/static ElmcValue \*build_launch_context\(AppLaunchReason launch\) \{(.*?)^\}/ms,
             template
           ) do
        [_, body] -> body
        _ -> flunk("build_launch_context body not found")
      end

    assert launch_body =~ "GRect bounds = compile_display_bounds();"
    refute launch_body =~ "GRect bounds = display_bounds();"
    assert launch_body =~ "elmc_record_new_values_take_value(4, screen_values)"
    assert launch_body =~ "screen_values[] = {screen_width, screen_height, screen_shape, screen_color_mode}"
    assert launch_body =~ "ELMC_PLATFORM_COLOR_CAPABILITY_COLOR"
    assert launch_body =~ "context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,"
  end

  test "pebble app template draw layer and display_bounds prefer compile size when root layer is undersized" do
    template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    window_load_body =
      case Regex.run(~r/static void main_window_load\(Window \*window\) \{(.*?)^\}/ms, template) do
        [_, body] -> body
        _ -> flunk("main_window_load body not found")
      end

    assert window_load_body =~ "GRect bounds = compile_display_bounds();"

    display_bounds_body =
      case Regex.run(~r/static GRect display_bounds\(void\) \{(.*?)^\}/ms, template) do
        [_, body] -> body
        _ -> flunk("display_bounds body not found")
      end

    assert display_bounds_body =~ "display bounds undersized"
    assert display_bounds_body =~ "layer.size.w < compile.size.w || layer.size.h < compile.size.h"
  end

  test "emulator install wipes before installing" do
    source = toolchain_impl_source()

    assert source =~ ~S|Command.run_pebble_with_timeout(["wipe"], timeout_seconds, cwd: cwd)|
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
    source = toolchain_impl_source()

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
    source = toolchain_impl_source()

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

  test "elm_bin prefers a working compiler over a broken asdf shim" do
    alias Ide.PebbleToolchain.Command

    bundled = Command.bundled_elm_bin()
    assert File.exists?(bundled), "bundled elm is not installed; run npm install in elm_pebble_dev"

    shim_dir =
      Path.join(
        System.tmp_dir!(),
        "ide_elm_bin_shim_#{System.unique_integer([:positive])}"
      )

    shim_path = Path.join(shim_dir, "elm")
    File.mkdir_p!(shim_dir)

    File.write!(shim_path, """
    #!/bin/sh
    echo "No version is set for command elm" 1>&2
    exit 126
    """)

    File.chmod!(shim_path, 0o755)

    original = Application.get_env(:ide, Ide.PebbleToolchain, [])
    original_path = System.get_env("PATH")
    original_elm_bin = System.get_env("ELM_BIN")

    Application.put_env(:ide, Ide.PebbleToolchain, Keyword.put(original, :elm_bin, nil))
    System.put_env("ELM_BIN", "")
    System.put_env("PATH", "#{shim_dir}:#{original_path}")

    on_exit(fn ->
      Application.put_env(:ide, Ide.PebbleToolchain, original)

      if is_binary(original_path), do: System.put_env("PATH", original_path), else: System.delete_env("PATH")

      if is_binary(original_elm_bin),
        do: System.put_env("ELM_BIN", original_elm_bin),
        else: System.delete_env("ELM_BIN")

      File.rm_rf(shim_dir)
    end)

    assert {:ok, resolved} = Command.elm_bin()
    assert Path.expand(resolved) == Path.expand(bundled)
  end
end
