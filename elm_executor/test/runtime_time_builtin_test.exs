defmodule ElmExecutor.Runtime.TimeBuiltinTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator

  test "Time.millisToPosix returns Posix constructor shape" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Time.millisToPosix",
      "args" => [%{"op" => :int_literal, "value" => 1234}]
    }

    assert {:ok, %{"ctor" => "Posix", "args" => [1234]}} =
             CoreIREvaluator.evaluate(expr, %{}, %{})
  end

  test "Time.toAdjustedMinutes applies zone offset for empty eras" do
    zone_expr = %{
      "op" => :constructor_call,
      "target" => "Time.Zone",
      "args" => [
        %{"op" => :int_literal, "value" => 120},
        %{"op" => :list_literal, "items" => []}
      ]
    }

    posix_expr = %{
      "op" => :constructor_call,
      "target" => "Time.Posix",
      "args" => [%{"op" => :int_literal, "value" => 0}]
    }

    expr = %{
      "op" => :qualified_call,
      "target" => "Time.toAdjustedMinutes",
      "args" => [zone_expr, posix_expr]
    }

    assert {:ok, 120} = CoreIREvaluator.evaluate(expr, %{}, %{})
  end

  test "Elm.Kernel.Time.nowMillis returns an integer timestamp" do
    expr = %{
      "op" => :qualified_call,
      "target" => "Elm.Kernel.Time.nowMillis",
      "args" => [%{"op" => :int_literal, "value" => 0}]
    }

    assert {:ok, value} = CoreIREvaluator.evaluate(expr, %{}, %{})
    assert is_integer(value)
    assert value > 0
  end
end
