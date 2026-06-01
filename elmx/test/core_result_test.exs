defmodule Elmx.CoreResultTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core

  test "result_and_then applies callback on Ok with (function, result) argument order" do
    f = fn text -> {:Ok, String.to_atom(text)} end

    assert Core.result_and_then(f, {:Ok, "imperial"}) == {:Ok, :imperial}
    assert Core.result_and_then(f, %{"ctor" => "Ok", "args" => ["metric"]}) == {:Ok, :metric}
    assert Core.result_and_then(f, {:Err, "nope"}) == {:Err, "nope"}
  end

  test "result_map_error applies callback on Err with (function, result) argument order" do
    f = &String.upcase/1

    assert Core.result_map_error(f, {:Err, "bad"}) == {:Err, "BAD"}
    assert Core.result_map_error(f, {:Ok, 1}) == {:Ok, 1}
  end

  test "runtime_call_parts emits result_andThen with (function, result) order" do
    fun = "unitsFromString"
    result = "Elmx.Runtime.Core.result_map_error(f, decoded)"

    code = Elmx.Runtime.Stdlib.runtime_call_parts("elmx_core_result_and_then", [fun, result])

    assert code ==
             "Elmx.Runtime.Core.result_and_then(unitsFromString, Elmx.Runtime.Core.result_map_error(f, decoded))"
  end

  test "runtime_call_parts emits result_map with (function, result) order" do
    assert Elmx.Runtime.Stdlib.runtime_call_parts("elmx_core_result_map", ["f", "decoded"]) ==
             "Elmx.Runtime.Core.result_map(f, decoded)"
  end
end
