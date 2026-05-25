defmodule Ide.Debugger.Types.StartEventPayload do
  @moduledoc "Payload for `debugger.start` session events."

  @type t :: %{
          optional(:launch_reason) => String.t(),
          optional(:watch_profile_id) => String.t(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec from_session(String.t(), String.t()) :: t()
  def from_session(launch_reason, watch_profile_id)
      when is_binary(launch_reason) and is_binary(watch_profile_id) do
    %{launch_reason: launch_reason, watch_profile_id: watch_profile_id}
  end
end
