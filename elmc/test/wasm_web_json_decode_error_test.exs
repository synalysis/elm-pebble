defmodule Elmc.WasmWebJsonDecodeErrorTest do
  use ExUnit.Case, async: false

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
                 Elmc.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        manifest =
          out_dir
          |> ProjectWriter.manifest_path()
          |> File.read!()
          |> Jason.decode!()

        assert manifest["constructor_tags"]["Json.Decode.Field"] != nil

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "field `missing`"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("wasm json decode error probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir) do
    WasmRcTrackHarness.run_node_script(@html_runner, [out_dir, "elmc_fn_Main_main"])
  end

  defp probe_skipped_under_ulimit?(output),
    do: WasmRcTrackHarness.probe_skipped_under_ulimit?(output)

  defp execution_tools_available? do
    WasmRcTrackHarness.execution_tools_available?()
  end
end
