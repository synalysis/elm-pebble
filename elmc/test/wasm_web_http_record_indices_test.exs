defmodule Elmc.WasmWebHttpRecordIndicesTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter

  @tag :wasm_execute
  test "Http.request emits distinct record field indices 0..6 on param r" do
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

    request_fn =
      wat
      |> String.split("(func $elmc_fn_Http_request", parts: 2)
      |> case do
        [_, rest] ->
          rest
          |> String.split("(func $", parts: 2)
          |> hd()

        _ ->
          flunk("missing Http.request function in WAT")
      end

    indices =
      ~r/call \$runtime_record_get \(i32\.const \d+\) \(local\.get \$reg0\) \(i32\.const (\d+)\)/
      |> Regex.scan(request_fn)
      |> Enum.map(fn [_, idx] -> String.to_integer(idx) end)
      |> Enum.uniq()
      |> Enum.sort()

    assert indices == [0, 1, 2, 3, 4, 5, 6],
           "expected Http.request param field indices 0..6, got #{inspect(indices)}"
  end
end
