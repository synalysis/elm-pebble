defmodule Elmc.WasmWebPageDataTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.{ElmPebbleDevWasmCompile, WasmRcTrackHarness}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @page_data_runner Path.expand("support/wasm_browser_page_data_probe_runner.mjs", __DIR__)
  @expected_title "Elm Pebble | Watch faces & apps in Elm"

  @tag :wasm_execute
  @tag :slow
  @tag timeout: 180_000
  test "elm_pebble_dev web wasm boots pageDataFromJs with the index route title" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not execution_tools_available?() ->
        :ok

      true ->
        out_dir = ElmPebbleDevWasmCompile.compile!(check: true)

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
        assert manifest["entry_export"] == "elmc_fn_Main_main"

        env = %{"ELM_PAGES_INDEX_HTML" => @index_html}

        case WasmRcTrackHarness.run_node_script(@page_data_runner, [out_dir], env: env) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ @expected_title

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("elm_pebble_dev page-data probe failed:\n#{output}")
            end
        end
    end
  end

  defp execution_tools_available? do
    WasmRcTrackHarness.execution_tools_available?()
  end
end
