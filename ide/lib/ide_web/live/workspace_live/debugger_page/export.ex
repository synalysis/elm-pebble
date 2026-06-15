defmodule IdeWeb.WorkspaceLive.DebuggerPage.Export do
  @moduledoc false

  alias Ide.Debugger
  alias Ide.Projects
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerPage.{
    Assigns,
    ModelMetadata,
    RuntimeWarnings,
    SessionState,
    WatchProfiles
  }

  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util, as: DebuggerUtil
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type assigns :: Assigns.t()
  @type runtime_input :: SupportTypes.runtime_input()
  @type export_snapshot :: {String.t(), map() | nil, non_neg_integer() | nil}
  @type surface :: :watch | :companion | :phone

  @spec snapshot(assigns(), Project.t() | nil) :: export_snapshot()
  def snapshot(assigns, %Project{} = project) do
    selected_seq = selected_seq_from_assigns(assigns)
    timeline_mode = Map.get(assigns, :debugger_timeline_mode, "mixed")
    event_limit = Map.get(assigns, :debugger_event_limit, 500)

    {:ok, state} =
      project |> Projects.scope_key() |> Debugger.snapshot(event_limit: event_limit)

    timeline_text =
      state
      |> DebuggerSupport.debugger_rows(event_limit)
      |> DebuggerSupport.debugger_rows_for_mode(timeline_mode)
      |> DebuggerSupport.filter_debugger_rows_for_display(Map.get(assigns, :debug_mode, false))
      |> DebuggerSupport.debugger_timeline_text()

    {timeline_text, state, selected_seq}
  end

  def snapshot(assigns, _project) do
    selected_seq = selected_seq_from_assigns(assigns)

    timeline_text =
      assigns
      |> Map.get(:debugger_rows, [])
      |> DebuggerSupport.debugger_rows_for_mode(
        Map.get(assigns, :debugger_timeline_mode, "mixed")
      )
      |> DebuggerSupport.filter_debugger_rows_for_display(Map.get(assigns, :debug_mode, false))
      |> DebuggerSupport.debugger_timeline_text()

    {timeline_text, Map.get(assigns, :debugger_state), selected_seq}
  end

  @spec watch_runtime(map(), non_neg_integer() | nil, non_neg_integer() | nil) ::
          runtime_input() | nil
  def watch_runtime(%{} = state, selected_seq, cursor_seq) do
    surface_runtime(state, selected_seq, cursor_seq, :watch)
  end

  def watch_runtime(_state, _selected_seq, _cursor_seq), do: nil

  @spec companion_runtime(map(), non_neg_integer() | nil, non_neg_integer() | nil) ::
          runtime_input() | nil
  def companion_runtime(%{} = state, selected_seq, cursor_seq) do
    surface_runtime(state, selected_seq, cursor_seq, :companion)
  end

  def companion_runtime(_state, _selected_seq, _cursor_seq), do: nil

  @spec watch_view_runtime(map(), non_neg_integer() | nil, non_neg_integer() | nil) ::
          map() | nil
  def watch_view_runtime(%{} = state, selected_seq, cursor_seq) do
    case surface_runtime(state, selected_seq, cursor_seq, :watch) do
      %{} = watch_runtime ->
        Debugger.render_runtime_preview_for_debugger(
          watch_runtime,
          Map.get(state, :watch),
          :watch
        )

      _ ->
        nil
    end
  end

  def watch_view_runtime(_state, _selected_seq, _cursor_seq), do: nil

  @spec surface_runtime(map(), non_neg_integer() | nil, non_neg_integer() | nil, surface()) ::
          runtime_input() | nil
  def surface_runtime(state, selected_seq, cursor_seq, surface)
      when surface in [:watch, :companion, :phone] do
    seq = selected_seq || cursor_seq

    row_runtime =
      state
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.find(fn row -> row.seq == seq end)
      |> case do
        %{watch_runtime: rt} when surface == :watch and is_map(rt) -> rt
        %{companion_runtime: rt} when surface == :companion and is_map(rt) -> rt
        %{phone_runtime: rt} when surface == :phone and is_map(rt) -> rt
        _ -> nil
      end

    row_runtime ||
      case {surface, DebuggerSupport.snapshot_runtime_at_cursor(Map.get(state, :events, []), seq)} do
        {:watch, %{watch: rt}} ->
          rt

        {:phone, %{phone: rt}} ->
          rt

        {:companion, %{companion: companion, phone: phone}} ->
          DebuggerUtil.companion_or_phone_runtime(companion, phone)
      end
  end

  @spec project_name(Project.t() | nil) :: String.t()
  def project_name(%Project{name: name}) when is_binary(name), do: name
  def project_name(_), do: ""

  @spec project_slug(Project.t() | nil) :: String.t()
  def project_slug(%Project{slug: slug}) when is_binary(slug), do: slug
  def project_slug(_), do: ""

  @spec agent_state_clipboard_text(assigns(), Project.t() | nil) :: String.t()
  def agent_state_clipboard_text(%{} = assigns, project) do
    {timeline_text, state, selected_seq} = snapshot(assigns, project)
    state = state || Map.get(assigns, :debugger_state)
    cursor_seq = Map.get(assigns, :debugger_cursor_seq)

    watch_runtime =
      watch_runtime(state, selected_seq, cursor_seq) ||
        Map.get(assigns, :debugger_watch_runtime)

    DebuggerSupport.debugger_agent_state_markdown(%{
      format_version: "elm-pebble.debugger_state.v1",
      project_name: project_name(project),
      project_slug: project_slug(project),
      timeline_mode: Map.get(assigns, :debugger_timeline_mode, "mixed"),
      timeline_text: timeline_text,
      runtime_model_warnings: RuntimeWarnings.text(watch_runtime),
      watch_model_json: DebuggerSupport.copy_json(ModelMetadata.public_model(watch_runtime)),
      companion_model_json:
        DebuggerSupport.copy_json(
          ModelMetadata.public_model(
            companion_runtime(state, selected_seq, cursor_seq) ||
              Map.get(assigns, :debugger_companion_runtime)
          )
        ),
      rendered_view_json:
        DebuggerSupport.copy_json(
          DebuggerSupport.rendered_tree(
            watch_view_runtime(state, selected_seq, cursor_seq) ||
              Map.get(assigns, :debugger_watch_view_runtime)
          )
        ),
      session_running: session_running?(state),
      session_event_count: session_event_count(state),
      debugger_cursor_seq: cursor_seq,
      selected_timeline_seq: selected_seq,
      watch_profile_id: watch_profile_id(state, project)
    })
  end

  @spec session_running?(map() | nil) :: boolean() | nil
  defp session_running?(state) do
    if is_map(state), do: SessionState.running?(state)
  end

  @spec session_event_count(map() | nil) :: non_neg_integer() | nil
  defp session_event_count(state) do
    if is_map(state), do: length(state.events)
  end

  @spec watch_profile_id(map() | nil, Project.t() | nil) :: String.t() | nil
  defp watch_profile_id(state, project) do
    if is_map(state), do: WatchProfiles.state_id(state, project)
  end

  @spec selected_seq_from_assigns(assigns()) :: non_neg_integer() | nil
  defp selected_seq_from_assigns(assigns) do
    case Map.get(assigns, :debugger_selected_row) do
      %{seq: seq} -> seq
      %{"seq" => seq} -> seq
      _ -> nil
    end
  end
end
