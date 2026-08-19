defmodule Ide.Debugger.HotReloadTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.HotReload

  test "put_source_fields does not replace a bound TEA entrypoint with a helper file" do
    state = %{
      watch: %{model: %{}},
      companion: %{model: %{}},
      phone: %{model: %{}}
    }

    companion =
      HotReload.put_source_fields(
        state,
        :companion,
        "src/CompanionApp.elm",
        "module CompanionApp exposing (main)\n",
        "phone"
      )

    assert get_in(companion, [:companion, :model, "last_path"]) == "src/CompanionApp.elm"

    after_prefs =
      HotReload.put_source_fields(
        companion,
        :companion,
        "src/CompanionPreferences.elm",
        "module CompanionPreferences exposing (settings)\n",
        "phone"
      )

    assert get_in(after_prefs, [:companion, :model, "last_path"]) == "src/CompanionApp.elm"
    assert get_in(after_prefs, [:companion, :model, "last_source"]) =~ "CompanionApp"

    watch =
      HotReload.put_source_fields(
        state,
        :watch,
        "src/Main.elm",
        "module Main exposing (main)\n",
        "watch"
      )

    after_resources =
      HotReload.put_source_fields(
        watch,
        :watch,
        "src/Pebble/Ui/Resources.elm",
        "module Pebble.Ui.Resources exposing (..)\n",
        "watch"
      )

    assert get_in(after_resources, [:watch, :model, "last_path"]) == "src/Main.elm"
  end

  test "put_source_fields records isolated non-entrypoint preview sources" do
    state = %{
      watch: %{model: %{}},
      companion: %{model: %{}},
      phone: %{model: %{}}
    }

    watch =
      HotReload.put_source_fields(
        state,
        :watch,
        "watch/DebuggerTimeline.elm",
        "module DebuggerTimeline exposing (..)\n",
        "watch"
      )

    assert get_in(watch, [:watch, :model, "last_path"]) == "watch/DebuggerTimeline.elm"
  end
end
