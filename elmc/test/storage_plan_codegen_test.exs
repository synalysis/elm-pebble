defmodule Elmc.StoragePlanCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

  defp compile_main!(source, project_name) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{project_name}", __DIR__)
    out_dir = Path.expand("tmp/#{project_name}_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end

  test "compact-only useCount emptyBoard emits single int-list loop" do
    generated_c =
      compile_main!(
        """
        module Main exposing (main)

        emptyBoard : List Int
        emptyBoard =
            List.repeat 16 0

        countEmpty : List Int -> Int
        countEmpty cells =
            case cells of
                [] ->
                    0

                value :: rest ->
                    (if value == 0 then
                        1

                     else
                        0
                    )
                        + countEmpty rest

        useCount : List Int -> Int
        useCount cells =
            countEmpty cells

        main =
            useCount emptyBoard
        """,
        "storage_plan_codegen_compact"
      )

    count_empty_native =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert count_empty_native =~ "ELMC_TAG_INT_LIST"
    refute count_empty_native =~ "list_walk_cursor_"
  end

  test "Array.get on Array.fromList (List.repeat 8 0) uses indexed int-list access" do
    generated_c =
      compile_main!(
        """
        module Main exposing (main)

        board : Array.Array Int
        board =
            Array.fromList (List.repeat 8 0)

        readFirst : Array.Array Int -> Int
        readFirst arr =
            Maybe.withDefault -1 (Array.get 0 arr)

        main =
            readFirst board
        """,
        "storage_plan_codegen_array_get"
      )

    assert generated_c =~ "elmc_array_get_with_default_int"
    refute generated_c =~ ~r/elmc_array_get_with_default_int[\s\S]{0,400}list_walk_cursor_/
  end

  test "record grid fixture compiles and emits sumRows" do
    fixture = Path.expand("fixtures/storage_plan_record_grid_project", __DIR__)
    out_dir = Path.expand("tmp/storage_plan_record_grid_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "elmc_fn_Main_sumRows"

    grid_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_grid")
    assert grid_body =~ "elmc_list_from_record_array"

    sum_rows_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_sumRows")
    assert sum_rows_body =~ "ELMC_TAG_RECORD_SEQ"
  end

  test "native_linked list loops accept compact int lists without cons walk" do
    loop =
      Elmc.Backend.CCodegen.ListLoopCodegen.emit_native_list_int_head_loop(
        "cells",
        1,
        "head",
        "      acc += head;\n",
        repr: :native_linked
      )

    assert loop =~ "ELMC_TAG_INT_LIST"
    assert loop =~ "ELMC_TAG_INT_SPINE"
    refute loop =~ "ELMC_TAG_LIST"
  end

  test "List.map over record list emits single cons walk without int-list dual branch" do
    generated_c =
      compile_main!(
        """
        module Main exposing (main)

        type alias Point =
            { x : Int, y : Int }

        tupleCoords : List Point -> List ( Int, Int )
        tupleCoords points =
            List.map (\\p -> ( p.x, p.y )) points

        main =
            tupleCoords [ { x = 0, y = 1 }, { x = 2, y = 3 } ]
        """,
        "storage_plan_codegen_record_map"
      )

    body =
      generated_c
      |> String.split("elmc_fn_Main_tupleCoords(", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert body =~ "list_map_head_"
    refute body =~ "ELMC_TAG_INT_LIST"
    refute body =~ "_ilp_"
    assert body =~ "ELMC_TAG_RECORD_SEQ" or body =~ "list_walk_cursor_"
    refute Regex.match?(~r/ELMC_TAG_INT_LIST[\s\S]*\} else \{/, body)
  end
end
