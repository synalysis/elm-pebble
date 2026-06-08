defmodule Ide.Debugger.SurfaceCompileArtifactsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SurfaceCompileArtifacts

  test "reload precompiled artifacts are scoped to the active source root" do
    watch_artifacts = %{"debugger_contract" => %{"module" => "WatchMain"}}

    state = %{
      __reload_precompiled_artifacts__: %{
        source_root: "watch",
        artifacts: watch_artifacts
      },
      watch: %{
        model: %{
          "last_source" => "module Main exposing (..)\n",
          "last_path" => "watch/src/Main.elm",
          "source_root" => "watch"
        }
      }
    }

    ctx = %{
      session_key_from_state: fn _ -> "session" end,
      source_root_for_target: fn
        :watch -> "watch"
        :companion -> "phone"
        :phone -> "phone"
      end,
      merge_runtime_artifacts: fn st, _target, _fields -> st end
    }

    assert SurfaceCompileArtifacts.artifacts_for_source_root(state, "watch", ctx) ==
             watch_artifacts

    refute get_in(
             SurfaceCompileArtifacts.artifacts_for_source_root(state, "phone", ctx),
             ["debugger_contract", "module"]
           ) == "WatchMain"
  end
end
