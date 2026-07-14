defmodule Elmc.Backend.Plan.Lower.Constructor do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.UnionCtor
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @nothing_names ~w(Nothing Maybe.Nothing)
  @just_names ~w(Just Maybe.Just)
  @order_names ~w(LT EQ GT Basics.LT Basics.EQ Basics.GT)
  @order_values %{"LT" => -1, "EQ" => 0, "GT" => 1}

  @payload_builtins %{
    "Just" => :maybe_just_own,
    "Ok" => :result_ok_own,
    "Err" => :result_err_own
  }

  @spec compile(Types.constructor_target_input() | Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()

  @spec compile_payload_tuple2(Types.ir_expr(), Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_payload_tuple2(%{op: :int_literal, value: tag, union_ctor: "Decoder"}, payload_expr, ctx, b) do
    operand_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, payload_reg, b1} <- Expr.compile(payload_expr, operand_ctx, b),
         {:ok, tag_reg, b2} <-
           Expr.compile_runtime_builtin(:new_int, [], operand_ctx, b1, %{literal: tag}) do
      Expr.compile_runtime_builtin(:tuple2, [tag_reg, payload_reg], ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def compile_payload_tuple2(
        %{op: :int_literal, union_ctor: ctor} = left,
        payload_expr,
        ctx,
        b
      )
      when is_binary(ctor) do
    case Map.get(@payload_builtins, short_name(ctor)) do
      nil ->
        qualified = UnionCtor.qualify(ctor, ctx)
        tag = Map.get(left, :value) || lookup_constructor_tag(qualified, nil)

        if is_integer(tag) do
          scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

          with {:ok, tag_reg, b1} <- compile_union_tag_int(qualified, tag, scratch_ctx, b),
               {:ok, payload_reg, b2} <- compile_union_payload([payload_expr], scratch_ctx, b1) do
            Expr.compile_runtime_builtin(:tuple2, [tag_reg, payload_reg], ctx, b2)
          else
            _ -> :unsupported
          end
        else
          :unsupported
        end

      builtin ->
        qualified = UnionCtor.qualify(ctor, ctx)
        tag = lookup_constructor_tag(qualified, nil)

        with {:ok, payload_reg, b1} <- Expr.compile(payload_expr, ctx, b),
             {owned_payload, b_owned} = Builder.copy_reg_owned(b1, payload_reg) do
          extra = if is_integer(tag), do: %{literal: tag}, else: %{}
          Expr.compile_runtime_builtin(builtin, [owned_payload], ctx, b_owned, extra)
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
      record_alias_ctor?(target, args, ctx) ->
        compile_record_alias_ctor(target, args || [], ctx, b)

      ResourceUnion.constructor?(target, args) ->
        compile_resource_union_index(target, ctx, b)

      short in @nothing_names ->
        compile_nothing(ctx, b)

      short in @just_names ->
        compile_just(args, ctx, b)

      unit_ctor?(target, short) ->
        Expr.compile_runtime_builtin(:unit, [], ctx, b)

      short in @order_names or target in @order_names ->
        compile_order_literal(short, ctx, b)

      true_or_false?(target) ->
        compile_bool_literal(target, ctx, b)

      true ->
        compile_union_value(target, args || [], Map.get(expr, :value), ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  defp record_alias_ctor?(target, args, ctx) when is_binary(target) do
    arity = args |> List.wrap() |> length()
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case record_alias_key(target, ctx, shapes) do
      {mod, name} ->
        case Map.get(shapes, {mod, name}) do
          fields when is_list(fields) -> length(fields) == arity
          _ -> false
        end

      _ ->
        false
    end
  end

  defp record_alias_key(target, ctx, shapes) do
    case String.split(target, ".", trim: true) do
      [name] ->
        mod = ctx && Map.get(ctx, :module)
        if is_binary(mod) and Map.has_key?(shapes, {mod, name}), do: {mod, name}, else: nil

      parts ->
        mod = parts |> Enum.drop(-1) |> Enum.join(".")
        name = parts |> List.last()
        if Map.has_key?(shapes, {mod, name}), do: {mod, name}, else: nil
    end
  end

  defp compile_record_alias_ctor(target, args, ctx, b) when is_binary(target) and is_list(args) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case record_alias_key(target, ctx, shapes) do
      {mod, name} ->
        field_names = Map.get(shapes, {mod, name}, []) |> List.wrap()
        shape = "#{mod}.#{name}"

        scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

        with {:ok, regs, b1} <- Expr.compile_args(args, scratch_ctx, b) do
          Expr.compile_runtime_builtin(:record_new, regs, ctx, b1, %{shape: shape, field_names: field_names})
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  defp compile_resource_union_index(target, _ctx, b) do
    {reg, b1} = Builder.emit_const_int(b, ResourceUnion.slot_index(target))
    {:ok, reg, b1}
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

      wrap_catch? = Builder.wrap_fallible_instr_catch?(b2, ctx, true)

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

  defp compile_order_literal(short, ctx, b) do
    value = Map.fetch!(@order_values, short_name(short))
    Expr.compile_runtime_builtin(:new_order, [], ctx, b, %{literal: value})
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
    qualified = UnionCtor.qualify(target, ctx)

    case lookup_constructor_tag(qualified, value) do
      tag when is_integer(tag) ->
        Builder.emit_const_int(b, tag, union_ctor: qualified)
        |> then(fn {reg, b1} -> {:ok, reg, b1} end)

      _ ->
        :unsupported
    end
  end

  # Generic custom type constructors are represented as (tag, payload) tuple2.
  # Payload is:
  # - `()` for nullary ctors
  # - the single value for unary ctors
  # - a list of values for n-ary ctors (n > 1)
  defp compile_union_value(target, args, value, ctx, b) when is_binary(target) and is_list(args) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, tag_reg, b1} <- compile_union_tag_int(target, value, scratch_ctx, b),
         {:ok, payload_reg, b2} <- compile_union_payload(args, scratch_ctx, b1) do
      Expr.compile_runtime_builtin(:tuple2, [tag_reg, payload_reg], ctx, b2)
    else
      _ -> :unsupported
    end
  end

  defp compile_union_payload([], ctx, b) do
    Expr.compile_runtime_builtin(:unit, [], ctx, b)
  end

  defp compile_union_payload([only], ctx, b) do
    Expr.compile(only, ctx, b)
  end

  defp compile_union_payload(args, ctx, b) when is_list(args) do
    with {:ok, regs, b1} <- Expr.compile_args(args, ctx, b) do
      Expr.compile_runtime_builtin(:list_from_values, regs, ctx, b1)
    else
      _ -> :unsupported
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
