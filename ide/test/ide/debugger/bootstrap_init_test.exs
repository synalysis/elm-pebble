defmodule Ide.Debugger.BootstrapInitTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.ElmIntrospectSnapshot
  alias Ide.Debugger.RuntimeExecutor

  test "clear_companion_bootstrap_flags removes defer_surface_effects" do
    state = BootstrapInit.with_companion_bootstrap_flags(%{})
    assert BootstrapInit.defer_surface_effects?(state)
    assert BootstrapInit.parser_only?(state)

    cleared = BootstrapInit.clear_companion_bootstrap_flags(state)

    refute BootstrapInit.defer_surface_effects?(cleared)
    refute BootstrapInit.parser_only?(cleared)
    refute Map.has_key?(cleared, :debugger_skip_blocking_compile)
  end

  describe "parser-only companion bootstrap" do
    test "apply uses introspect init without executor when parser_only flag is set" do
      ei = %{
        "init_model" => %{"count" => 0},
        "view_tree" => %{"kind" => "column", "children" => []},
        "msg_constructors" => []
      }

      state =
        %{
          companion: %{model: %{}, shell: %{}}
        }
        |> BootstrapInit.with_companion_bootstrap_flags()

      ctx = %{
        executor: RuntimeExecutor,
        attach_compile_artifacts: fn st, _target, _ei -> st end,
        hydrate_runtime_model: fn model, _msg, _path -> model end,
        append_event: fn st, _type, _payload -> st end,
        append_debugger_event: fn st, _kind, _target, _msg, _src, _opts -> st end,
        runtime_status_after_init: fn st, _target, _exec, _ei -> st end,
        apply_runtime_followups: fn st, _target, _msg, _src, _followups -> st end,
        drain_app_message_queue: fn _st, _target -> flunk("drain should be deferred") end
      }

      result = ElmIntrospectSnapshot.apply(state, ei, :companion, "module Main where", "Main.elm", ctx)

      assert get_in(result, [:companion, :model, "runtime_model"]) == %{"count" => 0}
      assert get_in(result, [:companion, :model, "elm_executor", "execution_backend"]) == "parser_only"
    end

    test "merge_from_source skips after_apply when defer_surface_effects is set" do
      state = %{watch: %{model: %{}, shell: %{}}} |> BootstrapInit.with_companion_bootstrap_flags()

      snapshot_ctx = %{
        executor: RuntimeExecutor,
        attach_compile_artifacts: fn st, _target, _ei -> st end,
        hydrate_runtime_model: fn model, _msg, _path -> model end,
        append_event: fn st, _type, _payload -> st end,
        append_debugger_event: fn st, _kind, _target, _msg, _src, _opts -> st end,
        runtime_status_after_init: fn st, _target, _exec, _ei -> st end,
        apply_runtime_followups: fn st, _target, _msg, _src, _followups -> st end,
        drain_app_message_queue: fn st, _target -> st end
      }

      merge_ctx = %{
        apply_snapshot: snapshot_ctx,
        after_apply: fn _st, _target, _source_root -> flunk("init surface effects should be deferred") end,
        apply_simulator_settings: fn st -> st end,
        introspect_event_payload: fn _ei, _rel, _root -> nil end
      }

      source = """
      module Main exposing (main)

      main =
          1
      """

      assert {st, _payload} =
               ElmIntrospectSnapshot.merge_from_source(state, "Main.elm", source, "watch", merge_ctx)

      assert get_in(st, [:watch, :model, "runtime_model"]) != nil
    end
  end
end
