defmodule Ide.Debugger.DigitalPreviewLayoutTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.StepExecution
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias ElmExecutor.Runtime.SemanticExecutor

  @digital_source File.read!("priv/project_templates/watchface_digital/src/Main.elm")

  test "digital watchface preview keeps centered card layout after render_view_from_surface" do
    slug = "digital-preview-layout-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "DigitalPreviewLayout",
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
               reason: "digital_preview_layout",
               source_root: "watch"
             })

    watch = state.watch
    screen_h = get_in(watch, [:model, "runtime_model", "screenH"]) || 168

    before_rows = get_in(watch, [:model, "runtime_view_output"]) || []

    before_rect =
      Enum.find(before_rows, fn row -> is_map(row) and row["kind"] == "round_rect" end)

    preview_runtime = RuntimePreview.render_view_from_surface(watch, :watch)
    assert is_map(preview_runtime)

    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []

    round_rect =
      Enum.find(rows, fn row -> is_map(row) and row["kind"] == "round_rect" end)

    assert round_rect, "expected round_rect in preview output, got #{inspect(rows)}"

    if before_rect do
      assert before_rect["y"] < screen_h * 0.45,
             "step output already misplaced: y=#{before_rect["y"]} screenH=#{screen_h}"
    end

    card_y = round_rect["y"]
    card_h = round_rect["h"]

    # Card should be vertically centered (cardY = (screenH - cardH) // 2), not pinned to bottom.
    assert card_y < screen_h * 0.45,
           "expected card above mid-screen, got y=#{card_y} screenH=#{screen_h}"

    assert card_y + card_h < screen_h - 8,
           "expected card not flush to bottom, got y=#{card_y} h=#{card_h} screenH=#{screen_h}"

    svg_ops = DebuggerPreview.svg_ops(nil, preview_runtime)
    rect_op = Enum.find(svg_ops, &(&1.kind == :round_rect))

    assert rect_op.y == card_y
  end

  test "semantic view preview evaluates centered cardY for digital template" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@digital_source, "Main.elm")

    view_tree = ei["view_tree"]
    runtime_model = %{"screenW" => 144, "screenH" => 168, "timeString" => "08:53"}

    rows =
      SemanticExecutor.derive_view_output_preview(view_tree, runtime_model, %{
        elm_introspect: ei
      })

    round_rect = Enum.find(rows, &(&1["kind"] == "round_rect"))
    assert round_rect

    assert round_rect["y"] < 60,
           "expected centered cardY, got #{inspect(round_rect)}"

    execution_model = %{"elm_introspect" => ei, "screen_width" => 144, "screen_height" => 168}

    supplemented =
      StepExecution.supplement_parser_runtime_view_output(
        execution_model,
        view_tree,
        runtime_model
      )

    sup_rect = Enum.find(supplemented, &(&1["kind"] == "round_rect"))
    assert sup_rect
    assert sup_rect["y"] < 60, "supplement_parser y=#{sup_rect["y"]}, expected centered layout"
  end

  test "preview re-derives layout instead of reusing stale step runtime_view_output coordinates" do
    slug = "digital-preview-fresh-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "DigitalPreviewFresh",
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
               reason: "digital_preview_freshness",
               source_root: "watch"
             })

    watch = state.watch
    screen_h = get_in(watch, [:model, "runtime_model", "screenH"]) || 168

    stale_y = trunc(screen_h * 0.9)

    watch_with_stale =
      put_in(watch, [:model, "runtime_view_output"], [
        %{"kind" => "round_rect", "x" => 0, "y" => stale_y, "w" => 100, "h" => 40, "radius" => 8}
      ])

    preview_runtime = RuntimePreview.render_view_from_surface(watch_with_stale, :watch)
    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []
    round_rect = Enum.find(rows, &(&1["kind"] == "round_rect"))

    assert round_rect
    assert round_rect["y"] < screen_h * 0.45,
           "expected fresh layout, not stale y=#{round_rect["y"]}"
  end
end
