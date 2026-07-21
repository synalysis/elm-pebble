defmodule ElmEx.IR.TypeSignatureTest do
  use ExUnit.Case

  alias ElmEx.IR.TypeSignature

  test "param_types splits top-level arrows while preserving nested function types" do
    assert TypeSignature.param_types("Font -> Point -> Int -> RenderOp") ==
             ["Font", "Point", "Int"]

    assert TypeSignature.param_types("(Int -> String) -> List Int -> Bool") ==
             ["(Int -> String)", "List Int"]
  end

  test "arity counts only required call arguments" do
    assert TypeSignature.arity("Program () Model Msg") == 0
    assert TypeSignature.arity("List Int -> Int") == 1
    assert TypeSignature.arity("Font -> Point -> Int -> RenderOp") == 3
  end

  test "type_variable? recognizes polymorphic names" do
    assert TypeSignature.type_variable?("a")
    assert TypeSignature.type_variable?("msg")
    refute TypeSignature.type_variable?("Int")
    refute TypeSignature.type_variable?("RenderOp")
  end

  test "extensible_record_field_names strips the row variable and returns field names" do
    assert TypeSignature.extensible_record_field_names("{c | lo : b, hi : b}") == ["lo", "hi"]
    assert TypeSignature.extensible_record_field_names("{ r | x : Float, y : Float }") == ["x", "y"]
    assert TypeSignature.extensible_record_field_names("{x : Float, y : Float}") == []
  end
end
