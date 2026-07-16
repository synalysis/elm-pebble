defmodule Elmc.WasmElmPebbleDevGateTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.ElmPebbleDevWasmCompile

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)

  @allowed_server_stubs MapSet.new([])

  @tag :slow
  @tag timeout: 180_000
  test "elm_pebble_dev wasm compile gate: no stubs, no skipped paths, constructor tags present" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      true ->
        out_dir = ElmPebbleDevWasmCompile.compile!(check: true)

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
        assert manifest["entry_export"] == "elmc_fn_Main_main"
        assert is_map(manifest["constructor_tags"]) and manifest["constructor_tags"] != %{}

        stub_functions = ProjectWriter.stub_functions(out_dir)

        unexpected_stubs =
          Enum.reject(stub_functions, fn entry ->
            MapSet.member?(@allowed_server_stubs, {entry["module"], entry["name"]})
          end)

        assert unexpected_stubs == []

        debug_skipped =
          case File.read(ProjectWriter.debug_manifest_path(out_dir)) do
            {:ok, body} -> body |> Jason.decode!() |> Map.get("skipped", [])
            _ -> []
          end

        assert debug_skipped == []

        if System.find_executable("wat2wasm") do
          wat_path = ProjectWriter.wat_path(out_dir)
          wasm_path = Path.join(out_dir, "wasm/app.wasm")
          assert File.regular?(wasm_path)

          assert ExUnit.CaptureIO.capture_io(fn ->
                   {output, code} =
                     System.cmd("wat2wasm", [wat_path, "-o", wasm_path], stderr_to_stdout: true)

                   assert code == 0, "wat2wasm failed:\n#{output}"
                 end)
        end
    end
  end
end
