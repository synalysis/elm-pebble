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
end
