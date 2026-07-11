defmodule Elmc.BytecodeProjectWriterTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.{Loader, Lower, ProjectWriter}

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "emits bytecode manifest and sections when plan_ir_mode is shadow" do
    out_dir = Path.expand("tmp/bytecode_project_writer", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow
             })

    manifest_path = ProjectWriter.manifest_path(out_dir)
    assert File.exists?(manifest_path)

    {:ok, manifest} = Loader.load_manifest(manifest_path)
    assert manifest["contract"] == "elmc.bytecode_manifest.v1"
    assert manifest["version"] == Lower.manifest_version()
    assert manifest["plan_toolchain"] == %{"mode" => "shadow", "strict" => false}

    functions = manifest["functions"]
    assert is_list(functions)
    assert length(functions) > 0

    assert Enum.any?(functions, &(&1["module"] == "Main" and &1["name"] == "init"))
    assert Enum.any?(functions, &(&1["module"] == "Main" and &1["name"] == "drawCell"))

    for %{"file" => file} <- functions, file != nil do
      path = Path.join([out_dir, "bytecode", file])
      assert File.exists?(path)
      bin = File.read!(path)
      section = Lower.decode_section(bin)
      assert section.magic == "ELMC"
      assert byte_size(section.code) > 0
    end
  end

  test "loader runs manifest entry for counterOf" do
    out_dir = Path.expand("tmp/bytecode_loader_counter", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    assert {:ok, 7} =
             Loader.run_manifest_entry(out_dir, {"Main", "probeScoreOf"}, params: [{:record, [nil, 7, nil, nil, nil, nil, nil, nil]}])
  end

  test "primary bytecode manifest runs fused watchToPhoneTag when present" do
    out_dir = Path.expand("tmp/bytecode_loader_watch_tag", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    {:ok, manifest} = Loader.load_manifest(ProjectWriter.manifest_path(out_dir))

    fusion_entry =
      Enum.find(manifest["fusion_functions"] || [], fn entry ->
        entry["module"] == "Companion.Internal" and entry["name"] == "watchToPhoneTag"
      end)

    if fusion_entry do
      assert fusion_entry["fusion_kind"] == "union_int_lut"

      assert {:ok, tag} =
               Loader.run_manifest_entry(out_dir, {"Companion.Internal", "watchToPhoneTag"}, params: [1])

      assert is_integer(tag)
      assert tag > 0
    else
      assert {:ok, tag} =
               Loader.run_manifest_entry(out_dir, {"Companion.Internal", "watchToPhoneTag"}, params: [1])

      assert is_integer(tag)
    end
  end

  test "primary bytecode manifest prunes unreachable bundled helpers" do
    out_dir = Path.expand("tmp/bytecode_project_writer_prune", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template("watchface_yes",
               out_dir: out_dir,
               plan_ir_mode: :primary,
               strip_dead_code: true
             )

    {:ok, manifest} = Loader.load_manifest(ProjectWriter.manifest_path(out_dir))

    assert manifest["pruned_count"] > 0

    refute Enum.any?(manifest["functions"], fn %{"module" => mod, "name" => name} ->
             mod == "Pebble.Platform" and String.ends_with?(name, "Decoder")
           end)

    reachable = get_in(manifest, ["plan_coverage", "reachable"])
    all = get_in(manifest, ["plan_coverage", "all"])
    assert reachable["failed_count"] == 0
    assert reachable["lowered"] == reachable["total"]
    assert manifest["plan_toolchain"] == %{"mode" => "primary", "strict" => true}
    assert all["lowered"] == reachable["lowered"]
    assert all["total"] == reachable["total"]
    assert length(manifest["functions"]) <= reachable["total"]
    assert length(manifest["functions"]) > 0
  end

  test "does not emit bytecode artifacts when plan_ir_mode is off" do
    out_dir = Path.expand("tmp/bytecode_project_writer_off", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :off
             })

    refute File.exists?(Path.join([out_dir, "bytecode", "elmc_bytecode.manifest.json"]))
  end
end
