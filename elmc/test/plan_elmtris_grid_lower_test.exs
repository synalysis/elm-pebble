defmodule Elmc.PlanElmtrisGridLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.Verify
  alias Elmc.TestSupport.TemplateCompile

  @names ~w(emptyBoard cellAt listAt boardCols offsetFits canPlace rowFull rowCells setCell clearLines stampPiece pieceOffsets)

  test "elmtris grid helpers lower to verified plans" do
    assert {:ok, result} = TemplateCompile.compile_watch_template("game_elmtris", plan_ir_mode: :shadow)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)

    for name <- @names do
      decl = Map.fetch!(decl_map, {"Main", name})

      assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: true),
             "expected #{name} to lower"

      assert :ok = Verify.run(plan)
    end
  end

  test "offsetFits primary codegen uses plan CFG not fusion native" do
    out_dir =
      System.tmp_dir!()
      |> Path.join("elmc-offsetfits-primary-#{System.unique_integer([:positive])}")

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("game_elmtris",
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = Elmc.Test.CCodegenExtract.fn_body(c, "elmc_fn_Main_offsetFits")

    assert body =~ ~r/elmc_plan_block/
    refute body =~ ~r/offsetFits_native/
    refute body =~ ~r/ELMC_RELEASE/
  end

  test "plan heap owned on pebble_int32 uses elmc_calloc for large functions" do
    out_dir =
      System.tmp_dir!()
      |> Path.join("elmc-lockpiece-plan-#{System.unique_integer([:positive])}")

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("game_elmtris",
               plan_ir_mode: :primary,
               pebble_int32: true,
               out_dir: out_dir
             )

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = Elmc.Test.CCodegenExtract.fn_body(c, "elmc_fn_Main_lockPiece")

    assert body =~ "elmc_calloc(ELMC_OWNED_SLOT_COUNT"
    assert body =~ "plan block"
    refute body =~ "elmc_owned_i"
    assert body =~ "elmc_free(owned)"
  end
end
