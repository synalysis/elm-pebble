defmodule Elmc.Backend.Bytecode.PhiShapes do
  @moduledoc false

  alias Elmc.Backend.Plan.Types

  @truthy_const0 0
  @truthy_const1 1
  @truthy_compare 2
  @truthy_reg 3

  @int_const0 0
  @int_const1 1
  @int_const 4
  @int_arith 10
  @int_new 11

  @spec encode_phi_args(Types.instr_args()) :: binary()
  def encode_phi_args(args) do
    base =
      <<
        encode_reg(Map.fetch!(args, :then))::16,
        encode_reg(Map.fetch!(args, :else))::16,
        encode_reg(Map.fetch!(args, :cond))::16
      >>

    cond do
      Map.get(args, :truthy_native) == true ->
        base <>
          <<1::8, encode_truthy_shape(Map.fetch!(args, :then_shape))::binary,
            encode_truthy_shape(Map.fetch!(args, :else_shape))::binary>>

      Map.get(args, :native_int_phi) == true ->
        base <>
          <<2::8, encode_int_shape(Map.fetch!(args, :then_shape))::binary,
            encode_int_shape(Map.fetch!(args, :else_shape))::binary>>

      true ->
        base <> <<0::8>>
    end
  end

  alias Elmc.Backend.Bytecode.Runtime

  @spec eval_phi(binary(), [Runtime.value()], (atom(), integer(), integer() -> boolean())) ::
          {Runtime.value(), binary()}
  def eval_phi(bin, locals, compare_fn) do
    <<then_reg::16, else_reg::16, cond::16, flags::8, rest::binary>> = bin
    cond_val = local_int(locals, cond) != 0

    case flags do
      1 ->
        {then_shape, rest} = decode_truthy_shape(rest)
        {else_shape, rest} = decode_truthy_shape(rest)
        shape = if cond_val, do: then_shape, else: else_shape
        {eval_truthy_shape(shape, locals, compare_fn), rest}

      2 ->
        {then_shape, rest} = decode_int_shape(rest)
        {else_shape, rest} = decode_int_shape(rest)
        shape = if cond_val, do: then_shape, else: else_shape
        {eval_int_shape(shape, locals, compare_fn), rest}

      _ ->
        chosen = if cond_val, do: then_reg, else: else_reg
        {get_local(locals, chosen), rest}
    end
  end

  defp encode_truthy_shape({:const_int, 0}), do: <<@truthy_const0::8>>
  defp encode_truthy_shape({:const_int, 1}), do: <<@truthy_const1::8>>

  defp encode_truthy_shape({:compare, kind, left, right}) do
    <<@truthy_compare::8, compare_kind(kind)::8, encode_reg(left)::16, encode_reg(right)::16>>
  end

  defp encode_truthy_shape({:reg, reg}), do: <<@truthy_reg::8, encode_reg(reg)::16>>
  defp encode_truthy_shape(_), do: <<@truthy_const0::8>>

  defp decode_truthy_shape(<<@truthy_const0::8, rest::binary>>), do: {{:const_int, 0}, rest}
  defp decode_truthy_shape(<<@truthy_const1::8, rest::binary>>), do: {{:const_int, 1}, rest}

  defp decode_truthy_shape(<<@truthy_compare::8, kind::8, left::16, right::16, rest::binary>>) do
    {{:compare, decode_compare_kind(kind), left, right}, rest}
  end

  defp decode_truthy_shape(<<@truthy_reg::8, reg::16, rest::binary>>), do: {{:reg, reg}, rest}
  defp decode_truthy_shape(rest), do: {{:const_int, 0}, rest}

  defp eval_truthy_shape({:const_int, 0}, _locals, _compare_fn), do: 0
  defp eval_truthy_shape({:const_int, 1}, _locals, _compare_fn), do: 1

  defp eval_truthy_shape({:compare, kind, left, right}, locals, compare_fn) do
    if compare_fn.(kind, local_int(locals, left), local_int(locals, right)), do: 1, else: 0
  end

  defp eval_truthy_shape({:reg, reg}, locals, _compare_fn) do
    if truthy?(get_local(locals, reg)), do: 1, else: 0
  end

  defp eval_truthy_shape(_, _locals, _compare_fn), do: 0

  defp encode_int_shape({:const_int, value}) when value in [0, 1] do
    if value == 0, do: <<@int_const0::8>>, else: <<@int_const1::8>>
  end

  defp encode_int_shape({:const_int, value}), do: <<@int_const::8, value::32>>

  defp encode_int_shape({:int_arith, args}) do
    encode_int_arith_shape(args)
  end

  defp encode_int_shape({:new_int, value}) when is_integer(value), do: <<@int_new::8, value::32>>

  defp encode_int_shape({:new_int, expr}) when is_binary(expr) do
    case Elmc.Backend.CCodegen.Emit.resolve_c_int_expr(expr) do
      {:ok, n} -> <<@int_new::8, n::32>>
      :error -> <<@int_const0::8>>
    end
  end

  defp encode_int_shape(_), do: <<@int_const0::8>>

  defp encode_int_arith_shape(args) do
    kind = Map.fetch!(args, :kind)
    lhs = Map.fetch!(args, :lhs)

    kind_n =
      case kind do
        :add_const -> 0
        :sub_const -> 1
        :add_vars -> 2
        :mul_vars -> 3
        :sub_vars -> 4
        :idiv_vars -> 5
        :min_vars -> 6
        :max_vars -> 7
        :mod_vars -> 8
        :rem_vars -> 9
        _ -> 0
      end

    payload =
      case kind do
        k when k in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :min_vars, :max_vars, :mod_vars, :rem_vars] ->
          <<encode_reg(lhs)::16, encode_reg(Map.fetch!(args, :rhs))::16>>

        _ ->
          <<encode_reg(lhs)::16, Map.fetch!(args, :value)::32>>
      end

    <<@int_arith::8, kind_n::8, payload::binary>>
  end

  defp decode_int_shape(<<@int_const0::8, rest::binary>>), do: {{:const_int, 0}, rest}
  defp decode_int_shape(<<@int_const1::8, rest::binary>>), do: {{:const_int, 1}, rest}
  defp decode_int_shape(<<@int_const::8, value::32, rest::binary>>), do: {{:const_int, value}, rest}
  defp decode_int_shape(<<@int_new::8, value::32, rest::binary>>), do: {{:new_int, value}, rest}

  defp decode_int_shape(<<@int_arith::8, kind::8, rest::binary>>) do
    {args, rest} = decode_int_arith_payload(kind, rest)
    {{:int_arith, args}, rest}
  end

  defp decode_int_shape(rest), do: {{:const_int, 0}, rest}

  defp decode_int_arith_payload(kind, <<lhs::16, rest::binary>>) do
    kind_atom = int_arith_kind(kind)

    case kind_atom do
      k when k in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :min_vars, :max_vars, :mod_vars, :rem_vars] ->
        <<rhs::16, tail::binary>> = rest
        {%{kind: k, lhs: lhs, rhs: rhs}, tail}

      _ ->
        <<value::32, tail::binary>> = rest
        {%{kind: kind_atom, lhs: lhs, value: value}, tail}
    end
  end

  defp eval_int_shape({:const_int, value}, _locals, _compare_fn), do: value

  defp eval_int_shape({:new_int, value}, _locals, _compare_fn) when is_integer(value), do: value

  defp eval_int_shape({:int_arith, args}, locals, _compare_fn) do
    eval_int_arith_args(args, locals)
  end

  defp eval_int_arith_args(%{kind: kind, lhs: lhs} = args, locals) do
    left = local_int(locals, lhs)

    case kind do
      :add_const -> left + Map.fetch!(args, :value)
      :sub_const -> left - Map.fetch!(args, :value)
      :add_vars -> left + local_int(locals, Map.fetch!(args, :rhs))
      :mul_vars -> left * local_int(locals, Map.fetch!(args, :rhs))
      :sub_vars -> left - local_int(locals, Map.fetch!(args, :rhs))
      :idiv_vars ->
        rhs = local_int(locals, Map.fetch!(args, :rhs))
        if rhs == 0, do: 0, else: div(left, rhs)

      :min_vars -> min(left, local_int(locals, Map.fetch!(args, :rhs)))
      :max_vars -> max(left, local_int(locals, Map.fetch!(args, :rhs)))
      :mod_vars -> elm_mod_by(left, local_int(locals, Map.fetch!(args, :rhs)))
      :rem_vars -> elm_rem_by(left, local_int(locals, Map.fetch!(args, :rhs)))
      _ -> left
    end
  end

  defp compare_kind(:eq), do: 0
  defp compare_kind(:neq), do: 1
  defp compare_kind(:gt), do: 2
  defp compare_kind(:gte), do: 3
  defp compare_kind(:lt), do: 4
  defp compare_kind(:lte), do: 5
  defp compare_kind(_), do: 0

  defp decode_compare_kind(0), do: :eq
  defp decode_compare_kind(1), do: :neq
  defp decode_compare_kind(2), do: :gt
  defp decode_compare_kind(3), do: :gte
  defp decode_compare_kind(4), do: :lt
  defp decode_compare_kind(5), do: :lte
  defp decode_compare_kind(_), do: :eq

  defp int_arith_kind(0), do: :add_const
  defp int_arith_kind(1), do: :sub_const
  defp int_arith_kind(2), do: :add_vars
  defp int_arith_kind(3), do: :mul_vars
  defp int_arith_kind(4), do: :sub_vars
  defp int_arith_kind(5), do: :idiv_vars
  defp int_arith_kind(6), do: :min_vars
  defp int_arith_kind(7), do: :max_vars
  defp int_arith_kind(8), do: :mod_vars
  defp int_arith_kind(9), do: :rem_vars
  defp int_arith_kind(_), do: :add_const

  defp encode_reg(nil), do: 0xFFFD
  defp encode_reg(:fn_out), do: 0xFFFF
  defp encode_reg(:branch_out), do: 0xFFFE
  defp encode_reg(reg) when is_integer(reg), do: reg

  defp get_local(locals, 0xFFFF), do: List.last(locals)
  defp get_local(locals, idx), do: Enum.at(locals, idx)

  defp local_int(locals, idx), do: get_local(locals, idx) |> to_int()

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: trunc(n)
  defp to_int(true), do: 1
  defp to_int(false), do: 0
  defp to_int({:just, v}), do: to_int(v)
  defp to_int(_), do: 0

  defp truthy?(v) when v in [false, 0, nil], do: false
  defp truthy?({:just, inner}), do: truthy?(inner)
  defp truthy?(_), do: true

  defp elm_mod_by(_a, 0), do: 0

  defp elm_mod_by(a, b) do
    r = rem(a, b)
    if r < 0, do: r + abs(b), else: r
  end

  defp elm_rem_by(a, b) do
    if b == 0, do: 0, else: rem(a, b)
  end
end
