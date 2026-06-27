defmodule Elmc.ImmortalStaticListCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.ImmortalStaticList

  test "emits immortal prelude and retain return for static int list constants" do
  expr = %{
      op: :list_literal,
      items: Enum.map(1..4, &%{op: :int_literal, value: &1})
    }

    assert {:ok, prelude, body} =
             ImmortalStaticList.try_emit_function_prelude_and_body("Main", "pages", expr, true, false)

    assert prelude =~ "elmc_immortal_list_Main_pages_values[4] = { 1, 2, 3, 4 }"
    assert prelude =~ "ELMC_TAG_INT_LIST"
    assert body =~ "return elmc_retain((ElmcValue *)&elmc_immortal_list_Main_pages_value)"
    refute prelude =~ "elmc_immortal_list_Main_pages_storage"
    refute body =~ "elmc_list_from_int_array"
  end

  test "emits nil retain for empty constant list" do
    expr = %{op: :list_literal, items: []}

    assert {:ok, "", body} =
             ImmortalStaticList.try_emit_function_prelude_and_body("Main", "empty", expr, false, false)

    assert body =~ "return elmc_retain(elmc_list_nil());"
    refute body =~ "elmc_immortal_list"
  end

  test "resolves static length for zero-arg list constants and list literals" do
    env = %{
      __module__: "Main",
      __program_decls__: %{
        {"Main", "pages"} => %{
          args: [],
          expr: %{
            op: :list_literal,
            items: Enum.map(1..8, &%{op: :int_literal, value: &1})
          }
        }
      }
    }

    assert {:ok, 8} = ImmortalStaticList.static_length(%{op: :var, name: "pages"}, env)
    assert {:ok, 3} =
             ImmortalStaticList.static_length(
               %{
                 op: :list_literal,
                 items: [
                   %{op: :int_literal, value: 1},
                   %{op: :int_literal, value: 2},
                   %{op: :int_literal, value: 3}
                 ]
               },
               env
             )
    assert :error = ImmortalStaticList.static_length(%{op: :var, name: "model"}, env)
  end

  test "rejects non-static list items" do
    expr = %{
      op: :list_literal,
      items: [
        %{op: :int_literal, value: 1},
        %{op: :var, name: "x"}
      ]
    }

    assert :error =
             ImmortalStaticList.try_emit_function_prelude_and_body("Main", "mixed", expr, true, false)
  end
end
