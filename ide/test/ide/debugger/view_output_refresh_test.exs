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

  test "tangram minute change with ahead-of-simulator payload refreshes view to payload minute" do
    slug = "view-refresh-tangram-payload-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ViewRefreshTangramPayload",
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
               reason: "view_refresh_tangram_payload",
               source_root: "watch"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(project.slug, %{
               "use_simulated_time" => true,
               "simulated_date" => "2026-05-27",
               "simulated_time" => "08:53:00",
               "timezone_offset_min" => 0
             })

    assert {:ok, triggered} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "MinuteChanged 54",
               count: 1
             })

    now =
      get_in(triggered, [:watch, :model, "now", "args", Access.at(0)]) ||
        get_in(triggered, [:watch, :model, "runtime_model", "now", "args", Access.at(0)])

    assert is_map(now)
    assert now["minute"] == 54

    view_output = get_in(triggered, [:watch, :model, "runtime_view_output"]) || []

    texts =
      for row <- view_output,
          is_map(row),
          row["kind"] in ["text", "text_label"],
          is_binary(row["text"]),
          do: row["text"]

    assert Enum.any?(texts, &(&1 == "08:54")),
           "expected rendered time 08:54 from MinuteChanged payload, got #{inspect(texts)}"
  end

  test "debugger preview at MinuteChanged cursor uses latest now for clock text" do
    slug = "view-refresh-cursor-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ViewRefreshCursor",
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
               reason: "view_refresh_cursor",
               source_root: "watch"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(project.slug, %{
               "use_simulated_time" => true,
               "simulated_date" => "2026-05-27",
               "simulated_time" => "08:53:00",
               "timezone_offset_min" => 0
             })

    assert {:ok, state} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "MinuteChanged 54",
               count: 1
             })

    minute_row =
      state
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.find(fn row ->
        row.type == "update" and String.contains?(row.message || "", "MinuteChanged")
      end)

    assert minute_row

    watch_runtime = minute_row.watch_runtime

    assert is_map(watch_runtime),
           "expected timeline row to carry watch runtime at MinuteChanged cursor"

    preview = RuntimePreview.render_view_from_surface(watch_runtime, :watch)

    now =
      get_in(preview, [:model, "runtime_model", "now", "args", Access.at(0)]) ||
        get_in(preview, [:model, "now", "args", Access.at(0)])

    assert is_map(now)
    assert now["minute"] == 54

    expected_label =
      now["hour"]
      |> Integer.to_string()
      |> String.pad_leading(2, "0")
      |> then(fn hour ->
        minute =
          now["minute"]
          |> Integer.to_string()
          |> String.pad_leading(2, "0")

        "#{hour}:#{minute}"
      end)

    texts =
      for row <- get_in(preview, [:model, "runtime_view_output"]) || [],
          is_map(row),
          row["kind"] in ["text", "text_label"],
          is_binary(row["text"]),
          do: row["text"]

    assert Enum.any?(texts, &(&1 == expected_label)),
           "expected preview at MinuteChanged cursor to show #{expected_label}, got #{inspect(texts)}"
  end

  test "tangram minute change refreshes rendered time text in view output" do
    slug = "view-refresh-tangram-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ViewRefreshTangram",
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
               reason: "view_refresh_tangram",
               source_root: "watch"
             })

    assert {:ok, triggered} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "MinuteChanged 42",
               count: 1
             })

    now =
      get_in(triggered, [:watch, :model, "now", "args", Access.at(0)]) ||
        get_in(triggered, [:watch, :model, "runtime_model", "now", "args", Access.at(0)])

    assert is_map(now)
    assert is_integer(now["hour"])
    assert is_integer(now["minute"])

    expected_label =
      now["hour"]
      |> Integer.to_string()
      |> String.pad_leading(2, "0")
      |> then(fn hour ->
        minute =
          now["minute"]
          |> Integer.to_string()
          |> String.pad_leading(2, "0")

        "#{hour}:#{minute}"
      end)

    view_output = get_in(triggered, [:watch, :model, "runtime_view_output"]) || []

    texts =
      for row <- view_output,
          is_map(row),
          row["kind"] in ["text", "text_label"],
          is_binary(row["text"]),
          do: row["text"]

    view_tree = get_in(triggered, [:watch, :view_tree]) || %{}
    tree_texts = collect_view_text(view_tree)

    assert Enum.any?(texts ++ tree_texts, &(&1 == expected_label)),
           "expected rendered time text #{expected_label} from model.now, got view_output=#{inspect(texts)} tree=#{inspect(tree_texts)}"
  end

  defp collect_view_text(node) when is_map(node) do
    own =
      case node["text"] do
        text when is_binary(text) -> [text]
        _ -> []
      end

    children =
      case node["children"] do
        list when is_list(list) -> Enum.flat_map(list, &collect_view_text/1)
        _ -> []
      end

    own ++ children
  end

  defp collect_view_text(_), do: []
end
