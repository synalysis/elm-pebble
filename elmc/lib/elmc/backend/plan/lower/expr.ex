defmodule Elmc.Backend.Plan.Lower.Expr do
  @moduledoc """
  Lower Elm IR expressions to verified `%FunctionPlan{}` fragments.
  """

  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.{FunctionEmit, Host, TypeParsing}
  alias Elmc.Backend.CCodegen.Native.{FunctionCall, TypedReturn}
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.{Arith, Call, Case, Cmd, Compare, Constructor, If, IntCall, Lambda, List, Port, Record, SpecialValues, StdlibCall, Tuple, UnionCtor}
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types

  @literal_ops [:int_literal, :c_int_expr, :bool_literal, :string_literal, :char_literal, :cmd_none, :sub_none, :float_literal]

  @qualified_unary %{
    "Basics.abs" => :basics_abs,
    "Basics.negate" => :basics_negate,
    "Basics.round" => :basics_round,
    "Basics.ceiling" => :basics_ceiling,
    "Basics.truncate" => :basics_truncate,
    "Basics.toFloat" => :basics_to_float,
    "Basics.not" => :basics_not,
    "Basics.floor" => :basics_floor,
    "Bitwise.complement" => :bitwise_complement,
    "String.fromInt" => :string_from_int_value,
    "String.toInt" => :string_to_int,
    "String.toFloat" => :string_to_float,
    "String.isEmpty" => :string_is_empty,
    "String.reverse" => :string_reverse,
    "String.trim" => :string_trim,
    "String.toUpper" => :string_to_upper,
    "String.toLower" => :string_to_lower,
    "String.length" => :string_length_val,
    "String.words" => :string_words,
    "String.lines" => :string_lines,
    "Char.toCode" => :char_to_code,
    "Char.fromCode" => :new_char,
    "List.reverse" => :list_reverse,
    "List.isEmpty" => :list_is_empty,
    "List.length" => :list_length,
    "List.head" => :list_head,
    "List.tail" => :list_tail,
    "List.sum" => :list_sum,
    "List.product" => :list_product,
    "List.maximum" => :list_maximum,
    "List.minimum" => :list_minimum,
    "List.concat" => :list_concat,
    "List.sort" => :list_sort,
    "Debug.toString" => :debug_to_string
  }

  @qualified_binary %{
    "Basics.compare" => :basics_compare,
    "Basics.xor" => :basics_xor,
    "Bitwise.and" => :bitwise_and,
    "Bitwise.or" => :bitwise_or,
    "Bitwise.xor" => :bitwise_xor,
    "Bitwise.shiftLeftBy" => :bitwise_shift_left_by,
    "Bitwise.shiftRightBy" => :bitwise_shift_right_by,
    "Bitwise.shiftRightZfBy" => :bitwise_shift_right_zf_by,
    "String.left" => :string_left,
    "String.right" => :string_right,
    "String.contains" => :string_contains,
    "String.cons" => :string_cons,
    "String.slice" => :string_slice,
    "String.split" => :string_split,
    "String.dropLeft" => :string_drop_left,
    "String.dropRight" => :string_drop_right,
    "String.trimLeft" => :string_trim_left,
    "String.trimRight" => :string_trim_right,
    "String.repeat" => :string_repeat,
    "List.member" => :list_member,
    "List.partition" => :list_partition,
    "List.sortBy" => :list_sort_by,
    "List.sortWith" => :list_sort_with,
    "Dict.insert" => :dict_insert,
    "Dict.remove" => :dict_remove,
    "Dict.member" => :dict_member,
    "Set.insert" => :set_insert,
    "Set.remove" => :set_remove,
    "Set.member" => :set_member,
    "Result.withDefault" => :result_with_default
  }

  @hof_closure_last_arg ~w(
    list_map list_all list_any list_filter list_indexed_map list_filter_map
    list_foldl list_concat_map maybe_map
    result_and_then result_map result_map_error maybe_and_then maybe_map2
    task_map task_map2 task_and_then task_perform
    cmd_map sub_map
    list_map2 list_map3 list_map4 list_map5 list_find_first dict_map set_map string_map array_map
    tuple_map_first tuple_map_second tuple_map_both
    json_decode_map json_decode_map2 json_decode_map3 json_decode_map4 json_decode_map5
    json_decode_map6 json_decode_map7 json_decode_and_then json_decode_lazy
    json_encode_list json_encode_array json_encode_set json_encode_dict
  )a

  @qualified_ternary %{
    "Basics.clamp" => :basics_clamp,
    "String.replace" => :string_replace,
    "String.pad" => :string_pad,
    "String.padLeft" => :string_pad_left,
    "String.padRight" => :string_pad_right
  }

  @spec compile(Types.ir_expr() | nil, Context.t(), Builder.t()) :: Types.compile_result()
  def compile(nil, _ctx, b), do: {:ok, nil, b}

  def compile(%{op: :pebble_cmd} = expr, ctx, b), do: Cmd.compile(expr, ctx, b)

  def compile(%{op: :html_cmd} = expr, ctx, b), do: PlatformWeb.compile_html_cmd(expr, ctx, b)

  def compile(%{op: :bytes_cmd} = expr, ctx, b), do: PlatformWeb.compile_bytes_cmd(expr, ctx, b)

  def compile(%{op: :dom_sub} = expr, ctx, b), do: PlatformWeb.compile_dom_sub(expr, ctx, b)

  def compile(%{op: :runtime_call} = expr, ctx, b) do
    compile_runtime_call(expr, ctx, b)
  end

  def compile(%{op: :port_outgoing_expr, port: port, payload: payload}, ctx, b)
      when is_binary(port) and is_map(payload) do
    value_ctx = Context.for_branch_arm(ctx)

    with {:ok, port_reg, b1} <- compile(%{op: :string_literal, value: port}, value_ctx, b),
         {:ok, payload_reg, b2} <- compile(payload, value_ctx, b1) do
      compile_runtime_builtin(:port_outgoing, [port_reg, payload_reg], ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_" <> _} = kind, ctx, b) do
    Cmd.compile(%{op: :pebble_cmd, kind: kind, params: []}, ctx, b)
  end

  def compile(%{op: op} = expr, ctx, b) when op in @literal_ops do
    compile_literal(expr, ctx, b)
  end

  def compile(%{op: :var, target: target}, ctx, b) when is_binary(target) do
    compile(%{op: :var, name: target}, ctx, b)
  end

  def compile(%{op: :var, name: name}, ctx, b) when is_binary(name) do
    case String.split(name, ".") do
      [single] ->
        compile_root_var(single, ctx, b)

      [root | fields] when fields != [] ->
        compile_dotted_var_path(root, fields, ctx, b)
    end
  end

  def compile(%{op: :compose_left, f: f, g: g}, ctx, b) do
    compile_compose(f, g, :left, ctx, b)
  end

  def compile(%{op: :compose_right, f: f, g: g}, ctx, b) do
    compile_compose(f, g, :right, ctx, b)
  end

  def compile(%{op: :call, name: "clamp", args: [low, high, value]}, ctx, b) do
    compile_ternary_runtime("clamp", low, high, value, :basics_clamp, ctx, b)
  end

  def compile(%{op: :call} = expr, ctx, b) do
    case IntCall.compile(expr, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        case Lambda.compile_partial(expr, ctx, b) do
          {:ok, _, _} = ok ->
            ok

          :unsupported ->
            Call.compile_call(expr, ctx, b)
        end
    end
  end

  def compile(%{op: :qualified_call} = expr, ctx, b) do
    case expr do
      %{target: "Maybe.withDefault", args: args} ->
        StdlibCall.compile_maybe_with_default(args, ctx, b)

      %{target: target, args: args} ->
        case compile_special_runtime_call(target, args, ctx, b) do
          {:ok, _, _} = ok ->
            ok

          :unsupported ->
            compile_qualified_call_dispatch(expr, target, ctx, b)
        end
    end
  end

  def compile(%{op: :pipe_chain} = expr, ctx, b) do
    expr
    |> ElmEx.IR.PipeChain.desugar()
    |> compile(ctx, b)
  end

  def compile(%{op: :let_in} = expr, ctx, b) do
    compile_let(expr, ctx, b)
  end

  def compile(%{op: :lambda} = expr, ctx, b), do: Lambda.compile(expr, ctx, b)

  def compile(%{op: op} = expr, ctx, b)
      when op in [:tuple_first_expr, :tuple_second_expr, :tuple_first, :tuple_second],
      do: Tuple.compile(expr, ctx, b)

  def compile(%{op: :if} = expr, ctx, b), do: If.compile(expr, ctx, b)
  def compile(%{op: :case} = expr, ctx, b), do: Case.compile(expr, ctx, b)

  def compile(%{op: :render_cmd} = expr, ctx, b),
    do: Elmc.Backend.Plan.Lower.Platform.Pebble.compile_render_cmd(expr, ctx, b)

  def compile(%{op: :render_text_cmd} = expr, ctx, b),
    do: Elmc.Backend.Plan.Lower.Platform.Pebble.compile_render_text_cmd(expr, ctx, b)

  def compile(%{op: :pebble_sub} = expr, ctx, b),
    do: Elmc.Backend.Plan.Lower.Platform.Pebble.compile_sub(expr, ctx, b)
  def compile(%{op: :compare} = expr, ctx, b), do: Compare.compile(expr, ctx, b)
  def compile(%{op: :constructor_call} = expr, ctx, b),
    do: Constructor.compile(expr, ctx, b)

  def compile(%{op: :order_literal, value: value}, ctx, b) when is_integer(value) do
    compile_runtime_builtin(:new_order, [], ctx, b, %{literal: value})
  end

  def compile(%{op: :string_length_expr, arg: arg}, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:string_length_boxed, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :char_from_code_expr, arg: arg}, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:char_from_code, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(
        %{op: :partial_constructor, target: target, args: bound_args, arity: full_arity} = expr,
        ctx,
        b
      )
      when is_binary(target) and is_list(bound_args) and is_integer(full_arity) and full_arity >= 0 do
    bound_count = length(bound_args)
    remaining = max(full_arity - bound_count, 0)

    cond do
      remaining == 0 ->
        # Saturated: treat as a constructor call with the bound args.
        Constructor.compile(%{op: :constructor_call, target: target, args: bound_args}, ctx, b)

      true ->
        cap_names =
          if bound_count > 0 do
            Enum.map(0..(bound_count - 1), fn i -> "__pc_cap_#{i}__" end)
          else
            []
          end

        arg_names = Enum.map(0..(remaining - 1), fn i -> "__pc_arg_#{i}__" end)

        ctor_args =
          Enum.map(cap_names, fn n -> %{op: :var, name: n} end) ++
            Enum.map(arg_names, fn n -> %{op: :var, name: n} end)

        lambda = %{
          op: :lambda,
          args: arg_names,
          body: %{op: :constructor_call, target: target, args: ctor_args}
        }

        desugared =
          bound_args
          |> Enum.with_index()
          |> Enum.reduce(lambda, fn {arg_expr, idx}, acc ->
            %{
              op: :let_in,
              name: Enum.at(cap_names, idx),
              value_expr: arg_expr,
              in_expr: acc
            }
          end)

        compile(desugared, ctx, b)
    end
  rescue
    _ -> record_unsupported(expr, ctx)
  end

  def compile(%{op: :partial_constructor, target: target, tag: tag, args: []} = expr, ctx, b)
      when is_binary(target) and is_integer(tag) do
    case Map.get(expr, :arity, 0) do
      full_arity when is_integer(full_arity) and full_arity > 0 ->
        compile(
          %{op: :partial_constructor, target: target, args: [], arity: full_arity},
          ctx,
          b
        )

      _ ->
        Builder.emit_const_int(b, tag, union_ctor: UnionCtor.qualify(target, ctx))
        |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
  end

  def compile(%{op: :partial_constructor, target: target, args: []}, ctx, b)
      when is_binary(target) do
    Constructor.compile(%{target: target, args: []}, ctx, b)
  end

  def compile(%{op: :msg_tag_expr, name: name}, _ctx, b) when is_binary(name) do
    macro = "ELMC_PEBBLE_MSG_#{Elmc.Backend.Pebble.Util.macro_name(name)}"
    {reg, b1} = Builder.emit_const_c_expr(b, macro)
    {:ok, reg, b1}
  end

  def compile(%{op: :record_update} = expr, ctx, b), do: Record.compile_update(expr, ctx, b)

  def compile(%{op: :qualified_ref, target: target} = expr, ctx, b) when is_binary(target) do
    compile_qualified_ref(expr, ctx, b)
  end

  def compile(%{op: op} = expr, ctx, b) when op in [:add_const, :sub_const, :add_vars],
    do: Arith.compile(expr, ctx, b)

  def compile(%{op: :tuple2, left: left, right: right}, ctx, b) do
    case Constructor.compile_payload_tuple2(left, right, ctx, b) do
      {:ok, reg, b1} ->
        {:ok, reg, b1}

      :unsupported ->
        compile_tuple2_pair(left, right, ctx, b)
    end
  end

  def compile(%{op: :tuple2} = expr, ctx, b) do
    operand_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, [a, b_reg], b1} <- compile_args(Map.get(expr, :args, []), operand_ctx, b) do
      compile_runtime_builtin(:tuple2, [a, b_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :record_literal} = expr, ctx, b) do
    fields =
      expr
      |> Map.get(:fields, [])
      |> Record.canonicalize_literal_fields(ctx)

    with {:ok, field_regs, b1} <- compile_field_values(fields, ctx, b) do
      field_names = Enum.map(fields, fn f -> Map.get(f, :name) || Map.get(f, :field) end)
      extra = %{shape: Map.get(expr, :type), field_names: field_names}

      id =
        if int_record_literal_fields?(fields) or int_record_shape?(field_names) do
          :record_new_values_ints
        else
          :record_new
        end

      compile_runtime_builtin(id, field_regs, ctx, b1, extra)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :list_literal, items: items}, ctx, b) do
    List.compile_literal(items, ctx, b)
  end

  def compile(%{op: :field_access, arg: %{op: :record_literal, fields: fields}, field: field}, ctx, b)
      when is_binary(field) do
    case Enum.find(fields, fn f -> Map.get(f, :name) == field end) do
      %{expr: expr} -> compile(expr, ctx, b)
      _ -> :unsupported
    end
  end

  def compile(%{op: :field_call, arg: arg, field: field, args: args}, ctx, b)
      when is_binary(field) do
    Record.compile_field_call(arg, field, args || [], ctx, b)
  end

  def compile(%{op: :field_access, arg: arg, field: field}, ctx, b) when is_binary(field) do
    with {:ok, base, b1} <- resolve_field_base(arg, ctx, b) do
      compile_record_get(base, field, ctx, b1, base_expr_for_field_access(arg))
    else
      _ -> :unsupported
    end
  end

  def compile(expr, ctx, _b) do
    record_unsupported(expr, ctx)
    :unsupported
  end

  defp record_unsupported(%{op: op} = expr, ctx) when is_map(ctx) do
    key = {Map.get(ctx, :module), Map.get(ctx, :function_name)}

    reason =
      %{
        op: op,
        target: Map.get(expr, :target) || Map.get(expr, :name),
        kind: Map.get(expr, :kind)
      }

    cache = Process.get(:elmc_plan_unsupported_reasons, %{})
    Process.put(:elmc_plan_unsupported_reasons, Map.put_new(cache, key, reason))
  end

  defp record_unsupported(_, _), do: :ok

  defp compile_qualified_call_dispatch(expr, _target, ctx, b) do
    case expr do
      %{target: "Elm.Kernel.Browser." <> name, args: args} when is_list(args) ->
        case PlatformWeb.compile_kernel_call("Elm.Kernel.Browser", name, args, ctx, b) do
          {:ok, dest, b1} -> {:ok, dest, b1}
          :unsupported -> Call.compile_call(expr, ctx, b)
        end

      %{target: "Json.Decode.map", args: args} ->
        compile_json_decode_partial(:json_decode_map, "Json.Decode.map", 2, args || [], ctx, b)

      %{target: "Json.Decode.map2", args: args} ->
        compile_json_decode_partial(:json_decode_map2, "Json.Decode.map2", 3, args || [], ctx, b)

      %{target: "Json.Decode.map3", args: args} ->
        compile_json_decode_partial(:json_decode_map3, "Json.Decode.map3", 4, args || [], ctx, b)

      %{target: "Json.Decode.map4", args: args} ->
        compile_json_decode_partial(:json_decode_map4, "Json.Decode.map4", 5, args || [], ctx, b)

      %{target: "Json.Decode.map5", args: args} ->
        compile_json_decode_partial(:json_decode_map5, "Json.Decode.map5", 6, args || [], ctx, b)

      %{target: "Json.Decode.map6", args: args} ->
        compile_json_decode_partial(:json_decode_map6, "Json.Decode.map6", 7, args || [], ctx, b)

      %{target: "Json.Decode.map7", args: args} ->
        compile_json_decode_partial(:json_decode_map7, "Json.Decode.map7", 8, args || [], ctx, b)

      %{target: "Basics.never", args: []} ->
        # `never : Never -> a` (used for Cmd.map/Sub.map when msg is Never).
        # We lower it as an identity closure.
        Lambda.compile(
          %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
          ctx,
          b
        )

      %{target: target, args: [tagger, cmd]}
      when target in ["Cmd.map", "Platform.Cmd.map", "Elm.Kernel.Platform.map"] ->
        with {:ok, tagger_reg, b1} <- compile(tagger, ctx, b),
             {:ok, cmd_reg, b2} <- compile(cmd, ctx, b1) do
          compile_runtime_builtin(:cmd_map, [tagger_reg, cmd_reg], ctx, b2)
        else
          _ -> :unsupported
        end

      # Partial application: `Cmd.map` and `Cmd.map tagger`.
      %{target: target, args: args}
      when target in ["Cmd.map", "Platform.Cmd.map", "Elm.Kernel.Platform.map"] and
             (args == [] or (is_list(args) and length(args) == 1)) ->
        compile_cmd_map_partial(args, ctx, b)

      %{target: target, args: nil}
      when target in ["Cmd.map", "Platform.Cmd.map", "Elm.Kernel.Platform.map"] ->
        compile_cmd_map_partial([], ctx, b)

      %{target: target, args: args}
      when target in ["Cmd.map", "Platform.Cmd.map", "Elm.Kernel.Platform.map"] and not is_list(args) ->
        compile_cmd_map_partial([], ctx, b)

      %{target: target, args: [tagger, sub]}
      when target in ["Sub.map", "Platform.Sub.map"] ->
        with {:ok, tagger_reg, b1} <- compile(tagger, ctx, b),
             {:ok, sub_reg, b2} <- compile(sub, ctx, b1) do
          compile_runtime_builtin(:sub_map, [tagger_reg, sub_reg], ctx, b2)
        else
          _ -> :unsupported
        end

      # Partial application: `Sub.map` and `Sub.map tagger`.
      %{target: target, args: args}
      when target in ["Sub.map", "Platform.Sub.map"] and (args == [] or (is_list(args) and length(args) == 1)) ->
        compile_sub_map_partial(args, ctx, b)

      %{target: target, args: nil} when target in ["Sub.map", "Platform.Sub.map"] ->
        compile_sub_map_partial([], ctx, b)

      %{target: target, args: args} when target in ["Sub.map", "Platform.Sub.map"] and not is_list(args) ->
        compile_sub_map_partial([], ctx, b)

      %{target: "Cmd.map", args: args} when is_list(args) and length(args) != 2 ->
        :unsupported

      %{target: "Bytes.Decode.map", args: args} ->
        compile_bytes_decode_partial("Bytes.Decode.map", 2, args || [], ctx, b)

      %{target: "Bytes.Decode.map2", args: args} ->
        compile_bytes_decode_partial("Bytes.Decode.map2", 3, args || [], ctx, b)

      %{target: "Bytes.Decode.map3", args: args} ->
        compile_bytes_decode_partial("Bytes.Decode.map3", 4, args || [], ctx, b)

      %{target: "Json.Decode.oneOf", args: args} ->
        compile_json_decode_partial(:json_decode_one_of, "Json.Decode.oneOf", 1, args || [], ctx, b)

      %{target: "Json.Decode.andThen", args: args} ->
        compile_json_decode_partial(:json_decode_and_then, "Json.Decode.andThen", 2, args || [], ctx, b)

      %{target: "Json.Decode.lazy", args: args} ->
        compile_json_decode_partial(:json_decode_lazy, "Json.Decode.lazy", 1, args || [], ctx, b)

      %{target: "Json.Decode.field", args: args} ->
        compile_json_decode_partial(:json_decode_field, "Json.Decode.field", 2, args || [], ctx, b)

      %{target: "Json.Decode.index", args: args} ->
        compile_json_decode_partial(:json_decode_index, "Json.Decode.index", 2, args || [], ctx, b)

      %{target: "Json.Decode.at", args: args} ->
        compile_json_decode_partial(:json_decode_at, "Json.Decode.at", 2, args || [], ctx, b)

      %{target: "Json.Decode.list", args: args} ->
        compile_json_decode_partial(:json_decode_list, "Json.Decode.list", 1, args || [], ctx, b)

      %{target: "Json.Decode.array", args: args} ->
        compile_json_decode_partial(:json_decode_array, "Json.Decode.array", 1, args || [], ctx, b)

      %{target: "Json.Decode.dict", args: args} ->
        compile_json_decode_partial(:json_decode_dict, "Json.Decode.dict", 1, args || [], ctx, b)

      %{target: "Json.Decode.maybe", args: args} ->
        compile_json_decode_partial(:json_decode_maybe, "Json.Decode.maybe", 1, args || [], ctx, b)

      %{target: "Json.Decode.nullable", args: args} ->
        compile_json_decode_partial(:json_decode_nullable, "Json.Decode.nullable", 1, args || [], ctx, b)

      %{target: "Json.Decode.null", args: args} ->
        compile_json_decode_partial(:json_decode_null, "Json.Decode.null", 1, args || [], ctx, b)

      %{target: "Json.Decode.succeed", args: args} ->
        compile_json_decode_partial(:json_decode_succeed, "Json.Decode.succeed", 1, args || [], ctx, b)

      %{target: "Json.Decode.fail", args: args} ->
        compile_json_decode_partial(:json_decode_fail, "Json.Decode.fail", 1, args || [], ctx, b)

      %{target: target, args: [low, high, value]}
      when target in ["Basics.clamp", "clamp"] ->
        compile_ternary_runtime(target, low, high, value, :basics_clamp, ctx, b)

      %{target: target, args: [arg]} when target in ["String.fromInt"] ->
        compile_string_unary(target, arg, ctx, b)

      %{target: target, args: [arg]}
      when target in [
             "Basics.abs",
             "Basics.negate",
             "Basics.round",
             "Basics.ceiling",
             "Basics.truncate",
             "Basics.toFloat",
             "Basics.not",
             "Bitwise.complement",
             "String.reverse",
             "String.trim",
             "String.toUpper",
             "String.toLower",
             "String.length",
             "String.words",
             "String.lines",
             "Char.fromCode",
             "Char.toCode",
             "List.reverse",
             "List.isEmpty",
             "List.length",
             "List.head",
             "List.tail",
             "List.sum",
             "List.product",
             "List.maximum",
             "List.minimum",
             "List.concat",
             "List.sort",
             "Debug.toString"
           ] ->
        compile_qualified_unary(target, arg, ctx, b)

      %{target: target, args: [left, right]} when target == "String.left" ->
        compile_qualified_binary(:string_left, left, right, ctx, b)

      %{target: target, args: [left, right]} ->
        case Map.get(@qualified_binary, target) do
          id when is_atom(id) and not is_nil(id) ->
            compile_qualified_binary(id, left, right, ctx, b)

          _ ->
            case IntCall.compile(%{op: :call, name: target, args: [left, right]}, ctx, b) do
              {:ok, _, _} = ok -> ok
              :unsupported -> Call.compile_call(expr, ctx, b)
            end
        end

      %{target: target, args: [arg_a, arg_b, arg_c]} ->
        case Map.get(@qualified_ternary, target) do
          id when is_atom(id) and not is_nil(id) ->
            compile_qualified_ternary(id, arg_a, arg_b, arg_c, ctx, b)

          _ ->
            Call.compile_call(expr, ctx, b)
        end

      _ ->
        Call.compile_call(expr, ctx, b)
    end
  end

  defp compile_cmd_map_partial([], ctx, b) do
    tagger_name = "__cmd_map_tagger__"
    cmd_name = "__cmd_map_cmd__"

    Lambda.compile(
      %{
        op: :lambda,
        args: [tagger_name],
        body: %{
          op: :lambda,
          args: [cmd_name],
          body: %{
            op: :call_runtime,
            args: %{builtin: :cmd_map, args: [%{op: :var, name: tagger_name}, %{op: :var, name: cmd_name}]}
          }
        }
      },
      ctx,
      b
    )
  end

  defp compile_cmd_map_partial([tagger], ctx, b) do
    cmd_name = "__cmd_map_cmd__"

    Lambda.compile(
      %{
        op: :lambda,
        args: [cmd_name],
        body: %{
          op: :call_runtime,
          args: %{builtin: :cmd_map, args: [tagger, %{op: :var, name: cmd_name}]}
        }
      },
      ctx,
      b
    )
  end

  defp compile_sub_map_partial([], ctx, b) do
    tagger_name = "__sub_map_tagger__"
    sub_name = "__sub_map_sub__"

    Lambda.compile(
      %{
        op: :lambda,
        args: [tagger_name],
        body: %{
          op: :lambda,
          args: [sub_name],
          body: %{
            op: :call_runtime,
            args: %{builtin: :sub_map, args: [%{op: :var, name: tagger_name}, %{op: :var, name: sub_name}]}
          }
        }
      },
      ctx,
      b
    )
  end

  defp compile_sub_map_partial([tagger], ctx, b) do
    sub_name = "__sub_map_sub__"

    Lambda.compile(
      %{
        op: :lambda,
        args: [sub_name],
        body: %{op: :call_runtime, args: %{builtin: :sub_map, args: [tagger, %{op: :var, name: sub_name}]}}
      },
      ctx,
      b
    )
  end

  defp compile_json_decode_map(id, args, ctx, b) when is_atom(id) and is_list(args) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, arg_regs, b1} <- compile_args(args, scratch_ctx, b) do
      compile_runtime_builtin(id, arg_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_bytes_decode_partial(target, expected_arity, provided_args, ctx, b)
       when is_binary(target) and is_integer(expected_arity) and is_list(provided_args) do
    callback_arity = max(expected_arity - 1, 0)

    rewritten_args =
      case provided_args do
        [callback | rest] ->
          [curried_constructor_callback(callback, callback_arity) | rest]

        _ ->
          provided_args
      end

    cond do
      length(rewritten_args) == expected_arity ->
        Call.compile_call(%{op: :qualified_call, target: target, args: rewritten_args}, ctx, b)

      length(rewritten_args) < expected_arity ->
        missing = expected_arity - length(rewritten_args)
        lambda_args = Enum.map(0..(missing - 1)//1, &"__bytes_decode_arg_#{&1}__")
        call_args = rewritten_args ++ Enum.map(lambda_args, fn n -> %{op: :var, name: n} end)

        Lambda.compile(
          %{
            op: :lambda,
            args: lambda_args,
            body: %{op: :qualified_call, target: target, args: call_args}
          },
          ctx,
          b
        )

      true ->
        Call.compile_call(%{op: :qualified_call, target: target, args: rewritten_args}, ctx, b)
    end
  end

  defp curried_constructor_callback(
         %{op: :constructor_call, target: target, args: bound_args},
         callback_arity
       )
       when is_binary(target) and is_integer(callback_arity) do
    bound_args = bound_args || []
    bound_count = length(bound_args)
    remaining = max(callback_arity - bound_count, 0)

    if remaining > 0 do
      arg_names = Enum.map(0..(remaining - 1), &"__bytes_ctor_#{&1}__")

      ctor_arg_exprs =
        bound_args ++ Enum.map(arg_names, fn name -> %{op: :var, name: name} end)

      %{
        op: :lambda,
        args: arg_names,
        body: %{op: :constructor_call, target: target, args: ctor_arg_exprs}
      }
    else
      %{op: :constructor_call, target: target, args: bound_args}
    end
  end

  defp curried_constructor_callback(
         %{op: :partial_constructor, target: target, args: bound_args} = pc,
         callback_arity
       )
       when is_binary(target) and is_integer(callback_arity) do
    bound_args = bound_args || []
    bound_count = length(bound_args)
    remaining = max(callback_arity - bound_count, 0)

    if remaining > 0 do
      Map.merge(pc, %{args: bound_args, arity: callback_arity})
    else
      pc
    end
  end

  defp curried_constructor_callback(expr, _callback_arity), do: expr

  defp compile_json_decode_partial(id, target, expected_arity, provided_args, ctx, b)
       when is_atom(id) and is_binary(target) and is_integer(expected_arity) and is_list(provided_args) do
    cond do
      length(provided_args) == expected_arity ->
        compile_json_decode_map(id, provided_args, ctx, b)

      length(provided_args) < expected_arity ->
        missing = expected_arity - length(provided_args)
        lambda_args = Enum.map(0..(missing - 1)//1, &"__json_arg_#{&1}__")
        call_args = provided_args ++ Enum.map(lambda_args, fn n -> %{op: :var, name: n} end)

        Lambda.compile(
          %{op: :lambda, args: lambda_args, body: %{op: :qualified_call, target: target, args: call_args}},
          ctx,
          b
        )

      true ->
        Call.compile_call(%{op: :qualified_call, target: target, args: provided_args}, ctx, b)
    end
  end

  defp compile_special_runtime_call(target, args, ctx, b) when is_binary(target) and is_list(args) do
    case SpecialValues.special_value_from_target(target, args) do
      %{op: :runtime_call} = rewritten ->
        compile(rewritten, ctx, b)

      %{op: :pebble_cmd} = rewritten ->
        Cmd.compile(rewritten, ctx, b)

      %{op: op} = rewritten when is_atom(op) and op != :unsupported ->
        compile(rewritten, ctx, b)

      _ ->
        :unsupported
    end
  end

  defp compile_special_runtime_call(_, _, _, _), do: :unsupported

  defp compile_dotted_var_path(root, fields, ctx, b) when is_binary(root) and is_list(fields) do
    root_ir = %{op: :var, name: root}

    with {:ok, reg, b1} <- compile_root_var(root, ctx, b) do
      Enum.reduce_while(fields, {:ok, reg, b1, root_ir}, fn field, {:ok, acc_reg, b_acc, base_ir} ->
        {:ok, next_reg, b2} = compile_record_get(acc_reg, field, ctx, b_acc, base_ir)
        next_ir = %{op: :field_access, arg: base_ir, field: field}
        {:cont, {:ok, next_reg, b2, next_ir}}
      end)
      |> case do
        {:ok, reg, b_final, _ir} -> {:ok, reg, b_final}
      end
    end
  end

  defp base_expr_for_field_access(%{op: :var, name: name}) when is_binary(name),
    do: %{op: :var, name: name}

  defp base_expr_for_field_access(name) when is_binary(name), do: %{op: :var, name: name}

  defp base_expr_for_field_access(arg) when is_map(arg), do: arg
  defp base_expr_for_field_access(_), do: nil

  defp compile_compose(f, g, :left, ctx, b) do
    arg_name = "__compose_arg__"
    inner = apply_expr_to_arg(g, arg_name)
    body = apply_expr_to_operand(f, inner)
    Lambda.compile(%{op: :lambda, args: [arg_name], body: body}, ctx, b)
  end

  defp compile_compose(f, g, :right, ctx, b) do
    arg_name = "__compose_arg__"
    inner = apply_expr_to_arg(f, arg_name)
    body = apply_expr_to_operand(g, inner)
    Lambda.compile(%{op: :lambda, args: [arg_name], body: body}, ctx, b)
  end

  defp apply_expr_to_arg(%{op: :qualified_call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :constructor_call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :var, name: name}, arg_name) when is_binary(name) do
    %{op: :call, name: name, args: [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :qualified_ref, target: target}, arg_name) do
    %{op: :qualified_call, target: target, args: [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :constructor_ref, target: target}, arg_name) do
    %{op: :constructor_call, target: target, args: [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(expr, arg_name) do
    %{op: :call, name: "__apply__", args: [expr, %{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_operand(%{op: :qualified_call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  defp apply_expr_to_operand(%{op: :call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  defp apply_expr_to_operand(%{op: :constructor_call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  defp apply_expr_to_operand(%{op: :var, name: name}, operand) when is_binary(name) do
    %{op: :call, name: name, args: [operand]}
  end

  defp apply_expr_to_operand(%{op: :qualified_ref, target: target}, operand) do
    %{op: :qualified_call, target: target, args: [operand]}
  end

  defp apply_expr_to_operand(%{op: :constructor_ref, target: target}, operand) do
    %{op: :constructor_call, target: target, args: [operand]}
  end

  defp apply_expr_to_operand(expr, operand) do
    %{op: :call, name: "__apply__", args: [expr, operand]}
  end

  defp compile_root_var(name, ctx, b) when is_binary(name) do
    cond do
      Lambda.partial_operator_var?(name) ->
        Lambda.compile_partial(%{op: :call, name: name, args: []}, ctx, b)

      true ->
        compile_root_var_binding(name, ctx, b)
    end
  end

  defp compile_root_var_binding(name, ctx, b) when is_binary(name) do
    case Context.local_reg(ctx, name) do
      reg when is_integer(reg) ->
        {:ok, reg, b}

      _ ->
        case Context.letrec_ref(ctx, name) do
          ref when is_binary(ref) ->
            compile_forward_ref_load(ref, ctx, b)

          _ ->
            case param_index(ctx, name) do
              idx when is_integer(idx) ->
                Builder.get_or_load_param(b, idx, name) |> then(fn {reg, b1} -> {:ok, reg, b1} end)

              _ ->
                case Builder.emit_load_local(b, name) do
                  {nil, _} ->
                    case Call.compile_top_level_ref(name, ctx, b) do
                      {:ok, reg, b1} -> {:ok, reg, b1}
                      :unsupported ->
                        ports_by_module = Process.get(:elmc_module_ports, %{})

                        if is_map(ports_by_module) and name in Map.get(ports_by_module, ctx.module || "Main", []) do
                          case Port.direction_from_type(port_decl_type(ctx, name)) do
                            :incoming ->
                              record_unsupported(%{op: :port_incoming_ref, name: name}, ctx)
                              :unsupported

                            _ ->
                              payload_arg = "__port_payload__"

                              Lambda.compile(
                                %{
                                  op: :lambda,
                                  args: [payload_arg],
                                  body: %{
                                    op: :port_outgoing_expr,
                                    port: name,
                                    payload: %{op: :var, name: payload_arg}
                                  }
                                },
                                ctx,
                                b
                              )
                          end
                        else
                          if String.starts_with?(name, "w3_") do
                            record_unsupported(%{op: :missing_generated_helper, name: name}, ctx)
                          else
                            record_unsupported(%{op: :unbound_var, name: name}, ctx)
                          end

                          :unsupported
                        end
                    end

                  {reg, b1} ->
                    {:ok, reg, b1}
                end
            end
        end
    end
  end

  defp compile_forward_ref_load(ref, ctx, b) when is_binary(ref) do
    {dest, b1} = Builder.fresh_reg(b)

    op =
      if Map.get(ctx, :letrec_in_closure) do
        :forward_ref_load_captured
      else
        :forward_ref_load
      end

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: dest,
        args: %{ref: ref},
        effects: Types.owned_effects(dest)
      })

    {:ok, dest, b2}
  end

  @spec compile_args([Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, [Types.reg()], Builder.t()} | :unsupported
  def compile_args(args, ctx, b) when is_list(args) do
    # Call operands must not target branch_out / fn_out — only the callee result may.
    operand_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(args, {:ok, [], b}, fn arg, {:ok, acc, b_acc} ->
      case compile(arg, operand_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ ->
          record_unsupported(arg, operand_ctx)
          {:halt, :unsupported}
      end
    end)
  end

  defp compile_literal(%{op: :int_literal, union_ctor: ctor} = expr, ctx, b) when is_binary(ctor) do
    Constructor.compile(
      %{target: UnionCtor.qualify(ctor, ctx), args: [], value: Map.get(expr, :value)},
      ctx,
      b
    )
  end

  defp compile_literal(%{op: :char_literal, value: value}, ctx, b) do
    compile_runtime_builtin(:new_char, [], ctx, b, %{literal: value})
  end

  defp compile_literal(%{op: :float_literal, value: value}, ctx, b) when is_number(value) do
    compile_runtime_builtin(:new_float, [], ctx, b, %{literal: value})
  end

  defp compile_literal(%{op: :int_literal, value: value}, ctx, b) do
    if ctx.rc_required and Context.function_tail?(ctx) do
      compile_runtime_builtin(:new_int, [], ctx, b, %{literal: value})
    else
      Builder.emit_const_int(b, value) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
  end

  defp compile_literal(%{op: :bool_literal, value: value}, ctx, b) do
    int_val = if value, do: 1, else: 0
    compile_runtime_builtin(:new_bool, [int_val], ctx, b, %{literal: int_val})
  end

  defp compile_literal(%{op: :sub_none}, ctx, b) do
    opts = Process.get(:elmc_codegen_opts, %{})

    if PlatformWeb.web_target?(opts) do
      PlatformWeb.compile_dom_sub(
        %{op: :dom_sub, kind: %{op: :int_literal, value: 0}, params: []},
        ctx,
        b
      )
    else
      Elmc.Backend.Plan.Lower.Platform.Pebble.compile_sub(
        %{mask: %{op: :int_literal, value: 0}, params: []},
        ctx,
        b
      )
    end
  end

  defp compile_literal(%{op: :cmd_none}, ctx, b) do
    opts = Process.get(:elmc_codegen_opts, %{})

    if PlatformWeb.web_target?(opts) do
      compile_runtime_builtin(:unit, [], ctx, b)
    else
      kind = SpecialValues.command_kind_expr(:none)
      Cmd.compile(%{op: :pebble_cmd, kind: kind, params: []}, ctx, b)
    end
  end

  defp compile_literal(%{op: :string_literal, value: value}, _ctx, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :const_immortal_string, %{
        dest: reg,
        args: %{value: value},
        effects: Types.owned_effects(reg)
      })

    {:ok, reg, b2}
  end

  defp compile_literal(%{op: :c_int_expr, value: value}, _ctx, b) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> Builder.emit_const_int(b, n) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
      _ -> Builder.emit_const_c_expr(b, value) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
  end

  defp compile_literal(_, _, _), do: :unsupported

  defp param_index(ctx, name) when is_binary(name) do
    ctx.params
    |> Enum.find_index(&(&1 == name))
  end

  defp resolve_field_base(arg, ctx, b) when is_binary(arg),
    do: compile(%{op: :var, name: arg}, ctx, b)

  defp resolve_field_base(arg, ctx, b) when is_map(arg), do: compile(arg, ctx, b)
  defp resolve_field_base(_, _, _), do: :unsupported

  defp compile_qualified_ref(%{target: target}, ctx, b) when is_binary(target) do
    case target do
      "Json.Decode.string" ->
        compile_runtime_builtin(:json_decode_string_decoder, [], ctx, b)

      "Json.Decode.int" ->
        compile_runtime_builtin(:json_decode_int_decoder, [], ctx, b)

      "Json.Decode.float" ->
        compile_runtime_builtin(:json_decode_float_decoder, [], ctx, b)

      "Json.Decode.bool" ->
        compile_runtime_builtin(:json_decode_bool_decoder, [], ctx, b)

      "Json.Decode.value" ->
        compile_runtime_builtin(:json_decode_value_decoder, [], ctx, b)

      _ ->
        case SpecialValues.special_value_from_target(target, nil) do
          %{op: op} = rewritten when is_atom(op) and op != :unsupported ->
            compile(rewritten, ctx, b)

          _ ->
            compile_qualified_ref_decl(target, ctx, b)
        end
    end
  end

  defp compile_qualified_ref_decl(target, ctx, b) when is_binary(target) do
    {mod, name} =
      case String.split(target, ".", trim: true) do
        [only] -> {Map.get(ctx, :module), only}
        parts -> {parts |> Enum.drop(-1) |> Enum.join("."), Elixir.List.last(parts)}
      end

    decl = Map.get(ctx.decl_map, {mod, name})

    if not is_map(decl) do
      record_unsupported(%{op: :qualified_ref, target: target}, ctx)
      :unsupported
    else
      arg_names = decl |> Map.get(:args, []) |> Elixir.List.wrap()

      case length(arg_names) do
        0 ->
          # Nullary function ref can be compiled as a call.
          Call.compile_call(%{op: :qualified_call, target: target, args: []}, ctx, b)

        arity ->
          lambda_args = Enum.map(0..(arity - 1)//1, &"__ref_arg_#{&1}__")

          call_args = Enum.map(lambda_args, fn a -> %{op: :var, name: a} end)

          Lambda.compile(
            %{op: :lambda, args: lambda_args, body: %{op: :qualified_call, target: target, args: call_args}},
            ctx,
            b
          )
      end
    end
  end

  defp compile_record_get(base, field, ctx, b, base_expr) when is_integer(base) do
    {reg, b1} = Builder.fresh_reg(b)
    field_index = Record.field_index_for(field, ctx, base_expr)
    int_field? = Record.int_field?(field)

    op = if int_field?, do: :record_get_int, else: :record_get

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: reg,
        args: %{base: base, field: field, field_index: field_index},
        effects: %{produces: {:owned, reg}, consumes: [], borrows: [base], fallible: false}
      })

    {:ok, reg, b2}
  end

  defp compile_let(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, ctx, b) do
    {bindings, tail_expr} = collect_let_bindings(%{name: name, value_expr: value_expr, in_expr: in_expr})

    cond do
      bindings == [] ->
        :unsupported

      let_bindings_need_recursion?(bindings, tail_expr) ->
        compile_let_block_letrec(bindings, tail_expr, ctx, b)

      true ->
        compile_let_block_sequential(bindings, tail_expr, ctx, b)
    end
  end

  defp collect_let_bindings(%{name: name, value_expr: value_expr, in_expr: in_expr})
       when is_binary(name) and is_map(value_expr) and is_map(in_expr) do
    do_collect_let_bindings([{name, value_expr}], in_expr)
  end

  defp do_collect_let_bindings(acc, %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr})
       when is_binary(name) and is_map(value_expr) and is_map(in_expr) do
    do_collect_let_bindings(acc ++ [{name, value_expr}], in_expr)
  end

  defp do_collect_let_bindings(acc, tail_expr) when is_list(acc) and is_map(tail_expr) do
    {acc, tail_expr}
  end

  defp let_bindings_need_recursion?(bindings, tail_expr) when is_list(bindings) do
    names = Enum.map(bindings, fn {n, _} -> n end)

    pattern_vars =
      (bound_vars_in_expr_patterns(tail_expr) ++
         Enum.flat_map(bindings, fn {_, value_expr} ->
           bound_vars_in_expr_patterns(value_expr)
         end))
      |> MapSet.new()

    Enum.reduce_while(Enum.with_index(bindings), false, fn {{name, value_expr}, idx}, _acc ->
      used =
        value_expr
        |> Elmc.Backend.CCodegen.VarAnalysis.used_vars()
        |> MapSet.new()

      cond do
        MapSet.member?(used, name) ->
          {:halt, true}

        true ->
          later = Enum.drop(names, idx + 1) |> MapSet.new() |> MapSet.union(pattern_vars)

          if MapSet.size(MapSet.intersection(used, later)) > 0 do
            {:halt, true}
          else
            {:cont, false}
          end
      end
    end)
  end

  defp compile_let_block_letrec(bindings, tail_expr, ctx, b) do
    # Elm `let` bindings are mutually recursive; generate forward refs so later bindings
    # are in-scope even when referenced earlier in the block.
    binding_names = Enum.map(bindings, fn {name, _} -> name end)
    ctx0 = drop_locals(ctx, binding_names)
    all_names = letrec_scope_names(bindings, tail_expr, ctx0)
    outer_locals = letrec_outer_local_names(bindings, tail_expr, ctx0)
    {ctx1, b1} = declare_letrec_refs(all_names, ctx0, b)
    b1a = sync_letrec_locals(outer_locals, ctx1, b1)

    with {:ok, ctx2, b2} <- compile_letrec_value_bindings(bindings, ctx1, b1a),
         {:ok, reg, b3} <- compile(tail_expr, ctx2, b2) do
      {:ok, reg, b3}
    else
      _ -> :unsupported
    end
  end

  defp letrec_scope_names(bindings, tail_expr, ctx) when is_list(bindings) do
    binding_names = Enum.map(bindings, fn {name, _} -> name end)

    binding_pattern_names =
      bindings
      |> Enum.flat_map(fn {_, value_expr} -> bound_vars_in_expr_patterns(value_expr) end)
      |> Enum.uniq()

    (binding_names ++ binding_pattern_names ++ letrec_outer_local_names(bindings, tail_expr, ctx))
    |> Enum.uniq()
  end

  defp letrec_outer_local_names(bindings, tail_expr, ctx) when is_list(bindings) do
    bindings
    |> Enum.reduce(MapSet.new(), fn {_, value_expr}, acc ->
      MapSet.union(acc, Elmc.Backend.CCodegen.VarAnalysis.used_vars(value_expr))
    end)
    |> MapSet.union(Elmc.Backend.CCodegen.VarAnalysis.used_vars(tail_expr))
    |> MapSet.intersection(MapSet.new(Map.keys(ctx.locals || %{})))
    |> MapSet.to_list()
  end

  defp drop_locals(ctx, names) when is_list(names) do
    locals = Map.drop(ctx.locals || %{}, names)
    %{ctx | locals: locals}
  end

  defp declare_letrec_refs(names, ctx, b) when is_list(names) do
    Enum.reduce(names, {ctx, b}, fn name, {ctx_acc, b_acc} ->
      case Context.letrec_ref(ctx_acc, name) do
        ref when is_binary(ref) ->
          {ctx_acc, b_acc}

        _ ->
          {ref, b_next} = Builder.declare_letrec(b_acc, name)
          {Context.put_letrec_ref(ctx_acc, name, ref), b_next}
      end
    end)
  end

  defp sync_letrec_locals(names, ctx, b) when is_list(names) do
    Enum.reduce(names, b, fn name, b_acc ->
      with reg when is_integer(reg) <- Context.local_reg(ctx, name),
           ref when is_binary(ref) <- Context.letrec_ref(ctx, name) do
        {_, b2} =
          Builder.emit(b_acc, :forward_ref_set, %{
            dest: nil,
            args: %{ref: ref, value: reg},
            effects: Types.empty_effects()
          })

        b2
      else
        _ -> b_acc
      end
    end)
  end

  defp sync_letrec_forward_ref(name, ctx, reg, b) when is_binary(name) and is_integer(reg) do
    case Context.letrec_ref(ctx, name) do
      ref when is_binary(ref) ->
        {_, b2} =
          Builder.emit(b, :forward_ref_set, %{
            dest: nil,
            args: %{ref: ref, value: reg},
            effects: Types.empty_effects()
          })

        b2

      _ ->
        b
    end
  end

  defp bound_vars_in_expr_patterns(expr) when is_map(expr) do
    do_bound_vars_in_expr_patterns(expr, MapSet.new()) |> MapSet.to_list()
  end

  defp bound_vars_in_expr_patterns(_), do: []

  defp do_bound_vars_in_expr_patterns(%{op: :case, branches: branches} = expr, acc)
       when is_list(branches) do
    acc =
      Enum.reduce(branches, acc, fn br, acc1 ->
        acc2 =
          case Map.get(br, :pattern) do
            pat when is_map(pat) -> bound_vars_in_pattern(pat, acc1)
            _ -> acc1
          end

        do_bound_vars_in_expr_patterns(Map.get(br, :expr), acc2)
      end)

    do_bound_vars_in_expr_patterns(Map.get(expr, :subject), acc)
  end

  defp do_bound_vars_in_expr_patterns(expr, acc) when is_map(expr) do
    Enum.reduce(expr, acc, fn {_k, v}, acc1 -> do_bound_vars_in_expr_patterns(v, acc1) end)
  end

  defp do_bound_vars_in_expr_patterns(list, acc) when is_list(list) do
    Enum.reduce(list, acc, fn v, acc1 -> do_bound_vars_in_expr_patterns(v, acc1) end)
  end

  defp do_bound_vars_in_expr_patterns(_, acc), do: acc

  defp bound_vars_in_pattern(%{kind: :var, name: name}, acc) when is_binary(name),
    do: MapSet.put(acc, name)

  defp bound_vars_in_pattern(%{kind: :alias, alias: name, pattern: inner}, acc)
       when is_binary(name) and is_map(inner) do
    bound_vars_in_pattern(inner, MapSet.put(acc, name))
  end

  defp bound_vars_in_pattern(%{kind: :tuple, elements: elements}, acc) when is_list(elements),
    do: Enum.reduce(elements, acc, &bound_vars_in_pattern/2)

  defp bound_vars_in_pattern(%{kind: :record, fields: fields}, acc) when is_list(fields),
    do: Enum.reduce(fields, acc, fn f, acc1 -> if is_binary(f), do: MapSet.put(acc1, f), else: acc1 end)

  defp bound_vars_in_pattern(%{kind: :constructor, bind: bind, arg_pattern: arg_pattern}, acc) do
    acc1 = if is_binary(bind), do: MapSet.put(acc, bind), else: acc

    if is_map(arg_pattern) do
      bound_vars_in_pattern(arg_pattern, acc1)
    else
      acc1
    end
  end

  defp bound_vars_in_pattern(%{kind: :wildcard}, acc), do: acc
  defp bound_vars_in_pattern(%{kind: :int}, acc), do: acc
  defp bound_vars_in_pattern(%{kind: :string}, acc), do: acc
  defp bound_vars_in_pattern(%{kind: :char}, acc), do: acc
  defp bound_vars_in_pattern(_pat, acc), do: acc

  defp compile_let_block_sequential(bindings, tail_expr, ctx, b) when is_list(bindings) do
    Enum.reduce_while(bindings, {:ok, ctx, b}, fn {name, value_expr}, {:ok, ctx_acc, b_acc} ->
      value_expr = maybe_packed_text_options_expr(value_expr)
      value_ctx = Context.for_branch_arm(ctx_acc)

      case compile(value_expr, value_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) ->
          ctx1 =
            ctx_acc
            |> Context.put_local(name, reg)
            |> maybe_put_local_type(name, value_expr, ctx_acc)

          b2 = Builder.bind_local(b1, name, reg)
          b3 = sync_letrec_forward_ref(name, ctx1, reg, b2)
          {:cont, {:ok, ctx1, b3}}

        _ ->
          {:halt, :unsupported}
      end
    end)
    |> then(fn
      {:ok, ctx2, b2} -> compile(tail_expr, ctx2, b2)
      _ -> :unsupported
    end)
  end

  defp compile_letrec_value_bindings(bindings, ctx, b) when is_list(bindings) do
    Enum.reduce_while(bindings, {:ok, ctx, b}, fn {name, value_expr}, {:ok, ctx_acc, b_acc} ->
      ref = Context.letrec_ref(ctx_acc, name)
      value_ctx = Context.for_branch_arm(ctx_acc)

      with ref when is_binary(ref) <- ref,
           {:ok, reg, b1} when is_integer(reg) <- compile(value_expr, value_ctx, b_acc),
           {_, b2} <-
             Builder.emit(b1, :forward_ref_set, %{
               dest: nil,
               args: %{ref: ref, value: reg},
               effects: Types.empty_effects()
             }),
           ctx1 = Context.put_local(ctx_acc, name, reg),
           b3 = Builder.bind_local(b2, name, reg) do
        {:cont, {:ok, ctx1, b3}}
      else
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp maybe_packed_text_options_expr(value_expr) do
    alias Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions

    if TextOptions.packable_value?(value_expr) do
      case TextOptions.packed_expr(value_expr) do
        {:ok, %{op: :direct_native_if} = packed} ->
          %{
            op: :if,
            cond: Map.fetch!(packed, :cond),
            then_expr: Map.fetch!(packed, :then_expr),
            else_expr: Map.fetch!(packed, :else_expr)
          }

        {:ok, packed} ->
          packed

        _ ->
          value_expr
      end
    else
      value_expr
    end
  end

  defp maybe_put_local_type(ctx, name, value_expr, parent_ctx) do
    case TypedReturn.expr_type(value_expr, let_type_env(parent_ctx)) do
      type when is_binary(type) -> Context.put_local_type(ctx, name, type)
      _ -> ctx
    end
  end

  defp let_type_env(%Context{} = ctx) do
    %{
      __module__: ctx.module || "Main",
      __var_types__:
        let_param_var_types(ctx)
        |> Map.merge(ctx.local_types),
      __program_decls__: ctx.decl_map,
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  defp let_param_var_types(%Context{decl_map: decl_map, module: module, params: params, function_name: fun})
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

  defp let_param_var_types(_), do: %{}

  defp compile_string_unary("String.fromInt", arg, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:string_from_int_value, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_qualified_unary(target, arg, ctx, b) do
    case Map.get(@qualified_unary, target) do
      id when is_atom(id) and not is_nil(id) ->
        with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
          compile_runtime_builtin(id, [arg_reg], ctx, b1)
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  defp compile_qualified_binary(id, left, right, ctx, b) do
    with {:ok, [left_reg, right_reg], b1} <- compile_args([left, right], ctx, b) do
      compile_runtime_builtin(id, [left_reg, right_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_qualified_ternary(id, a, b, c, ctx, builder) do
    with {:ok, [a_reg, b_reg, c_reg], b1} <- compile_args([a, b, c], ctx, builder) do
      compile_runtime_builtin(id, [a_reg, b_reg, c_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_ternary_runtime(_target, low, high, value, id, ctx, b) do
    with {:ok, [low_reg, high_reg, value_reg], b1} <- compile_args([low, high, value], ctx, b) do
      compile_runtime_builtin(id, [low_reg, high_reg, value_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_field_values(fields, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(fields, {:ok, [], b}, fn field, {:ok, acc, b_acc} ->
      expr = Map.get(field, :expr) || Map.get(field, :value)

      case compile(expr, operand_ctx, b_acc) do
        {:ok, reg, b1} -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp int_record_literal_fields?(fields) when is_list(fields) do
    fields != [] and
      Enum.all?(fields, fn field ->
        name = Map.get(field, :name) || Map.get(field, :field)

        is_binary(name) and Record.int_field?(name) and int_record_field_expr?(field)
      end)
  end

  defp int_record_shape?(field_names) when is_list(field_names) do
    field_names != [] and Enum.all?(field_names, &Record.int_field?/1)
  end

  defp int_record_field_expr?(field) do
    int_record_expr?(Map.get(field, :expr) || Map.get(field, :value))
  end

  defp int_record_expr?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor), do: false

  defp int_record_expr?(%{op: :int_literal, value: value}) when is_integer(value), do: true

  defp int_record_expr?(%{op: :var, name: _name}), do: false

  defp int_record_expr?(%{op: :qualified_call, target: target, args: args}) when is_list(args) do
    int_call_target?(target) and Enum.all?(args, &int_record_expr?/1)
  end

  defp int_record_expr?(%{op: :call, name: name, args: args}) when is_list(args) do
    name in ["max", "min", "modBy", "remainderBy", "__idiv__", "__mul__", "__add__", "__sub__"] and
      Enum.all?(args, &int_record_expr?/1)
  end

  defp int_record_expr?(%{op: op})
       when op in [
              :add_const,
              :sub_const,
              :add_vars,
              :sub_vars,
              :mul_vars,
              :idiv_vars,
              :min_vars,
              :max_vars,
              :mod_vars,
              :rem_vars,
              :record_get_int
            ],
       do: true

  defp int_record_expr?(%{op: :field_access, arg: arg, field: field})
       when is_binary(field) and is_map(arg),
       do: int_record_expr?(arg)

  defp int_record_expr?(_), do: false

  defp int_call_target?(target) when is_binary(target) do
    target in [
      "Basics.max",
      "Basics.min",
      "Basics.modBy",
      "Basics.remainderBy",
      "Basics.abs",
      "Basics.negate"
    ] or
      String.ends_with?(target, ".max") or
      String.ends_with?(target, ".min") or
      String.ends_with?(target, ".modBy")
  end

  defp compile_runtime_call(%{function: "elmc_list_repeat", args: args}, ctx, b) do
    case fold_list_repeat_literals(args, ctx, b) do
      {:ok, reg, b1} ->
        {:ok, reg, b1}

      :error ->
        compile_runtime_call_default(%{function: "elmc_list_repeat", args: args}, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListCursor.try_compile_map(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported ->
        case Elmc.Backend.Plan.Lower.ListRecord.try_compile_map(expr, ctx, b) do
          {:ok, reg, b1} -> {:ok, reg, b1}
          :unsupported -> compile_runtime_call_default(expr, ctx, b)
        end
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_filter_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.FilterMapIdentity.try_compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_filter"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListRecord.try_compile_filter(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_find_first", args: [pred, list]}, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListRecord.try_compile_filter(
           %{function: "elmc_list_filter", args: [pred, list]},
           ctx,
           b
         ) do
      {:ok, filtered_reg, b1} ->
        compile_runtime_builtin(:list_head, [filtered_reg], ctx, b1)

      :unsupported ->
        compile_runtime_call_default(
          %{function: "elmc_list_find_first", args: [pred, list]},
          ctx,
          b
        )
    end
  end

  defp compile_runtime_call(%{function: "elmc_maybe_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.MaybeMap.try_compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_maybe_and_then"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.MaybeAndThen.try_compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(expr, ctx, b), do: compile_runtime_call_default(expr, ctx, b)

  defp compile_runtime_call_default(%{function: "elmc_list_find_first", args: args}, ctx, b) do
    with {:ok, [pred_reg, list_reg], b1} <- compile_call_args(args, ctx, b),
         {:ok, filtered_reg, b2} <-
           compile_runtime_builtin(:list_filter, [pred_reg, list_reg], ctx, b1),
         {:ok, head_reg, b3} <- compile_runtime_builtin(:list_head, [filtered_reg], ctx, b2) do
      {:ok, head_reg, b3}
    else
      _ -> :unsupported
    end
  end

  defp compile_runtime_call_default(%{args: args} = expr, ctx, b) do
    callee = Map.get(expr, :function) || Map.get(expr, :callee)

    with callee when is_binary(callee) <- callee,
         id when not is_nil(id) <- RuntimeBuiltins.from_c_symbol(callee),
         {:ok, arg_regs, b1} <- compile_call_args(args, ctx, b) do
      compile_runtime_builtin(id, arg_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_runtime_call_default(_, _, _), do: :unsupported

  defp compile_call_args(args, ctx, b) when is_list(args) do
    compile_args(args, ctx, b)
  end

  defp compile_call_args(_, _, _), do: {:ok, [], nil}

  defp fold_list_repeat_literals([count_expr, item_expr], ctx, b) do
    with {:ok, count} <- fold_list_repeat_count(count_expr, ctx),
         {:ok, item} <- fold_list_repeat_item(item_expr, ctx),
         true <- count >= 4 do
      values = for _ <- 1..count, do: item
      compile_const_static_list({:int_array, values}, ctx, b)
    else
      _ -> :error
    end
  end

  defp fold_list_repeat_count(%{op: :int_literal, value: count}, _ctx) when is_integer(count),
    do: {:ok, count}

  defp fold_list_repeat_count(expr, ctx) do
    ConstantInt.literal_value(expr, constant_int_env(ctx))
  end

  defp fold_list_repeat_item(%{op: :int_literal, value: item}, _ctx) when is_integer(item),
    do: {:ok, item}

  defp fold_list_repeat_item(expr, ctx) do
    ConstantInt.literal_value(expr, constant_int_env(ctx))
  end

  defp constant_int_env(%Context{module: mod, decl_map: decl_map}) do
    %{
      __module__: mod,
      __program_decls__: decl_map,
      __literal_int_bindings__: %{}
    }
  end

  @doc false
  def compile_const_static_list(spec, ctx, b) do
    {dest, b1} = dest_for_builtin(ctx, b)
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1
    {args, effects} = static_list_instr(spec, dest)

    {_, b3} =
      Builder.emit(b2, :const_static_list, %{
        dest: dest,
        args: args,
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3
    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  defp static_list_instr({:int_array, values}, dest) do
    {%{kind: :int_array, values: values}, Types.fallible_effects(dest)}
  end

  defp static_list_instr({:float_array, values}, dest) do
    {%{kind: :float_array, values: values}, Types.fallible_effects(dest)}
  end

  defp static_list_instr({:tuple2_int_array, pairs}, dest) do
    {%{kind: :tuple2_int_array, pairs: pairs}, Types.fallible_effects(dest)}
  end

  defp static_list_instr({:values, regs}, dest) when is_list(regs) do
    {%{kind: :values, regs: regs}, Types.fallible_effects(dest, [], regs)}
  end

  defp static_list_instr({:record_array, regs}, dest) when is_list(regs) do
    {%{kind: :record_array, regs: regs}, Types.fallible_effects(dest, [], regs)}
  end

  @doc false
  @borrow_view_builtins [:union_payload, :maybe_just_payload]

  @borrow_list_view_builtins [
    :list_head,
    :int_list_head_int,
    :int_list_head_boxed,
    :list_is_empty,
    :list_length
  ]

  def compile_runtime_builtin(id, arg_regs, ctx, b, extra \\ %{}) do
    if id in @borrow_view_builtins do
      compile_borrow_view_builtin(id, arg_regs, ctx, b, extra)
    else
      compile_runtime_builtin_core(id, arg_regs, ctx, b, extra)
    end
  end

  defp compile_borrow_view_builtin(id, arg_regs, _ctx, b, extra) do
    [subject | _] = arg_regs
    {owned, b1} = Builder.fresh_reg(b)

    case id do
      :union_payload ->
        {_, b2} =
          Builder.emit(b1, :tuple_proj, %{
            dest: owned,
            args: %{base: subject, which: :second},
            effects: %{produces: {:owned, owned}, consumes: [], borrows: [subject], fallible: false}
          })

        {:ok, owned, b2}

      _ ->
        {_, b2} =
          Builder.emit(b1, :call_runtime, %{
            dest: owned,
            args: %{
              builtin: :retain,
              args: [subject],
              view_peel: id,
              view_peel_args: arg_regs,
              view_peel_extra: extra
            },
            effects: Types.fallible_effects(owned, arg_regs, [])
          })

        {:ok, owned, b2}
    end
  end

  defp compile_runtime_builtin_core(:list_from_values, arg_regs, ctx, b, _extra) do
    compile_const_static_list({:values, arg_regs}, ctx, b)
  end

  defp compile_runtime_builtin_core(id, arg_regs, ctx, b, extra) do
    {dest, b1} = dest_for_builtin(ctx, b)
    fallible? = RuntimeBuiltins.fallible?(id)
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, fallible?)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

    {arg_regs, b2a} =
      cond do
        id in [:record_new, :record_new_take, :record_new_values_ints] ->
          Builder.dup_named_locals_for_consume(b2, arg_regs)

        id in [:tuple2, :tuple2_take] ->
          Builder.dup_regs_for_owned_consume(b2, arg_regs)

        true ->
          {arg_regs, b2}
      end

    {borrows, consumes} =
      cond do
        id in @borrow_list_view_builtins and length(arg_regs) == 1 ->
          {arg_regs, []}

        id in [:record_new, :record_new_take, :record_new_values_ints] -> {[], arg_regs}
        id in [:cmd_batch, :sub_batch] -> {[], arg_regs}
        id == :debug_to_string -> {[], arg_regs}
        id in [:char_from_code] -> {[], arg_regs}
        id in [:string_length_boxed] -> {arg_regs, []}
        id == :tuple2_ints -> {arg_regs, []}
        id in @hof_closure_last_arg ->
          case arg_regs do
            args when length(args) >= 1 ->
              {prefix, [last]} = Enum.split(args, -1)
              {borrows, prefix_consumes} = Builder.partition_call_args(b2a, prefix)

              if Builder.borrow_arg?(b2a, last) do
                {borrows ++ [last], prefix_consumes}
              else
                {borrows, prefix_consumes ++ [last]}
              end

            _ ->
              Builder.partition_call_args(b2a, arg_regs)
          end

        true ->
          Builder.partition_call_args(b2a, arg_regs)
      end

    effects =
      if is_integer(dest) do
        if fallible? do
          Types.fallible_effects(dest, borrows, consumes)
        else
          %{produces: {:owned, dest}, consumes: consumes, borrows: borrows, fallible: false}
        end
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: fallible?}
      end

    {_, b3} =
      Builder.emit(b2a, :call_runtime, %{
        dest: dest,
        args: Map.merge(%{builtin: id, args: arg_regs}, extra),
        effects: effects
      })

    b4 =
      cond do
        wrap_catch? -> Builder.catch_end(b3)
        true -> b3
      end

    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  defp dest_for_builtin(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end

  defp compile_tuple2_pair(left, right, ctx, b) do
    operand_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, l, b1} <- compile(left, operand_ctx, b),
         {:ok, r, b2} <- compile(right, operand_ctx, b1) do
      if tuple2_ints_eligible?(left, right, ctx) do
        compile_runtime_builtin(:tuple2_ints, [l, r], ctx, b2)
      else
        compile_runtime_builtin(:tuple2, [l, r], ctx, b2)
      end
    else
      _ -> :unsupported
    end
  end

  defp tuple2_ints_eligible?(left, right, ctx) do
    tuple2_int_pair_operand?(left, ctx) and tuple2_int_pair_operand?(right, ctx) and
      not render_op_boxed_payload?(left, right)
  end

  defp tuple2_int_pair_operand?(%{op: :int_literal, union_ctor: ctor}, _ctx) when is_binary(ctor),
    do: false

  defp tuple2_int_pair_operand?(expr, ctx) do
    int_record_expr?(expr) or
      (native_int_operand_expr?(expr, ctx) and not field_access_expr?(expr))
  end

  defp field_access_expr?(%{op: :field_access}), do: true
  defp field_access_expr?(_), do: false

  # Render-op tuples (pathFilled, pathOutline, group, …) carry boxed payloads; never
  # lower them to tuple2_ints even when the payload is a bare var in IR.
  defp render_op_boxed_payload?(left, right) do
    render_op_kind_expr?(left) and boxed_payload_operand?(right)
  end

  defp render_op_kind_expr?(%{op: :c_int_expr, value: value}) when is_binary(value),
    do: String.starts_with?(value, "ELMC_RENDER_OP_")

  defp render_op_kind_expr?(_), do: false

  defp boxed_payload_operand?(%{op: op}) when op in [:var, :call, :qualified_call], do: true
  defp boxed_payload_operand?(_), do: false

  defp native_int_operand_expr?(%{op: op}, _ctx) when op in [:int_literal, :c_int_expr, :msg_tag_expr],
    do: true

  defp native_int_operand_expr?(%{op: :field_access}, _ctx), do: true

  defp native_int_operand_expr?(%{op: :var, name: name}, ctx) when is_binary(name) do
    case Enum.find_index(ctx.params, &(&1 == name)) do
      idx when is_integer(idx) -> native_int_param_index?(idx, ctx)
      _ -> false
    end
  end

  defp native_int_operand_expr?(%{op: op}, _ctx) when op in [:add_const, :sub_const, :add_vars], do: true

  defp native_int_operand_expr?(%{op: :constructor_call, args: []}, _ctx), do: true

  defp native_int_operand_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, ctx),
    do: native_int_operand_expr?(then_expr, ctx) and native_int_operand_expr?(else_expr, ctx)

  defp native_int_operand_expr?(_, _ctx), do: false

  defp native_int_param_index?(idx, ctx) do
    case Map.get(ctx.decl_map, {ctx.module, ctx.function_name}) do
      decl when is_map(decl) ->
        decl = %{decl | args: FunctionEmit.effective_decl_args(decl, ctx.module, ctx.decl_map)}
        Enum.at(FunctionCall.arg_kinds(decl, ctx.module, ctx.decl_map), idx) == :native_int

      _ ->
        false
    end
  end

  defp port_decl_type(ctx, name) do
    case Map.get(ctx.decl_map, {ctx.module || "Main", name}) do
      %{type: type} when is_binary(type) -> type
      decl when is_map(decl) -> Map.get(decl, :return_type)
      _ -> nil
    end
  end
end
