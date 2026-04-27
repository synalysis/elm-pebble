defmodule Elmc.PhoneBridgeGeneratorTest do
  use ExUnit.Case

  test "generates Elm and JS bridge files from schema" do
    python = System.find_executable("python3")
    if is_nil(python), do: flunk("python3 not available for bridge generator test")

    elmc_root = Path.expand("..", __DIR__)
    repo_root = Path.expand("..", elmc_root)
    schema_path = Path.join(repo_root, "shared/companion-protocol/phone_bridge_v1.json")
    script_path = Path.join(elmc_root, "scripts/generate_phone_bridge.py")
    out_dir = Path.join(__DIR__, "tmp/phone_bridge_generator")
    _ = File.rm_rf(out_dir)
    :ok = File.mkdir_p!(out_dir)

    out_elm = Path.join(out_dir, "GeneratedBridge.elm")
    out_js = Path.join(out_dir, "generated-bridge.js")

    {out, code} = System.cmd(python, [script_path, schema_path, out_elm, out_js])
    assert code == 0, out

    {:ok, elm_source} = File.read(out_elm)
    {:ok, js_source} = File.read(out_js)

    assert String.contains?(elm_source, "port module Pebble.Companion.GeneratedBridge")
    assert String.contains?(elm_source, "type Command")
    assert String.contains?(elm_source, "decodeResult")

    assert String.contains?(js_source, "const Bridge =")
    assert String.contains?(js_source, "\"http.send\"")
    assert String.contains?(js_source, "replyFailure")
  end
end
