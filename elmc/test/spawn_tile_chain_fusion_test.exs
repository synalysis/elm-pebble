defmodule Elmc.SpawnTileChainFusionTest do
  use ExUnit.Case, async: true

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "initialBoard fuses chained spawnTileWithSeed into one native buffer path" do
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
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             ~r/static RC elmc_fn_Main_initialBoard_native\(ElmcValue \*\*out, (?:const elmc_int_t|ElmcValue \*) ?seed\)/
    assert generated_c =~ "spawn_a_after_tile"
    assert generated_c =~ "spawn_b_after_tile"
    assert generated_c =~ "return elmc_fn_Main_initialBoard_native(out, seed);"
    refute generated_c =~ "elmc_fn_Main_initialBoard_native(ElmcValue **out, ElmcValue *seed, "
    refute generated_c =~ "ElmcValue *owned[0] = ({"
    assert generated_c =~
             ~r/static RC elmc_fn_Main_initialBoard_native[\s\S]*?Rc = elmc_tuple2_take\(out, owned\[0\], owned\[1\]\);\s*CHECK_RC\(Rc\);\s*owned\[0\] = NULL;\s*owned\[1\] = NULL;[\s\S]*?elmc_release_array_lifo\(owned, DIM\(owned\)\);/
    refute generated_c =~ "elmc_fn_Main_spawnTileWithSeed(&tmp_"
  end
end
