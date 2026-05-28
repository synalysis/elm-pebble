defmodule Ide.Debugger.CoreIrPreviewLayoutTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimePreview
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerPreview

  @digital_source File.read!("priv/project_templates/watchface_digital/src/Main.elm")
  @tangram_source File.read!("priv/project_templates/watchface_tangram_time/src/Main.elm")
  @tutorial_source File.read!("priv/project_templates/watchface_tutorial_complete/src/Main.elm")

  defp assert_centered_card(rows, screen_h) do
    round_rect = Enum.find(rows, &(is_map(&1) and &1["kind"] == "round_rect"))
    assert round_rect, "expected round_rect in preview output"

    card_y = round_rect["y"]
    card_h = round_rect["h"]

    assert card_y < screen_h * 0.45,
           "expected card above mid-screen, got y=#{card_y} screenH=#{screen_h}"

    assert card_y + card_h < screen_h - 8
  end

  test "digital watchface preview uses core IR layout when available" do
    slug = "core-ir-digital-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "CoreIrDigital",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: @digital_source,
               reason: "core_ir_digital_preview",
               source_root: "watch"
             })

    watch = state.watch
    screen_h = get_in(watch, [:model, "runtime_model", "screenH"]) || 168

    preview_runtime = RuntimePreview.render_view_from_surface(watch, :watch)
    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []

    assert_centered_card(rows, screen_h)

    svg_ops = DebuggerPreview.svg_ops(nil, preview_runtime)
    rect_op = Enum.find(svg_ops, &(&1.kind == :round_rect))
    assert rect_op
    assert rect_op.y < screen_h * 0.45
  end

  test "tangram watchface preview resolves if/case layout via core IR" do
    slug = "core-ir-tangram-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "CoreIrTangram",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: @tangram_source,
               reason: "core_ir_tangram_preview",
               source_root: "watch"
             })

    watch = state.watch
    preview_runtime = RuntimePreview.render_view_from_surface(watch, :watch)
    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []

    assert Enum.any?(
             rows,
             &(is_map(&1) and &1["kind"] in ["vector_at", "fill_circle", "circle", "text"])
           ),
           "expected drawable preview rows for tangram"

    assert not Enum.all?(rows, &(Map.get(&1, "kind") == "unresolved"))
  end

  test "tutorial watchface preview derives layout with Maybe fields in model" do
    slug = "core-ir-tutorial-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "CoreIrTutorial",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tutorial-complete"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: @tutorial_source,
               reason: "core_ir_tutorial_preview",
               source_root: "watch"
             })

    watch = state.watch
    preview_runtime = RuntimePreview.render_view_from_surface(watch, :watch)
    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []

    assert Enum.any?(rows, &(is_map(&1) and &1["kind"] in ["text", "text_label", "fill_rect", "round_rect"])),
           "expected drawable tutorial preview rows"
  end
end
