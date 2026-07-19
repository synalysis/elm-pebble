defmodule Elmc.Backend.Plan.Lower.CallCoerce do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{Host, TypeParsing}
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Expr

  @spec coerce_fn_call_args(
          String.t(),
          String.t(),
          [non_neg_integer()],
          [map()],
          Context.t(),
          Elmc.Backend.Plan.Builder.t()
        ) ::
          {[non_neg_integer()], Elmc.Backend.Plan.Builder.t()}
  def coerce_fn_call_args(module, name, arg_regs, arg_exprs, ctx, b)
      when is_binary(module) and is_binary(name) and is_list(arg_regs) and is_list(arg_exprs) do
    case Map.get(ctx.decl_map, {module, name}) do
      %{type: type} when is_binary(type) ->
        arg_types = TypeParsing.function_arg_types(type)

        arg_regs
        |> Enum.with_index()
        |> Enum.reduce({[], b}, fn {reg, idx}, {regs_acc, b_acc} ->
          param_type =
            arg_types
            |> Enum.at(idx)
            |> case do
              t when is_binary(t) -> Host.normalize_type_name(t)
              _ -> nil
            end

          arg_expr = Enum.at(arg_exprs, idx)

          case maybe_coerce_arg(reg, arg_expr, param_type, ctx, b_acc) do
            {:ok, coerced_reg, b1} -> {regs_acc ++ [coerced_reg], b1}
            :skip -> {regs_acc ++ [reg], b_acc}
          end
        end)

      _ ->
        {arg_regs, b}
    end
  end

  defp maybe_coerce_arg(reg, arg_expr, "Float", ctx, b) do
    cond do
      float_expr?(arg_expr, ctx) ->
        :skip

      int_literal_expr?(arg_expr) ->
        %{op: :int_literal, value: value} = arg_expr

        case Expr.compile_runtime_builtin(:new_float, [], ctx, b, %{literal: value * 1.0}) do
          {:ok, float_reg, b1} -> {:ok, float_reg, b1}
        end

      boxed_int_expr?(arg_expr, ctx) ->
        case Expr.compile_runtime_builtin(:basics_to_float, [reg], ctx, b) do
          {:ok, float_reg, b1} -> {:ok, float_reg, b1}
        end

      true ->
        case Expr.compile_runtime_builtin(:native_int_to_float, [reg], ctx, b) do
          {:ok, float_reg, b1} -> {:ok, float_reg, b1}
        end
    end
  end

  defp maybe_coerce_arg(_reg, _arg_expr, _param_type, _ctx, _b), do: :skip

  defp float_expr?(%{op: :float_literal}, _ctx), do: true

  defp float_expr?(expr, ctx) do
    case TypedReturn.expr_type(expr, type_env(ctx)) do
      "Float" -> true
      _ -> false
    end
  end

  defp boxed_int_expr?(%{op: :runtime_call, args: %{builtin: :new_int}}, _ctx), do: true

  defp boxed_int_expr?(%{op: :runtime_call, function: function}, _ctx)
       when function in [
              "elmc_string_length_boxed",
              "elmc_string_length",
              "elmc_string_length_val",
              "string_length_boxed"
            ],
       do: true

  defp boxed_int_expr?(%{op: :qualified_call, target: target}, _ctx)
       when target in ["String.length", "Basics.String.length"],
       do: true

  defp boxed_int_expr?(%{op: :var, name: name}, ctx) when is_binary(name) do
    case TypedReturn.expr_type(%{op: :var, name: name}, type_env(ctx)) do
      "Int" -> function_param_var?(name, ctx)
      _ -> false
    end
  end

  defp boxed_int_expr?(_expr, _ctx), do: false

  defp function_param_var?(name, %Context{params: params}) when is_list(params),
    do: name in params

  defp function_param_var?(_, _), do: false

  defp int_literal_expr?(%{op: :int_literal, union_ctor: _}), do: false
  defp int_literal_expr?(%{op: :int_literal, value: value}) when is_integer(value), do: true
  defp int_literal_expr?(_), do: false

  defp type_env(%Context{} = ctx) do
    %{
      __module__: ctx.module || "Main",
      __function_name__: ctx.function_name,
      __var_types__: ctx.local_types || %{},
      __program_decls__: ctx.decl_map || %{},
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end
end
