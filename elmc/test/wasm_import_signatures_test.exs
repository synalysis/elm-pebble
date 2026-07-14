defmodule Elmc.WasmImportSignaturesTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter

  @fixture Path.expand("fixtures/rc_track_list_project", __DIR__)

  test "list_append import declares three i32 params" do
    out_dir = Path.expand("tmp/wasm_import_signatures", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary,
               targets: [:wasm],
               wasm_strict: false
             })

    wat = File.read!(ProjectWriter.wat_path(out_dir))

    assert wat =~ "(import \"runtime\" \"list_append\" (func $runtime_list_append (param i32 i32 i32) (result i32))"

    refute wat =~ "(import \"runtime\" \"list_append\" (func $runtime_list_append (param i32 i32) (result i32))"

    {:ok, manifest} = File.read(ProjectWriter.manifest_path(out_dir)) |> then(&Jason.decode(elem(&1, 1)))
    sig = get_in(manifest, ["import_signatures", "runtime.list_append"])
    assert sig == %{"params" => 3, "results" => 1}
    assert manifest["export_signature"] == %{"results" => 2}
  end

  test "wasm-only compile writes pruned runtime from manifest imports" do
    out_dir = Path.expand("tmp/wasm_runtime_prune", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary,
               targets: [:wasm],
               wasm_strict: false
             })

    runtime_c = Path.join(out_dir, "runtime/elmc_runtime.c")
    assert File.regular?(runtime_c)
    source = File.read!(runtime_c)
    assert source =~ "elmc_list_append"
    refute source =~ "elmc_json_decode"
  end

  test "runtime import calls pad to declared max arity for wat2wasm" do
    fixture = Path.expand("fixtures/rc_track_char_project", __DIR__)
    out_dir = Path.expand("tmp/wasm_import_padding", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary,
               targets: [:wasm]
             })

    wat_path = ProjectWriter.wat_path(out_dir)
    wasm_path = Path.join(out_dir, "wasm/elmc_generated.wasm")
    assert File.regular?(wat_path)

    case System.cmd("wat2wasm", [wat_path, "-o", wasm_path], stderr_to_stdout: true) do
      {_, 0} ->
        assert File.regular?(wasm_path)

      {output, _} ->
        flunk("wat2wasm failed after import padding:\n#{String.slice(output, 0, 2000)}")
    end
  end
end
