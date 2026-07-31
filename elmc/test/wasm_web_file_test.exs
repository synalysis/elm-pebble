defmodule Elmc.WasmWebFileTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "web wasm lowers File.Download.string to file download task runtime" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_file_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_file_project", __DIR__)
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
        assert wat =~ "file_download_task"
        assert wat =~ "task_perform"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
