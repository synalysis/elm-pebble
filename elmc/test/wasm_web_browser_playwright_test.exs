defmodule Elmc.WasmWebBrowserPlaywrightTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.{ElmPebbleDevWasmCompile, ElmPebbleDevWasmServe}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @dist_root Path.expand("../../elm_pebble_dev/dist", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @wasm_build Path.expand("../tmp/elm_pebble_dev_wasm", __DIR__)
  @serve_root Path.expand("tmp/wasm_web_playwright_serve", __DIR__)
  @runner Path.expand("support/wasm_browser_playwright_probe_runner.mjs", __DIR__)
  @expected_title "Elm Pebble | Watch faces & apps in Elm"

  @tag :wasm_execute
  @tag :slow
  @tag :browser
  @tag timeout: 240_000
  test "playwright loads browser.html and renders elm_pebble_dev index route" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not playwright_available?() ->
        :ok

      true ->
        ElmPebbleDevWasmCompile.compile!(check: true)

        ElmPebbleDevWasmServe.prepare_playwright_serve_root!(
          @serve_root,
          @wasm_build,
          @dist_root
        )

        case run_playwright_probe() do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ @expected_title

          {:error, output} ->
            if playwright_missing_browser?(output) do
              :ok
            else
              flunk("playwright browser probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_playwright_probe do
    case System.find_executable("node") do
      nil ->
        {:error, "node not available"}

      node ->
        {output, code} =
          System.cmd(node, [@runner, @serve_root, @expected_title], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp playwright_available? do
    System.find_executable("node") != nil and
      File.regular?(Path.expand("../../elm_pebble_dev/node_modules/playwright/package.json", __DIR__))
  end

  defp playwright_missing_browser?(output) do
    output =~ "playwright not found" or
      output =~ "Executable doesn't exist" or
      output =~ "browserType.launch" or
      output =~ "npx playwright install"
  end
end
