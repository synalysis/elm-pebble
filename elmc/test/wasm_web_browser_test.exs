defmodule Elmc.WasmWebBrowserTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @browser_runner Path.expand("support/wasm_browser_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm boots Browser.sandbox program and renders view" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_browser_sandbox_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_browser/sandbox", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()

        refute Enum.any?(manifest["stub_functions"] || [], fn stub ->
                 stub["module"] == "Elm.Kernel.Browser"
               end)

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "browser_cmd"
        assert wat =~ "runtime_browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_browser_probe(out_dir, "elmc_fn_Main_main", "sandbox ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm browser probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_browser_probe(out_dir, export_name, expected_text) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        args = [out_dir, export_name, expected_text]

        {output, code} =
          System.cmd(node, [@browser_runner | args], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
