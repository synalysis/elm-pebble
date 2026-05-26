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
  @type elm_introspect :: introspect_payload()
  @type cmd_call :: cmd_call_row()
  @type view_tree :: ViewTreeNode.view_tree() | map()
  @type view_tree_node :: ViewTreeNode.t() | map()
  @type program_outline :: map() | nil
  @type case_subject :: ast_expr() | String.t()

  @type module_scan :: {
          [map()],
          boolean(),
          exposing_value(),
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
  @type binding_map :: %{optional(atom()) => json_value(), optional(String.t()) => json_value()}
  @type case_branch_labels :: {[String.t()], String.t() | nil}
  @type cmd_call_list :: [cmd_call_row()]
  @type string_list :: [String.t()]
  @type wire_pick :: json_value() | nil
  @type function_type_key :: String.t()
  @type function_types_index :: %{optional(function_type_key()) => String.t()}

  @type source_function_args_key :: {String.t(), String.t(), non_neg_integer()}
  @type source_api_metadata :: %{
          aliases: %{optional(String.t()) => String.t()},
          functions: %{optional(source_function_args_key()) => [String.t()]},
          unqualified: %{optional(String.t()) => String.t()}
        }

  @type view_build_metadata :: %{
          optional(:aliases) => %{optional(String.t()) => String.t()},
          optional(:functions) => map(),
          optional(:unqualified) => %{optional(String.t()) => String.t()},
          optional(:source_path) => String.t() | nil,
          optional(:source_lines) => [String.t()],
          optional(:module) => String.t(),
          optional(:module_ref) => Module.t() | nil,
          optional(:function_types) => function_types_index(),
          optional(atom()) => term()
        }
end
