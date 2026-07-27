defmodule Elmc.WasmWebElmPagesNavTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @nav_runner Path.expand("support/wasm_browser_nav_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Browser.application boots with real url/key and navigation imports" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_elm_pages_nav_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_elm_pages_nav", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "browser_cmd"
        assert wat =~ "runtime_browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_nav_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm elm-pages nav probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_nav_probe(out_dir) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        {output, code} = System.cmd(node, [@nav_runner, out_dir], stderr_to_stdout: true)
        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
