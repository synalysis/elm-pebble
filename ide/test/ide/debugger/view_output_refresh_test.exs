defmodule Ide.Debugger.ViewOutputRefreshTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimePreview
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @tangram_watch File.read!(
                   Path.join([
                     "priv",
                     "project_templates",
                     "watchface_tangram_time",
                     "src",
                     "Main.elm"
                   ])
                 )

  test "tangram MinuteChanged row leaves now unchanged until CurrentDateTime device follow-up" do
    slug = "view-refresh-tangram-elm-semantics-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ViewRefreshTangramSemantics",
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
               reason: "view_refresh_tangram_semantics",
               source_root: "watch"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(project.slug, %{
               "use_simulated_time" => true,
               "simulated_date" => "2026-05-27",
               "simulated_time" => "08:53:00",
               "timezone_offset_min" => 0
             })

    assert {:ok, before} = Debugger.snapshot(project.slug)

    baseline_minute =
      get_in(before, [:watch, :model, "now", "args", Access.at(0), "minute"]) ||
        get_in(before, [:watch, :model, "runtime_model", "now", "args", Access.at(0), "minute"])

    assert is_integer(baseline_minute)

    assert {:ok, state} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "MinuteChanged 54",
               count: 1
             })

    rows =
      state
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(&(&1.target == "watch" and &1.type == "update"))

    minute_row =
      Enum.find(rows, fn row ->
        String.contains?(row.message || "", "MinuteChanged")
      end)

    datetime_row =
      Enum.find(rows, fn row ->
        String.contains?(row.message || "", "CurrentDateTime")
      end)

    assert minute_row, "expected MinuteChanged timeline row, got: #{inspect(rows)}"
    assert datetime_row, "expected CurrentDateTime device follow-up row, got: #{inspect(rows)}"
    assert minute_row.seq < datetime_row.seq

    minute_now =
      get_in(minute_row, [:watch_runtime, :model, "now", "args", Access.at(0)]) ||
        get_in(minute_row, [:watch_runtime, :model, "runtime_model", "now", "args", Access.at(0)])

    assert is_map(minute_now)

    assert minute_now["minute"] == baseline_minute,
           "MinuteChanged must not patch now; expected minute #{baseline_minute}, got #{inspect(minute_now)}"

    datetime_now =
      get_in(datetime_row, [:watch_runtime, :model, "now", "args", Access.at(0)]) ||
        get_in(datetime_row, [
          :watch_runtime,
          :model,
          "runtime_model",
          "now",
          "args",
          Access.at(0)
        ])

    assert is_map(datetime_now)

    assert datetime_now["minute"] == 54,
           "CurrentDateTime device follow-up should apply subscription minute 54, got #{inspect(datetime_now)}"

    minute_preview = RuntimePreview.render_view_from_surface(minute_row.watch_runtime, :watch)
    datetime_preview = RuntimePreview.render_view_from_surface(datetime_row.watch_runtime, :watch)

    minute_label = clock_label(minute_now)
    datetime_label = clock_label(datetime_now)

    assert clock_texts(minute_preview) == [] or
             Enum.all?(clock_texts(minute_preview), &(&1 == minute_label)),
           "preview at MinuteChanged cursor must match pre-step now, got #{inspect(clock_texts(minute_preview))} vs #{minute_label}"

    datetime_rows = get_in(datetime_preview, [:model, "runtime_view_output"]) || []

    datetime_circle =
      Enum.find(datetime_rows, fn row ->
        is_map(row) and row["kind"] == "circle"
      end)

    assert datetime_circle,
           "expected circle in datetime preview, got #{inspect(datetime_rows)}"

    assert datetime_circle["cx"] > 0 and datetime_circle["r"] > 0,
           "expected non-zero datetime preview geometry, got #{inspect(datetime_circle)}"

    if clock_texts(datetime_preview) != [] do
      assert Enum.any?(clock_texts(datetime_preview), &(&1 == datetime_label))
    end
  end

  test "tangram view_output has centered clock geometry after CurrentDateTime" do
    slug = "view-refresh-tangram-geometry-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ViewRefreshTangramGeometry",
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
               reason: "view_refresh_tangram_geometry",
               source_root: "watch"
             })

    assert {:ok, _} = Debugger.set_watch_profile(project.slug, %{watch_profile_id: "aplite"})

    dt = %{
      "day" => 2,
      "hour" => 1,
      "minute" => 15,
      "month" => 6,
      "second" => 1,
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

    view_output = get_in(state, [:watch, :model, "runtime_view_output"]) || []

    circle =
      Enum.find(view_output, fn row ->
        is_map(row) and row["kind"] == "circle"
      end)

    assert circle, "expected circle row in runtime_view_output, got #{inspect(view_output)}"

    assert circle["cx"] == 72,
           "expected centered cx for aplite 144px width, got #{inspect(circle)}"

    assert circle["cy"] == 84,
           "expected centered cy for aplite 168px height, got #{inspect(circle)}"

    assert circle["r"] > 0, "expected non-zero clock radius, got #{inspect(circle)}"

    assert length(view_output) > 4,
           "expected full tangram draw ops, got #{length(view_output)}: #{inspect(view_output)}"

    text_row = Enum.find(view_output, fn row -> is_map(row) and row["kind"] == "text" end)

    assert text_row, "expected text row in runtime_view_output"

    assert text_row["y"] > 40,
           "expected time text below clock center, got #{inspect(text_row)}"

    vector_row = Enum.find(view_output, fn row -> is_map(row) and row["kind"] == "vector_at" end)

    assert vector_row, "expected vector_at row in runtime_view_output"

    assert vector_row["vector_id"] > 0,
           "expected resolved tangram vector resource id, got #{inspect(vector_row)}"
  end

  test "tangram preview refreshes stale zero-geometry runtime_view_output rows" do
    slug = "view-refresh-tangram-stale-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ViewRefreshTangramStale",
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
               reason: "view_refresh_tangram_stale",
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

    watch = state.watch

    stale_watch =
      put_in(watch, [:model, "runtime_view_output"], [
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

  defp clock_label(%{"hour" => hour, "minute" => minute})
       when is_integer(hour) and is_integer(minute) do
    hour = hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour}:#{minute}"
  end

  defp clock_label(_), do: ""

  defp clock_texts(%{model: model}) when is_map(model) do
    view_output = Map.get(model, "runtime_view_output") || []

    for row <- view_output,
        is_map(row),
        row["kind"] in ["text", "text_label"],
        is_binary(row["text"]),
        String.trim(row["text"]) != "",
        do: row["text"]
  end

  defp clock_texts(_), do: []
end
