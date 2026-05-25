defmodule ElmEx.Frontend.AstContract.Types.Expr do
  @moduledoc """
  Parser AST expression shapes validated by `ElmEx.Frontend.AstContract.validate_expr/1`.
  """

  alias ElmEx.Frontend.AstContract.Types.{CaseBranch, RecordField}
  alias ElmEx.Frontend.AstContract.Types, as: AstTypes

  @type int_literal :: %{required(:op) => :int_literal, required(:value) => integer()}
  @type string_literal :: %{required(:op) => :string_literal, required(:value) => String.t()}
  @type char_literal :: %{required(:op) => :char_literal, required(:value) => integer()}
  @type float_literal :: %{required(:op) => :float_literal, required(:value) => float() | integer()}
  @type var_expr :: %{required(:op) => :var, required(:name) => String.t()}
  @type cmd_none :: %{required(:op) => :cmd_none}
  @type add_const :: %{required(:op) => :add_const, required(:var) => String.t(), required(:value) => integer()}
  @type add_vars :: %{required(:op) => :add_vars, required(:left) => String.t(), required(:right) => String.t()}
  @type sub_const :: %{required(:op) => :sub_const, required(:var) => String.t(), required(:value) => integer()}
  @type compare :: %{
          required(:op) => :compare,
          required(:left) => t(),
          required(:right) => t(),
          required(:kind) => AstTypes.compare_kind()
        }
  @type tuple2 :: %{
          required(:op) => :tuple2,
          required(:left) => t(),
          required(:right) => t()
        }
  @type list_literal :: %{required(:op) => :list_literal, required(:items) => [t()]}
  @type call :: %{required(:op) => :call, required(:name) => String.t(), required(:args) => [t()]}
  @type qualified_call :: %{
          required(:op) => :qualified_call,
          required(:target) => String.t(),
          required(:args) => [t()]
        }
  @type constructor_call :: %{
          required(:op) => :constructor_call,
          required(:target) => String.t(),
          required(:args) => [t()]
        }
  @type field_access :: %{
          required(:op) => :field_access,
          required(:arg) => t() | String.t(),
          required(:field) => String.t()
        }
  @type field_call :: %{
          required(:op) => :field_call,
          required(:arg) => t() | String.t(),
          required(:field) => String.t(),
          required(:args) => [t()]
        }
  @type compose_left :: %{required(:op) => :compose_left, required(:f) => String.t(), required(:g) => String.t()}
  @type compose_right :: %{required(:op) => :compose_right, required(:f) => String.t(), required(:g) => String.t()}
  @type lambda :: %{
          required(:op) => :lambda,
          required(:args) => [String.t()],
          required(:body) => t()
        }
  @type let_in :: %{
          required(:op) => :let_in,
          required(:name) => String.t(),
          required(:value_expr) => t(),
          required(:in_expr) => t()
        }
  @type if_expr :: %{
          required(:op) => :if,
          required(:cond) => t(),
          required(:then) => t(),
          required(:else) => t()
        }
  @type case_expr :: %{
          required(:op) => :case,
          required(:subject) => t() | String.t(),
          required(:branches) => [CaseBranch.t()]
        }
  @type record_literal :: %{required(:op) => :record_literal, required(:fields) => [RecordField.t()]}
  @type record_update :: %{
          required(:op) => :record_update,
          required(:base) => t(),
          required(:fields) => [RecordField.t()]
        }
  @type tuple_first_expr :: %{required(:op) => :tuple_first_expr, required(:arg) => t()}
  @type tuple_second_expr :: %{required(:op) => :tuple_second_expr, required(:arg) => t()}
  @type string_length_expr :: %{required(:op) => :string_length_expr, required(:arg) => t()}
  @type char_from_code_expr :: %{required(:op) => :char_from_code_expr, required(:arg) => t()}
  @type unsupported :: %{required(:op) => :unsupported, required(:source) => String.t()}

  @type t ::
          int_literal()
          | string_literal()
          | char_literal()
          | float_literal()
          | var_expr()
          | cmd_none()
          | add_const()
          | add_vars()
          | sub_const()
          | compare()
          | tuple2()
          | list_literal()
          | call()
          | qualified_call()
          | constructor_call()
          | field_access()
          | field_call()
          | compose_left()
          | compose_right()
          | lambda()
          | let_in()
          | if_expr()
          | case_expr()
          | record_literal()
          | record_update()
          | tuple_first_expr()
          | tuple_second_expr()
          | string_length_expr()
          | char_from_code_expr()
          | unsupported()
          | %{required(:op) => atom(), optional(atom()) => AstTypes.invalid_input()}
end
