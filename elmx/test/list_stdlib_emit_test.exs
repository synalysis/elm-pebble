defmodule Elmx.ListStdlibEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Runtime.Core

  defp base_env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "List.foldr emits Core.foldr" do
    expr = %{
      op: :qualified_call,
      target: "List.foldr",
      args: [
        %{
          op: :lambda,
          args: ["x"],
          body: %{
            op: :lambda,
            args: ["acc"],
            body: %{
              op: :call,
              name: "__add__",
              args: [%{op: :var, name: "x"}, %{op: :var, name: "acc"}]
            }
          }
        },
        %{op: :int_literal, value: 0},
        %{op: :list_literal, items: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]}
      ]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    assert IO.iodata_to_binary(code) =~ "Elmx.Runtime.Core.foldr"
  end

  test "List.repeat emits Core.list_repeat" do
    expr = %{
      op: :qualified_call,
      target: "List.repeat",
      args: [%{op: :int_literal, value: 3}, %{op: :int_literal, value: 0}]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    assert IO.iodata_to_binary(code) =~ "Elmx.Runtime.Core.list_repeat"
  end

  test "List.sort emits Core.sort" do
    expr = %{
      op: :qualified_call,
      target: "List.sort",
      args: [%{op: :list_literal, items: [%{op: :int_literal, value: 3}, %{op: :int_literal, value: 1}]}]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    assert IO.iodata_to_binary(code) =~ "Elmx.Runtime.Core.sort"
  end

  test "List.sum and List.sortWith emit Core helpers" do
    sum_expr = %{
      op: :qualified_call,
      target: "List.sum",
      args: [%{op: :list_literal, items: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]}]
    }

    {sum_code, _, _} = Emit.compile_expr(sum_expr, base_env(), 0)
    assert IO.iodata_to_binary(sum_code) =~ "Elmx.Runtime.Core.list_sum"

    sort_with_expr = %{
      op: :qualified_call,
      target: "List.sortWith",
      args: [
        %{
          op: :lambda,
          args: ["a", "b"],
          body: %{
            op: :qualified_call,
            target: "Basics.compare",
            args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
          }
        },
        %{op: :list_literal, items: [%{op: :int_literal, value: 3}, %{op: :int_literal, value: 1}]}
      ]
    }

    {sort_code, _, _} = Emit.compile_expr(sort_with_expr, base_env(), 0)
    assert IO.iodata_to_binary(sort_code) =~ "Elmx.Runtime.Core.sort_with"
  end

  test "Core.foldr and list_repeat behave like Elm" do
    fun = fn x -> fn acc -> x + acc end end
    assert Core.foldr(fun, 0, [1, 2, 3]) == 6
    assert Core.list_repeat(4, 0) == [0, 0, 0, 0]
    assert Core.member(2, [1, 2, 3])
    refute Core.member(9, [1, 2, 3])
    assert Core.all(fn x -> x > 0 end, [1, 2])
    refute Core.all(fn x -> x > 1 end, [1, 2])
    assert Core.sort([3, 1, 2]) == [1, 2, 3]
    assert Core.list_sum([1, 2, 3]) == 6
    assert Core.list_product([2, 3, 4]) == 24
    assert Core.list_maximum([1, 3, 2]) == {:Just, 3}
    assert Core.list_minimum([1, 3, 2]) == {:Just, 1}
    assert Core.list_maximum([]) == :Nothing

    cmp = fn a, b ->
      cond do
        a < b -> :LT
        a > b -> :GT
        true -> :EQ
      end
    end

    assert Core.sort_with(cmp, [3, 1, 2]) == [1, 2, 3]
    assert Core.list_head([7, 8]) == {:Just, 7}
    assert Core.list_head([]) == :Nothing
  end

  test "List.head emits Core.list_head" do
    expr = %{
      op: :qualified_call,
      target: "List.head",
      args: [%{op: :list_literal, items: [%{op: :int_literal, value: 1}]}]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    assert IO.iodata_to_binary(code) =~ "Elmx.Runtime.Core.list_head"
  end
end
