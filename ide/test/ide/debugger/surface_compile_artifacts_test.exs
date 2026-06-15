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

  test "ensure_attached keeps versioned inline artifacts without recompiling project entrypoint" do
    state = %{
      watch: %{
        model: %{
          "last_source" => "module Main exposing (..)\n",
          "last_path" => "watch/src/Main.elm",
          "source_root" => "watch",
          "elmx_manifest" => %{"contract" => "elmx.runtime_executor.v1"},
          "elmx_revision" => "rev-1"
        },
        shell: %{"debugger_contract" => %{"module" => "Main"}}
      }
    }

    ctx = %{
      session_key_from_state: fn _ -> raise "project compile must not run" end,
      source_root_for_target: fn :watch -> "watch" end,
      merge_runtime_artifacts: fn st, _target, _fields -> st end
    }

    assert SurfaceCompileArtifacts.ensure_attached(state, :watch, ctx) == state
  end

  test "artifacts_for_source_root prefers inline compile before project entrypoint" do
    inline_artifacts = %{
      "debugger_contract" => %{"module" => "InlineMain"},
      "elmx_manifest" => %{"contract" => "elmx.runtime_executor.v1"},
      "elmx_revision" => "inline-rev"
    }

    state = %{
      __reload_precompiled_artifacts__: %{
        source_root: "watch",
        artifacts: inline_artifacts
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
      session_key_from_state: fn _ -> raise "project compile must not run" end,
      source_root_for_target: fn :watch -> "watch" end,
      merge_runtime_artifacts: fn st, _target, _fields -> st end
    }

    assert SurfaceCompileArtifacts.artifacts_for_source_root(state, "watch", ctx) ==
             inline_artifacts
  end
end
