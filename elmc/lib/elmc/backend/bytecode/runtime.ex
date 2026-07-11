defmodule Elmc.Backend.Bytecode.Runtime do
  @moduledoc """
  Minimal bytecode interpreter for IDE/emulator integration.

  Executes `.elmcbc` sections produced by `Bytecode.Lower` against the
  logical runtime builtin table.
  """

  alias Elmc.Backend.Bytecode.{FusionRunner, Lower, Opcodes, PhiShapes}
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @type value ::
          integer()
          | list()
          | map()
          | nil
          | {:tuple2, value(), value()}
          | {:closure, non_neg_integer(), [value()], {String.t(), String.t()}}
          | {:forward_ref, String.t()}
          | {:render_cmd, non_neg_integer(), [value()]}
          | {:pebble_sub, non_neg_integer(), [value()]}
          | {:pebble_cmd, atom(), non_neg_integer(), [value()]}
          | {:just, value()}
          | {:record, [value()]}
  @type frame :: %{
          locals: [value()],
          params: [value()],
          ip: non_neg_integer(),
          code: binary(),
          block_ips: %{non_neg_integer() => non_neg_integer()},
          fn_table: Elmc.Backend.Bytecode.FnTable.t(),
          fn_registry: map(),
          plans: %{optional({String.t(), String.t()}) => FunctionPlan.t()},
          plan_key: {String.t(), String.t()},
          forward_refs: %{String.t() => value()}
        }

  @spec run_function(FunctionPlan.t(), keyword()) :: {:ok, value()} | {:error, term()}
  def run_function(%FunctionPlan{} = plan, opts \\ []) do
    if FusionRunner.runnable?(plan) do
      case FusionRunner.run(plan, opts) do
        {:ok, value} -> {:ok, value}
        :unsupported -> run_function_section(plan, opts)
      end
    else
      run_function_section(plan, opts)
    end
  end

  defp run_function_section(%FunctionPlan{} = plan, opts) do
    section = Lower.lower(plan)

    merged_plans =
      opts
      |> Keyword.get(:plans, %{})
      |> Map.merge(plans_index(plan))

    opts =
      opts
      |> Keyword.put(:plans, merged_plans)
      |> Keyword.put(:plan_key, {plan.module, plan.name})
      |> Keyword.put_new_lazy(:forward_refs, fn ->
        (plan.letrec_refs || [])
        |> Enum.map(&{&1, nil})
        |> Map.new()
      end)

    run_section(section, opts)
  end

  @spec run_section(Lower.section(), keyword()) :: {:ok, value()} | {:error, term()}
  def run_section(section, opts \\ []) do
    param_values = Keyword.get(opts, :params, [])
    fn_registry = Keyword.get(opts, :fn_registry, %{})
    plans = Keyword.get(opts, :plans, %{})
    plan_key = Keyword.get(opts, :plan_key, {:Main, "anon"})

    forward_refs = Keyword.get(opts, :forward_refs, %{})

    locals = List.duplicate(nil, section.locals)

    execute_loop(%{
      locals: locals,
      params: param_values,
      ip: 0,
      code: section.code,
      block_ips: section.block_ips,
      fn_table: Map.get(section, :fn_table, []),
      fn_registry: fn_registry,
      plans: plans,
      plan_key: plan_key,
      forward_refs: forward_refs
    })
  end

  @doc false
  @spec execute(frame()) :: {:ok, value()}
  def execute(frame), do: execute_loop(frame)

  defp execute_loop(%{ip: ip, code: code} = frame) when ip >= byte_size(code) do
    {:ok, fn_out_value(frame.locals)}
  end

  defp execute_loop(%{ip: ip, code: code} = frame) do
    <<opcode::8, dest::16, rest::binary>> = binary_part(code, ip, byte_size(code) - ip)

    case Opcodes.name(opcode) do
      :const_int ->
        <<value::32, tail::binary>> = rest
        step(frame, dest, value, rest, tail)

      :load_param ->
        <<index::16, tail::binary>> = rest
        value = Enum.at(frame.params, index)
        step(frame, dest, value, rest, tail)

      :load_local ->
        <<source::16, tail::binary>> = rest
        step(frame, dest, get_local(frame.locals, source), rest, tail)

      :const_immortal_string ->
        <<size::16, bin::binary-size(size), tail::binary>> = rest
        step(frame, dest, bin, rest, tail)

      :const_c_expr ->
        <<size::16, bin::binary-size(size), tail::binary>> = rest
        value = resolve_const_c_expr(bin)
        step(frame, dest, value, rest, tail)

      :const_static_list ->
        args_bin = rest
        <<kind::8, count::16, payload::binary>> = args_bin

        {values, tail} =
          case kind do
            0 ->
              <<ints_bin::binary-size(^count * 4), tail::binary>> = payload
              values = for <<v::32 <- ints_bin>>, do: v
              {values, tail}

            1 ->
              <<floats_bin::binary-size(^count * 8), tail::binary>> = payload
              values = for <<v::float-64 <- floats_bin>>, do: v
              {values, tail}

            2 ->
              <<pairs_bin::binary-size(^count * 8), tail::binary>> = payload
              pairs = for <<l::32, r::32 <- pairs_bin>>, do: {l, r}
              {pairs, tail}

            kind when kind in [3, 4] ->
              <<regs_bin::binary-size(^count * 2), tail::binary>> = payload
              values = for <<r::16 <- regs_bin>>, do: get_local(frame.locals, r)
              {values, tail}

            _ ->
              {[], payload}
          end

        step(frame, dest, values, args_bin, tail)

      :int_arith ->
        {value, tail} = eval_int_arith(rest, frame.locals)
        step(frame, dest, value, rest, tail)

      :boxed_binop ->
        {value, tail} = eval_boxed_binop(rest, frame.locals)
        step(frame, dest, value, rest, tail)

      :call_runtime ->
        {value, tail} = eval_runtime_call(rest, frame)
        step(frame, dest, value, rest, tail)

      :call_fn ->
        {value, tail} = eval_call_fn(rest, frame)
        step(frame, dest, value, rest, tail)

      :compare ->
        <<kind::8, left::16, right::16, tail::binary>> = rest
        lv = local_int(frame.locals, left)
        rv = local_int(frame.locals, right)
        step(frame, dest, if(compare_kind(kind, lv, rv), do: 1, else: 0), rest, tail)

      :phi ->
        {value, tail} = PhiShapes.eval_phi(rest, frame.locals, &compare_kind/3)
        step(frame, dest, value, rest, tail)

      :test_maybe_nothing ->
        <<reg::16, tail::binary>> = rest
        value = if get_local(frame.locals, reg) == nil, do: 1, else: 0
        step(frame, dest, value, rest, tail)

      :test_string_literal ->
        <<subject::16, size::16, bin::binary-size(size), tail::binary>> = rest
        subj = get_local(frame.locals, subject)
        value = if is_binary(subj) and subj == bin, do: 1, else: 0
        step(frame, dest, value, rest, tail)

      :test_list_empty ->
        <<reg::16, tail::binary>> = rest
        value = if list_empty?(get_local(frame.locals, reg)), do: 1, else: 0
        step(frame, dest, value, rest, tail)

      :test_ctor_tag ->
        <<subject::16, tag::16, tail::binary>> = rest
        value = if ctor_tag_matches?(get_local(frame.locals, subject), tag), do: 1, else: 0
        step(frame, dest, value, rest, tail)

      :test_bool ->
        <<subject::16, want_true::8, tail::binary>> = rest
        truthy = bool_truthy?(get_local(frame.locals, subject))
        value = if (want_true == 1) == truthy, do: 1, else: 0
        step(frame, dest, value, rest, tail)

      :bool_and ->
        <<left::16, right::16, tail::binary>> = rest
        value =
          if local_int(frame.locals, left) != 0 and local_int(frame.locals, right) != 0,
            do: 1,
            else: 0

        step(frame, dest, value, rest, tail)

      :switch_ctor_tag ->
        {value, tail} = eval_switch_ctor_tag(rest, frame.locals)
        step(frame, dest, value, rest, tail)

      :pebble_cmd ->
        {value, tail} = eval_pebble_cmd(rest, frame.locals)
        step(frame, dest, value, rest, tail)

      :render_cmd ->
        {value, tail} = eval_platform_op(rest, frame.locals, :render_cmd)
        step(frame, dest, value, rest, tail)

      :pebble_sub ->
        {value, tail} = eval_platform_op(rest, frame.locals, :pebble_sub)
        step(frame, dest, value, rest, tail)

      :tuple_proj ->
        <<which::8, base::16, tail::binary>> = rest
        tuple = get_local(frame.locals, base)

        value =
          case tuple do
            {:tuple2, a, b} -> if which == 1, do: b, else: a
            {a, b} when is_integer(a) and is_integer(b) -> if which == 1, do: b, else: a
            _ -> 0
          end

        step(frame, dest, value, rest, tail)

      :make_closure ->
        <<idx::16, _arity::16, cap_size::16, rest2::binary>> = rest
        <<caps_bin::binary-size(^cap_size), tail::binary>> = rest2
        caps = decode_reg_list(caps_bin) |> Enum.map(&get_local(frame.locals, &1))
        step(frame, dest, {:closure, idx, caps, frame.plan_key}, rest, tail)

      :call_closure ->
        <<callee::16, argc::16, rest2::binary>> = rest
        <<args_bin::binary-size(^argc * 2), tail::binary>> = rest2
        call_args = decode_reg_list(args_bin) |> Enum.map(&get_local(frame.locals, &1))
        closure = get_local(frame.locals, callee)
        value = invoke_closure(closure, call_args, frame)
        step(frame, dest, value, rest, tail)

      :list_cursor_map ->
        {values, tail} = eval_list_cursor_map(rest, frame)
        step(frame, dest, values, rest, tail)

      :forward_ref_set ->
        <<ref_size::16, rest2::binary>> = rest
        <<ref_bin::binary-size(^ref_size), value::16, tail::binary>> = rest2
        ref = ref_bin
        val = get_local(frame.locals, value)
        forward_refs = Map.put(frame.forward_refs, ref, val)

        execute_loop(%{
          frame
          | forward_refs: forward_refs,
            ip: advance_ip(ip, rest, tail)
        })

      :forward_ref_load ->
        {value, tail} = eval_forward_ref_load(rest, frame)
        step(frame, dest, value, rest, tail)

      :forward_ref_capture ->
        {value, tail} = eval_forward_ref_capture(rest)
        step(frame, dest, value, rest, tail)

      :forward_ref_load_captured ->
        {value, tail} = eval_forward_ref_load(rest, frame)
        step(frame, dest, value, rest, tail)

      :record_update ->
        <<base::16, value::16, field_index::16, tail::binary>> = rest
        base_val = get_local(frame.locals, base)
        new_val = get_local(frame.locals, value)
        updated = record_set_field(base_val, field_index, new_val)
        step(frame, dest, updated, rest, tail)

      :record_get ->
        <<base::16, field_index::16, tail::binary>> = rest
        base_val = get_local(frame.locals, base)
        value = record_field_at(base_val, field_index)
        step(frame, dest, value, rest, tail)

      :publish ->
        case rest do
          <<source::16, tail::binary>> ->
            value = get_local(frame.locals, source)
            locals = set_local(frame.locals, dest_slot(dest), value)
            execute_loop(%{frame | locals: locals, ip: advance_ip(ip, rest, tail)})

          _ ->
            execute_loop(%{frame | ip: ip + 3})
        end

      :catch_begin ->
        execute_loop(%{frame | ip: ip + 3})

      :catch_end ->
        execute_loop(%{frame | ip: ip + 3})

      :release ->
        <<_reg::16, tail::binary>> = rest
        execute_loop(%{frame | ip: advance_ip(ip, rest, tail)})

      :ret ->
        {:ok, get_local(frame.locals, dest)}

      :br ->
        <<target::16, _::binary>> = rest
        jump_to_block(frame, target)

      :br_if ->
        <<then_id::16, else_id::16, _::binary>> = rest
        target = if local_int(frame.locals, dest) != 0, do: then_id, else: else_id
        jump_to_block(frame, target)

      :switch_tag ->
        <<default_id::16, arms_size::16, rest2::binary>> = rest
        <<arms_bin::binary-size(^arms_size), _::binary>> = rest2
        tag = union_tag(local_int(frame.locals, dest))

        target =
          arms_bin
          |> parse_switch_arms()
          |> Enum.find_value(fn {arm_tag, block_id} -> if arm_tag == tag, do: block_id end) ||
            default_id

        jump_to_block(frame, target)

      _ ->
        execute_loop(%{frame | ip: ip + 3})
    end
  end

  defp jump_to_block(frame, block_id) do
    case Map.get(frame.block_ips, block_id) do
      ip when is_integer(ip) -> execute_loop(%{frame | ip: ip})
      _ -> {:ok, fn_out_value(frame.locals)}
    end
  end

  defp step(frame, dest, value, rest, tail) do
    locals = set_local(frame.locals, dest_slot(dest), value)
    execute_loop(%{frame | locals: locals, ip: advance_ip(frame.ip, rest, tail)})
  end

  defp advance_ip(ip, rest, tail), do: ip + 3 + byte_size(rest) - byte_size(tail)

  defp eval_int_arith(<<kind::8, lhs::16, rest::binary>>, locals) do
    left = local_int(locals, lhs)

    case kind do
      0 ->
        <<value::32, tail::binary>> = rest
        {left + value, tail}

      1 ->
        <<value::32, tail::binary>> = rest
        {left - value, tail}

      2 ->
        <<rhs::16, tail::binary>> = rest
        {left + local_int(locals, rhs), tail}

      3 ->
        <<rhs::16, tail::binary>> = rest
        {left * local_int(locals, rhs), tail}

      4 ->
        <<rhs::16, tail::binary>> = rest
        {left - local_int(locals, rhs), tail}

      5 ->
        <<rhs::16, tail::binary>> = rest
        rhs_n = local_int(locals, rhs)
        {if(rhs_n == 0, do: 0, else: div(left, rhs_n)), tail}

      6 ->
        <<rhs::16, tail::binary>> = rest
        rhs_n = local_int(locals, rhs)
        {min(left, rhs_n), tail}

      7 ->
        <<rhs::16, tail::binary>> = rest
        rhs_n = local_int(locals, rhs)
        {max(left, rhs_n), tail}

      8 ->
        <<rhs::16, tail::binary>> = rest
        rhs_n = local_int(locals, rhs)
        {elm_mod_by(left, rhs_n), tail}

      9 ->
        <<rhs::16, tail::binary>> = rest
        rhs_n = local_int(locals, rhs)
        {if(rhs_n == 0, do: 0, else: rem(left, rhs_n)), tail}

      _ ->
        {left, rest}
    end
  end

  defp elm_mod_by(base, _value) when base == 0, do: 0

  defp elm_mod_by(base, value) do
    rem_n = rem(value, base)

    if rem_n < 0 do
      rem_n + if(base < 0, do: -base, else: base)
    else
      rem_n
    end
  end

  defp eval_boxed_binop(<<op_n::8, left::16, right::16, tail::binary>>, locals) do
    lv = get_local(locals, left)
    rv = get_local(locals, right)
    {boxed_binop_value(op_n, lv, rv), tail}
  end

  defp boxed_binop_value(0, a, b), do: boxed_add(a, b)
  defp boxed_binop_value(1, a, b), do: boxed_sub(a, b)
  defp boxed_binop_value(2, a, b), do: boxed_mul(a, b)
  defp boxed_binop_value(3, a, b), do: boxed_fdiv(a, b)
  defp boxed_binop_value(_, _a, _b), do: 0

  defp boxed_add(a, b),
    do:
      if(floatish?(a) or floatish?(b), do: boxed_to_float(a) + boxed_to_float(b),
        else: to_int(a) + to_int(b)
      )

  defp boxed_sub(a, b),
    do:
      if(floatish?(a) or floatish?(b), do: boxed_to_float(a) - boxed_to_float(b),
        else: to_int(a) - to_int(b)
      )

  defp boxed_mul(a, b),
    do:
      if(floatish?(a) or floatish?(b), do: boxed_to_float(a) * boxed_to_float(b),
        else: to_int(a) * to_int(b)
      )

  defp boxed_fdiv(a, b) do
    denom = boxed_to_float(b)
    if denom == 0.0, do: 0.0, else: boxed_to_float(a) / denom
  end

  defp floatish?(v) when is_float(v), do: true
  defp floatish?(_), do: false

  defp boxed_to_float(v) when is_float(v), do: v
  defp boxed_to_float(v) when is_integer(v), do: v * 1.0
  defp boxed_to_float(_), do: 0.0

  defp eval_runtime_call(<<id_idx::16, has_lit::8, rest::binary>>, frame) do
    {literal, rest1} =
      case has_lit do
        1 ->
          <<lit::signed-32, r::binary>> = rest
          {lit, r}

        2 ->
          <<lit::float-32, r::binary>> = rest
          {lit, r}

        _ ->
          {nil, rest}
      end

    <<args_size::16, args_bin::binary-size(args_size), tail::binary>> = rest1
    arg_regs = for <<reg::16 <- args_bin>>, do: reg
    id = Enum.at(RuntimeBuiltins.ids(), id_idx, :new_int)

    value =
      case id do
        op
        when op in [
               :list_map,
               :list_all,
               :list_any,
               :list_filter,
               :list_indexed_map,
               :list_filter_map,
               :list_foldl,
               :list_concat_map,
               :maybe_map,
               :maybe_map2,
               :list_map2,
               :list_map3,
               :list_map4,
               :list_map5,
               :task_map,
               :task_map2,
               :task_and_then,
               :task_perform,
               :cmd_map,
               :sub_map,
               :result_and_then,
               :result_map,
               :result_map_error
             ] ->
          apply_hof_builtin(id, arg_regs, frame)

        _ ->
          apply_builtin(id, arg_regs, frame.locals, literal)
      end

    {value, tail}
  end

  defp eval_call_fn(<<fn_idx::16, args_size::16, rest::binary>>, frame) do
    <<args_bin::binary-size(^args_size), tail::binary>> = rest
    arg_regs = for <<reg::16 <- args_bin>>, do: reg
    args = Enum.map(arg_regs, &get_local(frame.locals, &1))
    target = Enum.at(frame.fn_table, fn_idx)

    value =
      case target do
        {mod, name} ->
          case Map.get(frame.plans, {mod, name}) do
            %FunctionPlan{} = plan ->
              case run_function(plan, params: args, plans: frame.plans) do
                {:ok, val} -> val
                _ -> nil
              end

            %{code: _} = section ->
              case run_section(section,
                     Keyword.merge([params: args], plans: frame.plans, plan_key: {mod, name})
                   ) do
                {:ok, val} -> val
                _ -> nil
              end

            _ ->
              Map.get(frame.fn_registry, {mod, name}, fn _args -> 0 end).(args)
          end

        _ ->
          0
      end

    {value, tail}
  end

  defp eval_pebble_cmd(<<id_idx::16, kind_hash::16, params_size::16, rest::binary>>, locals) do
    <<params_bin::binary-size(^params_size), tail::binary>> = rest
    builtin = Enum.at(RuntimeBuiltins.ids(), id_idx, :cmd0)
    params = decode_param_values(params_bin, locals)
    {{:pebble_cmd, builtin, kind_hash, params}, tail}
  end

  defp eval_platform_op(<<kind_hash::16, params_size::16, rest::binary>>, locals, tag) do
    <<params_bin::binary-size(^params_size), tail::binary>> = rest
    params = decode_param_values(params_bin, locals)
    {{tag, kind_hash, params}, tail}
  end

  defp decode_param_values(params_bin, locals) do
    for <<reg::16 <- params_bin>>, do: get_local(locals, reg)
  end

  defp eval_switch_ctor_tag(<<subject::16, default::16, arms_size::16, rest::binary>>, locals) do
    <<arms_bin::binary-size(^arms_size), tail::binary>> = rest
    tag = union_tag(local_int(locals, subject))

    chosen =
      arms_bin
      |> parse_switch_arms()
      |> Enum.find_value(fn {arm_tag, reg} -> if arm_tag == tag, do: reg end) ||
        if default != 0xFFFF, do: default, else: nil

    value = if is_integer(chosen), do: get_local(locals, chosen), else: 0
    {value, tail}
  end

  defp parse_switch_arms(bin) do
    parse_switch_arms(bin, [])
  end

  defp parse_switch_arms(<<tag::16, reg::16, rest::binary>>, acc),
    do: parse_switch_arms(rest, [{tag, reg} | acc])

  defp parse_switch_arms(_, acc), do: Enum.reverse(acc)

  defp union_tag({:union, tag, _}), do: to_int(tag)
  defp union_tag(v), do: to_int(v)

  defp apply_builtin(:new_int, _args, _locals, literal) when is_integer(literal), do: literal
  defp apply_builtin(:new_int, _args, _locals, _), do: 0
  defp apply_builtin(:new_float, _args, _locals, literal) when is_float(literal), do: literal
  defp apply_builtin(:new_float, _args, _locals, _), do: 0.0
  defp apply_builtin(:maybe_nothing, _args, _locals, _), do: nil
  defp apply_builtin(:maybe_just_own, [payload | _], locals, _), do: {:just, get_local(locals, payload)}

  defp apply_builtin(:maybe_just_payload, [subj | _], locals, _) do
    case get_local(locals, subj) do
      {:just, payload} -> payload
      nil -> nil
      other -> other
    end
  end

  defp apply_builtin(:tuple2, [a, b | _], locals, _), do: {:tuple2, get_local(locals, a), get_local(locals, b)}

  defp apply_builtin(:tuple2_ints, [a, b | _], locals, _),
    do: {:tuple2, local_int(locals, a), local_int(locals, b)}
  defp apply_builtin(:record_new, args, locals, _), do: {:record, Enum.map(args, &get_local(locals, &1))}

  defp apply_builtin(:record_new_values_ints, args, locals, _),
    do: {:record, Enum.map(args, &get_local(locals, &1))}

  defp apply_builtin(:retain, [src | _], locals, _), do: get_local(locals, src)
  defp apply_builtin(:union_payload, [subj | _], locals, _) do
    case get_local(locals, subj) do
      {:union, _tag, payload} -> payload
      other -> other
    end
  end

  defp apply_builtin(:cmd0, _args, _locals, _), do: 0
  defp apply_builtin(:cmd_batch, [list_reg | _], locals, _), do: get_local(locals, list_reg) || :cmd_batch

  defp apply_builtin(:sub_batch, [list_reg | _], locals, _),
    do: get_local(locals, list_reg) || []
  defp apply_builtin(:list_repeat, [n, value | _], locals, _) do
    count = max(local_int(locals, n), 0)
    val = get_local(locals, value)
    List.duplicate(val, count)
  end

  defp apply_builtin(:list_nth_int_default, [list, idx, default | _], locals, _) do
    list_val = local_list(locals, list)
    index = local_int(locals, idx)
    default_val = local_int(locals, default)

    if index >= 0 and index < length(list_val) do
      Enum.at(list_val, index) |> to_int()
    else
      default_val
    end
  end

  defp apply_builtin(:list_nth_maybe, [list, idx | _], locals, _) do
    list_val = local_list(locals, list)
    index = local_int(locals, idx)

    if index >= 0 and index < length(list_val) do
      {:just, Enum.at(list_val, index)}
    else
      nil
    end
  end

  defp apply_builtin(:maybe_with_default, [default, maybe | _], locals, _) do
    case get_local(locals, maybe) do
      nil -> get_local(locals, default)
      {:just, val} -> val
      other -> other
    end
  end

  defp apply_builtin(:result_with_default, [default, result | _], locals, _) do
    case get_local(locals, result) do
      {:ok, value} -> value
      _ -> get_local(locals, default)
    end
  end

  defp apply_builtin(:task_succeed, [value | _], locals, _), do: {:task, :succeed, get_local(locals, value)}
  defp apply_builtin(:task_fail, [value | _], locals, _), do: {:task, :fail, get_local(locals, value)}

  defp apply_builtin(:basics_min, [a, b | _], locals, _), do: min(local_int(locals, a), local_int(locals, b))
  defp apply_builtin(:basics_max, [a, b | _], locals, _), do: max(local_int(locals, a), local_int(locals, b))

  defp apply_builtin(:basics_mod_by, [base, value | _], locals, _) do
    base_n = local_int(locals, base)
    value_n = local_int(locals, value)
    if base_n == 0, do: 0, else: rem(value_n, base_n)
  end

  defp apply_builtin(:basics_remainder_by, [base, value | _], locals, _) do
    base_n = local_int(locals, base)
    value_n = local_int(locals, value)
    if base_n == 0, do: 0, else: rem(value_n, base_n)
  end

  defp apply_builtin(:basics_not, [value | _], locals, _) do
    if truthy?(get_local(locals, value)), do: 0, else: 1
  end

  defp apply_builtin(:string_from_int, [value | _], locals, _) do
    local_int(locals, value) |> Integer.to_string()
  end

  defp apply_builtin(:string_to_int, [value | _], locals, _) do
    case Integer.parse(to_string(get_local(locals, value) || "")) do
      {n, ""} -> {:just, n}
      _ -> nil
    end
  end

  defp apply_builtin(:string_to_float, [value | _], locals, _) do
    case Float.parse(to_string(get_local(locals, value) || "")) do
      {n, ""} -> {:just, n}
      _ -> nil
    end
  end

  defp apply_builtin(:string_left, [n, value | _], locals, _) do
    count = local_int(locals, n)
    str = to_string(get_local(locals, value) || "")

    if count <= 0 do
      ""
    else
      String.slice(str, 0, count)
    end
  end

  defp apply_builtin(:basics_floor, [value | _], locals, _) do
    case get_local(locals, value) do
      n when is_integer(n) ->
        n

      n when is_float(n) ->
        trunc(n)

      {:just, n} when is_integer(n) ->
        n

      {:just, n} when is_float(n) ->
        trunc(n)

      other ->
        case Float.parse(to_string(other || "")) do
          {f, ""} -> trunc(f)
          _ -> 0
        end
    end
  end

  defp apply_builtin(:list_reverse, [list | _], locals, _) do
    local_list(locals, list) |> Enum.reverse()
  end

  defp apply_builtin(:render_op, args, locals, _), do: {:render_op, Enum.map(args, &get_local(locals, &1))}
  defp apply_builtin(:sub_entry, args, locals, _), do: {:sub, Enum.map(args, &get_local(locals, &1))}
  defp apply_builtin(:list_nil, _args, _locals, _), do: []
  defp apply_builtin(:list_cons, [head, tail | _], locals, _),
    do: [get_local(locals, head) | local_list(locals, tail)]

  defp apply_builtin(:list_append, [left, right | _], locals, _) do
    local_list(locals, left) ++ local_list(locals, right)
  end

  defp apply_builtin(:list_slice_int, [drop, take, list | _], locals, _) do
    list_val = local_list(locals, list)
    drop_n = max(local_int(locals, drop), 0)
    take_n = max(local_int(locals, take), 0)
    list_val |> Enum.drop(drop_n) |> Enum.take(take_n)
  end

  defp apply_builtin(:list_take, [n, list | _], locals, _) do
    list_val = local_list(locals, list)
    Enum.take(list_val, max(local_int(locals, n), 0))
  end

  defp apply_builtin(:list_drop, [n, list | _], locals, _) do
    list_val = local_list(locals, list)
    Enum.drop(list_val, max(local_int(locals, n), 0))
  end

  defp apply_builtin(:list_filter_record_field, [list, field | _], locals, _) do
    idx = local_int(locals, field)

    local_list(locals, list)
    |> Enum.filter(&record_field_truthy?(&1, idx))
  end

  defp apply_builtin(:list_filter_record_and, [list, field_a, field_b | _], locals, _) do
    a = local_int(locals, field_a)
    b = local_int(locals, field_b)

    local_list(locals, list)
    |> Enum.filter(fn item -> record_field_truthy?(item, a) and record_field_truthy?(item, b) end)
  end

  defp apply_builtin(:list_map_record_field, [list, field | _], locals, _) do
    idx = local_int(locals, field)

    local_list(locals, list)
    |> Enum.map(&record_field_at(&1, idx))
  end

  defp apply_builtin(:list_length, [list | _], locals, _) do
    local_list(locals, list) |> length()
  end

  defp apply_builtin(:list_is_empty, [list | _], locals, _) do
    if list_empty?(get_local(locals, list)), do: 1, else: 0
  end

  defp apply_builtin(:list_head, [list | _], locals, _) do
    case local_list(locals, list) do
      [h | _] -> {:just, h}
      _ -> nil
    end
  end

  defp apply_builtin(:list_tail, [list | _], locals, _) do
    case local_list(locals, list) do
      [_ | t] -> t
      _ -> []
    end
  end

  defp apply_builtin(:int_list_head_int, [list | _], locals, _) do
    case local_list(locals, list) do
      [h | _] -> to_int(h)
      _ -> 0
    end
  end

  defp apply_builtin(:int_list_head_boxed, [list | _], locals, _) do
    case local_list(locals, list) do
      [h | _] -> to_int(h)
      _ -> 0
    end
  end

  defp apply_builtin(:int_list_tail, [list | _], locals, _) do
    case local_list(locals, list) do
      [_ | t] -> t
      _ -> []
    end
  end

  defp apply_builtin(:list_concat, [lists | _], locals, _) do
    local_list(locals, lists)
    |> Enum.flat_map(fn
      items when is_list(items) -> items
      _ -> []
    end)
  end

  defp apply_builtin(:list_range, [lo, hi | _], locals, _) do
    lo_n = local_int(locals, lo)
    hi_n = local_int(locals, hi)
    if lo_n <= hi_n, do: Enum.to_list(lo_n..hi_n), else: []
  end

  defp apply_builtin(:cmd_backlight_from_maybe, [maybe_reg | _], locals, _) do
    mode = backlight_mode_from_maybe(get_local(locals, maybe_reg))
    {:pebble_cmd, :cmd1, 6, [mode]}
  end

  defp apply_builtin(_id, _args, _locals, _), do: nil

  defp backlight_mode_from_maybe(nil), do: 0
  defp backlight_mode_from_maybe({:just, true}), do: 2
  defp backlight_mode_from_maybe({:just, false}), do: 1
  defp backlight_mode_from_maybe({:just, 1}), do: 2
  defp backlight_mode_from_maybe({:just, 0}), do: 1
  defp backlight_mode_from_maybe({:just, v}) when v != nil and v != 0, do: 2
  defp backlight_mode_from_maybe(_), do: 0

  defp apply_hof_builtin(:list_map, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)
    Enum.map(list_val, &invoke_closure(fun_val, [&1], frame))
  end

  defp apply_hof_builtin(:list_all, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)

    Enum.all?(list_val, fn item ->
      invoke_closure(fun_val, [item], frame) |> truthy?()
    end)
  end

  defp apply_hof_builtin(:list_any, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)

    Enum.any?(list_val, fn item ->
      invoke_closure(fun_val, [item], frame) |> truthy?()
    end)
  end

  defp apply_hof_builtin(:maybe_map, [fun, maybe | _], frame) do
    fun_val = get_local(frame.locals, fun)

    case get_local(frame.locals, maybe) do
      {:just, payload} -> {:just, invoke_closure(fun_val, [payload], frame)}
      _ -> nil
    end
  end

  defp apply_hof_builtin(:list_concat_map, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)

    list_val
    |> Enum.flat_map(fn item ->
      case invoke_closure(fun_val, [item], frame) do
        items when is_list(items) -> items
        _ -> []
      end
    end)
  end

  defp apply_hof_builtin(:list_filter, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)

    Enum.filter(list_val, fn item ->
      invoke_closure(fun_val, [item], frame) |> truthy?()
    end)
  end

  defp apply_hof_builtin(:list_indexed_map, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)

    list_val
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      invoke_closure(fun_val, [index, item], frame)
    end)
  end

  defp apply_hof_builtin(:list_filter_map, [fun, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)

    Enum.flat_map(list_val, fn item ->
      case invoke_closure(fun_val, [item], frame) do
        nil -> []
        {:just, val} -> [val]
        other -> [other]
      end
    end)
  end

  defp apply_hof_builtin(:list_foldl, [fun, acc, list | _], frame) do
    locals = frame.locals
    list_val = local_list(locals, list)
    fun_val = get_local(locals, fun)
    start_acc = get_local(locals, acc)

    Enum.reduce(list_val, start_acc, fn item, acc ->
      invoke_closure(fun_val, [item, acc], frame)
    end)
  end

  defp apply_hof_builtin(:list_map2, [fun, a, b | _], frame) do
    list_a = local_list(frame.locals, a)
    list_b = local_list(frame.locals, b)
    fun_val = get_local(frame.locals, fun)

    Enum.zip(list_a, list_b)
    |> Enum.map(fn {x, y} -> invoke_closure(fun_val, [x, y], frame) end)
  end

  defp apply_hof_builtin(:list_map3, [fun, a, b, c | _], frame) do
    list_a = local_list(frame.locals, a)
    list_b = local_list(frame.locals, b)
    list_c = local_list(frame.locals, c)
    fun_val = get_local(frame.locals, fun)

    Enum.zip([list_a, list_b, list_c])
    |> Enum.map(fn [x, y, z] -> invoke_closure(fun_val, [x, y, z], frame) end)
  end

  defp apply_hof_builtin(:list_map4, [fun, a, b, c, d | _], frame) do
    list_a = local_list(frame.locals, a)
    list_b = local_list(frame.locals, b)
    list_c = local_list(frame.locals, c)
    list_d = local_list(frame.locals, d)
    fun_val = get_local(frame.locals, fun)

    Enum.zip([list_a, list_b, list_c, list_d])
    |> Enum.map(fn [w, x, y, z] -> invoke_closure(fun_val, [w, x, y, z], frame) end)
  end

  defp apply_hof_builtin(:list_map5, [fun, a, b, c, d, e | _], frame) do
    list_a = local_list(frame.locals, a)
    list_b = local_list(frame.locals, b)
    list_c = local_list(frame.locals, c)
    list_d = local_list(frame.locals, d)
    list_e = local_list(frame.locals, e)
    fun_val = get_local(frame.locals, fun)

    Enum.zip([list_a, list_b, list_c, list_d, list_e])
    |> Enum.map(fn [v, w, x, y, z] -> invoke_closure(fun_val, [v, w, x, y, z], frame) end)
  end

  defp apply_hof_builtin(:maybe_map2, [fun, a, b | _], frame) do
    fun_val = get_local(frame.locals, fun)
    va = get_local(frame.locals, a)
    vb = get_local(frame.locals, b)

    case {va, vb} do
      {{:just, xa}, {:just, xb}} -> {:just, invoke_closure(fun_val, [xa, xb], frame)}
      _ -> nil
    end
  end

  defp apply_hof_builtin(:task_map, [fun, task | _], frame),
    do: {:task, :map, {get_local(frame.locals, fun), get_local(frame.locals, task)}}

  defp apply_hof_builtin(:task_map2, [fun, a, b | _], frame),
    do: {:task, :map2, {get_local(frame.locals, fun), get_local(frame.locals, a), get_local(frame.locals, b)}}

  defp apply_hof_builtin(:task_and_then, [fun, task | _], frame),
    do: {:task, :and_then, {get_local(frame.locals, fun), get_local(frame.locals, task)}}

  defp apply_hof_builtin(:task_perform, [to_msg, task | _], frame),
    do: {:task, :perform, {get_local(frame.locals, to_msg), get_local(frame.locals, task)}}

  defp apply_hof_builtin(:cmd_map, [fun, cmd | _], frame),
    do: {:cmd, :map, {get_local(frame.locals, fun), get_local(frame.locals, cmd)}}

  defp apply_hof_builtin(:sub_map, [fun, sub | _], frame),
    do: {:sub, :map, {get_local(frame.locals, fun), get_local(frame.locals, sub)}}

  defp apply_hof_builtin(:result_map, [fun, result | _], frame) do
    case get_local(frame.locals, result) do
      {:ok, value} -> {:ok, invoke_closure(get_local(frame.locals, fun), [value], frame)}
      other -> other
    end
  end

  defp apply_hof_builtin(:result_map_error, [fun, result | _], frame) do
    case get_local(frame.locals, result) do
      {:err, value} -> {:err, invoke_closure(get_local(frame.locals, fun), [value], frame)}
      other -> other
    end
  end

  defp apply_hof_builtin(:result_and_then, [fun, result | _], frame) do
    case get_local(frame.locals, result) do
      {:ok, value} ->
        case invoke_closure(get_local(frame.locals, fun), [value], frame) do
          {:ok, _} = ok -> ok
          {:err, _} = err -> err
          other -> {:ok, other}
        end

      other ->
        other
    end
  end

  defp compare_kind(0, l, r), do: l == r
  defp compare_kind(1, l, r), do: l != r
  defp compare_kind(2, l, r), do: l > r
  defp compare_kind(3, l, r), do: l >= r
  defp compare_kind(4, l, r), do: l < r
  defp compare_kind(5, l, r), do: l <= r
  defp compare_kind(_, l, r), do: l == r

  defp local_int(locals, idx), do: get_local(locals, idx) |> to_int()

  defp local_list(locals, idx) do
    case get_local(locals, idx) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp list_empty?(list) when list == [], do: true
  defp list_empty?(_), do: false

  defp ctor_tag_matches?({:union, tag, _}, wanted), do: to_int(tag) == to_int(wanted)
  defp ctor_tag_matches?(subject, wanted), do: to_int(subject) == to_int(wanted)

  defp bool_truthy?(true), do: true
  defp bool_truthy?(false), do: false
  defp bool_truthy?(n) when is_integer(n), do: n != 0
  defp bool_truthy?({:just, v}), do: bool_truthy?(v)
  defp bool_truthy?(_), do: false

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: trunc(n)
  defp to_int(true), do: 1
  defp to_int(false), do: 0
  defp to_int({:just, v}), do: to_int(v)
  defp to_int({:record, fields}), do: Enum.at(fields, 0, 0) |> to_int()
  defp to_int(_), do: 0

  defp resolve_const_c_expr(expr) when is_binary(expr) do
    case Elmc.Backend.CCodegen.Emit.resolve_c_int_expr(expr) do
      {:ok, n} -> n
      :error -> 0
    end
  end

  defp record_field_at({:record, fields}, index) when is_list(fields), do: Enum.at(fields, index)
  defp record_field_at(value, _index), do: value

  defp record_field_truthy?(value, index) do
    case record_field_at(value, index) do
      n when is_integer(n) -> n != 0
      true -> true
      false -> false
      nil -> false
      _ -> true
    end
  end

  defp record_set_field({:record, fields}, index, value) when is_list(fields) do
    {:record, List.replace_at(pad_record_fields(fields, index + 1), index, value)}
  end

  defp record_set_field(_other, index, value), do: {:record, List.replace_at(List.duplicate(nil, index + 1), index, value)}

  defp pad_record_fields(fields, min_len) when length(fields) >= min_len, do: fields
  defp pad_record_fields(fields, min_len), do: fields ++ List.duplicate(nil, min_len - length(fields))

  defp fn_out_value(locals), do: get_local(locals, 0xFFFF) || List.last(locals)

  defp dest_slot(0xFFFF), do: 0xFFFF
  defp dest_slot(0xFFFE), do: 0xFFFE
  defp dest_slot(0xFFFD), do: 0xFFFD
  defp dest_slot(idx), do: idx

  defp get_local(locals, 0xFFFF), do: List.last(locals)
  defp get_local(locals, idx), do: Enum.at(locals, idx)

  defp set_local(locals, 0xFFFF, val) do
    List.replace_at(locals, length(locals) - 1, val)
  end

  defp set_local(locals, idx, val), do: List.replace_at(locals, idx, val)

  defp decode_reg_list(bin) do
    for <<reg::16 <- bin>>, do: reg
  end

  defp plans_index(%FunctionPlan{} = plan, acc \\ %{}) do
    key = {plan.module, plan.name}
    acc1 = Map.put(acc, key, plan)

    Enum.reduce(plan.lambdas || [], acc1, fn lam, a ->
      plans_index(lam, a)
    end)
  end

  defp invoke_closure({:closure, idx, caps, parent_key}, call_args, frame) when is_list(call_args) do
    case Map.fetch!(frame.plans, parent_key) do
      %FunctionPlan{lambdas: lambdas} = _parent when is_list(lambdas) and lambdas != [] ->
        case Enum.at(lambdas, idx) do
          %FunctionPlan{} = lambda ->
            case run_function(lambda,
                   params: caps ++ call_args,
                   plans: frame.plans,
                   plan_key: {lambda.module, lambda.name},
                   forward_refs: frame.forward_refs
                 ) do
              {:ok, val} -> val
              _ -> 0
            end

          _ ->
            0
        end

      %{lambdas: lambda_sections} = _parent when is_list(lambda_sections) and lambda_sections != [] ->
        case Enum.at(lambda_sections, idx) do
          %{code: _} = lambda_section ->
            case run_section(
                   lambda_section,
                   params: caps ++ call_args,
                   plans: frame.plans,
                   plan_key: parent_key,
                   forward_refs: frame.forward_refs
                 ) do
              {:ok, val} -> val
              _ -> 0
            end

          _ ->
            0
        end

      %FunctionPlan{} = parent ->
        case Enum.at(parent.lambdas || [], idx) do
          %FunctionPlan{} = lambda ->
            case run_function(lambda,
                   params: caps ++ call_args,
                   plans: frame.plans,
                   plan_key: {lambda.module, lambda.name},
                   forward_refs: frame.forward_refs
                 ) do
              {:ok, val} -> val
              _ -> 0
            end

          _ ->
            0
        end

      _ ->
        0
    end
  end

  defp invoke_closure(_, _, _), do: 0

  defp eval_list_cursor_map(<<flags::8, lambda_idx::16, rest::binary>>, frame) do
    {start_val, rest1} = cursor_map_bound(flags, 0, rest, frame.locals)
    {end_val, rest2} = cursor_map_bound(flags, 1, rest1, frame.locals)
    closure = {:closure, lambda_idx, [], frame.plan_key}

    values =
      for idx <- start_val..end_val,
          reduce: [] do
        acc ->
          item = invoke_closure(closure, [idx], frame)
          acc ++ [item]
      end

    {values, rest2}
  end

  defp cursor_map_bound(flags, bit, <<payload::binary>>, locals) do
    if Bitwise.band(flags, Bitwise.bsl(1, bit)) != 0 do
      <<value::32, tail::binary>> = payload
      {value, tail}
    else
      <<reg::16, tail::binary>> = payload
      {local_int(locals, reg), tail}
    end
  end

  defp eval_forward_ref_load(<<ref_size::16, rest::binary>>, frame) do
    <<ref_bin::binary-size(^ref_size), tail::binary>> = rest
    {Map.get(frame.forward_refs, ref_bin), tail}
  end

  defp eval_forward_ref_capture(<<ref_size::16, rest::binary>>) do
    <<ref_bin::binary-size(^ref_size), tail::binary>> = rest
    {{:forward_ref, ref_bin}, tail}
  end

  defp truthy?(v) when v in [false, 0, nil], do: false
  defp truthy?({:just, inner}), do: truthy?(inner)
  defp truthy?(_), do: true
end
