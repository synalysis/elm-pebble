defmodule ElmEx.IR.Types.Declaration do
  @moduledoc """
  IR declaration struct shape (`ElmEx.IR.Declaration`).

  Lowered from frontend `AstContract` declarations; `expr` remains parser AST until Core IR.
  """

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes
  alias ElmEx.Frontend.AstContract.Types.Expr

  @type kind :: :function | :type_alias | :union

  @type ownership ::
          :retain_on_assign
          | :release_on_scope_exit
          | :retain_on_constructor
          | :release_on_match_exit
          | atom()

  @type span :: %{optional(:start_line) => pos_integer(), optional(:end_line) => pos_integer()}

  @type span_wire :: %{optional(atom()) => pos_integer()}

  @type struct_t :: %ElmEx.IR.Declaration{
          kind: kind(),
          name: String.t(),
          type: String.t() | nil,
          args: [String.t()] | nil,
          expr: Expr.t() | AstTypes.invalid_input() | nil,
          span: span() | span_wire() | nil,
          ownership: [ownership()]
        }

  @type t :: struct_t()
end
