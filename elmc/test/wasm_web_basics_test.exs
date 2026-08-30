defmodule Elmc.WasmWebBasicsTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "Basics degrees radians modBy and Bitwise match official elm/core" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_basics_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_basics", __DIR__)
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
        assert wat =~ "basics_degrees"
        assert wat =~ "bitwise_and"
        assert wat =~ "basics_is_nan"
        assert wat =~ "basics_round"
        assert wat =~ "basics_compare"
        assert wat =~ "basics_to_polar"
        assert wat =~ "basics_atan2"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "deg:1|rad:1|trn:1|pol:1|tp:1|sn:1|at2:1|mb:1|mn:1|mbn:1|mbnn:1|rb:1|cl:1|mm:1|ba:1|bo:1|bx:1|bc:1|bl:1|br:1|bz:1|id:1|alw:1|nt:1|xr:1|ng:1|ab:1|tf:1|rd:1|flr:1|ce:1|tr:1|nan:1|inf:1|lb:1|sq:1|cmp:1|ord:1"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Basics probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, expected_text) do
    WasmRcTrackHarness.run_node_script(@html_runner, [out_dir, "elmc_fn_Main_main", expected_text])
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
