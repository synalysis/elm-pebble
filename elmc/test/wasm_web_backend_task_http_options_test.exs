defmodule Elmc.WasmWebBackendTaskHttpOptionsTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "BackendTask.Http.getWithOptions lowers to backend_task_http_get_with_options import" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_backend_task_http_options_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_backend_task_http_options", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, result} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        assert Enum.any?(result.informational_diagnostics, fn diagnostic ->
                 diagnostic["code"] == "browser_http_cache_ignored"
               end)

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "backend_task_http_get_with_options"
        assert wat =~ "backend_task_http_with_metadata"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("backend task http options probe failed:\n#{output}")
            end
        end
    end
  end

  @runner Path.expand("support/wasm_backend_task_http_options_probe_runner.mjs", __DIR__)

  defp run_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@runner, [out_dir])

  defp probe_skipped_under_ulimit?(output),
    do: WasmRcTrackHarness.probe_skipped_under_ulimit?(output)

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
