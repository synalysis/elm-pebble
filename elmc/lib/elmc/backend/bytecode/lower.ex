defmodule Elmc.Backend.Bytecode.Lower do
  @moduledoc """
  Lower `%FunctionPlan{}` to `.elmcbc` bytecode sections.
  """

  alias Elmc.Backend.Bytecode.{FnTable, Opcodes}
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type section :: %{
          magic: String.t(),
          version: non_neg_integer(),
          locals: non_neg_integer(),
          code: binary(),
          block_ips: %{non_neg_integer() => non_neg_integer()},
          fn_table: FnTable.t(),
          lambdas: [section()]
        }

  @magic "ELMC"
  @version 3

  @spec manifest_version() :: non_neg_integer()
  def manifest_version, do: @version

  @spec lower(FunctionPlan.t()) :: section()
  def lower(%FunctionPlan{} = plan) do
    fn_table = FnTable.collect(plan)
    {_slots, local_count} = Plan.allocate_slots(plan)

    {code, block_ips} = encode_blocks(plan.blocks, fn_table)

    lambdas =
      (Map.get(plan, :lambdas) || [])
      |> Enum.map(&lower_lambda_section/1)

    %{
      magic: @magic,
      version: @version,
      locals: local_count + length(plan.params),
      code: code,
      block_ips: block_ips,
      fn_table: fn_table,
      lambdas: lambdas
    }
  end

  defp lower_lambda_section(%FunctionPlan{} = plan) do
    fn_table = FnTable.collect(plan)
    {_slots, local_count} = Plan.allocate_slots(plan)
    {code, block_ips} = encode_blocks(plan.blocks, fn_table)

    %{
      locals: local_count + length(plan.params),
      code: code,
      block_ips: block_ips,
      fn_table: fn_table,
      lambdas: []
    }
  end

  defp encode_blocks(blocks, fn_table) do
    blocks
    |> Enum.reduce({<<>>, 0, %{}}, fn %Block{id: id, instrs: instrs, terminator: term},
                                      {acc, offset, ips} ->
      ips = Map.put(ips, id, offset)
      chunk = encode_block(instrs, term, fn_table)
      {acc <> chunk, offset + byte_size(chunk), ips}
    end)
    |> then(fn {code, _offset, ips} -> {code, ips} end)
  end

  defp encode_block(instrs, terminator, fn_table) do
    instr_bin = instrs |> Enum.map(&encode_instr(&1, fn_table)) |> IO.iodata_to_binary()
    instr_bin <> encode_terminator(terminator)
  end

  def encode_section(%{
        magic: magic,
        version: version,
        locals: locals,
        code: code,
        block_ips: block_ips,
        fn_table: fn_table,
        lambdas: lambdas
      }) do
    fn_bin = encode_fn_table(fn_table)
    block_bin = encode_block_ips(block_ips)
    lambdas_bin = encode_lambdas(lambdas)

    magic <>
      <<version::8, locals::16, byte_size(fn_bin)::16, fn_bin::binary,
        byte_size(block_bin)::16, block_bin::binary, byte_size(code)::32, code::binary,
        length(lambdas)::16, lambdas_bin::binary>>
  end

  def encode_section(section) do
    encode_section(Map.put_new(section, :lambdas, []))
  end

  @spec decode_section(binary()) :: section()
  def decode_section(<<"ELMC", version::8, locals::16, fn_size::16, rest::binary>>) do
    <<fn_bin::binary-size(^fn_size), block_size::16, rest2::binary>> = rest
    <<block_bin::binary-size(^block_size), code_size::32, rest3::binary>> = rest2
    <<code::binary-size(^code_size), rest4::binary>> = rest3
    fn_table = decode_fn_table(fn_bin)
    block_ips = decode_block_ips(block_bin)

    {lambdas, _} =
      case version do
        v when v >= 3 ->
          case rest4 do
            <<lambda_count::16, lambdas_bin::binary>> ->
              {decode_lambdas(lambdas_bin, lambda_count), <<>>}

            _ ->
              {[], rest4}
          end

        _ ->
          {[], rest4}
      end

    %{
      magic: @magic,
      version: version,
      locals: locals,
      code: code,
      block_ips: block_ips,
      fn_table: fn_table,
      lambdas: lambdas
    }
  end

  defp encode_instr(%{op: :const_c_expr, args: %{value: value}} = instr, fn_table) do
    case resolve_c_expr_int(value) do
      {:ok, n} ->
        encode_instr(%{instr | op: :const_int, args: %{value: n}}, fn_table)

      :error ->
        opcode = Opcodes.opcode(:const_c_expr) || 0
        dest_w = encode_dest(instr.dest)
        bin = :erlang.iolist_to_binary(value)
        args_bin = <<byte_size(bin)::16, bin::binary>>
        <<opcode::8, dest_w::16, args_bin::binary>>
    end
  end

  defp encode_instr(%{op: :record_get_int} = instr, fn_table) do
    encode_instr(%{instr | op: :record_get}, fn_table)
  end

  defp encode_instr(%{op: op, dest: dest, args: args}, fn_table) do
    opcode = Opcodes.opcode(op) || 0
    dest_w = encode_dest(dest)
    args_bin = encode_args(op, args, fn_table)
    <<opcode::8, dest_w::16, args_bin::binary>>
  end

  defp encode_terminator({:br_if, then_id, else_id, cond_reg}) do
    <<Opcodes.opcode(:br_if)::8, encode_dest(cond_reg)::16, then_id::16, else_id::16>>
  end

  defp encode_terminator({:br, target_id}) do
    <<Opcodes.opcode(:br)::8, 0xFFFD::16, target_id::16>>
  end

  defp encode_terminator({:switch_tag, subject, arms, default_id}) do
    arms_bin =
      Enum.map(arms, fn {tag, block_id} -> <<tag::16, block_id::16>> end)
      |> IO.iodata_to_binary()

    <<
      Opcodes.opcode(:switch_tag)::8,
      subject::16,
      default_id::16,
      byte_size(arms_bin)::16,
      arms_bin::binary
    >>
  end

  defp encode_terminator({:ret, reg}) do
    <<Opcodes.opcode(:ret)::8, encode_dest(reg)::16>>
  end

  defp encode_terminator(:none), do: <<>>
  defp encode_terminator(_), do: <<Opcodes.opcode(:ret)::8, 0xFFFD::16>>

  defp encode_dest(nil), do: 0xFFFD
  defp encode_dest(:fn_out), do: 0xFFFF
  defp encode_dest(:branch_out), do: 0xFFFE
  defp encode_dest(r) when is_integer(r), do: r

  defp encode_reg_word(reg), do: encode_dest(reg)

  defp encode_args(:load_param, %{index: idx}, _fn_table), do: <<idx::16>>

  defp encode_args(:load_local, %{source: source}, _fn_table) when is_integer(source),
    do: <<source::16>>

  defp encode_args(:const_immortal_string, %{value: value}, _fn_table) when is_binary(value) do
    bin = :erlang.iolist_to_binary(value)
    <<byte_size(bin)::16, bin::binary>>
  end

  defp encode_args(:call_runtime, args, _fn_table) do
    id = Map.get(args, :builtin)
    regs = Map.get(args, :args, [])
    id_bin = builtin_index(id)
    literal = Map.get(args, :literal)

    literal_bin = encode_runtime_literal(literal)

    args_bin = encode_reg_list(regs)
    <<id_bin::16, literal_bin::binary, byte_size(args_bin)::16, args_bin::binary>>
  end

  defp encode_args(:call_fn, %{module: mod, name: name, args: args}, fn_table) do
    idx = FnTable.index(fn_table, {mod, name}) || 0
    args_bin = encode_reg_list(args)
    <<idx::16, byte_size(args_bin)::16, args_bin::binary>>
  end

  defp encode_args(:int_arith, %{kind: kind, lhs: lhs} = args, _fn_table) do
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

    case kind do
      k when k in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :min_vars, :max_vars, :mod_vars, :rem_vars] ->
        rhs = Map.fetch!(args, :rhs)
        <<kind_n::8, encode_reg_word(lhs)::16, encode_reg_word(rhs)::16>>

      _ ->
        <<kind_n::8, encode_reg_word(lhs)::16, Map.fetch!(args, :value)::32>>
    end
  end

  defp encode_args(:boxed_binop, %{op: op, lhs: lhs, rhs: rhs}, _fn_table) do
    op_n =
      case op do
        :add -> 0
        :sub -> 1
        :mul -> 2
        :fdiv -> 3
        _ -> 0
      end

    <<op_n::8, encode_reg_word(lhs)::16, encode_reg_word(rhs)::16>>
  end

  defp encode_args(:compare, %{kind: kind, left: l, right: r}, _fn_table) do
    kind_n =
      case kind do
        :eq -> 0
        :neq -> 1
        :gt -> 2
        :gte -> 3
        :lt -> 4
        :lte -> 5
        _ -> 0
      end

    <<kind_n::8, encode_reg_word(l)::16, encode_reg_word(r)::16>>
  end

  defp encode_args(:phi, %{then: t, else: e, cond: c}, _fn_table),
    do: <<encode_reg_word(t)::16, encode_reg_word(e)::16, encode_reg_word(c)::16>>

  defp encode_args(:record_get, args, _fn_table) do
    base = Map.fetch!(args, :base)
    idx = field_index_word(args)
    <<base::16, idx::16>>
  end

  defp encode_args(:record_update, %{base: base, value: value} = args, _fn_table) do
    idx = field_index_word(args)
    <<base::16, value::16, idx::16>>
  end

  defp encode_args(:pebble_cmd, %{builtin: id, kind: kind, params: params}, _fn_table) do
    id_bin = builtin_index(id)
    kind_hash = kind |> Map.get(:c_expr, "") |> :erlang.phash2(65536)
    params_bin = encode_reg_list(params)
    <<id_bin::16, kind_hash::16, byte_size(params_bin)::16, params_bin::binary>>
  end

  defp encode_args(:render_cmd, %{kind: kind, params: params}, _fn_table) do
    encode_platform_op(kind, params)
  end

  defp encode_args(:pebble_sub, %{kind: kind, params: params}, _fn_table) do
    encode_platform_op(kind, params)
  end

  defp encode_args(:switch_ctor_tag, %{subject: subject, arms: arms, default: default}, _fn_table) do
    arms_bin =
      Enum.map(arms, fn %{tag: tag, reg: reg} -> <<tag::16, reg::16>> end)
      |> IO.iodata_to_binary()

    default_w = if is_integer(default), do: default, else: 0xFFFF
    <<subject::16, default_w::16, byte_size(arms_bin)::16, arms_bin::binary>>
  end

  defp encode_args(:test_maybe_nothing, %{reg: reg}, _fn_table), do: <<reg::16>>

  defp encode_args(:tuple_proj, %{base: base, which: which}, _fn_table) do
    which_n = if which == :second, do: 1, else: 0
    <<which_n::8, base::16>>
  end

  defp encode_args(:make_closure, %{index: idx, arity: arity, captures: caps}, _fn_table) do
    caps_bin = encode_reg_list(caps)
    <<idx::16, arity::16, byte_size(caps_bin)::16, caps_bin::binary>>
  end

  defp encode_args(:publish, %{source: reg}, _fn_table) when is_integer(reg), do: <<reg::16>>
  defp encode_args(:publish, _, _fn_table), do: <<>>

  defp encode_args(:const_int, %{value: v}, _fn_table), do: <<v::32>>

  defp encode_args(:const_static_list, args, _fn_table) do
    kind = Map.fetch!(args, :kind)

    case kind do
      :int_array ->
        values = Map.fetch!(args, :values)
        count = length(values)

        ints =
          Enum.reduce(values, <<0::8, count::16>>, fn v, acc ->
            acc <> <<v::32>>
          end)

        ints

      :float_array ->
        values = Map.fetch!(args, :values)
        count = length(values)

        floats =
          Enum.reduce(values, <<1::8, count::16>>, fn v, acc ->
            acc <> <<static_list_float(v)::float-64>>
          end)

        floats

      :tuple2_int_array ->
        pairs = Map.fetch!(args, :pairs)
        count = length(pairs)

        Enum.reduce(pairs, <<2::8, count::16>>, fn {left, right}, acc ->
          acc <> <<left::32, right::32>>
        end)

      :values ->
        regs = Map.fetch!(args, :regs)
        count = length(regs)

        Enum.reduce(regs, <<3::8, count::16>>, fn reg, acc ->
          acc <> <<reg::16>>
        end)

      :record_array ->
        regs = Map.fetch!(args, :regs)
        count = length(regs)

        Enum.reduce(regs, <<4::8, count::16>>, fn reg, acc ->
          acc <> <<reg::16>>
        end)
    end
  end

  defp encode_args(:catch_begin, _, _fn_table), do: <<>>
  defp encode_args(:catch_end, _, _fn_table), do: <<>>
  defp encode_args(:release, %{reg: reg}, _fn_table), do: <<reg::16>>
  defp encode_args(_, _, _fn_table), do: <<>>

  defp static_list_float(v) when is_integer(v), do: v * 1.0
  defp static_list_float(v) when is_float(v), do: v

  defp resolve_c_expr_int(value) when is_binary(value) do
    Elmc.Backend.CCodegen.Emit.resolve_c_int_expr(value)
  end

  defp encode_platform_op(kind, params) do
    kind_hash =
      case kind do
        %{c_expr: expr} when is_binary(expr) -> :erlang.phash2(expr, 65536)
        %{literal: lit} when is_integer(lit) -> rem(lit, 65536)
        _ -> 0
      end

    params_bin = encode_reg_list(params)
    <<kind_hash::16, byte_size(params_bin)::16, params_bin::binary>>
  end

  defp encode_fn_table(fn_table) do
    fn_table
    |> Enum.map(fn {mod, name} ->
      mod_bin = mod |> :erlang.iolist_to_binary()
      name_bin = name |> :erlang.iolist_to_binary()
      <<byte_size(mod_bin)::8, mod_bin::binary, byte_size(name_bin)::8, name_bin::binary>>
    end)
    |> IO.iodata_to_binary()
  end

  defp decode_fn_table(bin), do: decode_fn_table(bin, [])

  defp decode_fn_table(<<mod_len::8, rest::binary>>, acc) when mod_len > 0 do
    <<mod::binary-size(^mod_len), name_len::8, rest2::binary>> = rest
    <<name::binary-size(^name_len), rest3::binary>> = rest2
    decode_fn_table(rest3, [{mod, name} | acc])
  end

  defp decode_fn_table(_, acc), do: Enum.reverse(acc)

  defp encode_block_ips(block_ips) do
    block_ips
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.map(fn {id, ip} -> <<id::16, ip::32>> end)
    |> IO.iodata_to_binary()
  end

  defp decode_block_ips(bin), do: decode_block_ips(bin, %{})

  defp decode_block_ips(<<id::16, ip::32, rest::binary>>, acc),
    do: decode_block_ips(rest, Map.put(acc, id, ip))

  defp decode_block_ips(_, acc), do: acc

  defp encode_lambdas(lambdas) when is_list(lambdas) do
    lambdas
    |> Enum.map(fn lambda ->
      fn_bin = encode_fn_table(Map.get(lambda, :fn_table, []))
      block_bin = encode_block_ips(Map.get(lambda, :block_ips, %{}))
      code = Map.fetch!(lambda, :code)

      <<
        Map.fetch!(lambda, :locals)::16,
        byte_size(fn_bin)::16,
        fn_bin::binary,
        byte_size(block_bin)::16,
        block_bin::binary,
        byte_size(code)::32,
        code::binary
      >>
    end)
    |> IO.iodata_to_binary()
  end

  defp decode_lambdas(bin, count), do: decode_lambdas(bin, count, [])

  defp decode_lambdas(_bin, 0, acc), do: Enum.reverse(acc)

  defp decode_lambdas(bin, count, acc) do
    <<locals::16, fn_size::16, rest::binary>> = bin
    <<fn_bin::binary-size(^fn_size), block_size::16, rest2::binary>> = rest
    <<block_bin::binary-size(^block_size), code_size::32, rest3::binary>> = rest2
    <<code::binary-size(^code_size), rest4::binary>> = rest3

    lambda = %{
      locals: locals,
      code: code,
      block_ips: decode_block_ips(block_bin),
      fn_table: decode_fn_table(fn_bin),
      lambdas: []
    }

    decode_lambdas(rest4, count - 1, [lambda | acc])
  end

  defp builtin_index(id) do
    RuntimeBuiltins.ids()
    |> Enum.find_index(&(&1 == id))
    |> Kernel.||(0)
  end

  defp encode_reg_list(regs) do
    regs |> Enum.map(&encode_reg/1) |> IO.iodata_to_binary()
  end

  defp encode_reg(reg) when is_integer(reg), do: <<reg::16>>
  defp encode_reg(:fn_out), do: <<0xFFFF::16>>
  defp encode_reg(:branch_out), do: <<0xFFFE::16>>
  defp encode_reg(nil), do: <<0xFFFD::16>>

  defp encode_runtime_literal(value) when is_float(value), do: <<2::8, value::float-32>>
  defp encode_runtime_literal(value) when is_integer(value), do: <<1::8, value::signed-32>>
  defp encode_runtime_literal(_), do: <<0::8>>

  defp field_index_word(args) do
    args
    |> Map.get(:field_index)
    |> case do
      idx when is_integer(idx) -> idx
      idx when is_binary(idx) ->
        case Integer.parse(idx) do
          {n, _} -> n
          _ -> 0
        end

      _ ->
        case Map.get(args, :field) do
          field when is_binary(field) -> rem(:erlang.phash2(field, 65536), 256)
          _ -> 0
        end
    end
  end
end
