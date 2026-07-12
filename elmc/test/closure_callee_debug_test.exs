defmodule Elmc.ClosureCalleeDebugTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  alias Elmc.Test.ElmRunCorpus

  test "top_level_ref for RC callee uses wrapper" do
    source = """
    module ListFilterMap exposing (main)

    toPositive : Int -> Maybe Int
    toPositive x =
        if x > 0 then
            Just x
        else
            Nothing

    main =
        List.filterMap toPositive [ -1, 0, 1, 2 ]
            |> Debug.toString
    """

    project_dir = Path.expand("tmp/closure_callee_debug", __DIR__)
    out_dir = Path.join(project_dir, "out")
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/ListFilterMap.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "ListFilterMap"})
    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert c =~ "static RC elmc_fn_ListFilterMap_toPositive(ElmcValue **out, ElmcValue *x)",
           "expected direct RC callee for plan-primary filterMap closure"

    assert c =~ "elmc_fn_ListFilterMap_toPositive(&",
           "expected filterMap closure to call direct RC callee"
  end

  test "top_level_ref for RC callee in multi-binding let uses wrapper" do
    source = """
    module ListFilterMap exposing (main)

    toPositive : Int -> Maybe Int
    toPositive x =
        if x > 0 then
            Just x
        else
            Nothing

    main =
        let
            input =
                [ -1, 0, 1, 2 ]

            result =
                List.filterMap toPositive input
        in
        result
    """

    project_dir = Path.expand("tmp/closure_callee_let_chain", __DIR__)
    out_dir = Path.join(project_dir, "out")
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/ListFilterMap.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "ListFilterMap"})
    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert c =~ "static RC elmc_fn_ListFilterMap_toPositive(ElmcValue **out, ElmcValue *x)",
           "expected direct RC callee for plan-primary let-chain filterMap"

    assert c =~ "elmc_fn_ListFilterMap_toPositive(&",
           "expected let-chain filterMap closure to call direct RC callee"
  end

  test "corpus ListFilterMap host compile uses RC top_level_ref wrapper" do
    if ElmRunCorpus.available?() do
      tmp = Path.join(System.tmp_dir!(), "list_filter_map_corpus_debug")
      {project_dir, _} = ElmRunCorpus.write_execution_project!("KernelLowering/ListFilterMap.elm", tmp)

      out_dir = Path.join(project_dir, "out")

      assert {:ok, _} =
               Elmc.compile(project_dir, %{
                 out_dir: out_dir,
                 strip_dead_code: false,
                 entry_module: "CorpusHost",
                 named_record_literals: true
               })

      c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

      assert c =~ "static RC elmc_fn_ListFilterMap_toPositive(ElmcValue **out, ElmcValue *x)"
      assert c =~ "elmc_fn_ListFilterMap_toPositive(&"
    end
  end
end
