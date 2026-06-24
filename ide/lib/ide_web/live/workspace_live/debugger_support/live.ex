defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Live do
  @moduledoc false
  @dialyzer :no_match

  alias Phoenix.Component
  alias Ide.Debugger
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Live.{Cursor, RuntimeSnapshot, Triggers}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  defdelegate trigger_buttons(debugger_state), to: Triggers
  defdelegate snapshot_runtime_at_cursor(events, cursor_seq), to: RuntimeSnapshot
  defdelegate nearest_surface_runtime_at_or_before(events, upper_seq, surface), to: RuntimeSnapshot
  @default_event_limit 500
  @default_ui_snapshot_timeout_ms 5_000

  @spec assign_defaults(Types.socket()) :: Types.socket()
  def assign_defaults(socket) do
    socket
    |> Component.assign(:debugger_state, nil)
    |> Component.assign(:debugger_event_limit, @default_event_limit)
    |> Component.assign(:debugger_since_seq, nil)
    |> Component.assign(:debugger_types, [])
    |> Component.assign(:debugger_cursor_seq, nil)
    |> Component.assign(:debugger_follow_latest, true)
    |> Component.assign(:debugger_cursor_watch_runtime, nil)
    |> Component.assign(:debugger_cursor_companion_runtime, nil)
    |> Component.assign(:debugger_cursor_phone_runtime, nil)
    |> Component.assign(:debugger_hovered_rendered_scope, nil)
    |> Component.assign(:debugger_hovered_rendered_path, nil)
    |> Component.assign(:debugger_trigger_buttons, [])
    |> Component.assign(:debugger_watch_trigger_buttons, [])
    |> Component.assign(:debugger_companion_trigger_buttons, [])
    |> Component.assign(:debugger_watch_auto_fire, false)
    |> Component.assign(:debugger_companion_auto_fire, false)
    |> Component.assign(:debugger_auto_fire_subscriptions, [])
    |> Component.assign(:debugger_disabled_subscriptions, [])
    |> Component.assign(:debugger_speaker_effect, nil)
    |> Component.assign(:debugger_configuration_draft_values, %{})
    |> Component.assign(:debugger_trigger_modal_open, false)
    |> Component.assign(:debugger_trigger_form, Component.to_form(%{}, as: :debugger_trigger))
    |> Component.assign(:debugger_rows, [])
    |> Component.assign(:debugger_timeline_mode, "mixed")
    |> Component.assign(:debugger_selected_row, nil)
    |> Component.assign(:debugger_watch_runtime, nil)
    |> Component.assign(:debugger_companion_runtime, nil)
    |> Component.assign(:debugger_watch_view_runtime, nil)
    |> Component.assign(:debugger_bootstrap_status, :idle)
    |> Component.assign(:debugger_bootstrap_progress, nil)
    |> Component.assign(:debugger_bootstrap_token, nil)
    |> Component.assign(:debugger_companion_bootstrap_status, :idle)
    |> Component.assign(:debugger_companion_bootstrap_progress, nil)
    |> Component.assign(:debugger_runtime_refresh_ref, nil)
    |> Component.assign(:debugger_runtime_refresh_seq, 0)
  end

  @spec refresh(Types.socket()) :: Types.socket()
  def refresh(socket) do
    case socket.assigns[:project] do
      nil ->
        assign_defaults(socket)

      project ->
        case snapshot_project_state(project, socket) do
          {:ok, debugger_state} ->
            Cursor.assign_timeline(socket, debugger_state)

          :agent_busy ->
            socket
        end
    end
  end

  @spec refresh_following_debugger_latest(Types.socket()) :: Types.socket()
  def refresh_following_debugger_latest(socket) do
    follow_latest? =
      Map.get(socket.assigns, :debugger_follow_latest, Cursor.at_latest?(socket))

    socket = refresh(socket)

    if follow_latest? do
      Cursor.jump_latest(socket)
    else
      socket
    end
  end

  @spec set_debugger_cursor_seq(Types.socket(), Types.wire_input()) :: Types.socket()
  def set_debugger_cursor_seq(socket, value) do
    case parse_since_seq(value) do
      nil ->
        socket

      seq ->
        socket
        |> Cursor.assign_debugger_cursor(seq)
        |> Component.assign(:debugger_follow_latest, false)
    end
  end

  @spec set_debugger_timeline_mode(Types.socket(), Types.wire_input()) :: Types.socket()
  def set_debugger_timeline_mode(socket, value) do
    Component.assign(
      socket,
      :debugger_timeline_mode,
      Util.normalize_debugger_timeline_mode(value)
    )
  end

  @spec jump_latest(Types.socket()) :: Types.socket()
  def jump_latest(socket) do
    socket =
      case socket.assigns[:debugger_state] do
        %{events: events} when is_list(events) and events != [] ->
          [latest | _rest] = events
          Cursor.assign_cursor(socket, latest.seq)

        _ ->
          socket
      end

    Cursor.jump_latest(socket)
  end

  @spec step_back(Types.socket()) :: Types.socket()
  def step_back(socket) do
    Cursor.move_cursor(socket, :back)
  end

  @spec step_forward(Types.socket()) :: Types.socket()
  def step_forward(socket) do
    Cursor.move_cursor(socket, :forward)
  end

  @spec maybe_reload(Types.socket(), String.t() | nil, String.t(), String.t(), String.t() | nil) ::
          Types.socket()
  def maybe_reload(socket, rel_path, content, reason, source_root \\ nil) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        {:ok, _state} =
          Debugger.reload(Projects.scope_key(project), %{
            rel_path: rel_path,
            source: content,
            reason: reason,
            source_root: source_root || "watch"
          })

        refresh(socket)
    end
  end

  @spec snapshot_project_state(Projects.Project.t(), Types.socket()) ::
          {:ok, DebuggerTypes.runtime_state()} | :agent_busy
  defp snapshot_project_state(project, socket) do
    opts = [
      event_limit: socket.assigns[:debugger_event_limit] || @default_event_limit,
      since_seq: socket.assigns[:debugger_since_seq],
      types: socket.assigns[:debugger_types],
      timeout: ui_snapshot_timeout_ms()
    ]

    try do
      {:ok, debugger_state} = Debugger.snapshot(Projects.scope_key(project), opts)
      {:ok, debugger_state}
    catch
      :exit, {:timeout, _} -> :agent_busy
      :exit, _ -> :agent_busy
    end
  end

  @spec ui_snapshot_timeout_ms() :: pos_integer()
  defp ui_snapshot_timeout_ms do
    Application.get_env(:ide, :debugger_ui_snapshot_timeout_ms, @default_ui_snapshot_timeout_ms)
  end

  @spec parse_since_seq(Types.wire_input()) :: Types.maybe_non_neg_integer()
  defp parse_since_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_since_seq(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_since_seq(_value), do: nil
end
