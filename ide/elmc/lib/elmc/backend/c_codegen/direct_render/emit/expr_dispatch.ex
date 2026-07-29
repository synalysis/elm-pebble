defmodule Elmc.Backend.CCodegen.DirectRender.Emit.ExprDispatch do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types

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
  alias Elmc.Backend.Plan.Lower.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.UnsupportedSurface
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
    :cmd_none,
    :sub_none
  ]

  @sub_ops [:pebble_sub]
  @var_arith_ops [:add_const, :add_vars, :sub_const, :sub_vars, :mul_vars]
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
  @zero_arg_ref_ops [:constructor_ref, :qualified_ref, :qualified_var]

  @spec compile(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  @spec compile(nil, Types.compile_env(), Types.compile_counter()) :: Types.compile_result()
  def compile(%{op: op} = expr, env, counter) when op in @literal_ops,
    do: LiteralCompile.compile(expr, env, counter)

  def compile(%{op: :pebble_cmd} = expr, env, counter),
    do: CmdCompile.compile(expr, env, counter)

  def compile(%{op: :render_cmd} = expr, env, counter),
    do: RenderCmdCompile.compile(expr, env, counter)

  def compile(%{op: :render_text_cmd, kind: kind, int_params: params, text: text}, env, counter) do
    compile(
      %{op: :tuple2, left: kind, right: Helpers.tuple_chain(List.wrap(params) ++ [text])},
      env,
      counter
    )
  end

  def compile(%{op: op} = expr, env, counter) when op in @sub_ops,
    do: SubCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @var_arith_ops,
    do: VarArithCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @collection_ops,
    do: CollectionCompile.compile(expr, env, counter)

  def compile(%{op: op} = expr, env, counter) when op in @call_ops,
    do: CallCompile.compile(expr, env, counter)

  def compile(%{op: op, target: target}, env, counter)
      when op in @zero_arg_ref_ops and is_binary(target) do
    call_op = if op == :constructor_ref, do: :constructor_call, else: :qualified_call
    compile(%{op: call_op, target: target, args: []}, env, counter)
  end

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

  def compile(%{op: :unsupported} = expr, _env, counter) do
    UnsupportedSurface.record_from_expr(expr)
    compile_zero(counter)
  end

  def compile(%{op: op} = expr, _env, counter) when is_atom(op) do
    UnsupportedSurface.record_expr(%{
      kind: :expr,
      op: op,
      reason_op: op,
      target: Map.get(expr, :target) || Map.get(expr, :name),
      detail: "unhandled expr in DirectRender.Emit.ExprDispatch"
    })

    compile_zero(counter)
  end

  def compile(expr, _env, counter) do
    UnsupportedSurface.record_expr(%{
      kind: :expr,
      op: :non_map,
      reason_op: :non_map,
      detail: "unhandled expr in DirectRender.Emit.ExprDispatch (#{inspect(expr, limit: 8)})"
    })

    compile_zero(counter)
  end

  @spec compile_zero(Types.compile_counter()) :: Types.compile_result()
  defp compile_zero(counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_int_zero();", var, next}
  end
end
