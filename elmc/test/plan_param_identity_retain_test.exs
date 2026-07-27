defmodule Elmc.PlanParamIdentityRetainTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "identity return of boxed param retains into owned before publish" do
    project = Path.expand("tmp/plan_param_identity_retain_project", __DIR__)
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

      identity : a -> a
      identity x =
          x

      main =
          identity (Just 7)
              |> Maybe.withDefault 0
              |> String.fromInt
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
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_identity")

    # Must not alias the borrow into *out without retain (EscapeDictReturnShape).
    refute body =~ ~r/owned\[\d+\] = x;\s*\n\s*\*out = owned\[\d+\];/
    assert body =~ "elmc_retain"
  end
end
