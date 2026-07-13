defmodule ElmEx.CoreIR.Types.Expr do
  @moduledoc """
  Normalized Core IR expression maps use string keys at runtime (`"op"`, `"name"`, …).

  Typespecs use atom keys for Dialyzer compatibility; normalized output from
  `ElmEx.CoreIR.from_ir/2` stringifies all keys. Downstream backends read string
  keys and may coerce known `"op"` values to atoms at evaluation time.
  """

  alias ElmEx.CoreIR.Types, as: CoreIRTypes

  @type op_name :: String.t()

  @type t ::
          int_literal()
          | float_literal()
          | bool_literal()
          | char_literal()
          | string_literal()
          | expr_wrapper()
          | var_expr()
          | var_resolved()
          | add_const()
          | sub_const()
          | add_vars()
          | compare()
          | field_access()
          | field_call()
          | record_literal()
          | record_update()
          | list_literal()
          | tuple2()
          | tuple_expr()
          | tuple_first_expr()
          | tuple_second_expr()
          | tuple_first()
          | tuple_second()
          | string_length_expr()
          | char_from_code_expr()
          | let_in()
          | if_expr()
          | case_expr()
          | constructor_call()
          | lambda()
          | qualified_call()
          | qualified_call1()
          | call()
          | record_alias()
          | unsupported()
          | wire_expr()

  @type wire_expr :: CoreIRTypes.wire_map()

  @typedoc "Child expression before or after Core IR key normalization."
  @type expr_child :: t() | wire_expr()

  @type expr_child_or_name :: expr_child() | String.t()

  @type arg_list :: [expr_child()]

  @type record_field_pair :: {String.t(), expr_child()}
  @type record_field_row :: record_field_pair() | wire_expr()
  @type record_fields :: [record_field_row()] | wire_expr()

  @type case_branch :: %{
          optional(:pattern) => wire_expr(),
          optional(:expr) => expr_child(),
          optional(atom()) => CoreIRTypes.wire_input(),
          optional(String.t()) => CoreIRTypes.wire_input()
        }

  @type field_name_list :: [String.t()]
  @type field_names :: field_name_list() | %{optional(String.t()) => String.t()}

  @type field_types_map :: %{optional(String.t()) => String.t()}

  @type int_literal :: %{required(:op) => op_name(), required(:value) => integer()}
  @type float_literal :: %{required(:op) => op_name(), required(:value) => float()}
  @type bool_literal :: %{required(:op) => op_name(), required(:value) => boolean()}
  @type char_literal :: %{required(:op) => op_name(), required(:value) => String.t()}
  @type string_literal :: %{required(:op) => op_name(), required(:value) => String.t()}

  @type expr_wrapper :: %{
          required(:op) => op_name(),
          optional(:expr) => expr_child(),
          optional(:value_expr) => expr_child(),
          optional(:in_expr) => expr_child()
        }

  @type var_expr :: %{required(:op) => op_name(), required(:name) => String.t()}
  @type var_resolved :: %{required(:op) => op_name(), required(:value_expr) => expr_child()}

  @type add_const :: %{
          required(:op) => op_name(),
          required(:var) => String.t(),
          required(:value) => number()
        }
  @type sub_const :: %{
          required(:op) => op_name(),
          required(:var) => String.t(),
          required(:value) => number()
        }
  @type add_vars :: %{
          required(:op) => op_name(),
          required(:left) => String.t(),
          required(:right) => String.t()
        }

  @type compare :: %{
          required(:op) => op_name(),
          required(:kind) => String.t(),
          required(:left) => expr_child(),
          required(:right) => expr_child()
        }

  @type field_access :: %{
          required(:op) => op_name(),
          required(:arg) => expr_child_or_name(),
          required(:field) => String.t()
        }

  @type field_call :: %{
          required(:op) => op_name(),
          required(:arg) => expr_child_or_name(),
          required(:field) => String.t(),
          optional(:args) => arg_list()
        }

  @type record_literal :: %{required(:op) => op_name(), required(:fields) => record_fields()}
  @type record_update :: %{
          required(:op) => op_name(),
          required(:base) => expr_child(),
          required(:fields) => record_fields()
        }

  @type list_literal :: %{
          required(:op) => op_name(),
          optional(:items) => arg_list(),
          optional(:elements) => arg_list()
        }

  @type tuple2 :: %{
          required(:op) => op_name(),
          required(:left) => expr_child(),
          required(:right) => expr_child()
        }
  @type tuple_expr :: %{required(:op) => op_name(), optional(:elements) => arg_list()}

  @type tuple_first_expr :: %{required(:op) => op_name(), required(:arg) => expr_child()}
  @type tuple_second_expr :: %{required(:op) => op_name(), required(:arg) => expr_child()}
  @type tuple_first :: %{required(:op) => op_name(), required(:arg) => expr_child()}
  @type tuple_second :: %{required(:op) => op_name(), required(:arg) => expr_child()}
  @type string_length_expr :: %{required(:op) => op_name(), required(:arg) => expr_child()}
  @type char_from_code_expr :: %{required(:op) => op_name(), required(:arg) => expr_child()}

  @type let_in :: %{
          required(:op) => op_name(),
          required(:name) => String.t(),
          required(:value_expr) => expr_child(),
          required(:in_expr) => expr_child()
        }

  @type if_expr :: %{
          required(:op) => op_name(),
          required(:cond) => expr_child(),
          required(:then_expr) => expr_child(),
          required(:else_expr) => expr_child()
        }

  @type case_expr :: %{
          required(:op) => op_name(),
          required(:subject) => expr_child_or_name(),
          required(:branches) => [case_branch()]
        }

  @type constructor_call :: %{
          required(:op) => op_name(),
          required(:target) => String.t(),
          optional(:args) => arg_list()
        }

  @type lambda :: %{
          required(:op) => op_name(),
          optional(:params) => [String.t()],
          optional(:args) => [String.t()],
          required(:body) => expr_child()
        }

  @type qualified_call :: %{
          required(:op) => op_name(),
          required(:target) => String.t(),
          optional(:args) => arg_list()
        }

  @type qualified_call1 :: %{
          required(:op) => op_name(),
          required(:target) => String.t(),
          optional(:args) => arg_list()
        }

  @type call :: %{
          required(:op) => op_name(),
          required(:name) => String.t(),
          optional(:args) => arg_list()
        }

  @type record_alias :: %{
          required(:op) => op_name(),
          required(:fields) => field_names(),
          optional(:field_types) => field_types_map()
        }

  @type unsupported :: %{required(:op) => op_name(), optional(:source) => normalized_value()}

  @type normalized_value ::
          t()
          | wire_expr()
          | [normalized_value()]
          | String.t()
          | number()
          | boolean()
          | nil
          | atom()

  @doc false
  @spec known_ops() :: [String.t()]
  def known_ops, do: Map.keys(required_keys_by_op())

  @doc false
  @spec required_keys_by_op() :: %{String.t() => [String.t()]}
  def required_keys_by_op do
    %{
      "int_literal" => ["value"],
      "float_literal" => ["value"],
      "bool_literal" => ["value"],
      "char_literal" => ["value"],
      "string_literal" => ["value"],
      "expr" => [],
      "var" => ["name"],
      "var_resolved" => ["value_expr"],
      "add_const" => ["var", "value"],
      "sub_const" => ["var", "value"],
      "add_vars" => ["left", "right"],
      "compare" => ["kind", "left", "right"],
      "field_access" => ["arg", "field"],
      "field_call" => ["arg", "field"],
      "record_literal" => ["fields"],
      "record_update" => ["base", "fields"],
      "list_literal" => [],
      "tuple2" => ["left", "right"],
      "tuple" => [],
      "tuple_first_expr" => ["arg"],
      "tuple_second_expr" => ["arg"],
      "tuple_first" => ["arg"],
      "tuple_second" => ["arg"],
      "string_length_expr" => ["arg"],
      "char_from_code_expr" => ["arg"],
      "let_in" => ["name", "value_expr", "in_expr"],
      "if" => ["cond", "then_expr", "else_expr"],
      "case" => ["subject", "branches"],
      "constructor_call" => ["target"],
      "lambda" => ["body"],
      "qualified_call" => ["target"],
      "qualified_call1" => ["target"],
      "call" => ["name"],
      "record_alias" => ["fields"],
      "unsupported" => []
    }
  end
end
