defmodule Ide.Debugger.ElmIntrospect.Types do
  @moduledoc """
  Types for static Elm source introspection derived from the elmc frontend AST.
  """

  alias ElmEx.Frontend.Module
  alias Ide.Debugger.Types, as: DebuggerTypes

  @type ast_expr :: map()
  @type ast_declaration :: map()
  @type import_entry :: map()
  @type cmd_call_row :: DebuggerTypes.cmd_call()
  @type introspect_snapshot :: DebuggerTypes.elm_introspect()
  @type view_tree :: map()
  @type view_tree_node :: map()
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
  @type function_cmd_calls_map :: %{optional(String.t()) => [cmd_call_row()]}
  @type module_ref :: Module.t()
  @type exposing_value :: String.t() | [String.t()] | nil
  @type parse_error :: atom() | String.t() | map() | tuple()
  @type json_value :: String.t() | integer() | boolean() | map() | list()
  @type param_list :: [String.t()]
  @type binding_map :: %{optional(atom()) => term(), optional(String.t()) => term()}
  @type case_branch_labels :: {[String.t()], String.t() | nil}
  @type cmd_call_list :: [cmd_call_row()]
  @type string_list :: [String.t()]
  @type wire_pick :: term() | nil
end
