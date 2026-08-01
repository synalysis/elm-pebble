defmodule Elmc.PlanTupleIntArithNoSkipTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "int arith feeding tuple2 is emitted, not skipped then reconstructed after release" do
    project = Path.expand("tmp/plan_tuple_int_arith_no_skip_project", __DIR__)
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

      pair : Int -> ( Int, Int )
      pair key =
          ( key, key * 3 + 1 )

      main =
          case pair 7 of
              ( _, v ) ->
                  String.fromInt v
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
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_pair")

    # Real arith must not release a boxed mul slot then reconstruct add as
    # elmc_as_int(owned[i])+1 (EscapeDictLocalShape → every dict value becomes 1).
    refute body =~
             ~r/elmc_release\(owned\[\d+\]\);\s*\n\s*ElmcValue \*\w+ = elmc_new_int_take\(elmc_as_int\(owned\[\d+\]\) \+ 1\)/

    assert body =~ "elmc_tuple2" or body =~ ~r/\*out[01]\s*=/
    # Prefer a native int chain or a boxed mul that stays live until add/tuple2.
    assert body =~ ~r/\*\s*3\s*\+\s*1/ or body =~ ~r/elmc_new_int\([^;]+,\s*[^;]*\*\s*3/
  end
end
