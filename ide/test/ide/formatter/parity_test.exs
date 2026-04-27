defmodule Ide.Formatter.ParityTest do
  use ExUnit.Case, async: true

  alias Ide.Formatter.Parity

  test "discover_fixtures returns nested elm files only" do
    root = Path.join(System.tmp_dir!(), "ide_parity_test_#{System.unique_integer([:positive])}")
    nested = Path.join(root, "nested")
    File.mkdir_p!(nested)
    File.write!(Path.join(root, "A.elm"), "module A exposing (..)\n")
    File.write!(Path.join(nested, "B.elm"), "module B exposing (..)\n")
    File.write!(Path.join(nested, "notes.txt"), "ignore\n")

    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, fixtures} = Parity.discover_fixtures(root)

    rel =
      fixtures
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.sort()

    assert rel == ["A.elm", "nested/B.elm"]
  end

  test "run summary includes category_counts map" do
    root =
      Path.join(System.tmp_dir!(), "ide_parity_summary_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "A.elm"), "module A exposing (..)\n")
    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, result} = Parity.run(fixture_root: root, limit: 1)
    assert is_map(result.category_counts)
    assert is_integer(result.comparable_total)
    assert is_float(result.comparable_parity_pct)
    assert is_integer(result.known_limitations)
    assert is_integer(result.unexpected_formatter_error)
    assert is_integer(result.unexpected_reference_error)
    assert is_integer(result.actionable_total)
    assert is_integer(result.actionable_match)
    assert is_float(result.actionable_parity_pct)
  end

  test "known limitation fixtures are excluded from actionable metrics" do
    root =
      Path.join(System.tmp_dir!(), "ide_parity_known_limit_#{System.unique_integer([:positive])}")

    fixture = Path.join(root, "Elm-0.17/AllSyntax/LineComments/Module.elm")
    File.mkdir_p!(Path.dirname(fixture))
    File.write!(fixture, "value = @\n")
    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, result} = Parity.run(fixture_root: root)
    assert result.total == 1
    assert result.formatter_error == 1
    assert result.known_limitations == 1
    assert result.unexpected_formatter_error == 0
    assert result.actionable_total == 0
    assert result.actionable_match == 0
    assert result.actionable_parity_pct == 0.0
  end
end
