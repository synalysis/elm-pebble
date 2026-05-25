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
end
