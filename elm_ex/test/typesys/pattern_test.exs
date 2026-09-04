defmodule ElmEx.Typesys.PatternTest do
  use ExUnit.Case, async: true

  alias ElmEx.Typesys.{Env, Kernel, Pattern}

  test "recovers as and cons from unknown source" do
    assert {:ok, %{kind: :cons, head: %{kind: :var, name: "n"}, tail: %{kind: :wildcard}}} =
             Pattern.recover("n :: _")

    assert {:ok, %{kind: :alias, bind: "whole", pattern: %{kind: :cons}}} =
             Pattern.recover("n :: _ as whole")

    assert {:ok, %{kind: :constructor, name: "Just", arg_pattern: %{kind: :constructor, name: "Just"}}} =
             Pattern.recover("Just (Just n)")

    assert {:ok, %{kind: :alias, bind: "user", pattern: %{kind: :record, fields: ["address"]}}} =
             Pattern.recover("({ address } as user)")

    assert {:ok, %{kind: :record, fields: ["city", "zip"]}} = Pattern.recover("{ city, zip }")
  end

  test "nested Just (Just n) is missing Nothing and Just Nothing" do
    env = Kernel.install(Env.new())

    {_redundant, missing} =
      Pattern.analyze(
        [
          %{
            kind: :constructor,
            name: "Just",
            arg_pattern: %{kind: :constructor, name: "Just", bind: "n"}
          }
        ],
        env
      )

    assert "Nothing" in missing
    assert Enum.any?(missing, &String.contains?(&1, "Nothing"))
    assert Enum.any?(missing, &String.starts_with?(&1, "Just"))
  end

  test "Just _ then Just n is redundant" do
    env = Kernel.install(Env.new())

    {redundant, missing} =
      Pattern.analyze(
        [
          %{kind: :constructor, name: "Just", bind: "_"},
          %{kind: :constructor, name: "Just", bind: "n"},
          %{kind: :constructor, name: "Nothing"}
        ],
        env
      )

    assert 1 in redundant
    assert missing == []
  end

  test "cons-in-cons still misses [] and a singleton tail" do
    env = Kernel.install(Env.new())

    {_redundant, missing} =
      Pattern.analyze(
        [
          %{
            kind: :cons,
            head: %{kind: :var, name: "a"},
            tail: %{
              kind: :cons,
              head: %{kind: :var, name: "b"},
              tail: %{kind: :var, name: "rest"}
            }
          }
        ],
        env
      )

    assert "[]" in missing
    assert Enum.any?(missing, &String.contains?(&1, "::"))
  end

  test "tuple of Maybes reports the uncovered product" do
    env = Kernel.install(Env.new())

    {_redundant, missing} =
      Pattern.analyze(
        [
          %{
            kind: :tuple,
            elements: [
              %{kind: :constructor, name: "Just", bind: "a"},
              %{kind: :wildcard}
            ]
          }
        ],
        env
      )

    assert Enum.any?(missing, &String.contains?(&1, "Nothing"))
  end

  test "aliased constructors are not reported unreachable" do
    env =
      Env.new()
      |> Kernel.install()
      |> Env.put_import_lookup(%{alias_map: %{"Health" => "Pebble.Health"}})

    {redundant, missing} =
      Pattern.analyze(
        [
          %{kind: :constructor, name: "Health.HeartRateUpdate"},
          %{kind: :constructor, name: "Health.HrvUpdate"},
          %{kind: :constructor, name: "Health.MovementUpdate"},
          %{kind: :constructor, name: "Health.SignificantUpdate"},
          %{kind: :constructor, name: "Health.SleepUpdate"}
        ],
        env
      )

    assert redundant == []
    assert missing == []
  end
end
