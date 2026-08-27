defmodule Elmc.Backend.Plan.Lower.Platform.Pebble do
  @moduledoc """
  Pebble-specific plan lowering (`pebble_cmd`, companion send, etc.).

  Kept separate from core opcodes so web/WASM lowering can use
  `Plan.Lower.Platform.Web` instead.
  """
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.{Builder, Context, Types}
  alias Elmc.Backend.Plan.Lower.Expr

  @spec compile_cmd(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile_cmd(%{op: :pebble_cmd, params: params} = expr, ctx, b) do
    kind = Map.get(expr, :kind)
    params = List.wrap(params)
    arity = length(params)

    with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b),
         builtin <- cmd_builtin(kind, arity) do
      wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

      b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

      {dest, b_dest} =
        if Context.function_tail?(ctx) do
          {:fn_out, b2}
        else
          Builder.fresh_reg(b2)
        end

      kind_arg =
        case kind do
          %{op: :c_int_expr, value: v} -> %{c_expr: v}
          _ -> %{kind: :unknown}
        end

      {_, b3} =
        Builder.emit(b_dest, :pebble_cmd, %{
          dest: dest,
          args: %{
            builtin: builtin,
            kind: kind_arg,
            params: param_regs
          },
          effects: Types.fallible_transfer(param_regs, param_regs)
        })

      b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3

      if dest == :fn_out do
        {_, b5} =
          Builder.emit(b4, :publish, %{
            dest: :fn_out,
            args: %{},
            effects: Types.empty_effects()
          })

        {:ok, :fn_out, b5}
      else
        {:ok, dest, b4}
      end
    else
      _ -> :unsupported
    end
  end

  def compile_cmd(_, _, _), do: :unsupported

  @spec compile_render_cmd(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out | :stream_void, Builder.t()} | :unsupported
  def compile_render_cmd(%{kind: kind, params: params}, ctx, b) do
    params = List.wrap(params)

    if Context.stream_mode?(ctx) do
      with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
        emit_stream_platform_op(:render_cmd, normalize_kind(kind), param_regs, ctx, b1)
      else
        _ -> :unsupported
      end
    else
      compile_native_platform_op(:render_cmd, normalize_kind(kind), params, ctx, b)
    end
  end

  def compile_render_cmd(_, _, _), do: :unsupported

  @spec compile_render_text_cmd(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out | :stream_void, Builder.t()} | :unsupported
  def compile_render_text_cmd(%{kind: kind, int_params: int_params, text: text}, ctx, b) do
    int_params = List.wrap(int_params)

    if Context.stream_mode?(ctx) do
      with {:ok, param_regs, b1} <- compile_params_scratch(int_params, ctx, b),
           {:ok, text_reg, b2} <- compile_text_param(text, ctx, b1) do
        emit_stream_text_cmd(normalize_kind(kind), param_regs, text_reg, ctx, b2)
      else
        _ -> :unsupported
      end
    else
      with {:ok, param_regs, b1} <- compile_params_scratch(int_params, ctx, b),
           {:ok, text_reg, b2} <- compile_text_param(text, ctx, b1) do
        compile_native_text_cmd(:render_text_cmd, normalize_kind(kind), param_regs, text_reg, ctx, b2)
      else
        _ -> :unsupported
      end
    end
  end

  def compile_render_text_cmd(_, _, _), do: :unsupported

  @spec compile_sub(Types.pebble_sub_input() | Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile_sub(%{mask: mask, params: params}, ctx, b) do
    compile_native_platform_op(:pebble_sub, normalize_kind(mask), List.wrap(params), ctx, b)
  end

  def compile_sub(_, _, _), do: :unsupported

  @spec compile_native_platform_op(
          :render_cmd | :pebble_sub,
          %{c_expr: String.t()} | %{literal: integer()},
          [Types.ir_expr()],
          Context.t(),
          Builder.t()
        ) :: Types.compile_result_required()

  defp compile_native_platform_op(op, kind_arg, params, ctx, b) do
    with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

      b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

      {dest, b_dest} =
        if Context.function_tail?(ctx) do
          {:fn_out, b2}
        else
          Builder.fresh_reg(b2)
        end

      effects = borrow_only_platform_effects(dest, param_regs)

      {_, b3} =
        Builder.emit(b_dest, op, %{
          dest: dest,
          args: %{kind: kind_arg, params: param_regs},
          effects: effects
        })

      b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3

      if dest == :fn_out do
        {_, b5} =
          Builder.emit(b4, :publish, %{
            dest: :fn_out,
            args: %{},
            effects: Types.empty_effects()
          })

        {:ok, :fn_out, b5}
      else
        {:ok, dest, b4}
      end
    else
      _ -> :unsupported
    end
  end

  @spec borrow_only_platform_effects(
          Types.reg() | :fn_out | :stream_void,
          [Types.reg()]
        ) :: Types.effects()

  defp borrow_only_platform_effects(dest, param_regs) do
    if dest in [:fn_out, :stream_void] or not is_integer(dest) do
      %{produces: nil, consumes: [], borrows: param_regs, fallible: true}
    else
      Types.fallible_effects(dest, param_regs, [])
    end
  end

  @spec emit_stream_platform_op(
          atom(),
          %{c_expr: String.t()} | %{literal: integer()},
          [Types.reg()],
          Context.t(),
          Builder.t()
        ) :: {:ok, :stream_void, Builder.t()}

  defp emit_stream_platform_op(op, kind_arg, param_regs, ctx, b) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    effects = borrow_only_platform_effects(:stream_void, param_regs)

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: :stream_void,
        args: %{kind: kind_arg, params: param_regs, direct_scene_push: true},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2
    {:ok, :stream_void, b3}
  end

  @spec emit_stream_text_cmd(
          %{c_expr: String.t()} | %{literal: integer()},
          [Types.reg()],
          Types.reg(),
          Context.t(),
          Builder.t()
        ) :: {:ok, :stream_void, Builder.t()}

  defp emit_stream_text_cmd(kind_arg, param_regs, text_reg, ctx, b) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b
    borrow_regs = param_regs ++ [text_reg]
    effects = borrow_only_platform_effects(:stream_void, borrow_regs)

    {_, b2} =
      Builder.emit(b1, :render_text_cmd, %{
        dest: :stream_void,
        args: %{kind: kind_arg, params: param_regs, text: text_reg, direct_scene_push: true},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2
    {:ok, :stream_void, b3}
  end

  @spec normalize_kind(Types.ir_expr() | term()) ::
          %{c_expr: String.t()} | %{literal: integer()}

  defp normalize_kind(%{op: :c_int_expr, value: value}) when is_binary(value),
    do: %{c_expr: value}

  defp normalize_kind(%{op: :int_literal, value: value}) when is_integer(value),
    do: %{literal: value}

  defp normalize_kind(_), do: %{literal: 0}

  @spec compile_native_text_cmd(
          atom(),
          %{c_expr: String.t()} | %{literal: integer()},
          [Types.reg()],
          Types.reg(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result_required()

  defp compile_native_text_cmd(op, kind_arg, param_regs, text_reg, ctx, b) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)

    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    {dest, b_dest} =
      if Context.function_tail?(ctx) do
        {:fn_out, b1}
      else
        Builder.fresh_reg(b1)
      end

    borrow_regs = param_regs ++ [text_reg]

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrow_regs, [])
      else
        %{produces: nil, consumes: [], borrows: borrow_regs, fallible: true}
      end

    {_, b2} =
      Builder.emit(b_dest, op, %{
        dest: dest,
        args: %{kind: kind_arg, params: param_regs, text: text_reg},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2

    if dest == :fn_out do
      {_, b4} =
        Builder.emit(b3, :publish, %{
          dest: :fn_out,
          args: %{},
          effects: Types.empty_effects()
        })

      {:ok, :fn_out, b4}
    else
      {:ok, dest, b3}
    end
  end

  @spec compile_text_param(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_reg_result()

  defp compile_text_param(text, ctx, b) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false, stream_mode: false}

    case Expr.compile(text, scratch_ctx, b) do
      {:ok, reg, b1} when is_integer(reg) -> {:ok, reg, b1}
      _ -> :unsupported
    end
  end

  # Companion-send pattern: param calls must use scratch regs, not fn_out.
  @spec compile_params_scratch([Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, [Types.reg()], Builder.t()} | :unsupported

  defp compile_params_scratch(params, ctx, b) when is_list(params) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false, stream_mode: false}

    Enum.reduce_while(params, {:ok, [], b}, fn param, {:ok, acc, b_acc} ->
      case Expr.compile(param, scratch_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  @spec cmd_builtin(Types.ir_expr() | term(), non_neg_integer()) ::
          :cmd0 | :cmd1 | :cmd1_string | :cmd2 | :cmd3 | :cmd4

  defp cmd_builtin(kind, 2) do
    if storage_write_string_kind?(kind) do
      :cmd1_string
    else
      :cmd2
    end
  end

  defp cmd_builtin(_kind, arity), do: cmd_builtin_arity(arity)

  @spec cmd_builtin_arity(non_neg_integer()) :: :cmd0 | :cmd1 | :cmd2 | :cmd3 | :cmd4

  defp cmd_builtin_arity(0), do: :cmd0
  defp cmd_builtin_arity(1), do: :cmd1
  defp cmd_builtin_arity(2), do: :cmd2
  defp cmd_builtin_arity(3), do: :cmd3
  defp cmd_builtin_arity(4), do: :cmd4
  defp cmd_builtin_arity(_), do: :cmd4

  # Persist string cmds carry a boxed Elm string, not a second native int.
  # Lowering them as cmd2 + elmc_as_int(text) stores an empty persist value.
  defp storage_write_string_kind?(%{op: :c_int_expr, value: value}) when is_binary(value) do
    value == Elmc.Backend.Pebble.command_kind_c_name!(:storage_write_string)
  end

  defp storage_write_string_kind?(_), do: false
end
