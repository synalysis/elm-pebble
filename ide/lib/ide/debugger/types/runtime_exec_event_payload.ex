defmodule Ide.Debugger.Types.RuntimeExecEventPayload do
  @moduledoc """
  Payload for `debugger.runtime_exec` events (`append_runtime_exec_event_for_target/3`).
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ExecutionRuntimeSnapshot

  @type extra :: %{
          optional(:trigger) => String.t(),
          optional(:message) => String.t(),
          optional(:message_source) => String.t() | nil,
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type t :: %{
          optional(:target) => String.t(),
          optional(:engine) => String.t(),
          optional(:source_byte_size) => non_neg_integer(),
          optional(:msg_constructor_count) => non_neg_integer(),
          optional(:update_case_branch_count) => non_neg_integer(),
          optional(:view_case_branch_count) => non_neg_integer(),
          optional(:runtime_model_source) => String.t(),
          optional(:view_tree_source) => String.t(),
          optional(:execution_backend) => String.t(),
          optional(:runtime_mode) => String.t(),
          optional(:external_fallback_reason) => String.t(),
          optional(:followup_message_count) => non_neg_integer(),
          optional(:init_cmd_count) => non_neg_integer(),
          optional(:runtime_model_entry_count) => non_neg_integer(),
          optional(:view_tree_node_count) => non_neg_integer(),
          optional(:runtime_model_sha256) => String.t(),
          optional(:view_tree_sha256) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()

  @spec from_runtime(ExecutionRuntimeSnapshot.wire_map(), String.t(), extra()) :: t()
  def from_runtime(runtime, target_label, extra \\ %{})
      when is_map(runtime) and is_binary(target_label) and is_map(extra) do
    %{
      target: target_label,
      engine: Map.get(runtime, "engine") || Map.get(runtime, :engine) || "unknown",
      source_byte_size: Map.get(runtime, "source_byte_size") || Map.get(runtime, :source_byte_size),
      msg_constructor_count:
        Map.get(runtime, "msg_constructor_count") || Map.get(runtime, :msg_constructor_count),
      update_case_branch_count:
        Map.get(runtime, "update_case_branch_count") ||
          Map.get(runtime, :update_case_branch_count),
      view_case_branch_count:
        Map.get(runtime, "view_case_branch_count") || Map.get(runtime, :view_case_branch_count),
      runtime_model_source:
        Map.get(runtime, "runtime_model_source") || Map.get(runtime, :runtime_model_source),
      view_tree_source: Map.get(runtime, "view_tree_source") || Map.get(runtime, :view_tree_source),
      execution_backend:
        Map.get(runtime, "execution_backend") || Map.get(runtime, :execution_backend),
      runtime_mode: Map.get(runtime, "runtime_mode") || Map.get(runtime, :runtime_mode),
      external_fallback_reason:
        Map.get(runtime, "external_fallback_reason") ||
          Map.get(runtime, :external_fallback_reason),
      followup_message_count:
        Map.get(runtime, "followup_message_count") || Map.get(runtime, :followup_message_count),
      init_cmd_count: Map.get(runtime, "init_cmd_count") || Map.get(runtime, :init_cmd_count),
      runtime_model_entry_count:
        Map.get(runtime, "runtime_model_entry_count") ||
          Map.get(runtime, :runtime_model_entry_count),
      view_tree_node_count:
        Map.get(runtime, "view_tree_node_count") || Map.get(runtime, :view_tree_node_count),
      runtime_model_sha256:
        Map.get(runtime, "runtime_model_sha256") || Map.get(runtime, :runtime_model_sha256),
      view_tree_sha256: Map.get(runtime, "view_tree_sha256") || Map.get(runtime, :view_tree_sha256)
    }
    |> Map.merge(extra)
  end
end
