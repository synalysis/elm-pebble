defmodule Ide.PebbleToolchainCompanionElmWssTest do
  use ExUnit.Case, async: true

  alias Ide.PebbleToolchain

  @template_index Path.expand("../../priv/pebble_app_template/src/pkjs/index.js", __DIR__)
  @template_runtime Path.expand("../../priv/pebble_app_template/src/pkjs/elm-websockets.js", __DIR__)

  test "companion pkjs template gates elm-wss behind companionElmWssEnabled" do
    source = File.read!(@template_index)

    assert source =~ "var companionElmWssEnabled = false;"
    assert source =~ ~s/if (companionElmWssEnabled) {\n    require(".\/elm-websockets.js");/
    assert source =~ "ElmWebsockets.initApp(app)"
    refute source =~ "WebSocket unavailable from this Pebble companion runtime"
    refute source =~ "webSocketPlatformIncoming"
  end

  test "elm-wss runtime uses arraybuffer binary path when Blob is unavailable" do
    source = File.read!(@template_runtime)

    assert source =~ ~s/ws.binaryType = supportsBlobBinary() ? "blob" : "arraybuffer"/
    assert source =~ "arrayBufferView(messageEvent.data)"
    assert source =~ ~s/kind: kind, message: message/
  end

  test "phone_uses_elm_wss? reflects phone elm.json dependency" do
    root = Path.join(System.tmp_dir!(), "elm-wss-detect-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    phone_root = Path.join(root, "phone")
    File.mkdir_p!(Path.join(phone_root, "src"))
    File.write!(Path.join(phone_root, "src/CompanionApp.elm"), "module CompanionApp exposing (main)\n")

    base_elm_json = %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1 <= v < 0.20.0",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5"},
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(
      Path.join(phone_root, "elm.json"),
      Jason.encode!(base_elm_json, pretty: true)
    )

    refute PebbleToolchain.phone_uses_elm_wss?(root)

    with_dep =
      put_in(base_elm_json, ["dependencies", "direct", "mbr/elm-wss"], "2.0.0")

    File.write!(
      Path.join(phone_root, "elm.json"),
      Jason.encode!(with_dep, pretty: true)
    )

    assert PebbleToolchain.phone_uses_elm_wss?(root)
  end

  test "companion index writer enables elm-wss and copies runtime when dependency present" do
    root = Path.join(System.tmp_dir!(), "elm-wss-write-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    app_root = Path.join(root, "app")
    phone_root = Path.join(root, "phone")
    File.mkdir_p!(Path.join(phone_root, "src"))
    File.mkdir_p!(Path.join(app_root, "src/pkjs"))
    File.write!(Path.join(phone_root, "src/CompanionApp.elm"), "module CompanionApp exposing (main)\n")

    elm_json = %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1 <= v < 0.20.0",
      "dependencies" => %{
        "direct" => %{"mbr/elm-wss" => "2.0.0", "elm/core" => "1.0.5"},
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(phone_root, "elm.json"), Jason.encode!(elm_json, pretty: true))

    assert :ok = Ide.PebbleToolchain.Companion.write_index(root, app_root, nil)

    index = File.read!(Path.join(app_root, "src/pkjs/index.js"))
    runtime = File.read!(Path.join(app_root, "src/pkjs/elm-websockets.js"))

    assert index =~ "var companionElmWssEnabled = true;"
    assert index =~ ~s|require("./elm-websockets.js")|
    assert runtime =~ "ElmWebsockets"
  end

  test "companion index writer omits elm-websockets require when dependency absent" do
    root = Path.join(System.tmp_dir!(), "elm-wss-absent-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    app_root = Path.join(root, "app")
    phone_root = Path.join(root, "phone")
    File.mkdir_p!(Path.join(phone_root, "src"))
    File.mkdir_p!(Path.join(app_root, "src/pkjs"))
    File.write!(Path.join(phone_root, "src/CompanionApp.elm"), "module CompanionApp exposing (main)\n")

    elm_json = %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1 <= v < 0.20.0",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5"},
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(phone_root, "elm.json"), Jason.encode!(elm_json, pretty: true))

    assert :ok = Ide.PebbleToolchain.Companion.write_index(root, app_root, nil)

    index = File.read!(Path.join(app_root, "src/pkjs/index.js"))

    assert index =~ "var companionElmWssEnabled = false;"
    refute index =~ ~s|require("./elm-websockets.js")|
    refute File.exists?(Path.join(app_root, "src/pkjs/elm-websockets.js"))
  end
end
