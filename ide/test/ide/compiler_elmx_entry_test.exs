defmodule Ide.CompilerElmxEntryTest do
  use ExUnit.Case, async: true

  alias Ide.Compiler

  test "default_elmx_entry_module prefers CompanionApp when both exist" do
    tmp = System.tmp_dir!() |> Path.join("elmx-entry-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "src"))
    File.write!(Path.join(tmp, "src/Main.elm"), "module Main exposing (main)\nmain = 0\n")

    File.write!(
      Path.join(tmp, "src/CompanionApp.elm"),
      "module CompanionApp exposing (main)\nmain = 0\n"
    )

    on_exit(fn -> File.rm_rf!(tmp) end)

    assert Compiler.default_elmx_entry_module(tmp) == "CompanionApp"
  end

  test "default_elmx_entry_module uses sole src module when Main is absent" do
    tmp = System.tmp_dir!() |> Path.join("elmx-entry-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "src"))

    File.write!(
      Path.join(tmp, "src/TriggerSnap.elm"),
      "module TriggerSnap exposing (main)\nmain = 0\n"
    )

    on_exit(fn -> File.rm_rf!(tmp) end)

    assert Compiler.default_elmx_entry_module(tmp) == "TriggerSnap"
  end
end
