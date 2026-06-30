defmodule Elmc.MaybePatternConditionTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Patterns

  test "Just True uses elmc_maybe_just_true helper" do
    code =
      Patterns.pattern_condition(
        "health",
        %{
          kind: :constructor,
          name: "Just",
          arg_pattern: %{kind: :constructor, name: "True"}
        },
        %{}
      )

    assert code == "elmc_maybe_just_true(health)"
    refute code =~ "ELMC_TAG_MAYBE"
  end

  test "Just False uses elmc_maybe_just_false helper" do
    code =
      Patterns.pattern_condition(
        "flag",
        %{
          kind: :constructor,
          name: "Just",
          arg_pattern: %{kind: :constructor, name: "False"}
        },
        %{}
      )

    assert code == "elmc_maybe_just_false(flag)"
  end

  test "bare Just uses elmc_maybe_is_just helper" do
    code =
      Patterns.pattern_condition(
        "now",
        %{kind: :constructor, name: "Just", arg_pattern: %{kind: :wildcard}},
        %{}
      )

    assert code == "elmc_maybe_is_just(now)"
  end

  test "Nothing uses elmc_maybe_is_nothing helper" do
    code = Patterns.pattern_condition("slot", %{kind: :constructor, name: "Nothing"}, %{})

    assert code == "elmc_maybe_is_nothing(slot)"
  end

  test "standalone True uses elmc_value_is_true helper" do
    code = Patterns.pattern_condition("b", %{kind: :constructor, name: "True"}, %{})

    assert code == "elmc_value_is_true(b)"
  end

  test "Just with variable payload uses elmc_maybe_is_just helper" do
    code =
      Patterns.pattern_condition(
        "piece",
        %{
          kind: :constructor,
          name: "Just",
          arg_pattern: %{kind: :var, name: "x"}
        },
        %{}
      )

    assert code == "elmc_maybe_is_just(piece)"
  end

  test "Just with int payload uses elmc_maybe_just_payload helper" do
    code =
      Patterns.pattern_condition(
        "n",
        %{
          kind: :constructor,
          name: "Just",
          arg_pattern: %{kind: :int, value: 42}
        },
        %{}
      )

    assert code =~ "elmc_maybe_just_payload(n)"
    refute code =~ "is_just == 1"
    refute code =~ "ELMC_TAG_MAYBE"
  end

  test "union constructor tag uses elmc_union_tag_matches helper" do
    code =
      Patterns.pattern_condition(
        "msg",
        %{kind: :constructor, tag: 3},
        %{}
      )

    assert code == "elmc_union_tag_matches(msg, 3)"
  end
end
