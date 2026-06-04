defmodule Ide.Debugger.DrawingBitmapsPreviewTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimePreview
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @tag timeout: 180_000
  test "static bitmap page preview resolves flat drawBitmapInRect nodes" do
    slug = "drawing-bitmaps-preview-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "DrawingBitmapsPreview",
               "slug" => slug,
               "target_type" => "watchapp",
               "template" => "watch-demo-drawing-showcase"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, _reload_state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               reason: "drawing_bitmaps_preview",
               source_root: "watch"
             })

    assert {:ok, step_state} =
             Enum.reduce(1..3, nil, fn _i, _acc ->
               Debugger.step(project.slug, %{
                 target: "watch",
                 message: "DownPressed",
                 count: 1
               })
             end)

    watch = step_state.watch

    runtime_model =
      Map.merge(
        Map.get(watch.model, "runtime_model") || %{},
        %{
          "pageIndex" => 3,
          "screenW" => 144,
          "screenH" => 168,
          "rotationAngle" => 24_576
        }
      )

    stale_watch =
      watch
      |> put_in([:model, "runtime_model"], runtime_model)
      |> put_in([:model, "runtime_view_output"], [
        %{"kind" => "clear", "color" => 255},
        %{"kind" => "text", "x" => 0, "y" => 2, "w" => 144, "h" => 18, "text" => "Bitmap 4/8"},
        %{"kind" => "text", "x" => 4, "y" => 152, "w" => 136, "h" => 14, "text" => "Up/Down: page"}
      ])

    preview_runtime = RuntimePreview.render_view_from_surface(stale_watch, :watch)
    rendered = DebuggerSupport.rendered_tree(preview_runtime)

    svg_ops =
      rendered
      |> DebuggerPreview.svg_ops(preview_runtime)
      |> DebuggerPreview.resolve_bitmap_svg_ops(project)

    bitmap_in_rect =
      Enum.find(svg_ops, fn op ->
        op.kind == :bitmap_in_rect and op.bitmap_id == 1 and op.x == 8 and op.y == 30
      end)

    assert bitmap_in_rect

    rotated =
      Enum.find(svg_ops, fn op ->
        op.kind == :rotated_bitmap and op.bitmap_id == 1 and op.center_x == 72 and op.center_y == 95
      end)

    assert rotated
    assert rotated.angle == 24_576
  end
end
