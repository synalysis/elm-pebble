defmodule IdeWeb.WasmEmulatorControllerTest do
  use IdeWeb.ConnCase, async: false

  alias Ide.Projects

  setup do
    previous_wasm = Application.get_env(:ide, Ide.WasmEmulator)
    previous_screenshots = Application.get_env(:ide, Ide.Screenshots)

    root =
      Path.join(System.tmp_dir!(), "elm-pebble-wasm-test-#{System.unique_integer([:positive])}")

    screenshots = Path.join(root, "screenshots")
    assets = Path.join(root, "assets")
    File.mkdir_p!(assets)
    File.mkdir_p!(screenshots)

    Application.put_env(:ide, Ide.WasmEmulator, asset_root: assets)

    Application.put_env(:ide, Ide.Screenshots,
      storage_root: screenshots,
      public_prefix: "/screenshots"
    )

    on_exit(fn ->
      restore_env(Ide.WasmEmulator, previous_wasm)
      restore_env(Ide.Screenshots, previous_screenshots)
      File.rm_rf(root)
    end)

    {:ok, assets: assets}
  end

  test "status reports missing wasm assets", %{conn: conn, assets: assets} do
    conn = get(conn, ~p"/api/wasm-emulator/status")
    body = json_response(conn, 200)

    assert body["available?"] == false
    assert "qemu-system-arm.js" in body["missing"]
    assert "qemu-system-arm.js" in body["runtime_missing"]
    assert "firmware/sdk/qemu_micro_flash.bin" in body["firmware_missing"]
    assert "firmware/sdk/manifest.json" in body["firmware_missing"]
    assert body["install_bridge"]["available?"] == false

    assert body["install_bridge"]["required_api"] ==
             "Module.pebbleInstallPbw(plan), Module.pebbleControlSend(bytes) + Module.pebbleControlRecv(), or _pebble_control_wasm_send/_pebble_control_wasm_recv"

    assert body["firmware"]["sdk"] == nil
    assert body["setup"]["runtime_target"] == assets
    assert body["setup"]["build_command"] == "docker compose run --rm wasm-emulator-builder"
    assert Enum.any?(body["setup"]["notes"], &String.contains?(&1, "wasm-emulator-builder"))
  end

  test "status reports sdk firmware manifest when present", %{conn: conn, assets: assets} do
    firmware_dir = Path.join([assets, "firmware", "sdk"])
    File.mkdir_p!(firmware_dir)
    File.write!(Path.join(firmware_dir, "manifest.json"), ~s({"platform":"basalt"}))

    conn = get(conn, ~p"/api/wasm-emulator/status")
    body = json_response(conn, 200)

    assert body["firmware"]["sdk"]["platform"] == "basalt"
  end

  test "status accepts per-platform sdk firmware manifests", %{conn: conn, assets: assets} do
    firmware_dir = Path.join([assets, "firmware", "sdk", "chalk"])
    File.mkdir_p!(firmware_dir)
    File.write!(Path.join(firmware_dir, "qemu_micro_flash.bin"), "micro")
    File.write!(Path.join(firmware_dir, "qemu_spi_flash.bin"), "spi")

    File.write!(
      Path.join(firmware_dir, "manifest.json"),
      ~s({"platform":"chalk","machine":"pebble-s4-bb","storage":"pflash"})
    )

    conn = get(conn, ~p"/api/wasm-emulator/status")
    body = json_response(conn, 200)

    assert body["firmware_missing"] == []
    assert body["firmware"]["sdk"]["platforms"]["chalk"]["machine"] == "pebble-s4-bb"
  end

  test "wasm page and assets are served with cross-origin isolation headers", %{
    conn: conn,
    assets: assets
  } do
    File.write!(Path.join(assets, "qemu-system-arm.js"), "console.log('ok')")

    page_conn = get(conn, ~p"/wasm-emulator")
    page = response(page_conn, 200)
    assert page =~ "Pebble WASM Emulator"
    assert page =~ "pebbleControlSend"
    assert page =~ "_pebble_control_wasm_send"
    assert page =~ "Writing app metadata to BlobDB"
    assert page =~ "0xaf, 0x29, 0x00, 0x00"
    assert page =~ "BlobDB ${label} insert returned"
    assert page =~ "blobStatusName"
    assert page =~ "0x0020: \"MusicControl\""
    assert page =~ "MusicControl \"get current track\""
    assert page =~ "dumpDebugSerial"
    assert page =~ "decodeDebugSerial"
    assert page =~ "install failure debug serial"
    assert page =~ "watchVersion version="
    assert page =~ "watch-info"
    assert page =~ "maybeRespondToPhoneService"
    assert page =~ "qemuArgsForFirmware"
    assert page =~ "mtdblock"
    assert page =~ "return manifest.storage || \"pflash\";"
    assert page =~ "requiredSpiFlashSize"
    assert page =~ "padded.fill(0xff)"
    assert page =~ "describeDataLoggingPayload"
    assert page =~ "dataLogging command="
    assert page =~ "qemu-control host->watch protocol="
    assert page =~ "BluetoothConnection"
    assert page =~ "0x07d1: \"PingPong\""
    assert page =~ "0x1a7a: \"DataLogging\""
    assert get_resp_header(page_conn, "cross-origin-opener-policy") == ["same-origin"]
    assert get_resp_header(page_conn, "cross-origin-embedder-policy") == ["require-corp"]

    asset_conn = get(build_conn(), "/wasm-emulator/assets/qemu-system-arm.js")
    assert response(asset_conn, 200) == "console.log('ok')"

    assert get_resp_header(asset_conn, "content-type") == [
             "application/javascript"
           ]

    assert get_resp_header(asset_conn, "cross-origin-resource-policy") == ["same-origin"]
    assert get_resp_header(asset_conn, "cache-control") == ["no-store"]

    File.write!(Path.join(assets, "qemu-system-arm.wasm"), "wasm")
    wasm_conn = get(build_conn(), "/wasm-emulator/assets/qemu-system-arm.wasm")
    assert response(wasm_conn, 200) == "wasm"
    assert get_resp_header(wasm_conn, "content-type") == ["application/wasm"]

    assert get_resp_header(page_conn, "cache-control") == ["no-store"]
  end

  test "status detects wasm install bridge marker", %{conn: conn, assets: assets} do
    File.write!(
      Path.join(assets, "qemu-system-arm.js"),
      "Module.pebbleInstallPbw = async bytes => ({ok: true})"
    )

    conn = get(conn, ~p"/api/wasm-emulator/status")
    body = json_response(conn, 200)

    assert body["install_bridge"]["available?"] == true
  end

  test "status detects low level control bridge markers", %{conn: conn, assets: assets} do
    File.write!(
      Path.join(assets, "qemu-system-arm.js"),
      "Module.pebbleControlSend = bytes => {}; Module.pebbleControlRecv = () => null"
    )

    conn = get(conn, ~p"/api/wasm-emulator/status")
    body = json_response(conn, 200)

    assert body["install_bridge"]["available?"] == true
  end

  test "status detects patched C export bridge markers", %{conn: conn, assets: assets} do
    File.write!(
      Path.join(assets, "qemu-system-arm.js"),
      "_pebble_control_wasm_send _pebble_control_wasm_recv"
    )

    conn = get(conn, ~p"/api/wasm-emulator/status")
    body = json_response(conn, 200)

    assert body["install_bridge"]["available?"] == true
  end

  test "workspace emulator page is cross-origin isolated for wasm iframe", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WasmHeaders",
               "slug" => "wasm-headers",
               "target_type" => "app"
             })

    assert {:ok, project} =
             Projects.update_project(project, %{
               "debugger_settings" => %{"emulator_mode" => "wasm"}
             })

    conn = get(conn, ~p"/projects/#{project.slug}/emulator")
    html = html_response(conn, 200)
    assert html =~ "Emulator"
    assert html =~ "data-wasm-launch"
    refute html =~ "data-wasm-stop"
    assert html =~ "data-wasm-status"
    assert html =~ "data-wasm-assets"
    assert html =~ "data-wasm-log"
    assert get_resp_header(conn, "cross-origin-opener-policy") == ["same-origin"]
    assert get_resp_header(conn, "cross-origin-embedder-policy") == ["require-corp"]
  end

  test "screenshot endpoint stores a browser captured png", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WasmShot",
               "slug" => "wasm-shot",
               "target_type" => "app"
             })

    image = "data:image/png;base64," <> Base.encode64(minimal_png())

    conn =
      post(conn, ~p"/api/wasm-emulator/projects/#{project.slug}/screenshot", %{
        "platform" => "emery",
        "image" => image
      })

    body = json_response(conn, 200)
    assert body["status"] == "ok"
    assert body["screenshot"]["emulator_target"] == "emery"
    assert File.regular?(body["screenshot"]["absolute_path"])
  end

  defp restore_env(key, nil), do: Application.delete_env(:ide, key)
  defp restore_env(key, value), do: Application.put_env(:ide, key, value)

  defp minimal_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )
  end
end
