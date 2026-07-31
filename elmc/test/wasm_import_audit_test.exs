defmodule Elmc.WasmImportAuditTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Wasm.{ProjectWriter, RuntimeImports}

  @fixture Path.expand("fixtures/rc_track_list_project", __DIR__)

  test "runtime imports are defined for all logical builtins" do
    imports = RuntimeImports.all_imports()
    assert length(imports) == length(RuntimeBuiltins.ids())

    Enum.each(imports, fn {_id, name} ->
      assert String.starts_with?(name, "runtime.")
    end)
  end

  test "rc_track list fixture wasm manifest lists imports used by lowering" do
    out_dir = Path.expand("tmp/wasm_import_audit", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             CachedCompile.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary,
               targets: [:wasm],
               wasm_strict: false
             })

    {:ok, json} = File.read(ProjectWriter.manifest_path(out_dir)) |> then(&Jason.decode(elem(&1, 1)))
    imports = Map.get(json, "imports", [])
    assert is_list(imports)
    assert "runtime.list_append" in imports
    refute Enum.any?(imports, &String.contains?(&1, "json"))
  end
end
