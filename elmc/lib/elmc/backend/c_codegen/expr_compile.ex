defmodule Elmc.Backend.CCodegen.ExprCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CallCompile
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.CmdCompile
  alias Elmc.Backend.CCodegen.RenderCmdCompile
  alias Elmc.Backend.CCodegen.SubCompile
  alias Elmc.Backend.CCodegen.CollectionCompile
  alias Elmc.Backend.CCodegen.CompareCompile
  alias Elmc.Backend.CCodegen.IfCompile
  alias Elmc.Backend.CCodegen.LambdaCompile
  alias Elmc.Backend.CCodegen.LetCompile
  alias Elmc.Backend.CCodegen.LiteralCompile
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.RuntimeCall
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.VarArithCompile
  alias Elmc.Backend.CCodegen.VarCompile
  alias Elmc.Backend.CCodegen.PipeChainCompile

  @literal_ops [
    :int_literal,
    :c_int_expr,
    :msg_tag_expr,
    :string_literal,
    :char_literal,
    :bool_literal,
    :order_literal,
    :float_literal,
    :cmd_none
  ]

  @sub_ops [:pebble_sub]
  @var_arith_ops [:add_const, :add_vars, :sub_const]
  @collection_ops [
    :tuple2,
    :list_literal,
    :tuple_second,
    :tuple_second_expr,
    :tuple_first,
    :tuple_first_expr,
    :string_length,
    :string_length_expr,
    :char_from_code,
    :char_from_code_expr
  ]
  @call_ops [:qualified_call, :constructor_call, :partial_constructor, :call]
  @record_ops [:record_literal, :record_update, :field_access, :field_call]

  @spec compile(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  @spec compile(nil, Types.compile_env(), Types.compile_counter()) :: Types.compile_result()
  def compile(%{op: op} = expr, env, counter) when op in @literal_ops,
    do: LiteralCompile.compile(expr, env, counter)

  def compile(%{op: :pebble_cmd} = expr, env, counter),
    do: CmdCompile.compile(expr, env, counter)

  def compile(%{op: :render_cmd} = expr, env, counter),
    do: RenderCmdCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @sub_ops,
    do: SubCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @var_arith_ops,
    do: VarArithCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @collection_ops,
    do: CollectionCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @call_ops,
    do: CallCompile.compile(expr, env, counter)

  def compile(%{op: :var} = expr, env, counter),
    do: VarCompile.compile(expr, env, counter)

  def compile(%{op: :runtime_call} = expr, env, counter),
    do: RuntimeCall.compile(expr, env, counter)

  def compile(%{op: :let_in} = expr, env, counter),
    do: LetCompile.compile(expr, env, counter)

  def compile(%{op: :if} = expr, env, counter),
    do: IfCompile.compile(expr, env, counter)

  def compile(%{op: :compare} = expr, env, counter),
    do: CompareCompile.compile(expr, env, counter)

  def compile(%{op: :case} = expr, env, counter),
    do: CaseCompile.dispatch(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @record_ops,
    do: RecordCompile.compile(expr, env, counter)

  def compile(%{op: :lambda} = expr, env, counter),
    do: LambdaCompile.compile(expr, env, counter)

  def compile(%{op: :pipe_chain} = expr, env, counter),
    do: PipeChainCompile.compile(expr, env, counter)

  def compile(%{op: :unsupported}, _env, counter),
    do: compile_zero(counter)

  def compile(_expr, _env, counter),
    do: compile_zero(counter)

  @spec compile_zero(Types.compile_counter()) :: Types.compile_result()
  defp compile_zero(counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_int_zero();", var, next}
  end
end
