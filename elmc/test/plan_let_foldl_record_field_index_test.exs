defmodule Elmc.PlanLetFoldlRecordFieldIndexTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "foldl result field access uses distinct alphabetical indices" do
    project = Path.expand("tmp/plan_let_foldl_record_project", __DIR__)
    File.rm_rf!(project)
    File.mkdir_p!(Path.join(project, "src"))

    File.write!(
      Path.join(project, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}},
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(project, "src/Main.elm"),
      """
      module Main exposing (main)

      main =
          let
              step x acc =
                  { sum = acc.sum + x
                  , count = acc.count + 1
                  }

              result =
                  List.foldl step { sum = 0, count = 0 } [ 10, 20, 30 ]
          in
          { sum = result.sum, count = result.count }
      """
    )

    out = Path.join(project, "out")

    assert {:ok, _} =
             PrimaryCodegen.compile(project, %{
               out_dir: out,
               entry_module: "Main",
               plan_ir_mode: :primary,
               strip_dead_code: false
             })

    generated = File.read!(Path.join(out, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_main")

    # count @0, sum @1 (alphabetical). Both must not fall back to index 0.
    assert body =~ ~r/record_get_index\([^,]+,\s*0\s*\/\*\s*count\s*\*\//
    assert body =~ ~r/record_get_index\([^,]+,\s*1\s*\/\*\s*sum\s*\*\//
    refute body =~ ~r/record_get_index\([^,]+,\s*0\s*\/\*\s*sum\s*\*\//
  end
end
