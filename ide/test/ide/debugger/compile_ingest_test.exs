defmodule Ide.Debugger.CompileIngestTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.{CompileIngest, RuntimeSurfaceMerge}
  alias Ide.Debugger.Types.{CompileIngestBridge, RuntimeEventAppend}

  test "check_plan resolves wire type and ingest fields" do
    plan = CompileIngest.check_plan(%{status: :ok, checked_path: "/tmp"})

    assert plan.event_type == RuntimeEventAppend.wire_type(:elmc_check)
    assert plan.fields["elmc_check_status"] == "ok"
    assert is_map(plan.event_payload)
  end

  test "merge_fields_into_all_targets updates watch and phone surfaces" do
    state = %{
      running: true,
      watch: %{model: %{"n" => 1}, shell: %{}},
      companion: %{model: %{}, shell: %{}},
      phone: %{model: %{}, shell: %{}}
    }

    next =
      CompileIngest.merge_fields_into_all_targets(
        state,
        CompileIngest.check_plan(%{status: :error, checked_path: "/tmp"}).fields
      )

    assert get_in(next, [:watch, :model, "elmc_check_status"]) == "error"
    assert get_in(next, [:phone, :model, "elmc_check_status"]) == "error"
  end

  test "ingest via plan matches RuntimeSurfaceMerge on two targets" do
    fields = CompileIngest.compile_plan(%{status: :ok, compiled_path: "watch/out"}).fields

    for target <- [:watch, :phone] do
      state = %{target => %{model: %{}, shell: %{}}}
      via_ingest = CompileIngest.merge_fields_into_all_targets(state, fields)
      via_merge = RuntimeSurfaceMerge.merge_into_state(state, target, fields)
      assert get_in(via_ingest, [target, :model]) == get_in(via_merge, [target, :model])
    end
  end

  test "debugger session ingest uses compile plan" do
    slug = "compile_ingest_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)
    assert {:ok, _} = Debugger.start_session(slug)

    attrs =
      CompileIngestBridge.from_compiler_compile_result(%{
        status: :ok,
        compiled_path: "watch/.elmc-build",
        revision: "r1",
        cached?: false,
        output: "ok",
        diagnostics: [],
        error_count: 0,
        warning_count: 0
      })

    assert {:ok, state} = Debugger.ingest_elmc_compile(slug, attrs)
    assert get_in(state, [:watch, :model, "elmc_compile_status"]) == "ok"
    assert hd(state.events).type == RuntimeEventAppend.wire_type(:elmc_compile)
  end
end
