defmodule Elmc.WasmWebHttpRecordIndicesTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter

  @tag :wasm_execute
  test "Http.post intercepts to http_command (no leftover Http.request body)" do
    root = Path.expand("fixtures/wasm_web_http_post_project", __DIR__)
    out_dir = Path.expand("tmp/wasm_web_http_record_indices", __DIR__)
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

    assert wat =~ "$runtime_http_command"
    refute wat =~ "(func $elmc_fn_Http_request"
    assert wat =~ "call $runtime_http_command"
  end
end
