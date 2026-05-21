defmodule ElmEx.Frontend.AstContract.Types do
  @moduledoc false

  @type span :: %{start_line: pos_integer(), end_line: pos_integer()}
  @type expr :: map()
  @type pattern :: map()
  @type declaration :: map()
  @type union_constructor :: %{optional(atom()) => String.t() | nil}
  @type case_branch :: %{optional(atom()) => pattern() | expr()}
  @type record_field :: %{optional(atom()) => String.t() | expr()}
  @type compare_kind :: :eq | :neq | :gt | :gte | :lt | :lte
  @type compose_expr :: %{optional(atom()) => String.t()}
end
