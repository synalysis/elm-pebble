defmodule Elmc.PlanMjsTorecordFieldIndexTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Record

  test "Matrix4.toRecord .m44 uses alphabetical index 15 (not m11 at 0)" do
    base = %{
      op: :qualified_call,
      target: "Math.Matrix4.toRecord",
      args: [%{op: :var, name: "projectionMatrix"}]
    }

    assert Record.field_index_for("m44", Context.new(), base) =~ "15"
    assert Record.field_index_for("m11", Context.new(), base) =~ "0"
    assert Record.resolve_field_index_int("m44", Context.new(), base) == {:ok, 15}
  end

  test "Vector4.toRecord fields are alphabetical w,x,y,z" do
    base = %{
      op: :qualified_call,
      target: "Math.Vector4.toRecord",
      args: [%{op: :var, name: "color"}]
    }

    assert Record.field_index_for("w", Context.new(), base) =~ "0"
    assert Record.field_index_for("x", Context.new(), base) =~ "1"
    assert Record.field_index_for("y", Context.new(), base) =~ "2"
    assert Record.field_index_for("z", Context.new(), base) =~ "3"
  end
end
