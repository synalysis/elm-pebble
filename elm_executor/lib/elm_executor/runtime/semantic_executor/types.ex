defmodule ElmExecutor.Runtime.SemanticExecutor.Types do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @type runtime_value :: EvalTypes.runtime_value()

  @type core_ir :: map()

  @type eval_context :: map()

  @type runtime_model :: map()

  @type view_tree_node :: map()

  @type view_tree :: map()

  @type command_map :: map()

  @type introspect :: map()

  @type launch_context :: map()

  @type execution_request :: map()

  @type exec_error :: atom() | String.t() | tuple()

  @type view_output_row :: map()

  @type view_output :: [view_output_row()]

  @type expr :: map() | nil

  @type message_value :: runtime_value() | map()

  @type draw_args :: {:ok, [integer()]} | :error

  @type draw_args_mixed :: {:ok, list()} | :error

  @type path_args :: {:ok, map()} | :error

  @type point_pair :: {:ok, [integer()]} | :error

  @type point_list :: {:ok, [[integer()]]} | :error

  @type tagged_value :: {:ok, integer(), runtime_value()} | :error

  @type tagged_values :: {:ok, [runtime_value()]} | :error

  @type pebble_ui_normalizer :: (runtime_value() -> {:ok, map()} | :error)
end
