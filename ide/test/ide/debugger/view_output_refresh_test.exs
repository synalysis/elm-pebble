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
        get_in(datetime_row, [:watch_runtime, :model, "runtime_model", "now", "args", Access.at(0)])

    assert is_map(datetime_now)
    assert datetime_now["minute"] == 54,
           "CurrentDateTime device follow-up should apply subscription minute 54, got #{inspect(datetime_now)}"

    minute_preview = RuntimePreview.render_view_from_surface(minute_row.watch_runtime, :watch)
    datetime_preview = RuntimePreview.render_view_from_surface(datetime_row.watch_runtime, :watch)

    minute_label = clock_label(minute_now)
    datetime_label = clock_label(datetime_now)

    assert clock_texts(minute_preview) == [] or Enum.all?(clock_texts(minute_preview), &(&1 == minute_label)),
           "preview at MinuteChanged cursor must match pre-step now, got #{inspect(clock_texts(minute_preview))} vs #{minute_label}"

    assert Enum.any?(clock_texts(datetime_preview), &(&1 == datetime_label))
  end

  defp clock_label(%{"hour" => hour, "minute" => minute}) when is_integer(hour) and is_integer(minute) do
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
        do: row["text"]
  end

  defp clock_texts(_), do: []
end
