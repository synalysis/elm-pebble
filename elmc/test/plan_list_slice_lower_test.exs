defmodule Elmc.PlanListSliceLowerTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  test "rowAt lowers List.take + List.drop slice to list_slice_int" do
    source = """
    module Main exposing (rowAt)

    rowAt : Int -> List Int -> List Int
    rowAt row cells =
        List.take 4 (List.drop (row * 4) cells)
    """

    project_dir = Path.expand("tmp/plan_row_at", __DIR__)
    out_dir = Path.expand("tmp/plan_row_at_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "rowAt"})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: false)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "list_slice_int"

    assert {:ok, [0, 1, 2, 3]} =
             Elmc.Backend.Bytecode.Loader.run_manifest_entry(out_dir, {"Main", "rowAt"},
               params: [0, Enum.to_list(0..15)]
             )
  end
end
