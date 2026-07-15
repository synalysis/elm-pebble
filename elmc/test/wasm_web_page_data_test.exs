defmodule Elmc.WasmWebPageDataTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @index_html Path.expand("../../elm_pebble_dev/dist/index.html", __DIR__)
  @page_data_runner Path.expand("support/wasm_browser_page_data_probe_runner.mjs", __DIR__)
  @expected_title "Elm Pebble | Watch faces & apps in Elm"

  @tag :wasm_execute
  @tag :slow
  test "elm_pebble_dev web wasm boots pageDataFromJs with the index route title" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@index_html) ->
        :ok

      not execution_tools_available?() ->
        :ok

      true ->
        out_dir = Path.expand("tmp/wasm_web_page_data/elm_pebble_dev", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(@app_root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: false
                 })

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
        assert manifest["entry_export"] == "elmc_fn_Main_main"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_page_data_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ @expected_title

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("elm_pebble_dev page-data probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_page_data_probe(out_dir) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        env =
          System.get_env()
          |> Map.put("ELM_PAGES_INDEX_HTML", @index_html)
          |> Enum.to_list()

        {output, code} =
          System.cmd(node, [@page_data_runner, out_dir], stderr_to_stdout: true, env: env)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
