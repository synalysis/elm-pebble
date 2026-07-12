defmodule Elmc.Backend.Plan.Builder do
  @moduledoc """
  Append-only builder for `%FunctionPlan{}` during lowering.
  """

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

  defstruct [
    :module,
    :name,
    :params,
    :return_type,
    :fallible,
    :rc_required,
    :blocks,
    :current_block,
    :next_reg,
    :next_instr,
    :next_block,
    :locals,
    :catch_depth,
    :param_regs,
    :param_load_blocks,
    :lambdas,
    :pending_merge_block,
    :tag_switch_merge_block,
    :letrec_refs,
    :next_letrec
  ]

  @type t :: %__MODULE__{
          module: String.t(),
          name: String.t(),
          params: [Param.t()],
          return_type: String.t() | nil,
          fallible: boolean(),
          rc_required: boolean(),
          blocks: [Block.t()],
          current_block: Block.t(),
          next_reg: non_neg_integer(),
          next_instr: non_neg_integer(),
          next_block: non_neg_integer(),
          locals: %{String.t() => Types.reg()},
          catch_depth: non_neg_integer(),
          param_regs: %{String.t() => Types.reg()},
          param_load_blocks: %{String.t() => non_neg_integer()},
          lambdas: [FunctionPlan.t()],
          pending_merge_block: non_neg_integer() | nil,
          tag_switch_merge_block: non_neg_integer() | nil,
          letrec_refs: [String.t()],
          next_letrec: non_neg_integer()
        }

  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(module, name, opts \\ []) do
    arg_names = Keyword.get(opts, :args, [])
    params = Enum.with_index(arg_names, fn arg, i -> %Param{name: arg, type: nil, index: i} end)
    entry = %Block{id: 0, instrs: [], terminator: :none}

    %__MODULE__{
      module: module,
      name: name,
      params: params,
      return_type: Keyword.get(opts, :return_type),
      fallible: Keyword.get(opts, :fallible, false),
      rc_required: Keyword.get(opts, :rc_required, false),
      blocks: [],
      current_block: entry,
      next_reg: 0,
      next_instr: 0,
      next_block: 1,
      locals: %{},
      catch_depth: 0,
      param_regs: %{},
      param_load_blocks: %{},
      lambdas: [],
      pending_merge_block: nil,
      tag_switch_merge_block: nil,
      letrec_refs: [],
      next_letrec: 0
    }
  end

  @spec fresh_reg(t()) :: {Types.reg(), t()}
  def fresh_reg(%{next_reg: n} = b), do: {n, %{b | next_reg: n + 1}}

  @spec bind_local(t(), String.t(), Types.reg()) :: t()
  def bind_local(b, name, reg) when is_binary(name) do
    %{b | locals: Map.put(b.locals, name, reg)}
  end

  @spec fresh_locals(t()) :: t()
  def fresh_locals(b), do: %{b | locals: %{}}

  @doc false
  @spec begin_arm_block(t(), non_neg_integer()) :: t()
  def begin_arm_block(b, block_id), do: b |> fresh_locals() |> begin_block(block_id)

  @doc false
  @spec reset_param_cache(t()) :: t()
  def reset_param_cache(b), do: %{b | param_regs: %{}, param_load_blocks: %{}}

  @doc false
  @spec begin_cfg_arm_block(t(), non_neg_integer()) :: t()
  def begin_cfg_arm_block(b, block_id), do: %{b | param_load_blocks: %{}} |> begin_block(block_id)

  @spec emit(t(), Types.opcode(), keyword() | map()) :: {Types.reg() | Types.result_slot() | nil, t()}
  def emit(b, op, opts) when is_map(opts) and not is_list(opts) do
    emit(b, op, Map.to_list(opts))
  end

  def emit(b, op, opts) do
    dest = Keyword.get(opts, :dest)
    args = Keyword.get(opts, :args, %{})
    effects = Keyword.get(opts, :effects, Types.empty_effects())
    block_id = b.current_block.id

    instr = %Types{
      id: b.next_instr,
      op: op,
      dest: dest,
      args: args,
      effects: effects,
      block_id: block_id,
      span: Keyword.get(opts, :span)
    }

    current = %{b.current_block | instrs: b.current_block.instrs ++ [instr]}

    result_dest =
      case {op, dest} do
        {:publish, d} when d in [:fn_out, :branch_out] -> d
        {_, {:owned, r}} -> r
        {_, r} when is_integer(r) -> r
        _ -> dest
      end

    {result_dest, %{b | current_block: current, next_instr: b.next_instr + 1}}
  end

  @spec emit_const_int(t(), integer(), keyword()) :: {Types.reg(), t()}
  def emit_const_int(b, value, opts \\ []) do
    {reg, b1} = fresh_reg(b)

    args =
      case Keyword.get(opts, :union_ctor) do
        ctor when is_binary(ctor) -> %{value: value, union_ctor: ctor}
        _ -> %{value: value}
      end

    {_, b2} =
      emit(b1, :const_int, %{
        dest: reg,
        args: args,
        effects: Types.owned_effects(reg)
      })

    {reg, b2}
  end

  @spec emit_boxed_tag_peel(t(), Types.reg()) :: {Types.reg(), t()}
  def emit_boxed_tag_peel(b, subject_reg) when is_integer(subject_reg) do
    {reg, b1} = fresh_reg(b)

    {_, b2} =
      emit(b1, :boxed_tag_peel, %{
        dest: reg,
        args: %{subject: subject_reg},
        effects: Types.empty_effects()
      })

    {reg, b2}
  end

  @spec emit_const_c_expr(t(), String.t()) :: {Types.reg(), t()}
  def emit_const_c_expr(b, value) when is_binary(value) do
    {reg, b1} = fresh_reg(b)

    {_, b2} =
      emit(b1, :const_c_expr, %{
        dest: reg,
        args: %{value: value},
        effects: Types.owned_effects(reg)
      })

    {reg, b2}
  end

  def param_reg?(b, reg) when is_integer(reg), do: reg in Map.values(b.param_regs)
  def param_reg?(_, _), do: false

  @doc false
  @spec param_reg_block(t(), String.t()) :: non_neg_integer() | nil
  def param_reg_block(b, name) when is_binary(name) do
    case Map.get(b.param_load_blocks, name) do
      block_id when is_integer(block_id) -> block_id
      _ -> nil
    end
  end

  @spec get_or_load_param(t(), non_neg_integer(), String.t()) :: {Types.reg(), t()}
  def get_or_load_param(b, index, name) when is_binary(name) do
    case Map.get(b.param_regs, name) do
      reg when is_integer(reg) ->
        {reg, b}

      _ ->
        load_param_named(b, index, name)
    end
  end

  defp load_param_named(b, index, name) do
    {reg, b1} = emit_load_param(b, index)

    {reg,
     %{
       b1
       | param_regs: Map.put(b1.param_regs, name, reg),
         param_load_blocks: Map.put(b1.param_load_blocks, name, b1.current_block.id)
     }}
  end

  @spec partition_call_args(t(), [Types.reg()]) :: {[Types.reg()], [Types.reg()]}
  def partition_call_args(b, arg_regs) when is_list(arg_regs) do
    Enum.split_with(arg_regs, &borrow_arg?(b, &1))
  end

  @doc false
  @spec phi_branch_consumes(t(), [Types.reg()]) :: [Types.reg()]
  def phi_branch_consumes(b, regs) when is_list(regs) do
    live_locals = MapSet.new(Map.values(b.locals || %{}))

    regs
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&MapSet.member?(live_locals, &1))
  end

  @spec borrow_arg?(t(), Types.reg()) :: boolean()
  def borrow_arg?(b, reg) when is_integer(reg),
    do: param_reg?(b, reg) or named_local_reg?(b, reg)

  def borrow_arg?(_, _), do: false

  @spec retain_named_local_copies(t(), [Types.reg()]) :: {[Types.reg()], t()}
  def retain_named_local_copies(b, arg_regs) when is_list(arg_regs) do
    Enum.map_reduce(arg_regs, b, fn reg, b_acc ->
      if is_integer(reg) and named_local_reg?(b_acc, reg) do
        retain_reg_copy(b_acc, reg)
      else
        {reg, b_acc}
      end
    end)
  end

  @spec dup_regs_for_owned_consume(t(), [Types.reg()]) :: {[Types.reg()], t()}
  def dup_regs_for_owned_consume(b, arg_regs) when is_list(arg_regs) do
    dup_regs_with_canonical(b, arg_regs, param_retain?: true)
  end

  @spec dup_regs_for_consume(t(), [Types.reg()]) :: {[Types.reg()], t()}
  def dup_regs_for_consume(b, arg_regs) when is_list(arg_regs) do
    dup_regs_with_canonical(b, arg_regs, param_retain?: false)
  end

  defp dup_regs_with_canonical(b, arg_regs, opts) do
    param_retain? = Keyword.get(opts, :param_retain?, false)

    {regs, {b_final, _canon}} =
      Enum.map_reduce(arg_regs, {b, %{}}, fn reg, {b_acc, canon} ->
        cond do
          not is_integer(reg) ->
            {reg, {b_acc, canon}}

          Map.has_key?(canon, reg) ->
            {Map.fetch!(canon, reg), {b_acc, canon}}

          param_retain? and param_reg?(b_acc, reg) ->
            {dup, b1} = retain_reg_copy(b_acc, reg)
            {dup, {b1, Map.put(canon, reg, dup)}}

          true ->
            {reg, {b_acc, Map.put(canon, reg, reg)}}
        end
      end)

    {regs, b_final}
  end

  @spec dup_named_locals_for_consume(t(), [Types.reg()]) :: {[Types.reg()], t()}
  def dup_named_locals_for_consume(b, arg_regs) when is_list(arg_regs) do
    {regs, b1} = dup_regs_for_owned_consume(b, arg_regs)

    {regs, {b_final, _local_canon}} =
      Enum.map_reduce(regs, {b1, %{}}, fn reg, {b_acc, local_canon} ->
        cond do
          not is_integer(reg) ->
            {reg, {b_acc, local_canon}}

          Map.has_key?(local_canon, reg) ->
            {Map.fetch!(local_canon, reg), {b_acc, local_canon}}

          named_local_reg?(b_acc, reg) ->
            {dup, b2} = retain_reg_copy(b_acc, reg)
            {dup, {b2, Map.put(local_canon, reg, dup)}}

          true ->
            {reg, {b_acc, local_canon}}
        end
      end)

    {regs, b_final}
  end

  @spec dup_named_local_if_bound(t(), Types.reg()) :: {Types.reg(), t()}
  def dup_named_local_if_bound(b, reg) when is_integer(reg) do
    if named_local_reg?(b, reg), do: retain_reg_copy(b, reg), else: {reg, b}
  end

  def dup_named_local_if_bound(b, reg), do: {reg, b}

  defp named_local_reg?(b, reg) when is_integer(reg), do: reg in Map.values(b.locals)

  @doc false
  @spec copy_reg_owned(t(), Types.reg(), keyword()) :: {Types.reg(), t()}
  def copy_reg_owned(b, reg, opts \\ [])

  def copy_reg_owned(b, reg, opts) when is_integer(reg) do
    consume? = Keyword.get(opts, :consume_source, false)

    {dup, b1} = fresh_reg(b)

    {_, b2} =
      emit(b1, :call_runtime, %{
        dest: dup,
        args: %{builtin: :retain, args: [reg]},
        effects: %{
          produces: {:owned, dup},
          consumes: if(consume?, do: [reg], else: []),
          borrows: if(consume?, do: [], else: [reg]),
          fallible: false
        }
      })

    {dup, b2}
  end

  def copy_reg_owned(b, reg, _opts), do: {reg, b}

  defp retain_reg_copy(b, reg), do: copy_reg_owned(b, reg)

  @spec emit_load_param(t(), non_neg_integer()) :: {Types.reg(), t()}
  def emit_load_param(b, index) do
    {reg, b1} = fresh_reg(b)

    {_, b2} =
      emit(b1, :load_param, %{
        dest: reg,
        args: %{index: index},
        effects: %{produces: nil, consumes: [], borrows: [], fallible: false}
      })

    {reg, b2}
  end

  @doc false
  @spec reload_stale_param_args(t(), [String.t()], [Types.reg()], [map()]) ::
          {[Types.reg()], t()}
  def reload_stale_param_args(b, param_names, arg_regs, arg_exprs)
      when is_list(arg_regs) and is_list(arg_exprs) do
    current = b.current_block.id

    Enum.zip(arg_regs, arg_exprs)
    |> Enum.map_reduce(b, fn {reg, expr}, b_acc ->
      case expr do
        %{op: :var, name: name} ->
          case Enum.find_index(param_names, &(&1 == name)) do
            idx when is_integer(idx) ->
              case param_reg_block(b_acc, name) do
                ^current -> {reg, b_acc}
                _ -> load_param_named(b_acc, idx, name)
              end

            _ ->
              {reg, b_acc}
          end

        _ ->
          {reg, b_acc}
      end
    end)
  end

  @spec emit_load_local(t(), String.t()) :: {Types.reg() | nil, t()}
  def emit_load_local(b, name) when is_binary(name) do
    case Map.get(b.locals, name) do
      reg when is_integer(reg) ->
        {scratch, b1} = fresh_reg(b)

        {_, b2} =
          emit(b1, :load_local, %{
            dest: scratch,
            args: %{name: name, source: reg},
            effects: %{produces: {:owned, scratch}, consumes: [], borrows: [reg], fallible: false}
          })

        {scratch, b2}

      _ ->
        {nil, b}
    end
  end

  @spec emit_release(t(), Types.reg()) :: t()
  def emit_release(b, reg) do
    {_, b1} =
      emit(b, :release, %{
        args: %{reg: reg},
        effects: %{produces: nil, consumes: [reg], borrows: [], fallible: false}
      })

    b1
  end

  @spec emit_publish_fn_out(t(), Types.reg()) :: t()
  def emit_publish_fn_out(b, reg) when is_integer(reg) do
    {_, b1} =
      emit(b, :publish, %{
        dest: :fn_out,
        args: %{source: reg},
        effects: %{produces: nil, consumes: [reg], borrows: [], fallible: false}
      })

    b1
  end

  @spec emit_ret(t(), Types.reg() | :fn_out) :: t()
  def emit_ret(b, reg) do
    current = %{b.current_block | terminator: {:ret, reg}}
    %{b | current_block: current}
  end

  @doc false
  @spec reserved_next_block_id(t()) :: non_neg_integer()
  def reserved_next_block_id(b), do: skip_reserved(b.next_block, b.pending_merge_block)

  @spec finish_block(t(), Block.terminator()) :: t()
  def finish_block(b, terminator) do
    finished = %{b.current_block | terminator: terminator}
    next_id = skip_reserved(b.next_block, b.pending_merge_block)
    next = %Block{id: next_id, instrs: [], terminator: :none}
    %{b | blocks: b.blocks ++ [finished], current_block: next, next_block: next_id + 1}
  end

  @doc false
  @spec patch_terminator(t(), non_neg_integer(), Block.terminator()) :: t()
  def patch_terminator(b, block_id, terminator) when is_integer(block_id) do
    blocks =
      Enum.map(b.blocks, fn
        %Block{id: ^block_id} = block -> %{block | terminator: terminator}
        block -> block
      end)

    current =
      if b.current_block.id == block_id do
        %{b.current_block | terminator: terminator}
      else
        b.current_block
      end

    %{b | blocks: blocks, current_block: current}
  end

  @spec begin_block(t(), non_neg_integer()) :: t()
  def begin_block(b, block_id) when is_integer(block_id) do
    existing = Enum.find(b.blocks, &(&1.id == block_id))
    blocks = Enum.reject(b.blocks, &(&1.id == block_id))

    current =
      case existing do
        %Block{} = block -> %{block | instrs: [], terminator: :none}
        _ -> %Block{id: block_id, instrs: [], terminator: :none}
      end

    %{b | blocks: blocks, current_block: current, next_block: max(b.next_block, block_id + 1)}
  end

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id

  @spec in_catch?(t()) :: boolean()
  def in_catch?(%{catch_depth: depth}) when is_integer(depth), do: depth > 0

  @doc """
  RC function bodies use a single C `CATCH_BEGIN` from `C.Lower.Frame`;
  do not emit nested plan catch regions for fallible ops in that case.
  """
  @spec skip_instr_catch?(t(), Elmc.Backend.Plan.Context.t()) :: boolean()
  def skip_instr_catch?(b, ctx) do
    in_catch?(b) or (ctx.rc_required and ctx.fallible)
  end

  @doc """
  Per-instruction `catch_begin`/`catch_end` is only for fallible ops inside RC
  functions (where `CHECK_RC` + `break` exits the outer `CATCH_BEGIN`). Non-RC
  `ElmcValue *` helpers use `_take_value` allocators and must not get nested
  no-op catch regions.
  """
  @spec wrap_fallible_instr_catch?(t(), Elmc.Backend.Plan.Context.t(), boolean()) :: boolean()
  def wrap_fallible_instr_catch?(b, ctx, op_fallible?) do
    op_fallible? and ctx.rc_required and not skip_instr_catch?(b, ctx)
  end

  @spec catch_begin(t()) :: t()
  def catch_begin(b) do
    {_, b1} =
      emit(b, :catch_begin, %{
        effects: %{produces: nil, consumes: [], borrows: [], fallible: false}
      })

    %{b1 | catch_depth: b.catch_depth + 1, fallible: true}
  end

  @spec catch_end(t()) :: t()
  def catch_end(b) do
    {_, b1} =
      emit(b, :catch_end, %{
        effects: %{produces: nil, consumes: [], borrows: [], fallible: false}
      })

    %{b1 | catch_depth: max(0, b.catch_depth - 1)}
  end

  @spec to_function_plan(t()) :: FunctionPlan.t()
  def to_function_plan(b) do
    blocks =
      case b.current_block.terminator do
        :none -> b.blocks ++ [b.current_block]
        _ -> b.blocks ++ [b.current_block]
      end

    %FunctionPlan{
      module: b.module,
      name: b.name,
      params: b.params,
      return_type: b.return_type,
      fallible: b.fallible or b.catch_depth > 0,
      rc_required: b.rc_required,
      blocks: blocks,
      entry_block: 0,
      locals: b.locals,
      reg_count: b.next_reg,
      catch_depth: b.catch_depth,
      lambdas: b.lambdas,
      letrec_refs: b.letrec_refs || []
    }
  end

  @spec declare_letrec(t(), String.t()) :: {String.t(), t()}
  def declare_letrec(b, name) when is_binary(name) do
    n = b.next_letrec || 0
    ref = "elmc_plan_letrec_#{Elmc.Backend.CCodegen.Util.safe_c_suffix(name)}_#{n}"

    {ref,
     %{
       b
       | next_letrec: n + 1,
         letrec_refs: (b.letrec_refs || []) ++ [ref]
     }}
  end
end
