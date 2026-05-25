defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode do
  @moduledoc false

  @type node_type :: String.t()

  @type t :: %{
          optional(:type) => node_type(),
          optional(:label) => String.t(),
          optional(:children) => [t() | map()],
          optional(:value) => term(),
          optional(:op) => String.t(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type view_tree :: t() | %{String.t() => t() | map()}
end
