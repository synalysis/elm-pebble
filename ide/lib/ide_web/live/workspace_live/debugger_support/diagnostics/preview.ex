defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.Preview do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type execution_model :: Types.execution_model()
  @type timeline_event :: Types.timeline_event()
  @type elmc_diagnostic_row :: DebuggerTypes.elmc_diagnostic_row()
  @type diagnostics_preview_source :: Types.diagnostics_preview_source()

  @spec model_diagnostic_preview(execution_model()) :: [elmc_diagnostic_row()]
  def model_diagnostic_preview(nil), do: []

  def model_diagnostic_preview(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}

    list =
      Map.get(model, "elmc_diagnostic_preview") ||
        Map.get(model, :elmc_diagnostic_preview) ||
        []

    if is_list(list), do: list, else: []
  end

  def model_diagnostic_preview(_), do: []

  @spec event_diagnostic_preview(timeline_event() | nil) :: [elmc_diagnostic_row()]
  def event_diagnostic_preview(nil), do: []

  def event_diagnostic_preview(%{} = event) do
    payload = Map.get(event, :payload) || %{}

    list =
      Map.get(payload, :diagnostic_preview) ||
        Map.get(payload, "diagnostic_preview") ||
        []

    if is_list(list), do: list, else: []
  end

  def event_diagnostic_preview(_), do: []

  @spec diagnostics_preview_source_label(diagnostics_preview_source() | String.t()) :: String.t()
  def diagnostics_preview_source_label("event_payload"), do: "selected event payload"
  def diagnostics_preview_source_label("cursor_model"), do: "cursor model (watch)"
  def diagnostics_preview_source_label("cursor_model_companion"), do: "cursor model (companion)"
  def diagnostics_preview_source_label("cursor_model_phone"), do: "cursor model (phone)"
  def diagnostics_preview_source_label("none"), do: "none"
  def diagnostics_preview_source_label(other), do: other
end
