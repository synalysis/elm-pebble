defmodule ElmEx.Frontend.AstContract.Types.Declaration do
  @moduledoc """
  Top-level declarations validated by `AstContract.validate_declaration/1`.
  """

  alias ElmEx.Frontend.AstContract.Types.{Expr, UnionConstructor}
  alias ElmEx.Frontend.AstContract.Types, as: AstTypes

  @type function_definition :: %{
          required(:kind) => :function_definition,
          required(:name) => String.t(),
          required(:args) => [String.t()],
          required(:expr) => Expr.t(),
          required(:span) => AstTypes.span()
        }

  @type function_signature :: %{
          required(:kind) => :function_signature,
          required(:name) => String.t(),
          required(:type) => String.t(),
          required(:span) => AstTypes.span()
        }

  @type type_alias_decl :: %{
          required(:kind) => :type_alias,
          required(:name) => String.t(),
          required(:span) => AstTypes.span()
        }

  @type union_decl :: %{
          required(:kind) => :union,
          required(:name) => String.t(),
          required(:constructors) => [UnionConstructor.t()],
          required(:span) => AstTypes.span()
        }

  @type t ::
          function_definition()
          | function_signature()
          | type_alias_decl()
          | union_decl()
          | %{required(:kind) => atom(), optional(atom()) => AstTypes.invalid_input()}
end
