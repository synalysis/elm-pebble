defmodule Ide.Debugger.TriggerInjectionContext do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TriggerInjection

  @spec build(RuntimeContexts.host(), DeviceDataResponses.apply_ctx()) ::
          TriggerInjection.host()
  def build(host, device_data) when is_map(host) and is_map(device_data) do
    %{
      source_root_for_target: host.source_root_for_target,
      trigger_message_for_surface: host.trigger_message_for_surface,
      apply_step_once: host.apply_step_once,
      append_event: host.append_event,
      apply_device_data_responses: fn state, target, message, message_value ->
        surface = Surface.from_state(state, target)
        model = Surface.app_model(surface)

        DeviceDataResponses.apply_after_step(
          state,
          target,
          message,
          model,
          "subscription_trigger",
          device_data,
          message_value
        )
      end
    }
  end
end
