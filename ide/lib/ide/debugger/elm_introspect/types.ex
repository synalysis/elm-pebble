defmodule Ide.Debugger.ElmIntrospect.Types do
  @moduledoc false

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes
  alias ElmEx.Frontend.Module
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode
  alias Ide.Debugger.ElmIntrospect.Payload

  @type ast_expr :: AstTypes.expr()
  @type ast_declaration :: map()
  @type import_entry :: Payload.import_entry()
  @type cmd_call_row :: Ide.Debugger.Types.cmd_call()
  @type introspect_snapshot :: Payload.snapshot()
  @type introspect_payload :: Payload.wire_payload()
  @type view_tree :: ViewTreeNode.view_tree() | map()
  @type view_tree_node :: ViewTreeNode.t() | map()
  @type program_outline :: map() | nil
  @type module_scan :: {
          [map()],
          boolean(),
          term(),
          [import_entry()],
          non_neg_integer() | nil,
          non_neg_integer() | nil
        }

  @type declaration_names :: {[String.t()], [String.t()], [String.t()]}
  @type function_cmd_calls_map :: Payload.function_cmd_calls()
  @type module_ref :: Module.t()
  @type exposing_value :: String.t() | [String.t()] | nil
  @type parse_error :: atom() | String.t() | map() | tuple()
  @type json_value :: Payload.json_value()
  @type param_list :: [String.t()]
  @type binding_map :: %{optional(atom()) => term(), optional(String.t()) => term()}
  @type case_branch_labels :: {[String.t()], String.t() | nil}
  @type cmd_call_list :: [cmd_call_row()]
  @type string_list :: [String.t()]
  @type wire_pick :: term() | nil
end
