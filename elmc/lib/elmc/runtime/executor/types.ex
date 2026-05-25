defmodule Elmc.Runtime.Executor.Types do
  @moduledoc """
  Shared types for the experimental runtime executor API and message parsing.
  """

  alias ElmEx.CoreIR
  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias Elmc.Runtime.Executor.Types.ExecutionResult
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes

  @type core_ir :: CoreIR.t() | CoreIRTypes.wire_map() | map() | nil
  @type execution_result :: ExecutionResult.t()
  @type execution_wire_result :: ExecutionResult.wire_map()
  @type core_ir_expr :: CoreIRTypes.Expr.t() | CoreIRTypes.Expr.wire_expr()
  @type runtime_model :: SemTypes.runtime_model()
  @type view_tree :: SemTypes.view_tree()
  @type view_output :: SemTypes.view_output()

  @type dynamic_value :: SemTypes.runtime_value()
  @type introspect :: map()
  @type operation :: :set | :inc | :dec | :toggle | :enable | :disable | :reset | :tick
  @type set_payload_type :: :int | :bool | nil
  @type model_key :: String.t() | atom() | nil
  @type key_pair :: {model_key(), model_key()}
  @type message :: String.t()
  @type update_branches :: [String.t()]
  @type segments :: [String.t()]
  @type argument_pair :: {String.t(), String.t()}
  @type value_predicate :: (dynamic_value() -> boolean())
  @type numeric_mutator :: (integer() -> integer())
  @type boolean_mutator :: (boolean() -> boolean())
  @type segment_extractor :: (String.t() -> boolean() | nil)
  @type execution_request :: %{
          optional(:source_root) => String.t() | nil,
          optional(:rel_path) => String.t() | nil,
          optional(:source) => String.t() | nil,
          optional(:introspect) => map() | nil,
          optional(:current_model) => map() | nil,
          optional(:current_view_tree) => map() | nil,
          optional(:message) => String.t() | nil,
          optional(:update_branches) => [String.t()] | nil
        }

  @type execute_error :: :invalid_execution_request
  @type view_tree_source_label :: String.t()
  @type char_code :: non_neg_integer()
  @type closer_stack :: [char_code() | nil]
  @type hash_input :: SemTypes.runtime_value() | map() | list()
end
