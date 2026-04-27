defmodule Ide.Packages.VersionResolverTest do
  use ExUnit.Case, async: true

  alias Ide.Packages.VersionResolver

  test "chooses latest version when no constraint is provided" do
    assert {:ok, "2.1.0"} =
             VersionResolver.resolve_best(["1.0.0", "2.1.0", "2.0.5"], nil)
  end

  test "respects exact constraint" do
    assert {:ok, "1.0.5"} =
             VersionResolver.resolve_best(["1.0.5", "1.0.4"], "1.0.5")
  end

  test "respects elm-style range constraint" do
    assert {:ok, "1.2.0"} =
             VersionResolver.resolve_best(["2.0.0", "1.2.0", "1.0.0"], "1.0.0 <= v < 2.0.0")
  end

  test "returns compatibility error when no candidate fits the range" do
    assert {:error, :no_compatible_version} =
             VersionResolver.resolve_best(["2.0.0", "2.1.0"], "1.0.0 <= v < 2.0.0")
  end
end
