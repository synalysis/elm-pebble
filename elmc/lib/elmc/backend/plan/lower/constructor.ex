defmodule Elmc.Backend.Plan.Lower.Constructor do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @nothing_names ~w(Nothing Maybe.Nothing)
  @just_names ~w(Just Maybe.Just)

  @payload_builtins %{
    "Just" => :maybe_just_own,
    "Ok" => :result_ok_own,
    "Err" => :result_err_own
  }

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported

  @spec compile_payload_tuple2(map(), map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_payload_tuple2(
        %{op: :int_literal, union_ctor: ctor},
        payload_expr,
        ctx,
        b
      )
      when is_binary(ctor) do
    case Map.get(@payload_builtins, short_name(ctor)) do
      nil ->
        :unsupported

      builtin ->
        with {:ok, payload_reg, b1} <- Expr.compile(payload_expr, ctx, b),
             {owned_payload, b_owned} = Builder.copy_reg_owned(b1, payload_reg) do
          Expr.compile_runtime_builtin(builtin, [owned_payload], ctx, b_owned)
        else
          _ -> :unsupported
        end
    end
  end

  def compile_payload_tuple2(_, _, _, _), do: :unsupported

  def compile(%{target: target} = expr, ctx, b) when is_binary(target) do
    args = Map.get(expr, :args, [])
    short = target |> String.split(".") |> List.last()

    cond do
      ResourceUnion.constructor?(target, args) ->
        compile_resource_union_index(target, ctx, b)

      short in @nothing_names ->
        compile_nothing(ctx, b)

      short in @just_names ->
        compile_just(args, ctx, b)

      unit_ctor?(target, short) ->
        Expr.compile_runtime_builtin(:unit, [], ctx, b)

      true_or_false?(target) ->
        compile_bool_literal(target, ctx, b)

      true ->
        compile_union_tag_int(target, Map.get(expr, :value), ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  defp compile_resource_union_index(target, ctx, b) do
    Expr.compile_runtime_builtin(:new_int, [], ctx, b, %{literal: ResourceUnion.slot_index(target)})
  end

  defp compile_nothing(ctx, b) do
    {dest, b1} = dest_for_ctor(ctx, b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: dest,
        args: %{builtin: :maybe_nothing, args: []},
        effects:
          if(is_integer(dest),
            do: Types.owned_effects(dest),
            else: Types.empty_effects()
          )
      })

    {:ok, dest, b2}
  end

  defp compile_just(args, ctx, b) do
    payload = List.first(args || [])

    with {:ok, payload_reg, b1} <- Expr.compile(payload, ctx, b),
         {owned_payload, b_owned} = Builder.copy_reg_owned(b1, payload_reg) do
      {dest, b2} = dest_for_ctor(ctx, b_owned)

      wrap_catch? = (ctx.fallible or ctx.rc_required) and not Builder.skip_instr_catch?(b2, ctx)

      b3 = if wrap_catch?, do: Builder.catch_begin(b2), else: b2

      effects =
        if is_integer(dest) do
          Types.fallible_effects(dest, [owned_payload], [owned_payload])
        else
          Types.fallible_transfer([owned_payload], [owned_payload])
        end

      {_, b4} =
        Builder.emit(b3, :call_runtime, %{
          dest: dest,
          args: %{builtin: :maybe_just_own, args: [owned_payload]},
          effects: effects
        })

      b5 = if wrap_catch?, do: Builder.catch_end(b4), else: b4
      {:ok, dest, b5}
    else
      _ -> :unsupported
    end
  end

  defp unit_ctor?(target, short) do
    short == "()" or target in ["()", "Basics.()"]
  end

  defp true_or_false?(target) when is_binary(target) do
    target in ["True", "False", "Basics.True", "Basics.False"] or
      String.ends_with?(target, ".True") or
      String.ends_with?(target, ".False")
  end

  defp compile_bool_literal(target, _ctx, b) do
    value =
      cond do
        String.ends_with?(target, "True") -> 1
        true -> 0
      end

    Builder.emit_const_int(b, value) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
  end

  defp compile_union_tag_int(target, value, ctx, b) do
    case lookup_constructor_tag(target, value) do
      tag when is_integer(tag) ->
        Expr.compile_runtime_builtin(:new_int, [], ctx, b, %{literal: tag})

      _ ->
        :unsupported
    end
  end

  defp lookup_constructor_tag(target, value) do
    tags = Process.get(:elmc_constructor_tags, %{})

    Map.get(tags, target) ||
      Map.get(tags, short_name(target)) ||
      lookup_qualified_tag(target, tags) ||
      (is_integer(value) && value)
  end

  defp lookup_qualified_tag(name, tags) do
    Enum.find_value(tags, fn {key, tag} ->
      if String.ends_with?(key, "." <> short_name(name)), do: tag
    end)
  end

  defp short_name(name), do: name |> String.split(".") |> List.last()

  defp dest_for_ctor(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end
end
