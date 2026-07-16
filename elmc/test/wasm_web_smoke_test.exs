defmodule Elmc.WasmWebSmokeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.{ElmPebbleDevWasmCompile, WasmRcTrackHarness}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @export_all_out Path.expand("../tmp/elm_pebble_dev_wasm_export_all", __DIR__)

  @tag :wasm_execute
  @tag :slow
  @tag timeout: 180_000
  test "elm_pebble_dev web wasm compiles, links, and boots Main in node" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not execution_tools_available?() ->
        :ok

      true ->
        out_dir =
          ElmPebbleDevWasmCompile.compile!(
            export_all: true,
            out_dir: @export_all_out
          )

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
        assert manifest["entry_export"] == "elmc_fn_Main_main"
        refute manifest["minified"] == true
        assert File.regular?(Path.join(out_dir, "host/loader.js"))
        assert File.regular?(Path.join(out_dir, "host/rc_runtime.js"))
        assert File.regular?(Path.join(out_dir, "host/json_runtime.js"))
        assert File.regular?(Path.join(out_dir, "host/bytes_runtime.js"))

        case run_browser_main_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("elm_pebble_dev browser main probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_browser_main_probe(out_dir) do
    runner = Path.expand("support/wasm_browser_probe_runner.mjs", __DIR__)
    WasmRcTrackHarness.run_node_script(runner, [out_dir, "elmc_fn_Main_main"])
  end

  defp execution_tools_available? do
    WasmRcTrackHarness.execution_tools_available?()
  end
end
