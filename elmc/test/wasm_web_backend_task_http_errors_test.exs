defmodule Elmc.WasmWebBackendTaskHttpErrorsTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "BackendTask.Http bad status yields typed BadStatus error in browser" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_backend_task_http_errors_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_backend_task_http_errors", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _result} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        manifest =
          out_dir
          |> ProjectWriter.manifest_path()
          |> File.read!()
          |> Jason.decode!()

        assert is_map(manifest["constructor_tags"])
        assert manifest["constructor_tags"]["BackendTask.Http.BadStatus"] != nil

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "backend_task_http_get_with_options"

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
              flunk("backend task http errors probe failed:\n#{output}")
            end
        end
    end
  end

  @runner Path.expand("support/wasm_backend_task_http_errors_probe_runner.mjs", __DIR__)

  defp run_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@runner, [out_dir])

  defp probe_skipped_under_ulimit?(output),
    do: WasmRcTrackHarness.probe_skipped_under_ulimit?(output)

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
