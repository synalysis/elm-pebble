defmodule Elmx.CoreDebugMathTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.{Debug, Math}

  test "Debug.toString formats tagged constructors" do
    assert Debug.to_string(%{"ctor" => "Just", "args" => [42]}) == "Just 42"
    assert Debug.to_string(%{"ctor" => "Nothing", "args" => []}) == "Nothing"
  end

  test "Basics float edge helpers" do
    refute Math.is_nan(1.0)
    assert Math.is_infinite(:infinity)
    refute Math.is_infinite(1.0)
  end
end
