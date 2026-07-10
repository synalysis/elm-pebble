defmodule Elmc.UnionIntCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.UnionIntCase

  test "try_emit recognizes union int case IR" do
    expr = %{
      op: :case,
      subject: %{op: :var, name: "message"},
      branches: [
        %{
          pattern: %{kind: :constructor, name: "RequestUpdate", tag: 1, arg_pattern: nil},
          expr: %{op: :int_literal, value: 2}
        },
        %{
          pattern: %{kind: :constructor, name: "RequestSunData", tag: 2, arg_pattern: nil},
          expr: %{op: :int_literal, value: 3}
        },
        %{
          pattern: %{kind: :constructor, name: "RequestWeather", tag: 3, arg_pattern: nil},
          expr: %{op: :int_literal, value: 4}
        }
      ]
    }

    assert {:ok, body, [], :rc_native} =
             UnionIntCase.try_emit("Companion.Internal", "watchToPhoneTag", expr, %{
               {"Companion.Internal", "watchToPhoneTag"} => %{args: ["message"]}
             })

    assert body =~ "switch (message)"
    assert body =~ "elmc_int_t message"
    refute body =~ "case_msg_tag_"
    assert body =~ "elmc_new_int"
    refute body =~ "goto elmc_plan_block_"
  end
end
