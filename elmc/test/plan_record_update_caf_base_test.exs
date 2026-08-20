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

  test "record update of a borrowed param mutates in place without retain-then-copy" do
    project = Path.expand("tmp/plan_record_update_borrow_project", __DIR__)
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
          , d : Int
          , e : Int
          , f : Int
          , g : Int
          , h : Int
          }

      setH : Int -> Rec -> Rec
      setH h rec =
          { rec | h = h }

      main : Rec -> Int
      main rec =
          (setH 9 rec).h
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
    set_h = CCodegenExtract.fn_body(generated, "elmc_fn_Main_setH")

    assert set_h =~ "elmc_record_update_index_int_cow("
    refute set_h =~ "elmc_record_update_index_int_cow_drop"
    refute set_h =~ "__cow_base"
    assert set_h =~ "elmc_retain(__rc_ret)" or set_h =~ "elmc_retain(*out)"
  end

  test "Maybe Just record update peels without retain so COW can mutate in place" do
    project = Path.expand("tmp/plan_record_update_maybe_project", __DIR__)
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
          , d : Int
          , e : Int
          , f : Int
          , g : Int
          , h : Int
          }

      setH : Int -> Maybe Rec -> Maybe Rec
      setH h maybeRec =
          case maybeRec of
              Nothing ->
                  Nothing

              Just rec ->
                  Just { rec | h = h }

      main : Maybe Rec -> Int
      main maybeRec =
          case setH 9 maybeRec of
              Just rec ->
                  rec.h

              Nothing ->
                  0
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
    set_h = CCodegenExtract.fn_body(generated, "elmc_fn_Main_setH")

    refute set_h =~ "elmc_retain(elmc_maybe_just_payload"
    assert set_h =~ "elmc_maybe_just_payload"
    assert set_h =~ "elmc_record_update_index_int_cow("
    refute set_h =~ "elmc_record_update_index_int_cow_drop"
  end
end

