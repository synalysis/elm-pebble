defmodule Elmc.Runtime.Executor.Types do
  @moduledoc """
  Shared types for the experimental runtime executor API and message parsing.
  """

  alias ElmEx.CoreIR
  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmEx.DebuggerContract.Payload, as: IntrospectPayload
  alias Elmc.Runtime.Executor.Types.{ExecutionResult, ViewTree, WireJson}

  @type core_ir :: CoreIR.t() | CoreIRTypes.wire_map() | nil
  @type execution_result :: ExecutionResult.t()
  @type execution_wire_result :: ExecutionResult.wire_map()
  @type core_ir_expr :: CoreIRTypes.Expr.t() | CoreIRTypes.Expr.wire_expr()
  @type runtime_model :: %{optional(String.t()) => WireJson.t(), optional(atom()) => WireJson.t()}
  @type view_tree :: ViewTree.t()
  @type view_output :: [ViewTree.t()]

  @type dynamic_value :: WireJson.t() | atom()
  @type introspect :: IntrospectPayload.wire_payload()
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
          optional(:introspect) => introspect() | nil,
          optional(:current_model) => runtime_model() | nil,
          optional(:current_view_tree) => view_tree() | nil,
          optional(:message) => String.t() | nil,
          optional(:update_branches) => [String.t()] | nil
        }

  @type execute_error :: :invalid_execution_request
  @type view_tree_source_label :: String.t()
  @type char_code :: non_neg_integer()
  @type closer_stack :: [char_code() | nil]
  @type hash_input :: WireJson.t() | String.t() | integer() | [hash_input()]
end
