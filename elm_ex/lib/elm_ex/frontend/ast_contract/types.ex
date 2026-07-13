defmodule ElmEx.Frontend.AstContract.Types do
  @moduledoc false

  alias ElmEx.Frontend.AstContract.Types.{
    CaseBranch,
    Declaration,
    Expr,
    Pattern,
    RecordField,
    UnionConstructor
  }

  @type span :: %{start_line: pos_integer(), end_line: pos_integer()}
  @type expr :: Expr.t()
  @type pattern :: Pattern.t()
  @type declaration :: Declaration.t()
  @type union_constructor :: UnionConstructor.t()
  @type case_branch :: CaseBranch.t()
  @type record_field :: RecordField.t()
  @type compare_kind :: :eq | :neq | :gt | :gte | :lt | :lte
  @type compose_expr :: %{optional(atom()) => String.t()}

  @type invalid_map :: %{optional(atom() | String.t() | integer()) => invalid_input()}

  @type invalid_tuple :: {invalid_input(), invalid_input()}

  @type invalid_input ::
          invalid_map()
          | list()
          | atom()
          | String.t()
          | number()
          | boolean()
          | nil
          | invalid_tuple()

  @type ast_contract_error :: %{
          required(:kind) => :ast_contract_error,
          required(:reason) => atom(),
          optional(:declaration_index) => non_neg_integer()
        }

  @type declaration_error :: atom() | %{optional(atom()) => invalid_input()}

  @type pipe_chain_expr :: %{
          required(:steps) => list(),
          required(:base) => expr()
        }
end
