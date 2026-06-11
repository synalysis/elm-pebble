defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util.Debugger do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type wire_input :: Types.wire_input()
  @type execution_model :: Types.execution_model()
  @type debugger_timeline_mode :: Types.debugger_timeline_mode()
  @type debugger_surface_target :: Types.debugger_surface_target()

  @spec normalize_timeline_mode(wire_input()) :: debugger_timeline_mode()
  def normalize_timeline_mode("watch"), do: "watch"
  def normalize_timeline_mode("companion"), do: "companion"
  def normalize_timeline_mode("separate"), do: "separate"
  def normalize_timeline_mode(_), do: "mixed"

  @spec target(wire_input()) :: debugger_surface_target()
  def target("companion"), do: "companion"
  def target("protocol"), do: "companion"
  def target("phone"), do: "companion"
  def target(:companion), do: "companion"
  def target(:protocol), do: "companion"
  def target(:phone), do: "companion"
  def target(_), do: "watch"

  @spec target_runtime(debugger_surface_target(), execution_model(), execution_model()) ::
          execution_model()
  def target_runtime("companion", _watch_runtime, companion_runtime), do: companion_runtime
  def target_runtime(_target, watch_runtime, _companion_runtime), do: watch_runtime

  @spec other_runtime(debugger_surface_target(), execution_model(), execution_model()) ::
          execution_model()
  def other_runtime("companion", watch_runtime, _companion_runtime), do: watch_runtime
  def other_runtime(_target, _watch_runtime, companion_runtime), do: companion_runtime

  @spec companion_or_phone_runtime(execution_model(), execution_model()) :: execution_model()
  def companion_or_phone_runtime(companion_runtime, phone_runtime) do
    cond do
      app_runtime?(companion_runtime) -> companion_runtime
      app_runtime?(phone_runtime) -> phone_runtime
      is_map(companion_runtime) -> companion_runtime
      true -> phone_runtime
    end
  end

  @spec app_runtime?(execution_model()) :: boolean()
  def app_runtime?(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model) || %{}

    is_map(RuntimeArtifacts.introspect(runtime)) or
      (is_map(runtime_model) and
         Enum.any?(Map.keys(runtime_model), fn key ->
           to_string(key) not in [
             "protocol_message_count",
             "protocol_inbound_count",
             "protocol_outbound_count",
             "status"
           ]
         end))
  end

  def app_runtime?(_runtime), do: false
end
