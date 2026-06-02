defmodule Ide.Debugger.TangramViewOutputTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimePreview
  alias Ide.Projects

  @tangram_watch File.read!(
                   Path.join([
                     "priv",
                     "project_templates",
                     "watchface_tangram_time",
                     "src",
                     "Main.elm"
                   ])
                 )

  @tag timeout: 180_000
  test "tangram preview recovers from stale zero-geometry runtime_view_output" do
    slug = "tangram-stale-preview-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "TangramStalePreview",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, _} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: @tangram_watch,
               reason: "tangram_stale_preview",
               source_root: "watch"
             })

    assert {:ok, _} = Debugger.set_watch_profile(project.slug, %{watch_profile_id: "aplite"})

    dt = %{
      "day" => 2,
      "hour" => 9,
      "minute" => 1,
      "month" => 6,
      "second" => 2,
      "year" => 2026,
      "utcOffsetMinutes" => 120,
      "dayOfWeek" => %{"ctor" => "Tuesday", "args" => []}
    }

    assert {:ok, state} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "CurrentDateTime",
               message_value: dt,
               count: 1
             })

    stale_watch =
      put_in(state.watch, [:model, "runtime_view_output"], [
        %{"kind" => "clear", "color" => 4_294_967_295},
        %{"kind" => "circle", "cx" => 0, "cy" => 0, "r" => 0, "color" => 0},
        %{"kind" => "fill_circle", "cx" => 0, "cy" => 0, "r" => 0, "color" => 0},
        %{"kind" => "fill_circle", "cx" => 0, "cy" => 0, "r" => 0, "color" => 0}
      ])

    preview_runtime = RuntimePreview.render_view_from_surface(stale_watch, :watch)
    rows = get_in(preview_runtime, [:model, "runtime_view_output"]) || []

    circle = Enum.find(rows, &(&1["kind"] == "circle"))
    assert circle
    assert circle["cx"] == 72
    assert circle["cy"] == 84
    assert circle["r"] > 0
    assert length(rows) > 4
  end
end
