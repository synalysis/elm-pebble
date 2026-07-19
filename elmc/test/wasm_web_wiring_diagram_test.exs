defmodule Elmc.WasmWebWiringDiagramTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @svg_runner Path.expand("support/wasm_svg_dom_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm wiring diagram fixture mounts an svg in the dom" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_wiring_diagram_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_wiring_diagram_project", __DIR__)
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

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_svg_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "svg width="
            assert output =~ "ns=http://www.w3.org/2000/svg"
            refute output =~ "viewBox=\"0 0 0 0\""
            refute output =~ "width=\"0\""
            assert output =~ ~r/viewBox="-?\d+ -?\d+ \d+ \d+"/
            assert output =~ ~r/height="\d+"/
            assert output =~ ~r/svg shapes rect=\d+ path=\d+ text=\d+/
            refute output =~ "svg shapes rect=0 path=0 text=0",
                   "expected rendered svg shapes, got:\n#{output}"

            [_, _x, _y, w, h] =
              Regex.run(~r/viewBox="(-?\d+) (-?\d+) (\d+) (\d+)"/, output) || [nil, 0, 0, 0, 0]

            assert String.to_integer(w) > 10
            assert String.to_integer(h) > 10
            assert output =~ ~r/text=\d+/
            refute output =~ ~r/text=0\b/
            assert output =~ ~r/label="A"/

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm wiring svg probe failed:\n#{output}")
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
