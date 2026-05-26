defmodule Ide.Debugger.SourceRevisionTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SourceRevision

  test "compute is stable for the same path and source" do
    rev = SourceRevision.compute("src/Main.elm", "module Main exposing (main)")
    assert rev == SourceRevision.compute("src/Main.elm", "module Main exposing (main)")
    assert byte_size(rev) == 12
  end

  test "compute changes when source changes" do
    a = SourceRevision.compute("src/Main.elm", "a")
    b = SourceRevision.compute("src/Main.elm", "b")
    assert a != b
  end
end
