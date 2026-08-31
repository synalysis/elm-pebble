defmodule Elmc.Backend.Plan.Lower.PebbleWatchTrig do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ProdMode
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @trig_scale 65_536

  @spec enabled?() :: boolean()
  def enabled?, do: ProdMode.pebble_watch?()

  @spec try_compile_runtime_call(map(), map(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported

  def try_compile_runtime_call(%{function: fun, args: args}, ctx, b) do
    if enabled?() do
      case fun do
        "elmc_basics_cos" -> try_cos(args, ctx, b)
        "elmc_basics_sin" -> try_sin(args, ctx, b)
        "elmc_basics_round" -> try_round(args, ctx, b)
        _ -> :unsupported
      end
    else
      :unsupported
    end
  end

  def try_compile_runtime_call(_, _, _), do: :unsupported

  @spec try_compile_compare(map(), map(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported

  def try_compile_compare(%{kind: :lt, left: left, right: right}, ctx, b) do
    if enabled?() do
      with {:ok, phase_reg, denom, b1} <- phase_angle_from_illumination(left, ctx, b),
           true <- float_half_literal?(right),
           {:ok, reg, b2} <- emit_cos_positive_pred(phase_reg, denom, ctx, b1) do
        {:ok, reg, b2}
      else
        _ -> :unsupported
      end
    else
      :unsupported
    end
  end

  def try_compile_compare(_, _, _), do: :unsupported

  defp try_cos([turn_expr], ctx, b) do
    with {:ok, phase_reg, denom, b1} <- phase_angle_from_turns(turn_expr, ctx, b),
         {:ok, reg, b2} <- emit_trig_lookup("cos_lookup", phase_reg, denom, ctx, b1) do
      {:ok, reg, b2}
    else
      _ -> :unsupported
    end
  end

  defp try_cos(_, _, _), do: :unsupported

  defp try_sin([turn_expr], ctx, b) do
    with {:ok, phase_reg, denom, b1} <- phase_angle_from_turns(turn_expr, ctx, b),
         {:ok, reg, b2} <- emit_trig_lookup("sin_lookup", phase_reg, denom, ctx, b1) do
      {:ok, reg, b2}
    else
      _ -> :unsupported
    end
  end

  defp try_sin(_, _, _), do: :unsupported

  defp try_round([value], ctx, b) do
    case match_trig_radius_mul(value) do
      {:ok, radius_expr, trig_fun, turn_expr} ->
        with {:ok, radius_reg, _b1} <- compile_int_operand(radius_expr, ctx, b),
             {:ok, phase_reg, denom, b2} <- phase_angle_from_turns(turn_expr, ctx, b),
             lookup = if(trig_fun == :sin, do: "sin_lookup", else: "cos_lookup"),
             {:ok, reg, b3} <-
               emit_radius_trig_round(lookup, radius_reg, phase_reg, denom, ctx, b2) do
          {:ok, reg, b3}
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  defp try_round(_, _, _), do: :unsupported

  defp phase_angle_from_turns(%{op: :runtime_call, function: "elmc_basics_turns", args: [frac]}, ctx, b) do
    phase_fraction_units(frac, ctx, b)
  end

  defp phase_angle_from_turns(%{op: :call, name: "turns", args: [frac]}, ctx, b) do
    phase_fraction_units(frac, ctx, b)
  end

  defp phase_angle_from_turns(
         %{op: :qualified_call, target: target, args: [frac]},
         ctx,
         b
       )
       when target in ["Basics.turns", "turns"] do
    phase_fraction_units(frac, ctx, b)
  end

  defp phase_angle_from_turns(_, _, _), do: :error

  defp phase_fraction_units(expr, ctx, b) do
    expr = resolve_let_expr(expr, ctx)

    case fdiv_operands(expr) do
      {:ok, numerator, denominator} ->
        with {:ok, phase_reg, b1} <- compile_to_float_numerator(numerator, ctx, b),
             {:ok, denom} <- int_literal_value(denominator) do
          {:ok, phase_reg, denom, b1}
        else
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp resolve_let_expr(%{op: :var, name: name} = expr, ctx) when is_binary(name) do
    case Context.let_expr(ctx, name) || Context.stream_alias(ctx, name) do
      aliased when is_map(aliased) -> resolve_let_expr(aliased, ctx)
      _ -> expr
    end
  end

  defp resolve_let_expr(expr, _ctx), do: expr

  defp fdiv_operands(%{op: :call, name: "__fdiv__", args: [left, right]}),
    do: {:ok, left, right}

  defp fdiv_operands(%{op: :runtime_call, function: "elmc_basics_fdiv", args: [left, right]}),
    do: {:ok, left, right}

  defp fdiv_operands(%{op: :qualified_call, target: target, args: [left, right]})
       when target in ["Basics./", "/", "__fdiv__"],
       do: {:ok, left, right}

  defp fdiv_operands(_), do: :error

  defp compile_to_float_numerator(expr, ctx, b) do
    inner =
      case expr do
        %{op: :runtime_call, function: "elmc_basics_to_float", args: [value]} -> value
        %{op: :call, name: name, args: [value]} when name in ["toFloat", "Basics.toFloat"] -> value
        %{op: :qualified_call, target: target, args: [value]} when target in ["Basics.toFloat", "toFloat"] -> value
        other -> other
      end

    compile_int_operand(inner, ctx, b)
  end

  defp compile_int_operand(expr, ctx, b) do
    case Expr.compile(expr, ctx, b) do
      {:ok, reg, b1} when is_integer(reg) -> {:ok, reg, b1}
      _ -> :error
    end
  end

  defp int_literal_value(%{op: :int_literal, value: value}) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp int_literal_value(%{op: :float_literal, value: value}) when is_number(value) and value > 0,
    do: {:ok, trunc(value)}

  defp int_literal_value(_), do: :error

  defp emit_trig_lookup(lookup, phase_reg, denom, ctx, b) do
    angle = trig_angle_expr(phase_reg, denom)

    c_expr = "#{lookup}(#{angle})"
    Expr.compile_runtime_builtin(:new_int, [], ctx, b, %{c_expr: c_expr})
  end

  defp emit_radius_trig_round(lookup, radius_reg, phase_reg, denom, ctx, b) do
    angle = trig_angle_expr(phase_reg, denom)

    c_expr =
      "((elmc_int_t)((((int64_t)#{plan_reg(radius_reg)} * (int64_t)#{lookup}(#{angle})) + (TRIG_MAX_RATIO / 2)) / TRIG_MAX_RATIO))"

    Expr.compile_runtime_builtin(:new_int, [], ctx, b, %{c_expr: c_expr})
  end

  defp emit_cos_positive_pred(phase_reg, denom, ctx, b) do
    angle = trig_angle_expr(phase_reg, denom)
    c_expr = "(cos_lookup(#{angle}) > 0)"
    Expr.compile_runtime_builtin(:new_int, [], ctx, b, %{c_expr: c_expr})
  end

  defp trig_angle_expr(phase_reg, denom) do
    "((int32_t)(((int64_t)#{plan_reg(phase_reg)} * #{@trig_scale}LL) / #{denom}))"
  end

  defp plan_reg(reg) when is_integer(reg), do: "plan_native_int_#{reg}"

  defp float_half_literal?(%{op: :float_literal, value: value}), do: value == 0.5
  defp float_half_literal?(_), do: false

  defp phase_angle_from_illumination(expr, ctx, b) do
    with {:ok, numerator, denominator} <- illumination_fdiv_operands(expr),
         {:ok, phase_reg, denom, b1} <- phase_fraction_from_illumination(numerator, ctx, b),
         true <- int_literal_value(denominator) == {:ok, 2} do
      {:ok, phase_reg, denom, b1}
    else
      _ -> :error
    end
  end

  defp illumination_fdiv_operands(%{op: :call, name: "__fdiv__", args: [num, den]}),
    do: {:ok, num, den}

  defp illumination_fdiv_operands(%{op: :runtime_call, function: "elmc_basics_fdiv", args: [num, den]}),
    do: {:ok, num, den}

  defp illumination_fdiv_operands(_), do: :error

  defp phase_fraction_from_illumination(
         %{op: :call, name: "__sub__", args: [left, right]},
         ctx,
         b
       ) do
    with true <- one_literal?(left),
         {:ok, phase_reg, denom, b1} <- phase_angle_from_cos_turns(right, ctx, b) do
      {:ok, phase_reg, denom, b1}
    else
      _ -> :error
    end
  end

  defp phase_fraction_from_illumination(
         %{op: :runtime_call, function: "elmc_basics_sub", args: [left, right]},
         ctx,
         b
       ) do
    with true <- one_literal?(left),
         {:ok, phase_reg, denom, b1} <- phase_angle_from_cos_turns(right, ctx, b) do
      {:ok, phase_reg, denom, b1}
    else
      _ -> :error
    end
  end

  defp phase_fraction_from_illumination(_, _, _), do: :error

  defp one_literal?(%{op: :int_literal, value: 1}), do: true
  defp one_literal?(%{op: :float_literal, value: value}) when value in [1, 1.0], do: true
  defp one_literal?(_), do: false

  defp phase_angle_from_cos_turns(
         %{op: :runtime_call, function: "elmc_basics_cos", args: [turn_expr]},
         ctx,
         b
       ) do
    phase_angle_from_turns(turn_expr, ctx, b)
  end

  defp phase_angle_from_cos_turns(%{op: :call, name: "cos", args: [turn_expr]}, ctx, b) do
    phase_angle_from_turns(turn_expr, ctx, b)
  end

  defp phase_angle_from_cos_turns(
         %{op: :qualified_call, target: target, args: [turn_expr]},
         ctx,
         b
       )
       when target in ["Basics.cos", "cos"] do
    phase_angle_from_turns(turn_expr, ctx, b)
  end

  defp phase_angle_from_cos_turns(_, _, _), do: :error

  defp match_trig_radius_mul(expr) do
    case expr do
      %{op: :call, name: "__mul__", args: [left, right]} ->
        match_trig_radius_sides(left, right)

      %{op: :runtime_call, function: "elmc_basics_mul", args: [left, right]} ->
        match_trig_radius_sides(left, right)

      _ ->
        :error
    end
  end

  defp match_trig_radius_sides(left, right) do
    case {match_to_float_operand(left), match_trig_call(right)} do
      {{:ok, radius}, {:ok, fun, turn}} ->
        {:ok, radius, fun, turn}

      _ ->
        case {match_trig_call(left), match_to_float_operand(right)} do
          {{:ok, fun, turn}, {:ok, radius}} -> {:ok, radius, fun, turn}
          _ -> :error
        end
    end
  end

  defp match_to_float_operand(%{op: :runtime_call, function: "elmc_basics_to_float", args: [inner]}),
    do: {:ok, inner}

  defp match_to_float_operand(%{op: :call, name: name, args: [inner]})
       when name in ["toFloat", "Basics.toFloat"],
       do: {:ok, inner}

  defp match_to_float_operand(%{op: :qualified_call, target: target, args: [inner]})
       when target in ["Basics.toFloat", "toFloat"],
       do: {:ok, inner}

  defp match_to_float_operand(other), do: {:ok, other}

  defp match_trig_call(%{op: :runtime_call, function: fun, args: [turn_expr]})
       when fun in ["elmc_basics_sin", "elmc_basics_cos"] do
    fun_atom = if fun == "elmc_basics_sin", do: :sin, else: :cos
    {:ok, fun_atom, turn_expr}
  end

  defp match_trig_call(%{op: :call, name: name, args: [turn_expr]}) when name in ["sin", "cos"] do
    {:ok, String.to_existing_atom(name), turn_expr}
  end

  defp match_trig_call(
         %{op: :qualified_call, target: target, args: [turn_expr]}
       )
       when target in ["Basics.sin", "Basics.cos", "sin", "cos"] do
    fun = if target in ["Basics.sin", "sin"], do: :sin, else: :cos
    {:ok, fun, turn_expr}
  end

  defp match_trig_call(_), do: :error
end
