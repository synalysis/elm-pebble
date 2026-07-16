defmodule Elmc.PlanParamFieldInferenceTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.ParamFieldInference

  test "collects from record literal alone" do
    expr = %{
      op: :record_literal,
      fields: [
        %{name: "url", expr: %{op: :field_access, arg: "r", field: "url"}}
      ]
    }

    assert ParamFieldInference.infer(%{expr: expr, args: ["r"]}) == %{"r" => ["url"]}
  end

  test "collects from tuple2 wrapping record literal" do
    expr = %{
      op: :tuple2,
      left: %{value: 2, op: :int_literal, union_ctor: "Request"},
      right: %{
        op: :record_literal,
        fields: [
          %{name: "url", expr: %{op: :field_access, arg: "r", field: "url"}}
        ]
      }
    }

    assert ParamFieldInference.infer(%{expr: expr, args: ["r"]}) == %{"r" => ["url"]}
  end

  test "collects string-arg field_access on function param" do
    expr = %{
      op: :call,
      name: "command",
      args: [
        %{
          op: :tuple2,
          left: %{value: 2, op: :int_literal, union_ctor: "Request"},
          right: %{
            op: :record_literal,
            fields: [
              %{name: "method", expr: %{op: :field_access, arg: "r", field: "method"}},
              %{name: "url", expr: %{op: :field_access, arg: "r", field: "url"}},
              %{name: "body", expr: %{op: :field_access, arg: "r", field: "body"}}
            ]
          }
        }
      ]
    }

    assert ParamFieldInference.infer(%{expr: expr, args: ["r"]}) == %{
             "r" => ["method", "url", "body"]
           }
  end
end
