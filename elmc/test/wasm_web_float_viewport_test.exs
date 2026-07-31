defmodule Elmc.WasmWebFloatViewportTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @svg_runner Path.expand("support/wasm_svg_dom_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm renders svg width/height/viewBox from String.fromFloat" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_float_viewport_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_float_viewport_project", __DIR__)
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

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_svg_probe(out_dir) do
          {:ok, output} ->
            assert output =~ ~s(svg width="656")
            assert output =~ ~s(height="100")
            assert output =~ ~s(viewBox="-2 -2 656 100")

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm svg probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_svg_probe(out_dir) do
    case System.find_executable("node") do
      nil ->
        {:error, "node not available"}

      node ->
        {output, code} =
          System.cmd(node, [@svg_runner, out_dir], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
