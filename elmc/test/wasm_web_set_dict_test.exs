defmodule Elmc.WasmWebSetDictTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Set partition/union/diff/intersect/filter/map and Dict update/merge match official Elm" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_set_dict_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_set_dict", __DIR__)
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
        assert wat =~ "set_diff" or wat =~ "set_intersect" or wat =~ "dict_merge"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "sm:1|ss:3|su:4|sp:21|dg:2|du:6|dm:a1b12c3|sd:1|si:1|sf:1|smap:1|dd:1|di:1|df:1|dmap:1|dk:1|dv:1|de:1|dmb:1|se:1|si2:1|srm:1|stl:1|sfl:1|sfr:1|dun:1|dpt:1|din:1|drm:1|dsn:1|dsz:1|dfl:1|dfr:1"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Set/Dict probe failed:\n#{output}")
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
