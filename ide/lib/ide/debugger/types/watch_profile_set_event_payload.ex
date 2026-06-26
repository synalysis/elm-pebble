defmodule Ide.Debugger.Types.WatchProfileSetEventPayload do
  @moduledoc "Payload for `debugger.watch_profile_set` events."
  alias Ide.Debugger.Types

  @type t :: %{
          optional(:watch_profile_id) => String.t(),
          optional(:launch_reason) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_profile(String.t(), String.t()) :: t()
  def from_profile(watch_profile_id, launch_reason)
      when is_binary(watch_profile_id) and is_binary(launch_reason) do
    %{watch_profile_id: watch_profile_id, launch_reason: launch_reason}
  end
end
