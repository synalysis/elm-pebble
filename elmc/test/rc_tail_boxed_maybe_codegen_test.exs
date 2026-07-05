defmodule Elmc.RcTailBoxedMaybeCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

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

  setup do
    project_dir = Path.expand("tmp/rc_tail_boxed_maybe_project", __DIR__)
    out_dir = Path.expand("tmp/rc_tail_boxed_maybe_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))

    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(@elm_json))

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (currentPage, pages, probeJustAt, probeListHeadAt, probeNothingAt)

      type Page
          = Alpha
          | Beta
          | Gamma


      pages : List Page
      pages =
          [ Alpha, Beta, Gamma ]


      currentPage : Int -> Page
      currentPage index =
          pages
              |> List.drop (modBy (List.length pages) index)
              |> List.head
              |> Maybe.withDefault Alpha


      probeJustAt : Int -> Page
      probeJustAt _ =
          Maybe.withDefault Alpha (Just Beta)


      probeNothingAt : Int -> Page
      probeNothingAt _ =
          Maybe.withDefault Alpha Nothing


      probeListHeadAt : List Page -> Page
      probeListHeadAt list =
          Maybe.withDefault Alpha (List.head list)
      """
    )

    %{project_dir: project_dir, out_dir: out_dir}
  end

  test "RC tail Maybe.withDefault writes the resolved value to *out", %{
    project_dir: project_dir,
    out_dir: out_dir
  } do
    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    current_page =
      CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_currentPage_native")

    assert current_page =~ "*out ="
    assert current_page =~ "elmc_immortal_list_Main_pages_values"
    refute current_page =~ "ElmcValue *tmp_"

    probe_just =
      CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_probeJustAt_native")

    assert probe_just =~ "elmc_maybe_with_default"
    assert probe_just =~ "*out ="

    probe_nothing =
      CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_probeNothingAt_native")

    assert probe_nothing =~ "elmc_maybe_with_default"
    assert probe_nothing =~ "*out ="

    probe_list_head = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_probeListHeadAt")

    assert probe_list_head =~ "elmc_maybe_with_default"
    assert probe_list_head =~ "*out ="
    refute probe_list_head =~ "return tmp_"
  end
end
