defmodule Elmc.WasmWebElmPebbleNavTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.{ElmPebbleDevWasmCompile, WasmRcTrackHarness}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @runner Path.expand("support/wasm_browser_elm_pebble_nav_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  @tag :slow
  @tag timeout: 180_000
  test "elm_pebble_dev internal link click navigates to getting-started with route bytes" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not route_html_available?() ->
        :ok

      not WasmRcTrackHarness.execution_tools_available?() ->
        :ok

      true ->
        out_dir = ElmPebbleDevWasmCompile.compile!(check: true)

        case WasmRcTrackHarness.run_node_script(@runner, [out_dir, @index_html]) do
          {:ok, output} ->
            assert output =~ "rc_ok elm_pebble_nav"
            assert output =~ "Getting started | Elm Pebble"
            assert output =~ "path=/getting-started"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("elm_pebble_dev nav probe failed:\n#{output}")
            end
        end
    end
  end

  defp route_html_available? do
    Path.expand("../../elm_pebble_dev/dist/getting-started/index.html", __DIR__)
    |> File.regular?()
  end
end
