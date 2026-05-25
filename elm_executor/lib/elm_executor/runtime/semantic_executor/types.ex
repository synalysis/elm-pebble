defmodule ElmExecutor.Runtime.SemanticExecutor.Types do
  @moduledoc false

  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types.{
    CommandMap,
    ViewOutputRow,
    ViewTreeNode
  }

  @type runtime_value :: EvalTypes.runtime_value()

  @type core_ir :: EvalTypes.core_ir()

  @type eval_context :: map()

  @type runtime_model :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type view_tree_node :: ViewTreeNode.t()

  @type view_tree :: ViewTreeNode.view_tree()

  @type command_map :: CommandMap.t()

  @type introspect :: map()

  @type launch_context :: map()

  @type execution_request :: map()

  @type exec_error ::
          atom()
          | String.t()
          | tuple()
          | {:invalid_core_ir, [map()]}
          | {:invalid_core_ir, term()}

  @type view_output_row :: ViewOutputRow.t()

  @type view_output :: ViewOutputRow.view_output()

  @type expr :: CoreIRTypes.Expr.t() | CoreIRTypes.Expr.wire_expr() | nil

  @type message_value :: runtime_value() | EvalTypes.ctor_map()

  @type draw_args :: {:ok, [integer()]} | :error

  @type draw_args_mixed :: {:ok, list()} | :error

  @type path_args :: {:ok, map()} | :error

  @type point_pair :: {:ok, [integer()]} | :error

  @type point_list :: {:ok, [[integer()]]} | :error

  @type tagged_value :: {:ok, integer(), runtime_value()} | :error

  @type tagged_values :: {:ok, [runtime_value()]} | :error

  @type pebble_ui_normalizer :: (runtime_value() -> {:ok, ViewTreeNode.t()} | :error)
end
