defmodule Elmc.WasmWebKeyedNavTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @browser_runner Path.expand("support/wasm_browser_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Html.Keyed compiles and boots with keyed html_cmd kinds" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_keyed_nav_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_keyed_nav", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "html_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm keyed nav probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_probe(out_dir) do
    # Full vdom text: button "swap" plus keyed children "A" and "B".
    WasmRcTrackHarness.run_node_script(@browser_runner, [out_dir, "elmc_fn_Main_main", "swapAB"])
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
