defmodule Elmx.LetInEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  defp env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:function_arities, %{})
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:constructor_lookup, %{})
  end

  test "nested let_in emits IIFE so inner value sees outer binding" do
    inner =
      %{
        op: :let_in,
        name: "g",
        value_expr: %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
        in_expr: %{op: :var, name: "f"}
      }

    outer =
      %{
        op: :let_in,
        name: "f",
        value_expr: %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
        in_expr: inner
      }

    {code, _, _} = Emit.compile_expr(outer, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "(fn ->"
    assert source =~ "f = "
    assert source =~ "g = "
    assert source =~ "end).()"
  end

  test "nested let_in keeps binding referenced via field_access inside call args" do
    body = %{
      name: "row3",
      op: :let_in,
      value_expr: %{op: :int_literal, value: 0},
      in_expr: %{
        op: :record_literal,
        fields: [
          %{
            name: "cells",
            expr: %{
              args: [
                %{arg: "row0", op: :field_access, field: "cells"},
                %{arg: "row1", op: :field_access, field: "cells"}
              ],
              name: "__append__",
              op: :call
            }
          }
        ]
      }
    }

    let = %{
      name: "row0",
      op: :let_in,
      value_expr: %{op: :int_literal, value: 0},
      in_expr: %{
        name: "row1",
        op: :let_in,
        value_expr: %{op: :int_literal, value: 1},
        in_expr: body
      }
    }

    {code, _, _} = Emit.compile_expr(let, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "(fn row0 ->"
    refute source =~ "_row0"
  end

  test "single let_in drops unused binding while still evaluating its value" do
    let = %{
      op: :let_in,
      name: "deadMargin",
      value_expr: %{op: :int_literal, value: 4},
      in_expr: %{op: :int_literal, value: 42}
    }

    {code, _, _} = Emit.compile_expr(let, env(), 0)
    source = IO.iodata_to_binary(code)

    refute source =~ "deadMargin"
    assert source =~ "(fn ->"
    assert source =~ "42"
  end

  test "nested let_in keeps binding referenced from an inner let value" do
    body = %{
      name: "collapsed",
      op: :let_in,
      value_expr: %{name: "oriented", op: :var},
      in_expr: %{name: "oriented", op: :var}
    }

    let = %{
      name: "oriented",
      op: :let_in,
      value_expr: %{op: :int_literal, value: 1},
      in_expr: body
    }

    {code, _, _} = Emit.compile_expr(let, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "oriented"
  end

  test "single let_in keeps binding referenced via field_access in the body" do
    let = %{
      name: "collapsed",
      op: :let_in,
      value_expr: %{op: :int_literal, value: 0},
      in_expr: %{arg: "collapsed", op: :field_access, field: "cells"}
    }

    {code, _, _} = Emit.compile_expr(let, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "collapsed"
  end

  test "let chain with a var alias does not emit letrec IIFE" do
    body = %{
      name: "targetBoardSize",
      op: :let_in,
      value_expr: %{name: "availableW", op: :var},
      in_expr: %{name: "availableW", op: :var}
    }

    let = %{
      name: "availableW",
      op: :let_in,
      value_expr: %{op: :int_literal, value: 100},
      in_expr: body
    }

    {code, _, _} = Emit.compile_expr(let, env(), 0)
    source = IO.iodata_to_binary(code)

    refute source =~ "(fn ->\n"
    assert source =~ "availableW"
  end

  test "sequential let block omits bindings not referenced in the body" do
    bindings =
      [{"v1", %{op: :int_literal, value: 0}}] ++
        (for n <- 2..31, do: {"v#{n}", %{op: :add_const, var: "v#{n - 1}", value: 1}}) ++
        [{"deadMargin", %{op: :int_literal, value: 4}}]

    body = %{op: :var, name: "v31"}

    let_chain =
      Enum.reduce(Enum.reverse(bindings), body, fn {name, value}, inner ->
        %{op: :let_in, name: name, value_expr: value, in_expr: inner}
      end)

    {code, _, _} = Emit.compile_expr(let_chain, env(), 0)
    source = IO.iodata_to_binary(code)

    refute source =~ "deadMargin"
    assert source =~ "v31"
  end
end
