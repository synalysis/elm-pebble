defmodule Elmc.Backend.Pebble.AccelConfig.Resolve do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.AccelConfig.Resolve.{Bindings, Expr, SamplingHz}
  alias Elmc.Backend.Pebble.Types

  @spec bindings_from_ir(IR.t()) :: Types.record_literal_bindings()
  defdelegate bindings_from_ir(ir), to: Bindings, as: :from_ir

  @spec resolve_expr(CCodegenTypes.ir_expr(), Types.record_literal_bindings()) ::
          CCodegenTypes.ir_expr()
  defdelegate resolve_expr(expr, bindings), to: Expr, as: :resolve

  @spec int_field(CCodegenTypes.ir_expr(), String.t(), pos_integer()) :: pos_integer()
  defdelegate int_field(expr, field, default), to: Expr

  @spec sampling_hz(CCodegenTypes.ir_expr(), pos_integer()) :: pos_integer()
  defdelegate sampling_hz(expr, default), to: SamplingHz, as: :from_record
end
