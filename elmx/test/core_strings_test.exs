defmodule Elmx.CoreStringsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Strings

  test "String.toInt returns Maybe values" do
    assert Strings.to_int("42") == {:Just, 42}
    assert Strings.to_int("") == :Nothing
    assert Strings.to_int("nope") == :Nothing
  end

  test "Maybe.withDefault unwraps String.toInt for invalid input" do
    assert Core.maybe_with_default(0, Strings.to_int("")) == 0
    assert Core.maybe_with_default(0, Strings.to_int("12")) == 12
    assert Core.maybe_with_default(0, %{"ctor" => "Err", "args" => ["NOT_AN_INT"]}) == 0
  end

  test "corpus_fixed_random_int overrides random_int when configured" do
    Process.put(:elmx_corpus_fixed_random_int, 99)

    try do
      assert Core.random_int(%{low: 1, high: 100}) == 99
    after
      Process.delete(:elmx_corpus_fixed_random_int)
    end
  end
end
