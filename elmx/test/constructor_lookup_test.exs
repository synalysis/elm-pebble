defmodule Elmx.ConstructorLookupTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ConstructorLookup

  test "resolve tolerates empty lookup map without raising" do
    assert ConstructorLookup.resolve(%{}, "NotAConstructor", "Main") == nil
    assert ConstructorLookup.resolve(%{}, "Main.Foo", "Main") == nil
  end

  test "resolve finds unqualified constructor entry" do
    lookup = %{
      by_qualified: %{"Main.Just" => %{constructor: "Just", tag: 1}},
      by_unqualified: %{"Just" => %{constructor: "Just", tag: 1}}
    }

    assert %{constructor: "Just"} = ConstructorLookup.resolve(lookup, "Just", "Main")
  end
end
