defmodule ElmEx.DebuggerContract.Payload do
  @moduledoc """
  Declared fields for parser-derived `elm_introspect` snapshots (`ElmEx.DebuggerContract.build_snapshot/2`).

  Runtime maps use **string keys**. Typespecs use atoms where Dialyzer requires them;
  extra keys may appear from API metadata and remain valid via `wire_payload/0`.
  """

  alias ElmEx.DebuggerContract.CmdCall

  @type json_value ::
          String.t()
          | integer()
          | float()
          | boolean()
          | nil
          | [json_value()]
          | %{optional(String.t()) => json_value()}
          | %{optional(atom()) => json_value()}

  @type cmd_op_row :: CmdCall.t() | CmdCall.wire_map()
  @type import_entry :: %{optional(String.t()) => json_value(), optional(atom()) => json_value()}
  @type function_cmd_calls :: %{optional(String.t()) => [cmd_op_row()]}
  @type function_types :: %{optional(String.t()) => String.t()}
  @type view_source_locations :: %{optional(String.t()) => map()}

  @type t :: %{
          optional(:source) => String.t(),
          optional(:source_byte_size) => non_neg_integer(),
          optional(:source_line_count) => non_neg_integer(),
          optional(:module) => String.t(),
          optional(:module_exposing) => json_value(),
          optional(:imported_modules) => [String.t()],
          optional(:import_entries) => [import_entry()],
          optional(:type_aliases) => [String.t()],
          optional(:unions) => [String.t()],
          optional(:functions) => [String.t()],
          optional(:function_cmd_calls) => function_cmd_calls(),
          optional(:init_model) => json_value(),
          optional(:init_case_branches) => [String.t()],
          optional(:init_case_subject) => String.t() | nil,
          optional(:init_cmd_ops) => [cmd_op_row()],
          optional(:init_cmd_calls) => [cmd_op_row()],
          optional(:init_params) => [String.t()],
          optional(:msg_constructors) => [String.t()],
          optional(:msg_constructor_arities) => map(),
          optional(:msg_constructor_arg_types) => map(),
          optional(:update_case_branches) => [String.t()],
          optional(:update_case_subject) => String.t() | nil,
          optional(:update_ctor_model_fields) => %{optional(String.t()) => %{optional(String.t()) => String.t()}},
          optional(:update_cmd_ops) => [cmd_op_row()],
          optional(:update_cmd_calls) => [cmd_op_row()],
          optional(:update_params) => [String.t()],
          optional(:subscription_ops) => [cmd_op_row()],
          optional(:subscription_calls) => [cmd_op_row()],
          optional(:subscriptions_case_branches) => [String.t()],
          optional(:subscriptions_case_subject) => String.t() | nil,
          optional(:subscriptions_params) => [String.t()],
          optional(:view_params) => [String.t()],
          optional(:view_case_branches) => [String.t()],
          optional(:view_case_subject) => String.t() | nil,
          optional(:main_program) => json_value(),
          optional(:ports) => [String.t()],
          optional(:port_module) => String.t() | nil,
          optional(:view_tree) => map(),
          optional(:view_source_locations) => view_source_locations(),
          optional(:view_return_type) => String.t() | nil,
          optional(:function_types) => function_types(),
          optional(String.t()) => json_value(),
          optional(atom()) => json_value()
        }

  @type wire_payload :: t() | %{optional(String.t()) => json_value(), optional(atom()) => json_value()}

  @type snapshot :: %{
          optional(:elm_introspect) => wire_payload(),
          optional(String.t()) => json_value(),
          optional(atom()) => json_value()
        }
end
