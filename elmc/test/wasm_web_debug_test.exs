defmodule Elmc.WasmWebDebugTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Debug.log prints label: value and returns the value" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_debug_log_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_debug/log", __DIR__)
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
        assert wat =~ "debug_log"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ ~s/n: "ok"/

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) or
                 WasmRcTrackHarness.probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("wasm Debug.log probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Debug.toString matches official elm/core for Bool Int unit String Char List Tuple" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_debug_tostring_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_debug/tostring", __DIR__)
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
        assert wat =~ "debug_to_string"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "bt:1|bf:1|i:1|z:1|u:1|s:1|c:1|cv:1|l:1|t:1|t3:1|tn:1|tj:1|t3eq:1|j:1|n:1|ok:1|er:1|set:1|dct:1|arr:1|r:1|ru:1|id:1|rd:1|pr:1|tr:1|jt:1|eq:1"

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) or
                 WasmRcTrackHarness.probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("wasm Debug.toString probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Debug.todo fails with the label instead of returning 0" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_debug_todo_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_debug/todo", __DIR__)
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
        assert wat =~ "debug_todo"

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] in ["Debug", "Elm.Kernel.Debug"] and stub["name"] == "todo"
               end)

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            flunk("Debug.todo should fail, got:\n#{output}")

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) or
                 WasmRcTrackHarness.probe_skipped_under_ulimit?(output) do
              :ok
            else
              assert output =~ "Debug.todo"
              assert output =~ "missing-branch" or output =~ "rc=100"
            end
        end
    end
  end

  defp run_html_probe(out_dir, export_name, expected_text) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        args = [out_dir, export_name, expected_text]

        {output, code} =
          System.cmd(node, [@html_runner | args], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
