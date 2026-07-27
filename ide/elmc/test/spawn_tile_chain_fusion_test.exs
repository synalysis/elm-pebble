defmodule Elmc.SpawnTileChainFusionTest do
  use ExUnit.Case, async: true

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "initialBoard lowers spawnTileWithSeed chain under plan-primary" do
    project_dir = Path.expand("tmp/spawn_tile_chain_fusion", __DIR__)
    out_dir = Path.expand("tmp/spawn_tile_chain_fusion_out", __DIR__)

    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "static RC elmc_fn_Main_initialBoard("
    assert generated_c =~ "spawnTile"
  end
end
