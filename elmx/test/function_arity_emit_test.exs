defmodule Elmx.FunctionArityEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers

  test "function reference prefers callable arity when explicit args are empty" do
    env =
      %{module: "Main", explicit_function_arities: %{"stepAcc" => 0}, function_arities: %{"stepAcc" => 2}}
      |> Map.put(:zero_arity_fns, MapSet.new())

    assert Helpers.function_reference_uncurried("Main", "stepAcc", env) ==
             "&elmx_fn_Main_stepAcc/2"
  end
end
