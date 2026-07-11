defmodule Elmc.Backend.Plan.Lower.IntCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{FunctionCallAbi, FunctionEmit}
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.Plan.Lower.{Arith, Expr}
  alias Elmc.Backend.Plan.{Builder, Context, Types}

  @binary_ops %{
    "__add__" => :add_vars,
    "__mul__" => :mul_vars,
    "__sub__" => :sub_vars,
    "__idiv__" => :idiv_vars
  }

  @runtime_ops %{
    "modBy" => "elmc_basics_mod_by",
    "Basics.modBy" => "elmc_basics_mod_by",
    "remainderBy" => "elmc_basics_remainder_by",
    "Basics.remainderBy" => "elmc_basics_remainder_by",
    "Basics.min" => "elmc_basics_min",
    "Basics.max" => "elmc_basics_max"
  }

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, term(), Builder.t()} | :unsupported
  def compile(%{op: :call, name: name, args: [left, right]}, ctx, b) when is_binary(name) do
    cond do
      name == "__fdiv__" ->
        Arith.emit_boxed_binop(:fdiv, left, right, ctx, b)

      Map.has_key?(@binary_ops, name) and int_binop_operands?(left, right) ->
        Arith.emit_binary(Map.fetch!(@binary_ops, name), left, right, ctx, b)

      name in ["__add__", "__sub__", "__mul__", "__idiv__"] ->
        kind = Map.fetch!(@binary_ops, name)

        cond do
          float_mixture?(left, right) ->
            op =
              case name do
                "__add__" -> :add
                "__sub__" -> :sub
                "__mul__" -> :mul
                "__idiv__" -> :idiv
              end

            Arith.emit_boxed_binop(op, left, right, ctx, b)

          int_binop_operands?(left, right) ->
            Arith.emit_binary(kind, left, right, ctx, b)

          true ->
            with {:ok, l, b1} <- Expr.compile(left, ctx, b),
                 {:ok, r, b2} <- Expr.compile(right, ctx, b1) do
              Arith.emit_int_arith_regs(kind, l, r, ctx, b2)
            end
        end

      name == "__append__" ->
        folded =
          Elmc.Backend.CCodegen.StaticString.fold_append_literals(%{
            op: :call,
            name: "__append__",
            args: [left, right]
          })

        compile_folded_append(folded, ctx, b)

      Map.has_key?(@runtime_ops, name) ->
        target = Map.fetch!(@runtime_ops, name)

        cond do
          name in ["Basics.min", "Basics.max"] and int_binop_operands?(left, right) ->
            kind = if name == "Basics.min", do: :min_vars, else: :max_vars
            Arith.emit_binary(kind, left, right, ctx, b)

          name in ["modBy", "Basics.modBy"] and int_binop_operands?(left, right) and
              not native_int_param_in_operands?([left, right], ctx) ->
            Arith.emit_binary(:mod_vars, left, right, ctx, b)

          name in ["remainderBy", "Basics.remainderBy"] and int_binop_operands?(left, right) and
              not native_int_param_in_operands?([left, right], ctx) ->
            Arith.emit_binary(:rem_vars, left, right, ctx, b)

          true ->
            compile_runtime_binop_with_native_box(target, left, right, ctx, b)
        end

      true ->
        :unsupported
    end
  end

  def compile(%{op: :qualified_call, target: target, args: [left, right]}, ctx, b)
      when is_binary(target) do
    compile(%{op: :call, name: target, args: [left, right]}, ctx, b)
  end

  def compile(_, _, _), do: :unsupported

  defp compile_folded_append(%{op: :string_literal} = lit, ctx, b),
    do: Expr.compile(lit, ctx, b)

  defp compile_folded_append(%{op: :call, name: "__append__", args: [left, right]}, ctx, b) do
    append_builtin =
      cond do
        list_append_operand?(left) or list_append_operand?(right) -> :list_append
        string_append_operands?(left, right) -> :string_append
        true -> :list_append
      end

    with {:ok, arg_regs, b1} <- Expr.compile_args([left, right], ctx, b) do
      Expr.compile_runtime_builtin(append_builtin, arg_regs, ctx, b1)
    end
  end

  defp compile_folded_append(expr, ctx, b), do: Expr.compile(expr, ctx, b)

  defp compile_runtime_binop_with_native_box(target, left, right, ctx, b) do
    with {:ok, arg_regs, b1} <- Expr.compile_args([left, right], ctx, b),
         {boxed_regs, b2} <- box_native_int_call_args(arg_regs, ctx, b1),
         id when not is_nil(id) <- Elmc.Backend.Plan.RuntimeBuiltins.from_c_symbol(target) do
      Expr.compile_runtime_builtin(id, boxed_regs, ctx, b2)
    else
      _ -> :unsupported
    end
  end

  defp box_native_int_call_args(regs, ctx, b) when is_list(regs) do
    Enum.map_reduce(regs, b, fn reg, b_acc ->
      idx = param_reg_index(reg, ctx, b_acc)

      if is_integer(idx) and native_int_param_index?(idx, ctx) do
        box_native_int_param_reg(idx, ctx, b_acc)
      else
        {reg, b_acc}
      end
    end)
  end

  defp param_reg_index(reg, ctx, b) when is_integer(reg) do
    Enum.find_value(Enum.with_index(ctx.params), fn {name, idx} ->
      if Map.get(b.param_regs, name) == reg, do: idx
    end)
  end

  defp param_reg_index(_, _, _), do: nil

  defp native_int_param_index?(idx, ctx) do
    case Map.get(ctx.decl_map, {ctx.module, ctx.function_name}) do
      decl when is_map(decl) ->
        decl = %{decl | args: FunctionEmit.effective_decl_args(decl, ctx.module, ctx.decl_map)}
        Enum.at(NativeFunctionCall.arg_kinds(decl, ctx.module, ctx.decl_map), idx) == :native_int

      _ ->
        false
    end
  end

  defp native_int_param_in_operands?([left, right], ctx) do
    native_int_param_var?(left, ctx) or native_int_param_var?(right, ctx)
  end

  defp native_int_param_var?(%{op: :var, name: name}, ctx) when is_binary(name) do
    case Enum.find_index(ctx.params, &(&1 == name)) do
      idx when is_integer(idx) -> native_int_param_index?(idx, ctx)
      _ -> false
    end
  end

  defp native_int_param_var?(_, _), do: false

  defp box_native_int_param_reg(idx, ctx, b) do
    c_ref = FunctionCallAbi.param_c_arg(idx, ctx.params)
    {box_reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: box_reg,
        args: %{builtin: :new_int, c_expr: c_ref},
        effects: Types.fallible_effects(box_reg)
      })

    {box_reg, b2}
  end

  defp int_binop_operands?(left, right), do: int_operand?(left) and int_operand?(right)

  defp float_mixture?(left, right), do: float_operand?(left) or float_operand?(right)

  defp float_operand?(%{op: :float_literal}), do: true
  defp float_operand?(_), do: false

  defp int_operand?(%{op: :int_literal}), do: true
  defp int_operand?(%{op: :bool_literal}), do: true
  defp int_operand?(%{op: :var}), do: true
  defp int_operand?(%{op: :add_const, var: _, value: _}), do: true
  defp int_operand?(%{op: :sub_const, var: _, value: _}), do: true
  defp int_operand?(%{op: :add_vars, left: _, right: _}), do: true

  defp int_operand?(%{op: :call, name: name, args: [a, b]})
       when name in ["modBy", "Basics.modBy", "remainderBy", "Basics.remainderBy", "Basics.min", "Basics.max"],
       do: int_operand?(a) and int_operand?(b)

  defp int_operand?(%{op: :call, name: name, args: [a, b]})
       when name in ["__add__", "__sub__", "__mul__", "__idiv__"],
       do: int_operand?(a) and int_operand?(b)

  defp int_operand?(%{op: :qualified_call, target: target, args: args}) do
    case {target, args} do
      {t, [a, b]}
      when t in [
             "modBy",
             "Basics.modBy",
             "remainderBy",
             "Basics.remainderBy",
             "Basics.min",
             "Basics.max",
             "Basics.//",
             "__idiv__"
           ] ->
        int_operand?(a) and int_operand?(b)

      {"Basics.floor", [arg]} -> int_operand?(arg)
      {"Basics.round", [arg]} -> int_operand?(arg)
      {"Basics.abs", [arg]} -> int_operand?(arg)
      {"Basics.negate", [arg]} -> int_operand?(arg)
      {"Basics.ceiling", [arg]} -> int_operand?(arg)
      {"Basics.truncate", [arg]} -> int_operand?(arg)
      _ -> false
    end
  end

  defp int_operand?(%{op: :runtime_call, function: function, args: args}) when is_list(args) do
    case {function, args} do
      {f, [arg]}
      when f in [
             "elmc_basics_round",
             "elmc_basics_floor",
             "elmc_basics_mod_by",
             "elmc_basics_remainder_by",
             "elmc_basics_min",
             "elmc_basics_max",
             "elmc_basics_abs",
             "elmc_basics_negate",
             "elmc_basics_ceiling",
             "elmc_basics_truncate"
           ] ->
        int_operand?(arg)

      _ ->
        false
    end
  end

  defp int_operand?(%{op: :field_access, arg: arg}) when is_binary(arg), do: true
  defp int_operand?(%{op: :field_access, arg: arg}), do: int_operand?(arg)
  defp int_operand?(%{op: :record_literal, fields: fields}) when is_list(fields),
    do: Enum.all?(fields, fn f -> int_operand?(Map.get(f, :expr) || Map.get(f, :value)) end)

  defp int_operand?(_), do: false

  @string_append_runtime_functions ~w(
    elmc_string_from_int
    elmc_string_from_native_int
    elmc_string_from_float
    elmc_string_from_char
    elmc_string_from_list
    elmc_string_reverse
    elmc_string_to_upper
    elmc_string_to_lower
    elmc_string_trim
    elmc_string_trim_left
    elmc_string_trim_right
    elmc_string_left
    elmc_string_right
    elmc_string_drop_left
    elmc_string_drop_right
    elmc_string_cons
    elmc_string_repeat
    elmc_string_replace
    elmc_string_slice
    elmc_string_pad
    elmc_string_pad_left
    elmc_string_pad_right
    elmc_string_append
  )

  @string_append_call_targets ~w(
    String.fromInt
    String.fromFloat
    String.fromChar
    String.fromList
    String.reverse
    String.toUpper
    String.toLower
    String.trim
    String.trimLeft
    String.trimRight
    String.left
    String.right
    String.dropLeft
    String.dropRight
    String.cons
    String.repeat
    String.replace
    String.slice
    String.pad
    String.padLeft
    String.padRight
    fromInt
    fromFloat
    fromChar
    fromList
  )

  defp string_append_operands?(left, right),
    do: string_append_operand?(left) or string_append_operand?(right)

  defp string_append_operand?(%{op: :list_literal}), do: false
  defp string_append_operand?(%{op: :string_literal}), do: true

  defp string_append_operand?(%{op: :call, name: name, args: args}) do
    name in @string_append_call_targets or
      (name == "__append__" and match?([_, _], args) and
         string_append_operands?(hd(args), Enum.at(args, 1)))
  end

  defp string_append_operand?(%{op: :qualified_call, target: target, args: args}) do
    target in @string_append_call_targets or
      (target == "++" and match?([_, _], args) and string_append_operands?(hd(args), Enum.at(args, 1)))
  end

  defp string_append_operand?(%{op: :runtime_call, function: function}) when is_binary(function),
    do: function in @string_append_runtime_functions

  defp string_append_operand?(_), do: false

  defp list_append_operand?(%{op: :list_literal}), do: true

  defp list_append_operand?(%{op: :call, name: name, args: [left, right]})
       when name in ["__append__", "++"],
       do: list_append_operand?(left) or list_append_operand?(right)

  defp list_append_operand?(%{op: :qualified_call, target: target, args: [left, right]})
       when target in ["++", "Basics.++"],
       do: list_append_operand?(left) or list_append_operand?(right)

  defp list_append_operand?(_), do: false
end
