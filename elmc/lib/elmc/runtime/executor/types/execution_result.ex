defmodule Elmc.Runtime.Executor.Types.ExecutionResult do
  @moduledoc """
  Successful return map from `Elmc.Runtime.Executor.execute/1`.
  """

  alias Elmc.Runtime.Executor.Types.{RuntimeSnapshot, ViewTree, WireJson}

  @type model_patch :: %{
          optional(atom()) => WireJson.t(),
          optional(String.t()) => WireJson.t()
        }

  @type wire_model_patch :: model_patch()

  @type protocol_event :: %{optional(atom()) => WireJson.t(), optional(String.t()) => WireJson.t()}

  @type followup_message :: protocol_event() | String.t()

  @type t :: %{
          required(:model_patch) => wire_model_patch(),
          required(:view_output) => [ViewTree.t()],
          required(:runtime) => RuntimeSnapshot.t(),
          required(:protocol_events) => [protocol_event()],
          required(:followup_messages) => [followup_message()],
          optional(:view_tree) => ViewTree.t() | nil,
          optional(atom()) => WireJson.t(),
          optional(String.t()) => WireJson.t()
        }

  @type wire_map :: t() | %{optional(atom()) => WireJson.t(), optional(String.t()) => WireJson.t()}
end
