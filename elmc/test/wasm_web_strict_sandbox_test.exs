defmodule Elmc.WasmWebStrictSandboxTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "pure Browser.sandbox fixture compiles with wasm_strict true and no pebble ops" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_strict_sandbox_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_strict_sandbox_project", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, result} =
                 Elmc.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        debug = result[:wasm_debug] || result["wasm_debug"] || %{}
        stubs = Map.get(debug, :stub_functions, Map.get(debug, "stub_functions", []))
        skipped = Map.get(debug, :skipped, Map.get(debug, "skipped", []))

        assert stubs == []
        assert skipped == []

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        refute wat =~ "pebble_cmd"
        refute wat =~ "render_cmd"
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("strict sandbox probe failed:\n#{output}")
            end
        end
    end
  end

  @runner Path.expand("support/wasm_strict_sandbox_probe_runner.mjs", __DIR__)

  defp run_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@runner, [out_dir])

  defp probe_skipped_under_ulimit?(output),
    do: WasmRcTrackHarness.probe_skipped_under_ulimit?(output)

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
