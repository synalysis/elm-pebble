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

        wat = File.read!(ProjectWriter.wat_path(out_dir))

        # Layout moveTo must pass Float handles into *Centered, not f32.convert_i32_s
        # on the handle id (that produced y≈2700 viewBox origins).
        for export <- ["c20", "c37"] do
          assert wat =~ ~r/\(export "#{export}"\)/, "missing layout moveTo export #{export}"
        end

        refute Regex.match?(
                 ~r/\(export "c20"\)[\s\S]{0,800}?f32\.convert_i32_s/,
                 wat
               ),
               "horizontal moveTo still converts Float handle id via f32.convert_i32_s"

        refute Regex.match?(
                 ~r/\(export "c37"\)[\s\S]{0,800}?f32\.convert_i32_s/,
                 wat
               ),
               "vertical moveTo still converts Float handle id via f32.convert_i32_s"

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
            assert output =~ ~r/viewBox="-?\d+(?:\.\d+)? -?\d+(?:\.\d+)? \d+(?:\.\d+)? \d+(?:\.\d+)?"/
            assert output =~ ~r/height="\d+(?:\.\d+)?"/
            assert output =~ ~r/svg shapes rect=\d+ path=\d+ text=\d+/
            refute output =~ "svg shapes rect=0 path=0 text=0",
                   "expected rendered svg shapes, got:\n#{output}"

            [_, x, y, w, h] =
              Regex.run(~r/viewBox="(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+)"/, output) ||
                [nil, "0.0", "0.0", "0.0", "0.0"]

            parse_f = fn s ->
              case Float.parse(s) do
                {f, _} -> f
                :error -> flunk("bad float #{inspect(s)}")
              end
            end

            # Handle IDs leak as ~25k coords when float List.maximum / min-max is wrong,
            # or when Float args are coerced via f32.convert_i32_s on handle ids.
            assert parse_f.(w) > 10
            assert parse_f.(h) > 10
            assert parse_f.(w) < 5000, "viewBox width looks like a WASM handle: #{w}"
            assert parse_f.(h) < 5000, "viewBox height looks like a WASM handle: #{h}"
            # Layout centering can place lo.y negative; reject handle-sized origins only.
            assert abs(parse_f.(x)) < 500, "viewBox x origin looks wrong: #{x}"
            assert abs(parse_f.(y)) < 500, "viewBox y origin looks wrong: #{y}"
            # Match elm-pages JS TEA diagram geometry (spacing 34 + tie 10).
            # Broken filterMap-identity / bare int `tie 10` produced ~572×204 tall boxes.
            assert_in_delta parse_f.(w), 656.0, 2.0
            assert_in_delta parse_f.(h), 104.0, 2.0
            assert_in_delta parse_f.(x), -2.0, 2.0
            assert_in_delta parse_f.(y), -2.0, 2.0
            assert output =~ ~r/text=\d+/
            refute output =~ ~r/text=0\b/
            # Probe joins all <text> nodes into one label= attribute.
            assert output =~ ~r/label="[^"]*Events/
            assert output =~ ~r/label="[^"]*Update/
            assert output =~ ~r/width="72"/
            refute output =~ ~r/height="0"/
            refute output =~ ~r/width="0"/
            refute output =~ ~r/width="2"/
            # Arrows: JS TEA diagram has 24 paths. Arrowhead geometry must be
            # coherent (headLeft/end/headRight), not as_int(Point) → M0 0 only.
            assert output =~ ~r/path=\d+/
            [_, path_n] = Regex.run(~r/path=(\d+)/, output) || [nil, "0"]
            assert String.to_integer(path_n) >= 20, "expected ~24 arrow paths, got path=#{path_n}"
            # Degenerate as_int(Point) produced every path as "M0 0 C0 0…"; real
            # forEdgeWith stubs may start at local M0 0 but have non-zero end.
            refute output =~ ~r/d="M0 0 C0 0, 0 0, 0 0/,
                   "arrow path still fully origin-degenerate (Point as_int bug)"

            # List.map2 must pass Arrow/Port handles (not newIntHandle/intValue).
            # Broken map2 collapsed connect arrows; only Port stubs remained.
            assert output =~ ~r/path d="M304 45\.25 C326 45\.25, 326 19, 348 19/,
                   "missing Events→Update connect curve (list_map2 handle bug?):\n#{output}"
            assert output =~ ~r/path d="M304 45\.25 C326 45\.25, 326 81, 464 81/,
                   "missing Events→Subscriptions connect curve:\n#{output}"
            assert output =~ ~r/path d="M72 19 C94 19, 94 45\.25, 116 45\.25/,
                   "missing Init→Model connect curve:\n#{output}"

            # Svg.Attributes must emit DOM names from VirtualDom.attribute "…",
            # not Elm helper names (textAnchor).
            assert output =~ ~r/text-anchor="middle"/,
                   "expected centered SVG labels (text-anchor), got:\n#{output}"
            assert output =~ ~r/font-weight="700"/,
                   "expected bold SVG labels (font-weight), got:\n#{output}"
            assert output =~ ~r/font-size="12px"/,
                   "expected 12px label font-size override, got:\n#{output}"
            refute output =~ ~r/textAnchor=/,
                   "camelCase SVG attr textAnchor leaked into DOM:\n#{output}"
            refute output =~ ~r/fontWeight=/,
                   "camelCase SVG attr fontWeight leaked into DOM:\n#{output}"
            refute output =~ ~r/fontSize=/,
                   "camelCase SVG attr fontSize leaked into DOM:\n#{output}"

            # List.member must compare values (strings), not intValue handles —
            # otherwise every cell takes the green else-branch.
            assert output =~ ~r/rect [^\\n]*fill="#eff6ff"/,
                   "expected blue Events/Sub/Cmd boxes, got:\n#{output}"
            assert output =~ ~r/rect [^\\n]*fill="#ecfdf5"/,
                   "expected green Msg/Update boxes, got:\n#{output}"
            assert output =~ ~r/stroke="#2563eb"/,
                   "expected blue stroke on member labels, got:\n#{output}"
            assert output =~ ~r/stroke="#059669"/,
                   "expected green stroke on non-member labels, got:\n#{output}"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              # Node inherits mix-test-limited's RLIMIT_AS; large wasm may OOM under
              # the guard. Soft-skip rather than false-green on empty assertions.
              IO.puts(:stderr, "skip wasm wiring svg probe (instantiate OOM under ulimit)")
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
