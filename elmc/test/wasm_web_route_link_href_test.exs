defmodule Elmc.WasmWebRouteLinkHrefTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.{ElmPebbleDevWasmCompile, WasmRcTrackHarness}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @runner Path.expand("support/wasm_route_link_href_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  @tag :slow
  @tag timeout: 180_000
  test "elm_pebble_dev Route.link hrefs match routeToPath for nav anchors" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not WasmRcTrackHarness.execution_tools_available?() ->
        :ok

      true ->
        out_dir = ElmPebbleDevWasmCompile.compile!(check: true)
        env = %{"ELM_PAGES_INDEX_HTML" => @index_html}

        case WasmRcTrackHarness.run_node_script(@runner, [out_dir], env: env) do
          {:ok, output} ->
            assert output =~ "rc_ok route_link_hrefs="

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("route link href probe failed:\n#{output}")
            end
        end
    end
  end
end
