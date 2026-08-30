defmodule Elmc.WasmWebTimeEveryTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @every_runner Path.expand("support/wasm_time_every_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "Time.every lowers to dom_sub under wasm_strict" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_time_every_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_time_every_project", __DIR__)
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
        assert wat =~ "dom_sub"
        refute wat =~ "pebble_sub"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@every_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "time_every_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Time.every probe failed:\n#{output}")
            end
        end
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
