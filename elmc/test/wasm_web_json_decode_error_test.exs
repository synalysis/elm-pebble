defmodule Elmc.WasmWebJsonDecodeErrorTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Json.Decode.field errors use structured Error values" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_decode_error_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/decode_error", __DIR__)
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

        assert manifest["constructor_tags"]["Json.Decode.Field"] != nil
        assert manifest["constructor_tags"]["Json.Decode.Failure"] != nil

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "json_decode_error_to_string"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "mf:1|xf:1|pj:1|oo:1|oe:1|os:1|pp:1"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("wasm json decode error probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, expected_text) do
    WasmRcTrackHarness.run_node_script(@html_runner, [out_dir, "elmc_fn_Main_main", expected_text])
  end

  defp probe_skipped_under_ulimit?(output),
    do: WasmRcTrackHarness.probe_skipped_under_ulimit?(output)

  defp execution_tools_available? do
    WasmRcTrackHarness.execution_tools_available?()
  end
end
