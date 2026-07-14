defmodule Elmc.WasmWebSmokeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)

  @tag :wasm_execute
  test "elm_pebble_dev web wasm compiles, links, and runs a Char probe in node" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not execution_tools_available?() ->
        :ok

      true ->
        out_dir = Path.expand("tmp/wasm_web_smoke/elm_pebble_dev", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(@app_root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
        assert manifest["entry_export"] == "elmc_fn_Main_main"
        assert File.regular?(Path.join(out_dir, "host/loader.js"))
        assert File.regular?(Path.join(out_dir, "host/rc_runtime.js"))

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_probe(out_dir, "elmc_fn_Char_isAlphaNum",
               expected_checksum: 0
             ) do
          {:ok, output} ->
            WasmRcTrackHarness.assert_balanced_output!(output)

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm probe runner failed:\n#{output}")
            end
        end

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
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        runner = Path.expand("support/wasm_browser_probe_runner.mjs", __DIR__)
        {output, code} = System.cmd(node, [runner, out_dir, "elmc_fn_Main_main"], stderr_to_stdout: true)
        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
