defmodule ElmExecutor.Runtime.CoreIREvaluator.Types do
  @moduledoc false

  @type runtime_scalar ::
          number() | boolean() | String.t() | :nan | :infinity | :neg_infinity

  @type runtime_value :: runtime_scalar() | list() | map() | tuple() | nil

  @type runtime_values :: [runtime_value()]

  @type eval_error :: atom() | tuple() | String.t()

  @type eval_ok :: {:ok, runtime_value()}

  @type eval_result :: eval_ok() | {:error, eval_error()}

  @type pattern_bindings :: env()

  @type pattern_match_result :: {:ok, pattern_bindings()} | :nomatch

  @type builtin_eval_result :: eval_result() | :no_builtin

  @type ops_context :: map()

  @type expr :: map()

  @type env :: map()

  @type core_ir_map :: map()

  @type pair_entry :: {runtime_value(), runtime_value()} | runtime_values() | map()

  @type dict_map :: map()

  @type ctor_name :: String.t()

  @type command_map :: map()

  @type cmd_ok :: {:ok, command_map()}

  @type cmd_eval_result :: cmd_ok() | :no_builtin

  @type json_decoder :: {:json_decoder, atom()} | map()

  @type builtin_partial :: {:builtin_partial, String.t(), runtime_values()}

  @type ctor_map :: map()

  @type maybe_parsed :: {:just, runtime_value()} | :nothing | :invalid

  @type result_parsed :: {:ok, runtime_value()} | {:err, runtime_value()} | :invalid

  @type maybe_ctor_input :: {:just, runtime_value()} | :nothing

  @type result_ctor_input :: {:ok, runtime_value()} | {:err, runtime_value()}

  @type maybe_rep :: map() | non_neg_integer() | {1, runtime_value()}

  @type result_rep :: map() | {0, runtime_value()} | {1, runtime_value()}

  @type extreme_kind :: :max | :min

  @type char_codepoint :: non_neg_integer()

  @type dict_pairs :: [{runtime_value(), runtime_value()}]

  @type eval_stack :: list()

  @type ui_node_map :: map()

  @type color_result :: {:ok, non_neg_integer()} | :error | :no_builtin
end
