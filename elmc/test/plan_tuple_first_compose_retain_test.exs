defmodule Elmc.PlanTupleFirstComposeRetainTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile

  @elm_json %{
    "type" => "application",
    "source-directories" => ["src"],
    "elm-version" => "0.19.1",
    "dependencies" => %{
      "direct" => %{"elm/core" => "1.0.5"},
      "indirect" => %{}
    },
    "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
  }

  test "foldl >> Tuple.first publishes retained borrow (not bare pointer)" do
    project_dir = Path.expand("tmp/tuple_first_compose_retain", __DIR__)
    out_dir = Path.expand("tmp/tuple_first_compose_retain_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(@elm_json))

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (main)


      main : List Int
      main =
          [ 1, 2, 3 ]
              |> (List.foldl (\\n ( acc, i ) -> ( n :: acc, i + 1 )) ( [], 0 )
                      >> Tuple.first
                      >> List.reverse
                 )
      """
    )

    assert {:ok, _} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    # Escaping Tuple.first must retain the borrowed peel before *out publish.
    assert generated_c =~
             ~r/owned\[\d+\] = elmc_tuple_first_borrow\([^\n]+\);\s*\n\s*\*out = elmc_retain\(owned\[\d+\]\);/
  end
end
