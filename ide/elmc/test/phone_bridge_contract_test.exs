defmodule Elmc.PhoneBridgeContractTest do
  use ExUnit.Case

  test "schema excludes watch-only API areas" do
    schema_path = Path.expand("../../shared/companion-protocol/phone_bridge_v1.json", __DIR__)
    {:ok, schema_json} = File.read(schema_path)
    {:ok, schema} = Jason.decode(schema_json)
    apis = schema["apis"] |> Enum.map(& &1["name"])

    refute "watchInfo" in apis
    refute "light" in apis
    refute "vibes" in apis
    refute "wakeup" in apis
    refute "graphics" in apis
    assert "http" in apis
    assert "storage" in apis
    assert "webSocket" in apis
  end

  test "generated JS bridge dispatches supported operations" do
    python = System.find_executable("python3")
    if is_nil(python), do: flunk("python3 not available for bridge generator test")

    node = System.find_executable("node")
    if is_nil(node), do: flunk("node not available for bridge generator test")

    elmc_root = Path.expand("..", __DIR__)
    repo_root = Path.expand("..", elmc_root)
    schema_path = Path.join(repo_root, "shared/companion-protocol/phone_bridge_v1.json")
    script_path = Path.join(elmc_root, "scripts/generate_phone_bridge.py")
    out_dir = Path.join(__DIR__, "tmp/phone_bridge_contract")
    _ = File.rm_rf(out_dir)
    :ok = File.mkdir_p!(out_dir)

    out_elm = Path.join(out_dir, "GeneratedBridge.elm")
    out_js = Path.join(out_dir, "generated-bridge.js")

    {gen_out, gen_code} = System.cmd(python, [script_path, schema_path, out_elm, out_js])
    assert gen_code == 0, gen_out

    node_script = """
    const bridge = require(process.argv[1]);
    bridge.setHandler("http", "send", (payload) => ({ status: 200, body: payload.url || "" }));
    Promise.resolve(bridge.dispatch({ id: "1", api: "http", op: "send", payload: { url: "https://example.com" } }))
      .then((res1) => {
        const res2 = bridge.dispatch({ id: "2", api: "watchInfo", op: "getModel", payload: {} });
        console.log(JSON.stringify({ res1, res2 }));
      });
    """

    {run_out, run_code} = System.cmd(node, ["-e", node_script, out_js])
    assert run_code == 0, run_out

    {:ok, decoded} = Jason.decode(String.trim(run_out))
    assert decoded["res1"]["ok"] == true
    assert decoded["res1"]["payload"]["status"] == 200
    assert decoded["res2"]["ok"] == false
    assert decoded["res2"]["error"]["type"] == "unsupported_operation"
  end
end
