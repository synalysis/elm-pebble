defmodule Elmx.QualifiedHandlesTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Stdlib.Qualified

  @known_targets [
    "List.map",
    "String.split",
    "Dict.get",
    "Set.insert",
    "Array.fromList",
    "Task.map",
    "Json.Decode.field",
    "Json.Encode.null",
    "Maybe.withDefault",
    "Result.andThen",
    "Basics.compare",
    "Basics.clamp",
    "String.append",
    "Maybe.andThen",
    "Basics.negate"
  ]

  test "handles?/1 accepts known stdlib qualified targets and collection prefixes" do
    for target <- @known_targets do
      assert Qualified.handles?(target), "expected #{target} to be handled"
    end

    refute Qualified.handles?("Not.A.Real.Target")
  end

  test "Stdlib.handles_qualified?/1 delegates to Qualified.handles?/1" do
    assert Elmx.Runtime.Stdlib.handles_qualified?("List.map")
    refute Elmx.Runtime.Stdlib.handles_qualified?("Unknown.Target")
  end

  test "every explicit call/2 target in Stdlib.Qualified is handles?" do
    targets = Qualified.explicit_call_targets()

    assert length(targets) >= 100
    assert "List.map" in targets
    assert "String.padRight" in targets
    assert "Json.Decode.map5" in targets

    for target <- targets do
      assert Qualified.handles?(target),
             "expected #{inspect(target)} to be handled (#{length(targets)} explicit targets)"
    end
  end

  test "Stdlib.handles_qualified? tracks Qualified.handles? for collection ops" do
    assert Elmx.Runtime.Stdlib.handles_qualified?("Dict.union")
    assert Elmx.Runtime.Stdlib.handles_qualified?("Array.map")
  end

  test "handles?/1 agrees with qualified_call for List.map" do
    assert Qualified.handles?("List.map")
    assert {:ok, code} = Qualified.call("List.map", "f, xs")
    assert code =~ ".map(f, xs)"
  end
end
