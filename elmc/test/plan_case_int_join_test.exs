defmodule Elmc.PlanCaseIntJoinTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile

  @moduletag :plan_surface
  @moduletag timeout: 120_000

  test "case Ready cursor+cmd vs -1 emits add and does not always return -1" do
    # Regression: build_const_int_regs treated a multi-def join reg as literal -1
    # when one arm was const_int (CaseBranch5Plus returned -1 instead of 101).
    project_dir = Path.expand("tmp/case_int_join_project", __DIR__)
    out_dir = Path.expand("tmp/case_int_join_out", __DIR__)

    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))

    File.cp!(
      Path.expand("fixtures/simple_project/elm.json", __DIR__),
      Path.join(project_dir, "elm.json")
    )

    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    type AppState
        = Loading
        | Ready { cursor : Int }
        | Exiting

    type alias Model =
        { value : Int
        , state : AppState
        }

    main : Int
    main =
        let
            model =
                { value = 0
                , state = Ready { cursor = 0 }
                }

            result =
                ( { model | state = Ready { cursor = 1 } }, 100 )
        in
        case result of
            ( newModel, cmd ) ->
                case newModel.state of
                    Ready rs ->
                        rs.cursor + cmd

                    _ ->
                        -1
    """)

    assert {:ok, _} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               named_record_literals: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "elmc_fn_Main_main"
    assert c =~ "+"
    assert c =~ "-1"
    # Success arm must not fall through into the -1 block.
    assert c =~ ~r/goto elmc_plan_block_\d+;/
  end
end
