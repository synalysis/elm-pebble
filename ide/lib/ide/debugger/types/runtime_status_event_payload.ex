defmodule Ide.Debugger.Types.RuntimeStatusEventPayload do
  @moduledoc """
  Payload for `debugger.runtime_status` events (`maybe_append_runtime_status_debugger_event/4`).
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ExecutionRuntimeSnapshot

  @type t :: %{
          optional(:target) => String.t(),
          optional(:message) => String.t(),
          optional(:execution_backend) => String.t() | nil,
          optional(:runtime_mode) => String.t() | nil,
          optional(:external_fallback_reason) => String.t() | nil,
          optional(:followup_message_count) => non_neg_integer() | nil,
          optional(:init_cmd_count) => non_neg_integer() | nil,
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()

  @spec from_runtime(ExecutionRuntimeSnapshot.wire_map(), String.t(), String.t()) :: t()
  def from_runtime(runtime, target_label, message)
      when is_map(runtime) and is_binary(target_label) and is_binary(message) do
    %{
      target: target_label,
      message: message,
      execution_backend:
        Map.get(runtime, "execution_backend") || Map.get(runtime, :execution_backend),
      runtime_mode: Map.get(runtime, "runtime_mode") || Map.get(runtime, :runtime_mode),
      external_fallback_reason:
        Map.get(runtime, "external_fallback_reason") ||
          Map.get(runtime, :external_fallback_reason),
      followup_message_count:
        Map.get(runtime, "followup_message_count") || Map.get(runtime, :followup_message_count),
      init_cmd_count: Map.get(runtime, "init_cmd_count") || Map.get(runtime, :init_cmd_count)
    }
  end
end
