defmodule ElmEx.IR.Types.Expr do
  @moduledoc """
  Expression maps produced by `ElmEx.IR.Lowerer` (`:op` atom discriminators).

  Variant shapes align with `ElmEx.CoreIR.Types.Expr` before Core IR string
  normalization. Lowering may emit additional ops such as `:compose_left`,
  `:compose_right`, `:partial_constructor`, `:qualified_ref`, and
  `:constructor_ref`.
  """

  @type op ::
          :int_literal
          | :float_literal
          | :bool_literal
          | :char_literal
          | :string_literal
          | :expr
          | :var
          | :var_resolved
          | :add_const
          | :sub_const
          | :add_vars
          | :compare
          | :field_access
          | :field_call
          | :record_literal
          | :record_update
          | :record_alias
          | :list_literal
          | :tuple2
          | :tuple
          | :tuple_first_expr
          | :tuple_second_expr
          | :tuple_first
          | :tuple_second
          | :string_length_expr
          | :char_from_code_expr
          | :let_in
          | :if
          | :case
          | :constructor_call
          | :constructor_ref
          | :partial_constructor
          | :lambda
          | :qualified_call
          | :qualified_call1
          | :qualified_ref
          | :pipe_chain
          | :call
          | :compose_left
          | :compose_right
          | :unsupported
          | atom()

  @type t :: %{
          required(:op) => op(),
          optional(atom()) => ElmEx.IR.Types.FieldValue.t()
        }

  @type wire_expr :: t()

  @type compose_left :: %{
          required(:op) => :compose_left,
          required(:f) => String.t() | t(),
          required(:g) => String.t() | t()
        }

  @type compose_right :: %{
          required(:op) => :compose_right,
          required(:f) => String.t() | t(),
          required(:g) => String.t() | t()
        }

  @type partial_constructor :: %{
          required(:op) => :partial_constructor,
          required(:target) => String.t(),
          required(:tag) => integer(),
          required(:args) => [t()],
          required(:arity) => non_neg_integer()
        }
end
