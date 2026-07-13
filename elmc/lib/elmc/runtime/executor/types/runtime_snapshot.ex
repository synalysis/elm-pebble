defmodule Elmc.Runtime.Executor.Types.RuntimeSnapshot do
  @moduledoc """
  Runtime metadata map attached to successful `Elmc.Runtime.Executor.execute/1` results.

  Runtime maps use string keys (`"engine"`, `"view_tree_source"`, …).
  """

  alias Elmc.Runtime.Executor.Types.WireJson

  @type t :: %{
          optional(:engine) => String.t(),
          optional(:source_root) => String.t(),
          optional(:rel_path) => String.t() | nil,
          optional(:source_byte_size) => non_neg_integer(),
          optional(:msg_constructor_count) => non_neg_integer(),
          optional(:update_case_branch_count) => non_neg_integer(),
          optional(:view_case_branch_count) => non_neg_integer(),
          optional(:runtime_model_source) => String.t(),
          optional(:view_tree_source) => String.t(),
          optional(:runtime_model_entry_count) => non_neg_integer(),
          optional(:view_tree_node_count) => non_neg_integer(),
          optional(:runtime_model_sha256) => String.t(),
          optional(:view_tree_sha256) => String.t(),
          optional(atom()) => WireJson.t(),
          optional(String.t()) => WireJson.t()
        }

  @type wire_map :: t()
end
