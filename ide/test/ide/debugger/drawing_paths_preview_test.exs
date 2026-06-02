defmodule Ide.Debugger.DrawingPathsPreviewTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimePreview
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @tag timeout: 180_000
  test "paths page preview recovers when stored runtime_view_output omits path drawables" do
    slug = "drawing-paths-preview-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "DrawingPathsPreview",
               "slug" => slug,
               "target_type" => "watchapp",
               "template" => "watch-demo-drawing-showcase"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, _reload_state} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               reason: "drawing_paths_preview",
               source_root: "watch"
             })

    assert {:ok, step_state} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "DownPressed",
               count: 1
             })

    watch = step_state.watch

    runtime_model =
      Map.merge(
        Map.get(watch.model, "runtime_model") || %{},
        %{
          "pageIndex" => 1,
          "screenW" => 144,
          "screenH" => 168,
          "rotationAngle" => 0
        }
      )

    stale_watch =
      watch
      |> put_in([:model, "runtime_model"], runtime_model)
      |> put_in([:model, "runtime_view_output"], [
        %{"kind" => "clear", "color" => 255},
        %{"kind" => "text", "x" => 0, "y" => 2, "w" => 144, "h" => 18, "text" => "Paths 2/8"},
        %{"kind" => "text", "x" => 4, "y" => 152, "w" => 136, "h" => 14, "text" => "Up/Down: page"}
      ])

    preview_runtime = RuntimePreview.render_view_from_surface(stale_watch, :watch)
    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []

    assert Enum.any?(rows, &(&1["kind"] == "path_filled"))
    assert Enum.any?(rows, &(&1["kind"] == "path_outline"))

    rendered = DebuggerSupport.rendered_tree(preview_runtime)

    svg_ops = DebuggerPreview.svg_ops(rendered, preview_runtime)

    assert Enum.any?(svg_ops, &(&1.kind == :path_filled))
    assert Enum.any?(svg_ops, &(&1.kind == :path_outline))

    path_filled = Enum.find(svg_ops, &(&1.kind == :path_filled))
    assert DebuggerPreview.svg_path_d(path_filled, true) =~ "M"
    assert path_filled.fill_color == 248
    assert path_filled.stroke_color == 192
  end
end
