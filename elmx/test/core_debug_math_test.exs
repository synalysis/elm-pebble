defmodule Elmx.CoreDebugMathTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.{Debug, Math}

  test "Debug.toString formats tagged constructors" do
    assert Debug.to_string(%{"ctor" => "Just", "args" => [42]}) == "Just 42"
    assert Debug.to_string(%{"ctor" => "Nothing", "args" => []}) == "Nothing"
    assert Debug.to_string({:Ok, 5}) == "Ok 5"
    assert Debug.to_string(:Nothing) == "Nothing"
    assert Debug.to_string(:LT) == "LT"
  end

  test "Debug.toString keeps plain integers separate from Order" do
    assert Debug.to_string(0) == "0"
    assert Debug.to_string(1) == "1"
    assert Debug.to_string([1, 4, 9]) == "[1,4,9]"
  end

  test "Debug.toString formats tuples and records like Elm" do
    assert Debug.to_string({{:Ok, 5}, "5"}) == "(Ok 5,\"5\")"
    assert Debug.to_string({3, [1, 2, 3]}) == "(3,[1,2,3])"
    assert Debug.to_string(%{"name" => "Bob", "zip" => "1000"}) == "{ name = \"Bob\", zip = \"1000\" }"
    assert Debug.to_string({:Char, {:elmx_char, 97}}) == "Char 'a'"
    assert Debug.to_string({:elmx_char, 97}) == "'a'"
    assert Debug.to_string([99]) == "[99]"
    assert Debug.to_string({:elmx_set, ["b", "a"]}) == "Set.fromList [\"a\",\"b\"]"
    assert Debug.to_string({:elmx_dict, [{"b", 2}, {"a", 1}]}) ==
             "HashMap.fromList [(\"a\",1),(\"b\",2)]"
  end

  test "Debug.toString formats nested tuple spines without flattening inner tuples" do
    assert Debug.to_string({{:Just, 42}, :Nothing}) == "(Just 42,Nothing)"
    assert Debug.to_string({{:Ok, 1}, {:Err, "error"}}) == "(Ok 1,Err \"error\")"

    assert Debug.to_string({ {{:Just, 42}, :Nothing}, {{:Ok, 1}, {:Err, "error"}} }) ==
             "((Just 42,Nothing),(Ok 1,Err \"error\"))"
  end

  test "Basics float edge helpers" do
    refute Math.is_nan(1.0)
    assert Math.is_infinite(:infinity)
    refute Math.is_infinite(1.0)
    assert Math.is_nan(:nan)
    assert Math.is_infinite(Math.fdiv(1.0, 0.0))
    assert Math.sqrt(-1.0) == :nan
  end

  test "Debug.toString formats order tuples flat" do
    assert Debug.to_string({:LT, :EQ}) == "(LT,EQ)"
    assert Debug.to_string({{:LT, :EQ}, :GT}) == "(LT,EQ,GT)"
  end

  test "Debug.toString formats triple Maybe tuple from MaybeMap" do
    assert Debug.to_string({{:Just, 20}, {:Nothing, {:Just, "hello"}}}) ==
             "(Just 20,Nothing,Just \"hello\")"
  end

  test "Debug.toString formats union constructor tuple spines" do
    assert Debug.to_string({{:Just, 20}, :Nothing}) == "(Just 20,Nothing)"
    assert Debug.to_string({{:Ok, 20}, {:Err, "error"}}) == "(Ok 20,Err \"error\")"
    assert Debug.to_string({{:Ok, 20}, {:Err, "error"}, {:Ok, "HELLO"}}) == "(Ok 20,Err \"error\",Ok \"HELLO\")"
  end
end
