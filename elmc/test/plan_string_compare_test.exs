defmodule Elmc.PlanStringCompareTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "string equality uses elmc_string_equals not elmc_as_int" do
    project = Path.expand("tmp/plan_string_compare_project", __DIR__)
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
              a = "apple"
              b = "banana"
          in
          ("rD" == "rS", a < b)
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

    assert body =~ "elmc_string_equals"
    assert body =~ "elmc_string_compare"
    refute body =~ ~r/elmc_as_int\(owned\[\d+\]\)\s*==\s*elmc_as_int\(owned\[\d+\]\)/
  end
end
