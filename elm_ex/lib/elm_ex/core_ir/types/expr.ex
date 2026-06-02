defmodule ElmEx.CoreIR.Types.Expr do
  @moduledoc """
  Normalized Core IR expression maps use string keys at runtime (`"op"`, `"name"`, …).

  Typespecs use atom keys for Dialyzer compatibility; normalized output from
  `ElmEx.CoreIR.from_ir/2` stringifies all keys. Downstream backends read string
  keys and may coerce known `"op"` values to atoms at evaluation time.
  """

  alias ElmEx.CoreIR.Types

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

  @type wire_expr :: Types.wire_map()

  @type int_literal :: %{required(:op) => op_name(), required(:value) => integer()}
  @type float_literal :: %{required(:op) => op_name(), required(:value) => float()}
  @type bool_literal :: %{required(:op) => op_name(), required(:value) => boolean()}
  @type char_literal :: %{required(:op) => op_name(), required(:value) => String.t()}
  @type string_literal :: %{required(:op) => op_name(), required(:value) => String.t()}

  @type expr_wrapper :: %{
          required(:op) => op_name(),
          optional(:expr) => t() | map(),
          optional(:value_expr) => t() | map(),
          optional(:in_expr) => t() | map()
        }

  @type var_expr :: %{required(:op) => op_name(), required(:name) => String.t()}
  @type var_resolved :: %{required(:op) => op_name(), required(:value_expr) => t() | map()}

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
          required(:left) => t() | map(),
          required(:right) => t() | map()
        }

  @type field_access :: %{
          required(:op) => op_name(),
          required(:arg) => t() | map() | String.t(),
          required(:field) => String.t()
        }

  @type field_call :: %{
          required(:op) => op_name(),
          required(:arg) => t() | map() | String.t(),
          required(:field) => String.t(),
          optional(:args) => [t() | map()]
        }

  @type record_fields :: [{String.t(), t() | map()} | map()] | map()

  @type record_literal :: %{required(:op) => op_name(), required(:fields) => record_fields()}
  @type record_update :: %{
          required(:op) => op_name(),
          required(:base) => t() | map(),
          required(:fields) => record_fields()
        }

  @type list_literal :: %{
          required(:op) => op_name(),
          optional(:items) => [t() | map()],
          optional(:elements) => [t() | map()]
        }

  @type tuple2 :: %{
          required(:op) => op_name(),
          required(:left) => t() | map(),
          required(:right) => t() | map()
        }
  @type tuple_expr :: %{required(:op) => op_name(), optional(:elements) => [t() | map()]}

  @type tuple_first_expr :: %{required(:op) => op_name(), required(:arg) => t() | map()}
  @type tuple_second_expr :: %{required(:op) => op_name(), required(:arg) => t() | map()}
  @type tuple_first :: %{required(:op) => op_name(), required(:arg) => t() | map()}
  @type tuple_second :: %{required(:op) => op_name(), required(:arg) => t() | map()}
  @type string_length_expr :: %{required(:op) => op_name(), required(:arg) => t() | map()}
  @type char_from_code_expr :: %{required(:op) => op_name(), required(:arg) => t() | map()}

  @type let_in :: %{
          required(:op) => op_name(),
          required(:name) => String.t(),
          required(:value_expr) => t() | map(),
          required(:in_expr) => t() | map()
        }

  @type if_expr :: %{
          required(:op) => op_name(),
          required(:cond) => t() | map(),
          required(:then_expr) => t() | map(),
          required(:else_expr) => t() | map()
        }

  @type case_branch :: map()

  @type case_expr :: %{
          required(:op) => op_name(),
          required(:subject) => t() | map() | String.t(),
          required(:branches) => [case_branch()]
        }

  @type constructor_call :: %{
          required(:op) => op_name(),
          required(:target) => String.t(),
          optional(:args) => [t() | map()]
        }

  @type lambda :: %{
          required(:op) => op_name(),
          optional(:params) => [String.t()],
          optional(:args) => [String.t()],
          required(:body) => t() | map()
        }

  @type qualified_call :: %{
          required(:op) => op_name(),
          required(:target) => String.t(),
          optional(:args) => [t() | map()]
        }

  @type qualified_call1 :: %{
          required(:op) => op_name(),
          required(:target) => String.t(),
          optional(:args) => [t() | map()]
        }

  @type call :: %{
          required(:op) => op_name(),
          required(:name) => String.t(),
          optional(:args) => [t() | map()]
        }

  @type record_alias :: %{
          required(:op) => op_name(),
          required(:fields) => [String.t()] | map(),
          optional(:field_types) => map()
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
