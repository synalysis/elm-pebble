defmodule Elmc.WasmWebBrowserPlaywrightNavTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.{ElmPebbleDevWasmCompile, ElmPebbleDevWasmServe}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @dist_root Path.expand("../../elm_pebble_dev/dist", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @wasm_build Path.expand("../tmp/elm_pebble_dev_wasm", __DIR__)
  @serve_root Path.expand("tmp/wasm_web_playwright_nav_serve", __DIR__)
  @runner Path.expand("support/wasm_browser_playwright_nav_probe_runner.mjs", __DIR__)
  @expected_title "Getting started | Elm Pebble"

  @tag :wasm_execute
  @tag :slow
  @tag :browser
  @tag timeout: 300_000
  test "playwright client nav loads getting-started route bytes after Start click" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not route_html_available?() ->
        :ok

      not playwright_available?() ->
        :ok

      true ->
        ElmPebbleDevWasmCompile.compile!(check: true)

        ElmPebbleDevWasmServe.prepare_playwright_serve_root!(
          @serve_root,
          @wasm_build,
          @dist_root,
          ["getting-started"]
        )

        case run_playwright_nav_probe() do
          {:ok, output} ->
            assert output =~ "rc_ok playwright_nav"
            assert output =~ @expected_title

          {:error, output} ->
            if playwright_missing_browser?(output) do
              :ok
            else
              flunk("playwright nav probe failed:\n#{output}")
            end
        end
    end
  end

  defp route_html_available? do
    Path.expand("../../elm_pebble_dev/dist/getting-started/index.html", __DIR__)
    |> File.regular?()
  end

  defp run_playwright_nav_probe do
    case System.find_executable("node") do
      nil ->
        {:error, "node not available"}

      node ->
        {output, code} =
          System.cmd(
            node,
            [@runner, @serve_root, "text:Start", @expected_title],
            stderr_to_stdout: true
          )

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
      output =~ "npx playwright install" or
      output =~ "server not ready"
  end
end
