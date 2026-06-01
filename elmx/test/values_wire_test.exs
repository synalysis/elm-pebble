defmodule Elmx.ValuesWireTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Values

  test "wire_value maps bare union atoms to ctor wire maps" do
    assert Values.wire_value(:Waiting) == %{"ctor" => "Waiting", "args" => []}
    assert Values.wire_value(:Nothing) == %{"ctor" => "Nothing", "args" => []}
  end

  test "wire_value leaves booleans unchanged" do
    assert Values.wire_value(true) == true
    assert Values.wire_value(false) == false
  end

  test "wire_value normalizes Elm Bool constructors to booleans" do
    assert Values.wire_value(:True) == true
    assert Values.wire_value(:False) == false
    assert Values.wire_value(%{"ctor" => "True", "args" => []}) == true
    assert Values.wire_value(%{"ctor" => "False", "args" => []}) == false
  end

  test "model_to_runtime_map wires union fields in records" do
    assert Values.model_to_runtime_map(%{scene: :Waiting, count: 2}) == %{
             "scene" => %{"ctor" => "Waiting", "args" => []},
             "count" => 2
           }
  end

  test "wire_value maps Maybe and Result tuples to ctor wire maps" do
    assert Values.wire_value({:Just, :Finished}) == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Finished", "args" => []}]
           }

    assert Values.wire_value({:Err, :NoMicrophone}) == %{
             "ctor" => "Err",
             "args" => [%{"ctor" => "NoMicrophone", "args" => []}]
           }

    assert Values.model_to_runtime_map(%{
             status: {:Just, :Finished},
             result: {:Err, :NoMicrophone}
           }) == %{
             "status" => %{
               "ctor" => "Just",
               "args" => [%{"ctor" => "Finished", "args" => []}]
             },
             "result" => %{
               "ctor" => "Err",
               "args" => [%{"ctor" => "NoMicrophone", "args" => []}]
             }
           }
  end
end
