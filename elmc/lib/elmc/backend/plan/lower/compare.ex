defmodule Elmc.Backend.Plan.Lower.Compare do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{Host, TypeParsing}
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @nothing_names ~w(Nothing Maybe.Nothing)

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported
  def compile(%{op: :compare, kind: kind, left: left, right: right}, ctx, b) do
    compile(%{kind: kind, left: left, right: right}, ctx, b)
  end

  def compile(%{kind: kind, left: left, right: right}, ctx, b) do
    case maybe_vs_nothing_compare(kind, left, right) do
      {:ok, maybe_expr, compare_kind} ->
        compile_maybe_vs_nothing(maybe_expr, compare_kind, ctx, b)

      :error ->
        compile_generic_compare(kind, left, right, ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  defp compile_generic_compare(kind, left, right, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, left_reg, left_owned?, b1} <- compile_operand(left, operand_ctx, b),
         {:ok, right_reg, right_owned?, b2} <- compile_operand(right, operand_ctx, b1) do
      {reg, b3} = Builder.fresh_reg(b2)

      consumes =
        [left_reg, right_reg]
        |> Enum.zip([left_owned?, right_owned?])
        |> Enum.flat_map(fn
          {r, true} -> [r]
          _ -> []
        end)

      borrows =
        [left_reg, right_reg]
        |> Enum.reject(&(&1 in consumes))

      {_, b4} =
        Builder.emit(b3, :compare, %{
          dest: reg,
          args: %{
            kind: kind || :eq,
            left: left_reg,
            right: right_reg,
            mode: compare_equality_mode(left, right, ctx)
          },
          effects: %{
            produces: {:owned, reg},
            consumes: consumes,
            borrows: borrows,
            fallible: false
          }
        })

      {:ok, reg, b4}
    else
      _ -> :unsupported
    end
  end

  defp compile_maybe_vs_nothing(maybe_expr, :eq, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, subj_owned?, b1} <- compile_operand(maybe_expr, operand_ctx, b),
         {:ok, reg, b2} <- emit_test_maybe_nothing(subj_reg, b1) do
      b3 = maybe_consume_owned(b2, subj_reg, subj_owned?)
      {:ok, reg, b3}
    else
      _ -> :unsupported
    end
  end

  defp compile_maybe_vs_nothing(maybe_expr, :neq, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, subj_owned?, b1} <- compile_operand(maybe_expr, operand_ctx, b),
         {:ok, nothing_reg, b2} <- emit_test_maybe_nothing(subj_reg, b1),
         {:ok, zero_reg, b3} <- emit_const_int(0, b2),
         {:ok, reg, b4} <- emit_compare_eq(nothing_reg, zero_reg, b3) do
      b5 = maybe_consume_owned(b4, subj_reg, subj_owned?)
      {:ok, reg, b5}
    else
      _ -> :unsupported
    end
  end

  defp maybe_vs_nothing_compare(kind, left, right)
       when kind in [:eq, :neq] do
    cond do
      nothing_literal?(right) -> {:ok, left, kind}
      nothing_literal?(left) -> {:ok, right, kind}
      true -> :error
    end
  end

  defp maybe_vs_nothing_compare(_kind, _left, _right), do: :error

  defp nothing_literal?(%{op: :constructor_call, target: target}) when is_binary(target) do
    short_ctor_name(target) in @nothing_names
  end

  defp nothing_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    String.ends_with?(ctor, ".Nothing") or ctor == "Nothing"
  end

  defp nothing_literal?(_expr), do: false

  defp emit_test_maybe_nothing(subj_reg, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_maybe_nothing, %{
        dest: reg,
        args: %{reg: subj_reg},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [subj_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  defp emit_const_int(value, b) do
    {reg, b1} = Builder.emit_const_int(b, value)
    {:ok, reg, b1}
  end

  defp emit_compare_eq(left, right, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :compare, %{
        dest: reg,
        args: %{kind: :eq, left: left, right: right, mode: :int_boxed},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [left, right],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  defp maybe_consume_owned(b, _reg, false), do: b
  defp maybe_consume_owned(b, _reg, true), do: b

  defp compile_operand(expr, ctx, b) do
    case Expr.compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, operand_owned?(expr), b1}
      other -> other
    end
  end

  defp operand_owned?(%{op: :field_access}), do: true

  defp operand_owned?(%{op: op})
       when op in [:int_literal, :bool_literal, :string_literal, :cmd_none, :sub_none],
       do: true

  defp operand_owned?(_), do: false

  defp short_ctor_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  defp compare_equality_mode(left, right, ctx) do
    env = type_env(ctx)

    cond do
      TypedReturn.list_int_expr?(left, env) and TypedReturn.list_int_expr?(right, env) ->
        :list_int

      int_equality_operand?(left, env) and int_equality_operand?(right, env) ->
        :int_boxed

      true ->
        :pointer
    end
  end

  defp int_equality_operand?(%{op: :int_literal}, _env), do: true

  defp int_equality_operand?(expr, env) do
    case TypedReturn.expr_type(expr, env) do
      "Int" -> true
      _ -> false
    end
  end

  defp type_env(%Context{} = ctx) do
    %{
      __module__: ctx.module || "Main",
      __var_types__:
        param_var_types(ctx)
        |> Map.merge(ctx.local_types),
      __program_decls__: ctx.decl_map,
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  defp param_var_types(%Context{decl_map: decl_map, module: module, params: params, function_name: fun})
       when is_binary(module) and is_binary(fun) and is_list(params) do
    with decl when is_map(decl) <- Map.get(decl_map, {module, fun}, %{}),
         type when is_binary(type) <- Map.get(decl, :type),
         arg_types when is_list(arg_types) <- TypeParsing.function_arg_types(type) do
      params
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {name, idx}, acc ->
        case Enum.at(arg_types, idx) do
          arg_type when is_binary(arg_type) ->
            Map.put(acc, name, Host.normalize_type_name(arg_type))

          _ ->
            acc
        end
      end)
    else
      _ -> %{}
    end
  end

  defp param_var_types(_), do: %{}
end
