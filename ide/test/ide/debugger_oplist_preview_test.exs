defmodule Ide.DebuggerOplistPreviewTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Projects

  test "op-list watchface-tutorial-complete reload compiles Core IR and renders drawable preview" do
    slug = "oplist-preview-tutorial-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "TutorialOpListPreview",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tutorial-complete"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, source} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: source,
               reason: "tutorial_oplist_preview",
               source_root: "watch"
             })

    assert get_in(state, [:watch, :view_tree, "type"]) == "windowStack"
    refute get_in(state, [:watch, :view_tree, "type"]) == "previewUnavailable"

    runtime_output = get_in(state, [:watch, :model, "runtime_view_output"]) || []
    assert runtime_output != []

    assert Enum.any?(runtime_output, fn row ->
             is_map(row) and (row["kind"] || row[:kind]) == "text"
           end)
  end

  test "op-list watchface-tangram-time reload compiles Core IR and renders drawable preview" do
    slug = "oplist-preview-tangram-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "TangramOpListPreview",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, source} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: source,
               reason: "tangram_oplist_preview",
               source_root: "watch"
             })

    assert get_in(state, [:watch, :view_tree, "type"]) == "windowStack"
    refute get_in(state, [:watch, :view_tree, "type"]) == "previewUnavailable"

    runtime_output = get_in(state, [:watch, :model, "runtime_view_output"]) || []
    assert runtime_output != []

    assert Enum.any?(runtime_output, fn row ->
             is_map(row) and (row["kind"] || row[:kind]) in ["circle", "fill_circle", "line"]
           end)
  end

  test "game-jump-n-run reload compiles Core IR, ticks update model, and renders drawable preview" do
    slug = "oplist-preview-jnr-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "JumpNRunOpListPreview",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "game-jump-n-run"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, source} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: source,
               reason: "jnr_oplist_preview",
               source_root: "watch"
             })

    assert match?(%{modules: _}, RuntimeArtifacts.decode_core_ir(RuntimeArtifacts.execution_model(state.watch)))
    assert get_in(state, [:watch, :shell, "bitmap_resource_indices", "JumpHero"]) == 1

    initial_offset = get_in(state, [:watch, :model, "runtime_model", "offset"]) || 0

    assert {:ok, ticked} = Debugger.tick(project.slug, %{target: "watch", count: 5})

    assert get_in(ticked, [:watch, :model, "elm_executor", "operation_source"]) ==
             "core_ir_update_eval"

    assert get_in(ticked, [:watch, :model, "runtime_model", "offset"]) > initial_offset

    runtime_output = get_in(ticked, [:watch, :model, "runtime_view_output"]) || []
    assert runtime_output != []

    assert Enum.any?(runtime_output, fn row ->
             is_map(row) and (row["kind"] || row[:kind]) in ["clear", "fill_rect", "bitmap_in_rect"]
           end)
  end
end
