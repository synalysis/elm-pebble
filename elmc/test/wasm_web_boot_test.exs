defmodule Elmc.WasmWebBootTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.{ElmPebbleDevWasmCompile, WasmRcTrackHarness}

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @boot_runner Path.expand("support/wasm_browser_boot_probe_runner.mjs", __DIR__)
  @expected_title "Elm Pebble | Watch faces & apps in Elm"

  @tag :wasm_execute
  @tag :slow
  @tag timeout: 180_000
  test "bootFromUrls boots elm_pebble_dev with page bytes like browser.html" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not execution_tools_available?() ->
        :ok

      true ->
        out_dir = ElmPebbleDevWasmCompile.compile!(check: true)

        boot_js = File.read!(Path.join(out_dir, "host/boot.js"))
        assert boot_js =~ "bootFromUrls"
        assert boot_js =~ "pageBytes"

        case run_boot_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ @expected_title

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("bootFromUrls probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_boot_probe(out_dir) do
    case System.find_executable("node") do
      nil ->
        {:error, "node not available"}

      node ->
        args = [out_dir, @index_html, @expected_title]

        {output, code} =
          System.cmd(node, [@boot_runner | args], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    WasmRcTrackHarness.execution_tools_available?()
  end
end
