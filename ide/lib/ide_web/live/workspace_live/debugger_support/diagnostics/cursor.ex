defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.Cursor do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.{Fingerprint, Preview}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type events :: Types.events()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type timeline_event :: Types.timeline_event()
  @type execution_model :: Types.execution_model()
  @type diagnostics_preview_result :: Types.diagnostics_preview_result()
  @type surface_contracts_at_cursor :: Types.surface_contracts_at_cursor()
  @type surface_fingerprints_at_cursor :: Types.surface_fingerprints_at_cursor()
  @type elm_introspect :: Types.elm_introspect()
  @type runtime_fingerprint :: DebuggerTypes.runtime_fingerprint()

  @spec selected_event(events(), maybe_non_neg_integer()) :: timeline_event() | nil
  defp selected_event(events, cursor_seq) when is_list(events) do
    case Timeline.normalize_cursor_seq(events, cursor_seq) do
      seq when is_integer(seq) -> Enum.find(events, &(&1.seq == seq))
      _ -> nil
    end
  end

  @spec diagnostics_preview_at_cursor(events(), maybe_non_neg_integer()) ::
          diagnostics_preview_result()
  def diagnostics_preview_at_cursor(events, cursor_seq) when is_list(events) do
    case Preview.event_diagnostic_preview(selected_event(events, cursor_seq)) do
      [] ->
        selected = selected_event(events, cursor_seq)
        watch = if selected, do: Map.get(selected, :watch), else: nil
        companion = if selected, do: Map.get(selected, :companion), else: nil
        phone = if selected, do: Map.get(selected, :phone), else: nil

        watch_rows = Preview.model_diagnostic_preview(watch)
        companion_rows = Preview.model_diagnostic_preview(companion)
        phone_rows = Preview.model_diagnostic_preview(phone)

        cond do
          watch_rows != [] ->
            %{source: "cursor_model", rows: watch_rows}

          companion_rows != [] ->
            %{source: "cursor_model_companion", rows: companion_rows}

          phone_rows != [] ->
            %{source: "cursor_model_phone", rows: phone_rows}

          true ->
            %{source: "none", rows: []}
        end

      rows ->
        %{source: "event_payload", rows: rows}
    end
  end

  @spec debugger_contract_at_cursor(events(), maybe_non_neg_integer()) ::
          surface_contracts_at_cursor()
  def debugger_contract_at_cursor(events, cursor_seq) when is_list(events) do
    case selected_event(events, cursor_seq) do
      %{} = selected ->
        %{
          watch: runtime_debugger_contract(Map.get(selected, :watch)),
          companion: runtime_debugger_contract(Map.get(selected, :companion)),
          phone: runtime_debugger_contract(Map.get(selected, :phone))
        }

      _ ->
        %{watch: nil, companion: nil, phone: nil}
    end
  end

  @spec elm_introspect_at_cursor(events(), maybe_non_neg_integer()) ::
          surface_contracts_at_cursor()
  def elm_introspect_at_cursor(events, cursor_seq),
    do: debugger_contract_at_cursor(events, cursor_seq)

  @spec fingerprints_at_cursor(events(), maybe_non_neg_integer()) ::
          surface_fingerprints_at_cursor()
  def fingerprints_at_cursor(events, cursor_seq) when is_list(events) do
    case selected_event(events, cursor_seq) do
      %{} = selected ->
        %{
          watch: Fingerprint.from_runtime(Map.get(selected, :watch)),
          companion: Fingerprint.from_runtime(Map.get(selected, :companion)),
          phone: Fingerprint.from_runtime(Map.get(selected, :phone))
        }

      _ ->
        %{watch: nil, companion: nil, phone: nil}
    end
  end

  @spec runtime_debugger_contract(execution_model()) :: elm_introspect() | nil
  defp runtime_debugger_contract(nil), do: nil
  defp runtime_debugger_contract(%{} = rt), do: RuntimeArtifacts.introspect(rt)
  defp runtime_debugger_contract(_), do: nil
end
