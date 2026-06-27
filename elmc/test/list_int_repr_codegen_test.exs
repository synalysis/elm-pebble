defmodule Elmc.ListIntReprCodegenTest do
  use ExUnit.Case, async: true

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

  test "countEmpty emits int-list-only loop when all callers pass compact lists" do
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
        "list_int_repr_compact_only"
      )

    count_empty_native =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert count_empty_native =~ "ELMC_TAG_INT_LIST"
    refute count_empty_native =~ "list_walk_cursor_"
    refute count_empty_native =~ "list_walk_node_"
  end

  test "countEmpty keeps dual loop when a caller passes cons nil" do
    generated_c =
      compile_main!(
        """
        module Main exposing (main)

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
            useCount []
        """,
        "list_int_repr_dual_path"
      )

    assert generated_c =~ "elmc_fn_Main_countEmpty_native"
    assert generated_c =~ "list_walk_cursor_"
    assert generated_c =~ "ELMC_TAG_INT_LIST"
  end
end
