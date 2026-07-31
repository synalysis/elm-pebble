defmodule Elmc.TailRecursiveLoopFusionTest do
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

  test "plan-primary fuses Int and List accumulator self-tail loops to while(1)" do
    project_dir = Path.expand("tmp/tail_recursive_loop_fusion", __DIR__)
    out_dir = Path.expand("tmp/tail_recursive_loop_fusion_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(@elm_json))

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (main)


      tailLoop : Int -> Int -> Int
      tailLoop n acc =
          if n <= 0 then
              acc

          else
              tailLoop (n - 1) (acc + 1)


      bigList : Int -> List Int -> List Int
      bigList n acc =
          if n <= 0 then
              acc

          else
              bigList (n - 1) (n :: acc)


      main : Int
      main =
          List.length (bigList 8 []) + tailLoop 5 0
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

    tail_native = extract_fn!(generated_c, "elmc_fn_Main_tailLoop_native")
    list_native = extract_fn!(generated_c, "elmc_fn_Main_bigList_native")

    assert tail_native =~ "while (1)"
    assert list_native =~ "while (1)"
    assert tail_native =~ "(n_loop <= 0)"
    refute tail_native =~ "elmc_new_bool"
    refute tail_native =~ "elmc_fn_Main_tailLoop("
    refute list_native =~ "elmc_fn_Main_bigList("
    refute list_native =~ "elmc_list_cons(&owned[1], n,"
    refute list_native =~ "int_list_cons_buf_0[0] = elmc_as_int((n))"
    assert list_native =~ "elmc_list_cons"
  end

  test "tail loop keeps Set insert/remove results as ElmcValue pointers" do
    project_dir = Path.expand("tmp/tail_recursive_loop_set_workset", __DIR__)
    out_dir = Path.expand("tmp/tail_recursive_loop_set_workset_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(@elm_json))

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (main)

      import Set


      loop : Int -> Set.Set Int -> Int -> Int
      loop remaining workset acc =
          if remaining <= 0 then
              acc

          else
              let
                  key =
                      remainderBy 1024 remaining

                  withInsert =
                      Set.insert key workset

                  nextWorkset =
                      if remainderBy 3 remaining == 0 then
                          Set.remove key withInsert

                      else
                          withInsert
              in
              loop
                  (remaining - 1)
                  nextWorkset
                  (acc
                      + (if Set.member key withInsert then
                            key

                         else
                            0
                        )
                  )


      main : String
      main =
          String.fromInt (loop 8 Set.empty 0)
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
    loop_native = extract_fn!(generated_c, "elmc_fn_Main_loop_native")

    assert loop_native =~ "while (1)"
    assert loop_native =~ "(remaining_loop <= 0)"
    assert loop_native =~ "elmc_set_insert_int"
    refute loop_native =~ ~r/elmc_set_insert_int\([^)]+\);\s*\n\s*const elmc_int_t native_i_\d+ = elmc_as_int\(owned\[\d+\]\)/s
    assert loop_native =~ "workset_loop = owned["
  end

  defp extract_fn!(c, name) do
    pattern = ~r/static RC #{Regex.escape(name)}\s*\([^)]*\)\s*\{/

    case Regex.scan(pattern, c, return: :index) do
      [[{start, len}] | _] ->
        rest = binary_part(c, start + len - 1, byte_size(c) - (start + len - 1))
        body = take_balanced_brace(rest)
        assert is_binary(body) and body != "", "could not extract body for #{name}"
        body

      _ ->
        flunk("missing function #{name} in generated C")
    end
  end

  defp take_balanced_brace(<<?{, rest::binary>>), do: do_take_brace(rest, 1, "{")
  defp take_balanced_brace(_), do: nil

  defp do_take_brace(_rest, 0, acc), do: acc
  defp do_take_brace(<<>>, _depth, _acc), do: nil

  defp do_take_brace(<<?}, rest::binary>>, depth, acc),
    do: do_take_brace(rest, depth - 1, acc <> "}")

  defp do_take_brace(<<?{, rest::binary>>, depth, acc),
    do: do_take_brace(rest, depth + 1, acc <> "{")

  defp do_take_brace(<<c::utf8, rest::binary>>, depth, acc),
    do: do_take_brace(rest, depth, acc <> <<c::utf8>>)
end
