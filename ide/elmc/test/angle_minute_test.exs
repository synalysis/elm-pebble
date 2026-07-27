defmodule Elmc.AngleMinuteTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Native.AngleMinute

  test "body_expr? matches modBy 65536 minute-to-angle numerator" do
    minute = %{op: :var, name: "minute"}

    numerator =
      %{
        op: :call,
        name: "__idiv__",
        args: [
          %{
            op: :call,
            name: "__mul__",
            args: [
              %{op: :call, name: "__sub__", args: [minute, %{op: :int_literal, value: 720}]},
              %{op: :int_literal, value: 65_536}
            ]
          },
          %{op: :int_literal, value: 1440}
        ]
      }

    body = %{
      op: :runtime_call,
      function: "elmc_basics_mod_by",
      args: [%{op: :int_literal, value: 65_536}, numerator]
    }

    assert AngleMinute.body_expr?(body)
    assert {:ok, ^minute} = AngleMinute.minute_expr_from_angle_numerator(numerator)
  end

  test "body_expr? matches lowered Basics.modBy with sub_const minute-720" do
    minute = %{op: :var, name: "minute"}

    numerator = %{
      op: :call,
      name: "__idiv__",
      args: [
        %{
          op: :call,
          name: "__mul__",
          args: [
            %{op: :sub_const, var: "minute", value: 720},
            %{op: :int_literal, value: 65_536}
          ]
        },
        %{op: :int_literal, value: 1440}
      ]
    }

    body = %{
      op: :qualified_call,
      target: "Basics.modBy",
      args: [%{op: :int_literal, value: 65_536}, numerator]
    }

    assert AngleMinute.body_expr?(body)
    assert {:ok, ^minute} = AngleMinute.minute_expr_from_angle_numerator(numerator)
  end

  test "body_expr? rejects unrelated modBy" do
    body = %{
      op: :call,
      name: "modBy",
      args: [
        %{op: :int_literal, value: 5},
        %{op: :var, name: "x"}
      ]
    }

    refute AngleMinute.body_expr?(body)
  end
end
