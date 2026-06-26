defmodule Ide.Debugger.Types.DeviceDataEventPayload do
  @moduledoc "Payload for `debugger.device_data` simulated device API responses."

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.DeviceRequest

  @type t :: %{
          optional(:target) => String.t(),
          optional(:request) => DeviceRequest.kind(),
          optional(:response_message) => String.t(),
          optional(:response_value) => DeviceRequest.preview(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_request(String.t(), DeviceRequest.t()) :: t()
  def from_request(target, request) when is_binary(target) and is_map(request) do
    %{
      target: target,
      request: Map.get(request, :kind) || Map.get(request, "kind"),
      response_message:
        Map.get(request, :response_message) || Map.get(request, "response_message"),
      response_value: Map.get(request, :preview) || Map.get(request, "preview")
    }
  end
end
