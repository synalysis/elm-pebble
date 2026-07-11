defmodule Elmc.IntStringCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.IntStringCase

  test "try_emit recognizes int to string lookup case IR" do
    branches =
      for {label, month} <- Enum.with_index(["Jan", "Feb", "Mar"], 1) do
        %{
          pattern: %{kind: :int, value: month},
          expr: %{op: :string_literal, value: label}
        }
      end

    expr = %{op: :case, subject: %{op: :var, name: "month"}, branches: branches}

    assert {:ok, body, [], :rc_native} =
             IntStringCase.try_emit("Main", "monthString", expr, %{
               {"Main", "monthString"} => %{args: ["month"]}
             })

    assert body =~ "native_str_immortal_lut_"
    assert body =~ "*out"
    refute body =~ "goto elmc_plan_block_"
  end

  test "try_emit and extract_fusion_data handle wildcard default monthString shape" do
    branches =
      for m <- 1..11 do
        %{
          pattern: %{kind: :int, value: m},
          expr: %{op: :string_literal, value: "Mon"}
        }
      end ++
        [
          %{
            pattern: %{kind: :wildcard},
            expr: %{op: :string_literal, value: "Dec"}
          }
        ]

    expr = %{op: :case, subject: %{op: :var, name: "month"}, branches: branches}

    assert {:ok, body, [], :rc_native} =
             IntStringCase.try_emit("Main", "monthString", expr, %{
               {"Main", "monthString"} => %{args: ["month"]}
             })

    assert body =~ "native_str_immortal_lut_"

    assert {:ok, :int_string_lut, data} =
             IntStringCase.extract_fusion_data("Main", "monthString", expr, %{})

    assert data.default == "Dec"
    assert Map.fetch!(data.lut, 1) == "Mon"
  end
end
