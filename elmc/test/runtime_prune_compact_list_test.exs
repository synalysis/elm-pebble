defmodule Elmc.RuntimePruneCompactListTest do
  use ExUnit.Case, async: false

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "pruned int-only runtime keeps float/record-seq release stubs and compiles" do
    project_dir = Path.expand("tmp/runtime_prune_compact_list_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_prune_compact_list_out", __DIR__)

    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               prune_runtime: true
             })

    runtime = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute runtime =~ "elmc_float_list_alloc_copy"
    refute runtime =~ "elmc_record_seq_alloc_copy"
    refute runtime =~ "ELMC_TAG_FLOAT_LIST"
    refute runtime =~ "ELMC_TAG_RECORD_SEQ"
    refute runtime =~ "elmc_int_spine_head_native"

    count_empty =
      generated
      |> String.split("static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert count_empty =~ "ELMC_TAG_INT_LIST"
    refute count_empty =~ "list_walk_cursor_"

    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available")

    runtime_dir = Path.join(out_dir, "runtime")
    c_dir = Path.join(out_dir, "c")
    object = Path.join(out_dir, "runtime_prune_compact_list.o")

    {output, exit_code} =
      System.cmd(cc, [
        "-c",
        "-std=c99",
        "-I",
        runtime_dir,
        "-I",
        c_dir,
        "-DELMC_RC_TRACK=0",
        Path.join(runtime_dir, "elmc_runtime.c"),
        "-o",
        object
      ], stderr_to_stdout: true)

    assert exit_code == 0, output
  end
end
