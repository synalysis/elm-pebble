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
    assert template =~ "resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING"
    assert template =~ "font_from_id_for_height"
    assert template =~ "static ElmcPebbleDrawCmd *s_draw_cmds = NULL;"
    assert template =~ "ensure_draw_capacity"
    assert template =~ "realloc(s_draw_cmds"
    refute template =~ "resource_id == 0"
  end

  test "Elm companion index queues early appmessages until incoming port is ready" do
    generated_source = File.read!("lib/ide/pebble_toolchain.ex")
    template_source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    for source <- [generated_source, template_source] do
      assert source =~ "var pendingIncoming = [];"
      assert source =~ "function deliverIncoming(payload)"
      assert source =~ "deliverIncoming(normalizeIncomingAppMessage(event.payload));"
      assert source =~ "while (pendingIncoming.length > 0)"
      assert source =~ "incomingPort.send(pendingIncoming.shift());"
      assert source =~ "normalizeIncomingAppMessage(event.payload)"
    end
  end

  test "Elm companion index supports generated configuration pages" do
    generated_source = File.read!("lib/ide/pebble_toolchain.ex")
    template_source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    for source <- [generated_source, template_source] do
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
  end

  test "Elm companion index shims PebbleKit XMLHttpRequest for elm/http" do
    generated_source = File.read!("lib/ide/pebble_toolchain.ex")
    template_source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    for source <- [generated_source, template_source] do
      assert source =~ "installXmlHttpRequestCompatibility"
      assert source =~ "proto.addEventListener"
      assert source =~ "this.response = this.responseText"
      assert source =~ "this.response === null"
      assert source =~ "proto.getAllResponseHeaders"
    end
  end

  test "Elm companion index normalizes AppMessage keys in both directions" do
    generated_source = File.read!("lib/ide/pebble_toolchain.ex")
    template_source = File.read!("priv/pebble_app_template/src/pkjs/index.js")

    for source <- [generated_source, template_source] do
      assert source =~ "require(\"./companion-protocol.js\")"
      assert source =~ "appMessageKeyNamesById"
      assert source =~ "normalizeIncomingAppMessage"
      assert source =~ "normalizeOutgoingAppMessage"
    end
  end

  test "Elm companion index emits JavaScript null for absent preferences URL" do
    source = File.read!("lib/ide/pebble_toolchain.ex")

    assert source =~ "Jason.encode!(preferences_url)"
    refute source =~ "generatedConfigurationUrl = \#{inspect(preferences_url)}"
  end

  test "Pebble bundle includes JavaScript only when PKJS exists" do
    wscript = File.read!("priv/pebble_app_template/wscript")
    app_template = File.read!("priv/pebble_app_template/src/c/pebble_app_template.c")

    assert wscript =~ "if os.path.exists('src/pkjs/index.js')"
    assert wscript =~ "ctx.pbl_bundle(**bundle_args)"

    assert app_template =~
             "#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND || ELMC_PEBBLE_FEATURE_INBOX_EVENTS"
  end

  test "emulator install wipes before installing" do
    source = File.read!("lib/ide/pebble_toolchain.ex")

    assert source =~ ~S|run_pebble_with_timeout(["wipe"], timeout_seconds, cwd: cwd)|
    assert source =~ ~S|["install", "--emulator", emulator_target, package_path]|
    assert source =~ "ensure_successful_wipe"
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
      touch build/app.pbw
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
end
