defmodule Elmc.Runtime.Executor.Types do
  @moduledoc """
  Shared types for the experimental runtime executor API and message parsing.
  """

  @type dynamic_value :: term()
  @type runtime_model :: map()
  @type view_tree :: map()
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
  @type execute_error :: :invalid_execution_request
  @type view_tree_source_label :: String.t()
  @type char_code :: non_neg_integer()
  @type closer_stack :: [char_code() | nil]
  @type hash_input :: term()
end
