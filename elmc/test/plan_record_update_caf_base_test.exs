defmodule Elmc.PlanRecordUpdateCafBaseTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "record update of CAF base is not dropped as early return" do
    project = Path.expand("tmp/plan_record_update_caf_project", __DIR__)
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

      type alias Rec =
          { a : Int
          , b : Int
          , c : Int
          }

      initial : Rec
      initial =
          { a = 1
          , b = 2
          , c = 3
          }

      updated : Rec
      updated =
          { initial | b = 99 }

      main : Int
      main =
          updated.b
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
    updated = CCodegenExtract.fn_body(generated, "elmc_fn_Main_updated")

    assert updated =~ "elmc_record_update_index_int_cow_drop" or
             updated =~ "elmc_record_update_index_cow_drop"
    refute updated =~ ~r/return __rc_call_0;\s*\}\s*\z/
  end
end
