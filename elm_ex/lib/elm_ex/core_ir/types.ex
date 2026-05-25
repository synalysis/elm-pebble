defmodule ElmEx.CoreIR.Types do
  @moduledoc """
  Shared types for backend-stable normalized Core IR (`elm_ex.core_ir.v1`).
  """

  alias ElmEx.CoreIR.Types.{CoreIR, Declaration, Diagnostic, Expr, Module, ShapeError, UnionEntry}

  @type t :: CoreIR.t()
  @type diagnostic :: Diagnostic.t()
  @type declaration :: Declaration.t()
  @type module_t :: Module.t()
  @type union_entry :: UnionEntry.t()
  @type shape_error :: ShapeError.t()
  @type expr :: Expr.t()

  @type wire_scalar :: String.t() | integer() | float() | boolean() | nil

  @type wire_input :: wire_scalar() | list() | map()

  @type wire_map :: %{optional(String.t()) => wire_input(), optional(atom()) => wire_input()}

  @type normalized_module :: module_t()
  @type normalized_diagnostic :: diagnostic()
  @type normalized_value :: Expr.normalized_value()

  @type wire_core_ir :: wire_map() | ElmEx.CoreIR.t()
end
