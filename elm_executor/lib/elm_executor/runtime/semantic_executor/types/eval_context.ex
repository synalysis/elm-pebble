defmodule ElmExecutor.Runtime.SemanticExecutor.Types.EvalContext do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.CoreIREvaluator.Types.ConstructorTagEntry
  alias ElmExecutor.Runtime.CoreIREvaluator.Types.RecordAliasIndex
  alias ElmExecutor.Runtime.SemanticExecutor.Types.LaunchContext

  @type function_index_key :: EvalTypes.function_index_key()
  @type function_entry :: EvalTypes.function_entry()

  @type resource_indices :: %{optional(String.t()) => integer()}

  @type record_aliases :: RecordAliasIndex.t()

  @type record_alias_field_types :: %{optional(RecordAliasIndex.key()) => map()}

  @type constructor_tags :: [ConstructorTagEntry.t()]

  @type launch_context :: LaunchContext.t() | LaunchContext.wire_map()

  @type t :: %{
          optional(:module) => String.t(),
          optional(:source_module) => String.t(),
          optional(:functions) => %{optional(function_index_key()) => function_entry()},
          optional(:record_aliases) => record_aliases(),
          optional(:record_alias_field_types) => record_alias_field_types(),
          optional(:constructor_tags) => constructor_tags(),
          optional(:vector_resource_indices) => resource_indices(),
          optional(:bitmap_resource_indices) => resource_indices(),
          optional(:launch_context) => launch_context(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
end
