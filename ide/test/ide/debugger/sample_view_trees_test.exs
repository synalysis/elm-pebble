defmodule Ide.Debugger.SampleViewTreesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SampleViewTrees

  test "watch and companion trees include revision metadata" do
    watch = SampleViewTrees.watch("src/Main.elm", "rev1")
    assert watch["meta"]["revision"] == "rev1"
    assert watch["label"] == "src/Main.elm"

    companion = SampleViewTrees.companion("src/Main.elm", "rev2")
    assert companion["meta"]["revision"] == "rev2"
    assert companion["type"] == "CompanionRoot"
  end

  test "default_for_target returns runtime surface defaults" do
    assert is_map(SampleViewTrees.default_for_target(:watch))
    assert is_map(SampleViewTrees.default_for_target(:phone))
  end
end
