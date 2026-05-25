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

  @type normalized_module :: module_t()
  @type normalized_diagnostic :: diagnostic()
  @type normalized_value :: Expr.normalized_value()

  @type wire_map :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_core_ir :: wire_map() | ElmEx.CoreIR.t()
end
