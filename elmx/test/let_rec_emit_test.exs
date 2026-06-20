defmodule Elmx.LetRecEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "function let block emits sequential IIFE with fix for self recursion" do
    c_body = %{
      op: :if,
      cond: %{
        op: :if,
        cond: %{
          op: :compare,
          left: %{name: "n", op: :var},
          right: %{value: 0, op: :int_literal},
          kind: :lt
        },
        then_expr: %{op: :constructor_call, target: "True", args: []},
        else_expr: %{
          op: :compare,
          left: %{name: "n", op: :var},
          right: %{value: 0, op: :int_literal},
          kind: :eq
        }
      },
      then_expr: %{value: 0, op: :int_literal},
      else_expr: %{
        op: :call,
        name: "__add__",
        args: [
          %{value: 1, op: :int_literal},
          %{op: :call, name: "c", args: [%{op: :sub_const, var: "n", value: 1}]}
        ]
      }
    }

    expr = %{
      op: :let_in,
      name: "a",
      value_expr: %{
        op: :lambda,
        args: ["x"],
        body: %{op: :call, name: "b", args: [%{op: :var, name: "x"}]}
      },
      in_expr: %{
        op: :let_in,
        name: "b",
        value_expr: %{
          op: :lambda,
          args: ["y"],
          body: %{op: :add_const, var: "y", value: 1}
        },
        in_expr: %{
          op: :let_in,
          name: "c",
          value_expr: %{op: :lambda, args: ["n"], body: c_body},
          in_expr: %{
            op: :call,
            name: "__add__",
            args: [
              %{op: :call, name: "a", args: [%{value: 0, op: :int_literal}]},
              %{op: :call, name: "c", args: [%{value: 3, op: :int_literal}]}
            ]
          }
        }
      }
    }

    env =
      Emit.function_env("LetRecForwardRefMinimal", [])
      |> Map.put(:module, "LetRecForwardRefMinimal")

    assert {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "(fn ->"
    assert source =~ "b = "
    assert source =~ "Elmx.Runtime.Core.Apply.fix(fn c ->"
    assert source =~ "a = "
    assert source =~ "end).()"
    refute source =~ "(fn a, b, c ->"
  end
end
