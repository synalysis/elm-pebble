defmodule Ide.Debugger.TriggerInjectionContext do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.TriggerInjection

  @spec build(RuntimeContexts.host(), DeviceDataResponses.apply_ctx()) :: TriggerInjection.host()
  def build(host, _device_data) when is_map(host) do
    %{
      source_root_for_target: host.source_root_for_target,
      trigger_message_for_surface: host.trigger_message_for_surface,
      apply_step_once: host.apply_step_once,
      append_event: host.append_event
    }
  end
end
