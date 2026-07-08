defmodule Elmc.Backend.CCodegen.BuiltinUnion do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @maybe_nothing "Nothing"
  @maybe_just "Just"
  @result_ok "Ok"
  @result_err "Err"

  @payload_ctors %{
    @maybe_just => "elmc_maybe_just",
    @result_ok => "elmc_result_ok",
    @result_err => "elmc_result_err"
  }

  @payload_take_ctors %{
    @maybe_just => "elmc_maybe_just_own",
    @result_ok => "elmc_result_ok_own",
    @result_err => "elmc_result_err_own"
  }

  @spec union_ctor_short_name(String.t()) :: String.t()
  def union_ctor_short_name(qualified) when is_binary(qualified) do
    qualified
    |> String.split(".")
    |> List.last()
  end

  @spec maybe_nothing_literal?(Types.ir_expr()) :: boolean()
  def maybe_nothing_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    union_ctor_short_name(ctor) == @maybe_nothing
  end

  def maybe_nothing_literal?(%{op: :constructor_call, target: target, args: args})
      when args in [[], nil] and is_binary(target) do
    union_ctor_short_name(target) == @maybe_nothing
  end

  def maybe_nothing_literal?(%{op: :qualified_call, target: target, args: args})
      when args in [[], nil] and is_binary(target) do
    union_ctor_short_name(target) == @maybe_nothing
  end

  def maybe_nothing_literal?(_expr), do: false

  @spec compile_maybe_nothing(Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile_maybe_nothing(env, counter) do
    {out, counter, declare?} = union_out_target(env, counter)

    code =
      if declare? do
        "ElmcValue *#{out} = elmc_maybe_nothing();"
      else
        "#{RcRuntimeEmit.assignment_lhs(out)} = elmc_maybe_nothing();"
      end

    {code, out, counter}
  end

  @spec try_compile_tuple2(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, Types.compile_result()} | :error
  def try_compile_tuple2(%{op: :tuple2, left: left, right: right}, env, counter) do
    with %{op: :int_literal, union_ctor: ctor} <- left,
         short when is_map_key(@payload_ctors, short) <- union_ctor_short_name(ctor) do
      {payload_code, payload_var, counter} = Host.compile_expr(right, env, counter)
      {out, counter, _} = union_out_target(env, counter)
      payload_var = ValueSlots.resolve_result_slot(payload_var)

      ctor =
        if Map.has_key?(@payload_take_ctors, short) and ValueSlots.owned_ref?(payload_var) do
          Map.fetch!(@payload_take_ctors, short)
        else
          Map.fetch!(@payload_ctors, short)
        end

      assign = RcRuntimeEmit.assign_call(env, out, ctor, RcRuntimeEmit.value_expr(payload_var))

      payload_release =
        cond do
          payload_var == out ->
            ""

          # Ok/Err payload release is emitted by RcRuntimeEmit.assign_call/4
          # (result_payload_owned_release); do not release twice here.
          ValueSlots.owned_ref?(payload_var) and short in [@result_ok, @result_err] ->
            ValueSlots.abandon_stmt(payload_var)

          ValueSlots.owned_ref?(payload_var) ->
            ValueSlots.abandon_stmt(payload_var)

          true ->
            ValueSlots.release_stmt(payload_var)
        end

      out = ValueSlots.resolve_result_slot(out)

      code = """
      #{payload_code}
        #{assign}
        #{payload_release}
      """

      {:ok, {code, out, counter}}
    else
      _ -> :error
    end
  end

  def try_compile_tuple2(_expr, _env, _counter), do: :error

  defp union_out_target(env, counter) do
    {out, counter} = RcRuntimeEmit.compile_result_slot(env, counter)

    declare? =
      not ValueSlots.owned_ref?(out) and not RcRuntimeEmit.function_out_ref?(out)

    {out, counter, declare?}
  end
end
