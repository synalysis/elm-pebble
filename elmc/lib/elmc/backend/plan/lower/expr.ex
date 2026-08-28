defmodule Elmc.Backend.Plan.Lower.Expr do
  @moduledoc """
  Lower Elm IR expressions to verified `%FunctionPlan{}` fragments.
  """
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.{ConstantInt, VarAnalysis}
  alias Elmc.Backend.CCodegen.{FunctionEmit, Host, TypeParsing}
  alias Elmc.Backend.CCodegen.Native.{FunctionCall, TypedReturn}
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.{Arith, Call, Case, Cmd, Compare, Constructor, If, IntCall, Lambda, List, PipeChain, Port, Record, SpecialValues, StdlibCall, Tuple, UnionCtor}
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb
  alias Elmc.Backend.Plan.ParamFieldInference
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Stream
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Pebble.Util, as: PebbleUtil

  @literal_ops [:int_literal, :c_int_expr, :bool_literal, :string_literal, :char_literal, :cmd_none, :sub_none, :float_literal]

  @qualified_unary %{
    "Basics.abs" => :basics_abs,
    "Basics.negate" => :basics_negate,
    "Basics.round" => :basics_round,
    "Basics.ceiling" => :basics_ceiling,
    "Basics.truncate" => :basics_truncate,
    "Basics.toFloat" => :basics_to_float,
    "Basics.log" => :basics_log,
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

  # Runtime takes ownership of the last operand (named `let` locals still transfer).
  @hof_consumes_last_operand ~w(result_and_then maybe_and_then)a

  @qualified_ternary %{
    "Basics.clamp" => :basics_clamp,
    "String.replace" => :string_replace,
    "String.pad" => :string_pad,
    "String.padLeft" => :string_pad_left,
    "String.padRight" => :string_pad_right
  }

  @spec compile(Types.ir_expr() | nil, Context.t(), Builder.t()) :: Types.compile_result()
  def compile(nil, _ctx, b), do: {:ok, nil, b}

  def compile(%{op: :pebble_cmd} = expr, ctx, b) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      record_unsupported(expr, ctx)
      :unsupported
    else
      Cmd.compile(expr, ctx, b)
    end
  end

  def compile(%{op: :html_cmd} = expr, ctx, b), do: PlatformWeb.compile_html_cmd(expr, ctx, b)

  def compile(%{op: :bytes_cmd} = expr, ctx, b), do: PlatformWeb.compile_bytes_cmd(expr, ctx, b)
  def compile(%{op: :parser_cmd} = expr, ctx, b), do: PlatformWeb.compile_parser_cmd(expr, ctx, b)

  def compile(%{op: :dom_sub} = expr, ctx, b), do: PlatformWeb.compile_dom_sub(expr, ctx, b)

  def compile(%{op: :runtime_call, function: "elmc_string_from_int", args: [arg]}, ctx, b) do
    compile_string_unary("String.fromInt", arg, ctx, b)
  end

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

  # Bare `ELMC_PEBBLE_CMD_*` c-int values are integer kind constants (used as the
  # left of encoded_cmd_as_tuple and similar). Zero-arity commands must be emitted
  # as `%{op: :pebble_cmd, params: []}` at the special-value site — do not rewrite
  # every CMD c-int into `elmc_cmd0`, or tuple-encoded cmds become
  # `tuple2(cmd0, params)` and `elmc_cmd_from_value` loses the payload.
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

  # Binary `(==)` / `(/=)` / order ops parse as bare `__eq__` etc. Partial
  # application (1-arg) is handled by Lambda; saturated 2-arg calls must become
  # `:compare` — otherwise Call scopes the name to the current module and emits
  # a missing `Module.__eq__` callee stub.
  def compile(%{op: :call, name: name, args: [left, right]}, ctx, b)
      when name in ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__) do
    Compare.compile(
      %{op: :compare, kind: compare_op_kind(name), left: left, right: right},
      ctx,
      b
    )
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
    # Prefer native Int lowering (modBy/min/max/…) before SpecialValues rewrites
    # those callees to boxed `elmc_basics_*` runtime calls.
    case IntCall.compile(expr, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        case expr do
          %{target: "Maybe.withDefault", args: args} ->
            StdlibCall.compile_maybe_with_default(args, ctx, b)

          # Prefer typed Set Debug.toString before SpecialValues hardcodes elmc_debug_to_string.
          %{target: "Debug.toString", args: [arg]} ->
            compile_qualified_unary("Debug.toString", arg, ctx, b)

          %{target: "String.fromInt", args: [arg]} ->
            compile_string_unary("String.fromInt", arg, ctx, b)

          %{target: target, args: args} ->
            case compile_stream_list_call(target, args, ctx, b) do
              {:ok, _, _} = ok ->
                ok

              :unsupported ->
                case compile_stream_ui_shell(target, args, ctx, b) do
                  {:ok, _, _} = ok ->
                    ok

                  :unsupported ->
                    case compile_special_runtime_call(target, args, ctx, b) do
                      {:ok, _, _} = ok ->
                        ok

                      :unsupported ->
                        compile_qualified_call_dispatch(expr, target, ctx, b)
                    end
                end
            end
        end
    end
  end

  # Long homogeneous chains stay as `:pipe_chain` after IR desugar so backends can
  # flatten them. Never desugar+recurse here — that loops forever on those nodes.
  def compile(%{op: :pipe_chain} = expr, ctx, b), do: PipeChain.compile(expr, ctx, b)

  def compile(%{op: :apply_left} = expr, ctx, b) do
    expr
    |> ElmEx.Frontend.ApplyLeft.expand()
    |> compile(ctx, b)
  end

  def compile(%{op: :let_bindings} = expr, ctx, b) do
    expr
    |> ElmEx.Frontend.LetBindings.expand()
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

  def compile(%{op: :render_cmd} = expr, ctx, b) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      record_unsupported(expr, ctx)
      :unsupported
    else
      Elmc.Backend.Plan.Lower.Platform.Pebble.compile_render_cmd(expr, ctx, b)
    end
  end

  def compile(%{op: :render_text_cmd} = expr, ctx, b) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      record_unsupported(expr, ctx)
      :unsupported
    else
      Elmc.Backend.Plan.Lower.Platform.Pebble.compile_render_text_cmd(expr, ctx, b)
    end
  end

  def compile(%{op: :pebble_sub} = expr, ctx, b) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      record_unsupported(expr, ctx)
      :unsupported
    else
      Elmc.Backend.Plan.Lower.Platform.Pebble.compile_sub(expr, ctx, b)
    end
  end
  def compile(%{op: :compare} = expr, ctx, b), do: Compare.compile(expr, ctx, b)
  def compile(%{op: :constructor_call, target: target, args: [head, tail]} = expr, ctx, b)
      when is_binary(target) do
    if Context.stream_mode?(ctx) and
         Elmc.Backend.Plan.Lower.Stream.List.cons_target?(target) do
      Elmc.Backend.Plan.Lower.Stream.List.compile_cons(head, tail, ctx, b)
    else
      Constructor.compile(expr, ctx, b)
    end
  end

  def compile(%{op: :constructor_call} = expr, ctx, b),
    do: Constructor.compile(expr, ctx, b)

  def compile(%{op: :constructor_ref, target: target}, ctx, b) when is_binary(target) do
    # Bare ctor refs used as functions (`Tuple.mapBoth ModelIndex …`) must be
    # unary+ partials. Compiling them as nullary values makes `invokeClosure`
    # return Int(0) and corrupts mapped payloads (elm-pages Main.init).
    case constructor_ref_arity(target, ctx) do
      arity when is_integer(arity) and arity > 0 ->
        compile(%{op: :partial_constructor, target: target, args: [], arity: arity}, ctx, b)

      _ ->
        Constructor.compile(%{target: target, args: []}, ctx, b)
    end
  end

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

  def compile(%{op: op} = expr, ctx, b) when op in [:add_const, :sub_const, :add_vars, :sub_vars],
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
    if Context.stream_mode?(ctx) do
      Elmc.Backend.Plan.Lower.Stream.List.compile(items, ctx, b)
    else
      List.compile_literal(items, ctx, b)
    end
  end

  def compile(%{op: :list_literal, elements: items}, ctx, b) when is_list(items) do
    compile(%{op: :list_literal, items: items}, ctx, b)
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

  @spec record_unsupported(Types.ir_expr() | term(), Context.t() | term()) :: :ok

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
    :ok
  end

  defp record_unsupported(_, _), do: :ok

  @spec compile_qualified_call_dispatch(Types.expr(), String.t(), Context.t(), Builder.t()) ::
          Types.compile_result()

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

  @spec compile_cmd_map_partial([Types.expr()], Context.t(), Builder.t()) :: Types.compile_result()

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

  @spec compile_sub_map_partial([Types.expr()], Context.t(), Builder.t()) :: Types.compile_result()

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

  @spec compile_json_decode_map(atom(), [Types.expr()], Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_json_decode_map(id, args, ctx, b) when is_atom(id) and is_list(args) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, arg_regs, b1} <- compile_args(args, scratch_ctx, b) do
      compile_runtime_builtin(id, arg_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @spec compile_bytes_decode_partial(
          String.t(),
          non_neg_integer(),
          [Types.expr()],
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

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

  @spec curried_constructor_callback(map() | Types.expr(), non_neg_integer()) :: Types.ir_expr()

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

  @spec compile_json_decode_partial(
          atom(),
          String.t(),
          non_neg_integer(),
          [Types.expr()],
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

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

  @spec compile_special_runtime_call(
          String.t() | term(),
          [Types.expr()] | term(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_stream_list_call(target, args, ctx, b) do
    if Context.stream_mode?(ctx) do
      Elmc.Backend.Plan.Lower.Stream.List.try_compile_call(target, args, ctx, b)
    else
      :unsupported
    end
  end

  defp compile_stream_ui_shell(target, args, ctx, b) do
    Call.try_compile_ui_shell(target, args, ctx, b)
  end

  defp compile_special_runtime_call(target, args, ctx, b) when is_binary(target) and is_list(args) do
    case SpecialValues.special_value_from_target(target, args) do
      %{op: :runtime_call, function: fun, args: call_args} = rewritten
      when is_binary(fun) and is_list(call_args) ->
        case compile_runtime_call_with_callee_arg_types(rewritten, target, ctx, b) do
          {:ok, _, _} = ok -> ok
          :unsupported -> compile(rewritten, ctx, b)
        end

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

  # Thread Elm callee arg types into lambda operands (e.g. BackendTask.Http.withMetadata
  # `(Metadata -> a -> b) -> …` so combine closures resolve Metadata.statusCode@1).
  @spec compile_runtime_call_with_callee_arg_types(
          Types.runtime_call_input() | map() | term(),
          String.t() | term(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_runtime_call_with_callee_arg_types(
         %{function: fun, args: args} = rewritten,
         elm_target,
         ctx,
         b
       )
       when is_binary(fun) and is_list(args) and is_binary(elm_target) do
    # IR-shaped specializers (field-accessor Maybe.andThen/map, list fusions, …) must
    # run before args are compiled to regs. The typed-args path below is for HOF
    # lambdas that need callee param types (e.g. BackendTask.Http.withMetadata).
    case try_stream_list_runtime_call(rewritten, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        compile_ir_or_typed_runtime_call(rewritten, elm_target, args, fun, ctx, b)
    end
  end

  defp compile_runtime_call_with_callee_arg_types(_, _, _, _), do: :unsupported

  defp try_stream_list_runtime_call(expr, ctx, b) do
    if Context.stream_mode?(ctx) do
      Elmc.Backend.Plan.Lower.Stream.List.try_compile_runtime(expr, ctx, b)
    else
      :unsupported
    end
  end

  defp compile_ir_or_typed_runtime_call(rewritten, elm_target, args, fun, ctx, b) do
    case try_ir_specialized_runtime_call(rewritten, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        arg_types =
          elm_target
          |> elm_callee_arg_types(ctx)
          |> refine_hof_arg_types(elm_target, args, ctx)

        with id when not is_nil(id) <- RuntimeBuiltins.from_c_symbol(fun),
             {:ok, arg_regs, b1} <- compile_args_with_expected_types(args, arg_types, ctx, b) do
          compile_runtime_builtin(id, arg_regs, ctx, b1)
        else
          _ -> :unsupported
        end
    end
  end

  # Specialize polymorphic HOF param types from known list/array element types so
  # lambdas like `List.map (\p -> p.x) points` with `points : List Point` get
  # `expected_fn_type` `Point -> …` and native Int field reads.
  @spec refine_hof_arg_types(
          [String.t()],
          String.t() | term(),
          [Types.expr()] | term(),
          Context.t() | term()
        ) :: [String.t()]

  defp refine_hof_arg_types(arg_types, target, args, ctx)
       when is_list(arg_types) and is_binary(target) and is_list(args) do
    short = target |> String.split(".") |> Elixir.List.last()

    case {short, args, arg_types} do
      {name, [_fun, list | _], [fun_type | rest]}
      when name in ["map", "filter", "filterMap", "any", "all", "foldl", "foldr"] and
             is_binary(fun_type) ->
        case list_element_type(list, ctx) do
          elem when is_binary(elem) ->
            if ElmEx.IR.TypeSignature.type_variable?(elem) do
              arg_types
            else
              [specialize_fun_type_elem(fun_type, elem) | rest]
            end

          _ ->
            arg_types
        end

      _ ->
        arg_types
    end
  end

  defp refine_hof_arg_types(arg_types, _, _, _), do: arg_types

  @spec list_element_type(Types.expr() | String.t() | term(), Context.t() | term()) ::
          String.t() | nil

  defp list_element_type(%{op: :var, name: name}, ctx) when is_binary(name) do
    ctx
    |> Context.local_type(name)
    |> list_element_type_from_sig()
  end

  defp list_element_type(name, ctx) when is_binary(name) do
    ctx
    |> Context.local_type(name)
    |> list_element_type_from_sig()
  end

  defp list_element_type(_, _), do: nil

  @spec list_element_type_from_sig(String.t() | term()) :: String.t() | nil

  defp list_element_type_from_sig(type) when is_binary(type) do
    trimmed = TypeParsing.normalize_type_name(type)

    cond do
      String.starts_with?(trimmed, "List ") ->
        String.trim_leading(trimmed, "List ") |> String.trim()

      String.starts_with?(trimmed, "Array ") ->
        String.trim_leading(trimmed, "Array ") |> String.trim()

      true ->
        nil
    end
  end

  defp list_element_type_from_sig(_), do: nil

  @spec specialize_fun_type_elem(String.t(), String.t()) :: String.t()

  defp specialize_fun_type_elem(fun_type, elem) when is_binary(fun_type) and is_binary(elem) do
    # List.map etc. store the mapper type as `(a -> b)` — strip parens before
    # splitting arrows or the inner `->` stays nested and specialization no-ops.
    fun_type = TypeParsing.normalize_type_name(fun_type)
    [head | rest] =
      TypeParsing.function_arg_types(fun_type) ++ [TypeParsing.function_return_type(fun_type)]

    head_norm = TypeParsing.normalize_type_name(head)

    if ElmEx.IR.TypeSignature.type_variable?(head_norm) do
      Enum.join([elem | rest], " -> ")
    else
      fun_type
    end
  end

  @spec try_ir_specialized_runtime_call(map() | term(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp try_ir_specialized_runtime_call(%{function: "elmc_maybe_map"} = expr, ctx, b) do
    Elmc.Backend.Plan.Lower.MaybeMap.try_compile(expr, ctx, b)
  end

  defp try_ir_specialized_runtime_call(%{function: "elmc_maybe_and_then"} = expr, ctx, b) do
    Elmc.Backend.Plan.Lower.MaybeAndThen.try_compile(expr, ctx, b)
  end

  defp try_ir_specialized_runtime_call(%{function: "elmc_list_repeat", args: args}, ctx, b) do
    case fold_list_repeat_literals(args, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :error -> :unsupported
    end
  end

  defp try_ir_specialized_runtime_call(%{function: "elmc_list_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListCursor.try_compile_map(expr, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        Elmc.Backend.Plan.Lower.ListRecord.try_compile_map(expr, ctx, b)
    end
  end

  defp try_ir_specialized_runtime_call(%{function: "elmc_list_filter_map"} = expr, ctx, b) do
    Elmc.Backend.Plan.Lower.FilterMapIdentity.try_compile(expr, ctx, b)
  end

  defp try_ir_specialized_runtime_call(%{function: "elmc_list_filter"} = expr, ctx, b) do
    Elmc.Backend.Plan.Lower.ListRecord.try_compile_filter(expr, ctx, b)
  end

  defp try_ir_specialized_runtime_call(%{function: fun, args: [left, right]}, ctx, b)
       when fun in ["elmc_basics_max", "elmc_basics_min"] do
    name = if fun == "elmc_basics_max", do: "Basics.max", else: "Basics.min"
    Elmc.Backend.Plan.Lower.IntCall.compile(%{op: :call, name: name, args: [left, right]}, ctx, b)
  end

  defp try_ir_specialized_runtime_call(%{function: fun} = expr, ctx, b)
       when fun in ["elmc_tuple_map_first", "elmc_tuple_map_second", "elmc_tuple_map_both"] do
    Elmc.Backend.Plan.Lower.TupleMap.try_compile(expr, ctx, b)
  end

  defp try_ir_specialized_runtime_call(_, _, _), do: :unsupported

  @spec retain_last_hof_operand_if_borrowed(Builder.t(), [Types.reg()]) ::
          {[Types.reg()], Builder.t()}

  defp retain_last_hof_operand_if_borrowed(b, arg_regs) when is_list(arg_regs) do
    case arg_regs do
      [] ->
        {arg_regs, b}

      args ->
        {prefix, [last]} = Enum.split(args, -1)

        if Builder.borrow_arg?(b, last) do
          {owned, b1} = Builder.retain_reg_copy(b, last)
          {prefix ++ [owned], b1}
        else
          {arg_regs, b}
        end
    end
  end

  @spec elm_callee_arg_types(String.t(), Context.t()) :: [String.t()]

  defp elm_callee_arg_types(target, ctx) when is_binary(target) do
    {mod, fun} = split_elm_callee(target, ctx.module)

    case Map.get(ctx.decl_map, {mod, fun}) do
      %{type: type} when is_binary(type) -> TypeParsing.function_arg_types(type)
      _ -> []
    end
  end

  @spec split_elm_callee(String.t(), String.t() | nil) :: {String.t(), String.t()}

  defp split_elm_callee(target, default_module) when is_binary(target) do
    parts = String.split(target, ".")

    case parts do
      [single] ->
        {default_module || "Main", single}

      many ->
        {Enum.join(Enum.drop(many, -1), "."), Enum.at(many, -1)}
    end
  end

  @spec compile_args_with_expected_types(
          [Types.expr()],
          [String.t()],
          Context.t(),
          Builder.t()
        ) :: {:ok, [Types.reg()], Builder.t()} | :unsupported

  defp compile_args_with_expected_types(args, arg_types, ctx, b)
       when is_list(args) and is_list(arg_types) do
    operand_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(Enum.with_index(args), {:ok, [], b}, fn {arg, idx}, {:ok, acc, b_acc} ->
      expected = Enum.at(arg_types, idx)
      arg_ctx = maybe_expect_fn_type(operand_ctx, arg, expected)

      case compile(arg, arg_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ ->
          record_unsupported(arg, arg_ctx)
          {:halt, :unsupported}
      end
    end)
  end

  @spec maybe_expect_fn_type(Context.t(), Types.expr() | term(), String.t() | term()) ::
          Context.t()

  defp maybe_expect_fn_type(ctx, %{op: :lambda}, type) when is_binary(type) do
    normalized = TypeParsing.normalize_type_name(type)

    if String.contains?(normalized, "->") do
      Context.with_expected_fn_type(ctx, normalized)
    else
      ctx
    end
  end

  defp maybe_expect_fn_type(ctx, _, _), do: ctx

  @spec compile_dotted_var_path(String.t(), [String.t()], Context.t(), Builder.t()) ::
          Types.compile_result()

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

  @spec base_expr_for_field_access(Types.expr() | String.t() | term()) :: Types.ir_expr() | nil

  defp base_expr_for_field_access(%{op: :var, name: name}) when is_binary(name),
    do: %{op: :var, name: name}

  defp base_expr_for_field_access(name) when is_binary(name), do: %{op: :var, name: name}

  defp base_expr_for_field_access(arg) when is_map(arg), do: arg
  defp base_expr_for_field_access(_), do: nil

  @spec compile_compose(
          Types.expr(),
          Types.expr(),
          :left | :right,
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

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

  @spec apply_expr_to_arg(map() | Types.expr(), String.t()) :: Types.ir_expr()

  defp apply_expr_to_arg(%{op: :qualified_call, args: args} = expr, arg_name) do
    %{expr | args: args ++ [%{op: :var, name: arg_name}]}
  end

  defp apply_expr_to_arg(%{op: :call, name: "__apply__"} = expr, arg_name) do
    %{op: :call, name: "__apply__", args: [expr, %{op: :var, name: arg_name}]}
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

  @spec apply_expr_to_operand(map() | Types.expr(), Types.ir_expr()) :: Types.ir_expr()

  defp apply_expr_to_operand(%{op: :qualified_call, args: args} = expr, operand) do
    %{expr | args: args ++ [operand]}
  end

  # Never append into `__apply__` — nest binary applies (compose / expand chains).
  defp apply_expr_to_operand(%{op: :call, name: "__apply__"} = expr, operand) do
    %{op: :call, name: "__apply__", args: [expr, operand]}
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

  @spec compile_root_var(String.t(), Context.t(), Builder.t()) :: Types.compile_result()

  defp compile_root_var(name, ctx, b) when is_binary(name) do
    cond do
      Lambda.partial_operator_var?(name) ->
        Lambda.compile_partial(%{op: :call, name: name, args: []}, ctx, b)

      true ->
        compile_root_var_binding(name, ctx, b)
    end
  end

  @spec compile_root_var_binding(String.t(), Context.t(), Builder.t()) :: Types.compile_result()

  defp compile_root_var_binding(name, ctx, b) when is_binary(name) do
    case Context.stream_alias(ctx, name) do
      expr when is_map(expr) ->
        compile(expr, ctx, b)

      _ ->
        compile_root_var_local_or_param(name, ctx, b)
    end
  end

  defp compile_root_var_local_or_param(name, ctx, b) when is_binary(name) do
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
                        port_module = ctx.module || "Main"

                        if is_map(ports_by_module) and name in Map.get(ports_by_module, port_module, []) do
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
                                    port: Port.qualified_name(port_module, name),
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

  @spec compile_forward_ref_load(String.t(), Context.t(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()}
  def compile_forward_ref_load(ref, ctx, b) when is_binary(ref) do
    {dest, b1} = Builder.fresh_reg(b)

    op =
      if Map.get(ctx, :letrec_in_closure) do
        :forward_ref_load_captured
      else
        :forward_ref_load
      end

    capture_index = Map.get(ctx.letrec_capture_indices, ref, 0)

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: dest,
        args: %{ref: ref, capture_index: capture_index},
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

  @spec compile_literal(Types.expr() | term(), Context.t(), Builder.t()) :: Types.compile_result()

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
    # Heap ABI (WASM RC and memoized top-level values): never publish a raw
    # i32 as fn_out. Unboxed `64` collides with handle id 64 and Time.every
    # used to install a ~2ms timer (Scene3d rebuild storm / tab crash).
    # Float-typed returns must be TAG_FLOAT — Time.every takes Float ms.
    cond do
      Context.function_tail?(ctx) and float_return?(ctx) ->
        compile_runtime_builtin(:new_float, [], ctx, b, %{literal: value * 1.0})

      Context.function_tail?(ctx) ->
        compile_runtime_builtin(:new_int, [], ctx, b, %{literal: value})

      true ->
        Builder.emit_const_int(b, value) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
  end

  defp compile_literal(%{op: :bool_literal, value: value}, ctx, b) do
    int_val = if value, do: 1, else: 0

    # Keep True/False as const_int + bool_lit so if-phi can stay truthy_native
    # (no heap bool). Function-tail publish boxes only when the ABI is boxed.
    if Context.function_tail?(ctx) and not native_bool_return?(ctx) do
      compile_runtime_builtin(:new_bool, [], ctx, b, %{literal: int_val})
    else
      Builder.emit_const_int(b, int_val, bool_lit: true)
      |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
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

  @spec float_return?(Context.t()) :: boolean()

  defp float_return?(%Context{} = ctx) do
    name = ctx.function_name
    mod = ctx.module || "Main"

    type =
      case Map.get(ctx.decl_map, {mod, name}) do
        %{type: t} when is_binary(t) and t != "" -> t
        _ -> nil
      end

    is_binary(type) and Host.function_return_type(type) == "Float"
  end

  @spec native_bool_return?(Context.t()) :: boolean()

  defp native_bool_return?(%Context{} = ctx) do
    name = ctx.function_name
    mod = ctx.module || "Main"

    case Map.get(ctx.decl_map, {mod, name}) do
      %{type: type} = decl when is_binary(type) and type != "" ->
        Host.function_return_type(type) == "Bool" or
          FunctionCall.return_kind(decl, mod, ctx.decl_map) == :native_bool

      decl when is_map(decl) ->
        FunctionCall.return_kind(decl, mod, ctx.decl_map) == :native_bool

      _ ->
        false
    end
  end

  @spec param_index(Context.t(), String.t()) :: non_neg_integer() | nil

  defp param_index(ctx, name) when is_binary(name) do
    ctx.params
    |> Enum.find_index(&(&1 == name))
  end

  @spec resolve_field_base(String.t() | Types.expr() | term(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp resolve_field_base(arg, ctx, b) when is_binary(arg),
    do: compile(%{op: :var, name: arg}, ctx, b)

  defp resolve_field_base(arg, ctx, b) when is_map(arg), do: compile(arg, ctx, b)
  defp resolve_field_base(_, _, _), do: :unsupported

  @spec compile_qualified_ref(map(), Context.t(), Builder.t()) :: Types.compile_result()

  defp compile_qualified_ref(%{target: target}, ctx, b) when is_binary(target) do
    case String.split(target, ".") do
      [_root, _field | _rest] = parts ->
        root = hd(parts)

        if dotted_var_root?(root, ctx) do
          compile_dotted_var_path(root, tl(parts), ctx, b)
        else
          compile_qualified_ref_target(target, ctx, b)
        end

      _ ->
        compile_qualified_ref_target(target, ctx, b)
    end
  end

  @spec compile_qualified_ref_target(String.t(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_qualified_ref_target(target, ctx, b) when is_binary(target) do
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
        case SpecialValues.special_value_from_target(target, []) do
          %{op: op} = rewritten when is_atom(op) and op != :unsupported ->
            compile(rewritten, ctx, b)

          _ ->
            compile_qualified_ref_decl(target, ctx, b)
        end
    end
  end

  @spec dotted_var_root?(String.t(), Context.t()) :: boolean()

  defp dotted_var_root?(root, ctx) when is_binary(root) and is_map(ctx) do
    is_integer(Context.local_reg(ctx, root)) or
      is_integer(param_index(ctx, root)) or
      is_binary(Context.letrec_ref(ctx, root))
  end

  @spec compile_qualified_ref_decl(String.t(), Context.t(), Builder.t()) ::
          Types.compile_result()

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
      arg_names =
        decl
        |> Elmc.Backend.CCodegen.FunctionEmit.effective_decl_args(mod, ctx.decl_map)
        |> Elixir.List.wrap()

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

  @spec compile_record_get(
          Types.reg(),
          String.t(),
          Context.t(),
          Builder.t(),
          Types.expr()
        ) :: Types.compile_reg_result()

  defp compile_record_get(base, field, ctx, b, base_expr) when is_integer(base) do
    {reg, b1} = Builder.fresh_reg(b)
    field_index = Record.field_index_for(field, ctx, base_expr)
    int_field? = Record.int_field?(field, ctx, base_expr)

    op = if int_field?, do: :record_get_int, else: :record_get

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: reg,
        args: %{base: base, field: field, field_index: field_index},
        effects: %{produces: {:owned, reg}, consumes: [], borrows: [base], fallible: false}
      })

    {:ok, reg, b2}
  end

  @spec compile_let(Types.expr(), Context.t(), Builder.t()) :: Types.compile_result()

  defp compile_let(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, ctx, b) do
    {bindings, tail_expr} = collect_let_bindings(%{name: name, value_expr: value_expr, in_expr: in_expr})

    case peel_tuple2_maybe_pair_case(bindings, tail_expr) do
      {:ok, case_expr} ->
        Case.compile(case_expr, ctx, b)

      :error ->
        case split_pattern_bind_reorder(bindings, tail_expr) do
          {:ok, bind_name, bind_value, pattern, deferred, case_tail, prefix_bindings} ->
            compile_pattern_bind_reordered(
              prefix_bindings,
              bind_name,
              bind_value,
              pattern,
              deferred,
              case_tail,
              ctx,
              b
            )

          :error ->
            if let_bindings_need_recursion?(bindings, tail_expr) do
              compile_let_block_letrec_or_sequential(bindings, tail_expr, ctx, b)
            else
              compile_let_block_sequential(bindings, tail_expr, ctx, b)
            end
        end
    end
  end

  # `let caseSubject = (a, b[, c]) in case caseSubject of (Just …, Just …) / _`
  # → case (a, b[, c]) of … so Case can avoid heap tuple2 + GuardedSwitch.
  @spec peel_tuple2_maybe_pair_case(list(), Types.expr()) :: {:ok, map()} | :error

  defp peel_tuple2_maybe_pair_case([{bind_name, %{op: :tuple2} = tup}], %{op: :case} = case_expr)
       when is_binary(bind_name) do
    subj = Map.get(case_expr, :subject)
    branches = Map.get(case_expr, :branches)

    subj_name =
      cond do
        is_binary(subj) -> subj
        match?(%{op: :var, name: _}, subj) -> subj.name
        true -> nil
      end

    if subj_name == bind_name and is_list(branches) and Case.tuple2_maybe_pair_branches?(branches) do
      {:ok, %{case_expr | subject: tup}}
    else
      :error
    end
  end

  defp peel_tuple2_maybe_pair_case(_, _), do: :error

  @spec split_pattern_bind_reorder([{String.t(), Types.expr()}], Types.expr()) ::
          {:ok, String.t(), Types.expr(), Types.pattern(), [{String.t(), Types.expr()}],
           Types.expr(), [{String.t(), Types.expr()}]}
          | :error

  defp split_pattern_bind_reorder(bindings, tail_expr) do
    with [%{pattern: pattern, expr: case_tail} | _] <- case_branches(tail_expr),
         subject when is_binary(subject) <- case_subject_name(tail_expr),
         bind_idx when is_integer(bind_idx) <-
           Enum.find_index(bindings, fn {name, _} -> name == subject end),
         {bind_name, bind_value} <- Enum.at(bindings, bind_idx) do
      pattern_vars = bound_vars_in_pattern(pattern, MapSet.new())

      uses_pattern_var? = fn value ->
        value
        |> VarAnalysis.free_vars()
        |> MapSet.intersection(pattern_vars)
        |> MapSet.size() > 0
      end

      deferred =
        bindings
        |> Enum.with_index()
        |> Enum.filter(fn {{_name, value}, idx} ->
          idx != bind_idx and uses_pattern_var?.(value)
        end)
        |> Enum.map(fn {pair, _} -> pair end)

      prefix_bindings =
        bindings
        |> Enum.reject(fn {name, value} ->
          {name, bind_value} == {bind_name, bind_value} or {name, value} in deferred
        end)

      if deferred == [] do
        :error
      else
        {:ok, bind_name, bind_value, pattern, deferred, case_tail, prefix_bindings}
      end
    else
      _ -> :error
    end
  end

  @spec case_branches(Types.expr() | term()) :: Types.case_branches() | :error

  defp case_branches(%{op: :case, branches: branches}) when is_list(branches), do: branches
  defp case_branches(_), do: :error

  @spec case_subject_name(Types.expr() | term()) :: String.t() | :error

  defp case_subject_name(%{op: :case, subject: subject}) when is_binary(subject), do: subject
  defp case_subject_name(%{op: :case, subject: %{op: :var, name: name}}), do: name
  defp case_subject_name(_), do: :error

  @spec compile_pattern_bind_reordered(
          [{String.t(), Types.expr()}],
          String.t(),
          Types.expr(),
          Types.pattern(),
          [{String.t(), Types.expr()}],
          Types.expr(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_pattern_bind_reordered(
         prefix_bindings,
         bind_name,
         bind_value,
         pattern,
         deferred_bindings,
         case_tail,
         ctx,
         b
       ) do
    with {:ok, ctx1, b1} <- compile_prefix_bindings(prefix_bindings, ctx, b),
         {:ok, ctx2, b2} <- compile_single_binding(bind_name, bind_value, ctx1, b1),
         deferred_expr <- nest_deferred_lets(deferred_bindings, case_tail),
         case_expr <- %{
           op: :case,
           subject: bind_name,
           branches: [%{pattern: pattern, expr: deferred_expr}]
         },
         {:ok, reg, b3} <- Case.compile(case_expr, ctx2, b2) do
      {:ok, reg, b3}
    else
      _ -> :unsupported
    end
  end

  @spec compile_prefix_bindings([{String.t(), Types.expr()}], Context.t(), Builder.t()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported

  defp compile_prefix_bindings([], ctx, b), do: {:ok, ctx, b}

  defp compile_prefix_bindings([{name, value_expr} | rest], ctx, b) do
    with {:ok, ctx1, b1} <- compile_single_binding(name, value_expr, ctx, b),
         {:ok, ctx2, b2} <- compile_prefix_bindings(rest, ctx1, b1) do
      {:ok, ctx2, b2}
    else
      _ -> :unsupported
    end
  end

  @spec compile_single_binding(String.t(), Types.expr(), Context.t(), Builder.t()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported

  defp compile_single_binding(name, value_expr, ctx, b) do
    value_expr = maybe_packed_text_options_expr(value_expr)
    value_ctx = Context.for_branch_arm(ctx)

    case compile(value_expr, value_ctx, b) do
      {:ok, reg, b1} when is_integer(reg) ->
        ctx1 =
          ctx
          |> Context.put_local(name, reg)
          |> maybe_put_local_type(name, value_expr, ctx)

        b2 = Builder.bind_local(b1, name, reg)
        b3 = sync_letrec_forward_ref(name, ctx1, reg, b2)
        {:ok, ctx1, b3}

      _ ->
        :unsupported
    end
  end

  @spec nest_deferred_lets([{String.t(), Types.expr()}], Types.expr()) :: Types.ir_expr()

  defp nest_deferred_lets([], tail_expr), do: tail_expr

  defp nest_deferred_lets([{name, value_expr} | rest], tail_expr) do
    %{
      op: :let_in,
      name: name,
      value_expr: value_expr,
      in_expr: nest_deferred_lets(rest, tail_expr)
    }
  end

  @spec compile_let_block_letrec_or_sequential(
          [{String.t(), Types.expr()}],
          Types.expr(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_let_block_letrec_or_sequential(bindings, tail_expr, ctx, b) do
    if letrec_sequential_reorder_eligible?(bindings) do
      case reorder_letrec_bindings(bindings) do
        {:ok, sorted} ->
          compile_let_block_sequential(sorted, tail_expr, ctx, b)

        :cycle ->
          compile_let_block_letrec(bindings, tail_expr, ctx, b)
      end
    else
      compile_let_block_letrec(bindings, tail_expr, ctx, b)
    end
  end

  @spec letrec_sequential_reorder_eligible?(list()) :: boolean()

  defp letrec_sequential_reorder_eligible?(bindings) when is_list(bindings) do
    Enum.all?(bindings, fn {_, value_expr} ->
      not match?(%{op: :lambda}, value_expr)
    end)
  end

  @spec collect_let_bindings(%{
          name: String.t(),
          value_expr: Types.expr(),
          in_expr: Types.expr()
        }) :: {[{String.t(), Types.expr()}], Types.expr()}

  defp collect_let_bindings(%{name: name, value_expr: value_expr, in_expr: in_expr})
       when is_binary(name) and is_map(value_expr) and is_map(in_expr) do
    do_collect_let_bindings([{name, value_expr}], in_expr)
  end

  @spec do_collect_let_bindings([{String.t(), Types.expr()}], Types.expr()) ::
          {[{String.t(), Types.expr()}], Types.expr()}

  defp do_collect_let_bindings(acc, %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr})
       when is_binary(name) and is_map(value_expr) and is_map(in_expr) do
    do_collect_let_bindings(acc ++ [{name, value_expr}], in_expr)
  end

  defp do_collect_let_bindings(acc, tail_expr) when is_list(acc) and is_map(tail_expr) do
    {acc, tail_expr}
  end

  @spec let_bindings_need_recursion?(list(), Types.expr()) :: boolean()

  defp let_bindings_need_recursion?(bindings, _tail_expr) when is_list(bindings) do
    names = Enum.map(bindings, fn {n, _} -> n end)

    Enum.reduce_while(Enum.with_index(bindings), false, fn {{name, value_expr}, idx}, _acc ->
      # Free vars only — nested `let caseSubject = …` must not look like a use of
      # a later sibling binding also named `caseSubject` (Scene3d.toWebGLEntities).
      used =
        value_expr
        |> Elmc.Backend.CCodegen.VarAnalysis.free_vars()
        |> MapSet.new()

      cond do
        MapSet.member?(used, name) ->
          {:halt, true}

        true ->
          # Only sibling let bindings declared later in the same block can force
          # letrec. Case-pattern locals (for example pageData in a Platform
          # FrozenViewsReady arm) must not be treated as "later bindings".
          later = Enum.drop(names, idx + 1) |> MapSet.new()

          if MapSet.size(MapSet.intersection(used, later)) > 0 do
            {:halt, true}
          else
            {:cont, false}
          end
      end
    end)
  end

  @spec compile_let_block_letrec(
          [{String.t(), Types.expr()}],
          Types.expr(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_let_block_letrec(bindings, tail_expr, ctx, b) do
    # Elm `let` bindings are mutually recursive; generate forward refs so later bindings
    # are in-scope even when referenced earlier in the block.
    binding_names = Enum.map(bindings, fn {name, _} -> name end)
    ctx0 = drop_locals(ctx, binding_names)
    all_names = letrec_scope_names(bindings, tail_expr, ctx0)
    outer_locals = letrec_outer_local_names(bindings, tail_expr, ctx0)
    outer_local_regs =
      Map.new(outer_locals, fn name ->
        {name, Context.local_reg(ctx0, name)}
      end)

    {ctx1, b1} = declare_letrec_refs(all_names, ctx0, b)
    b1a = sync_letrec_outer_regs(outer_local_regs, ctx1, b1)

    with {:ok, ctx2, b2} <- compile_letrec_value_bindings(bindings, ctx1, b1a),
         {:ok, reg, b3} <- compile(tail_expr, ctx2, b2) do
      {:ok, reg, b3}
    else
      _ -> :unsupported
    end
  end

  @spec letrec_scope_names([{String.t(), Types.expr()}], Types.expr(), Context.t()) ::
          [String.t()]

  defp letrec_scope_names(bindings, tail_expr, ctx) when is_list(bindings) do
    binding_names = Enum.map(bindings, fn {name, _} -> name end)

    binding_pattern_names =
      bindings
      |> Enum.flat_map(fn {_, value_expr} -> bound_vars_in_expr_patterns(value_expr) end)
      |> Enum.uniq()

    (binding_names ++ binding_pattern_names ++ letrec_outer_local_names(bindings, tail_expr, ctx))
    |> Enum.uniq()
  end

  @spec reorder_letrec_bindings([{String.t(), Types.expr()}]) ::
          {:ok, [{String.t(), Types.expr()}]} | :cycle

  defp reorder_letrec_bindings(bindings) when is_list(bindings) do
    indexed = Enum.with_index(bindings)
    names = Enum.map(bindings, fn {name, _} -> name end)
    name_to_binding = Map.new(bindings)

    var_to_def =
      Enum.reduce(indexed, %{}, fn {{name, value_expr}, idx}, acc ->
        letrec_binding_defined_vars(name, value_expr)
        |> Enum.reduce(acc, fn var, acc2 ->
          Map.put_new(acc2, var, {name, idx})
        end)
      end)

    deps =
      indexed
      |> Enum.flat_map(fn {{name, value_expr}, idx} ->
        value_expr
        |> Elmc.Backend.CCodegen.VarAnalysis.free_vars()
        |> Enum.filter(&Map.has_key?(var_to_def, &1))
        |> Enum.flat_map(fn var ->
          {_dep_name, dep_idx} = Map.fetch!(var_to_def, var)

          if dep_idx > idx do
            [{Map.fetch!(var_to_def, var) |> elem(0), name}]
          else
            []
          end
        end)
      end)

    case topo_sort_dependency_order(names, deps) do
      {:ok, sorted_names} ->
        {:ok, Enum.map(sorted_names, fn name -> {name, Map.fetch!(name_to_binding, name)} end)}

      :cycle ->
        :cycle
    end
  end

  @spec letrec_binding_defined_vars(String.t(), Types.expr()) :: [String.t()]

  defp letrec_binding_defined_vars(name, value_expr) when is_binary(name) do
    [name | bound_vars_in_expr_patterns(value_expr)] |> Enum.uniq()
  end

  @spec topo_sort_dependency_order([String.t()], [{String.t(), String.t()}]) ::
          {:ok, [String.t()]} | :cycle

  defp topo_sort_dependency_order(names, deps) when is_list(names) and is_list(deps) do
    edges =
      Enum.reduce(deps, %{}, fn {before, after_name}, acc ->
        Map.update(acc, before, [after_name], &[after_name | &1])
      end)

    in_count =
      names
      |> Map.new(fn name -> {name, 0} end)
      |> then(fn counts ->
        Enum.reduce(deps, counts, fn {_before, after_name}, acc ->
          Map.update!(acc, after_name, &(&1 + 1))
        end)
      end)

    sorted = topo_sort_kahn(names, edges, in_count, [])

    if length(sorted) == length(names) do
      {:ok, sorted}
    else
      :cycle
    end
  end

  @spec topo_sort_kahn(
          [String.t()],
          %{optional(String.t()) => [String.t()]},
          %{optional(String.t()) => non_neg_integer()},
          [String.t()]
        ) :: [String.t()]

  defp topo_sort_kahn([], _edges, _in_count, acc), do: Enum.reverse(acc)

  defp topo_sort_kahn(remaining, edges, in_count, acc) do
    ready = Enum.filter(remaining, fn name -> Map.fetch!(in_count, name) == 0 end)

    if ready == [] do
      []
    else
      {next, rest} =
        case ready do
          [first | _] -> {first, remaining -- [first]}
        end

      in_count2 =
        Enum.reduce(Map.get(edges, next, []), in_count, fn child, acc_in ->
          Map.update!(acc_in, child, &(&1 - 1))
        end)

      topo_sort_kahn(rest, edges, in_count2, [next | acc])
    end
  end

  @spec letrec_outer_local_names([{String.t(), Types.expr()}], Types.expr(), Context.t()) ::
          [String.t()]

  defp letrec_outer_local_names(bindings, tail_expr, ctx) when is_list(bindings) do
    bindings
    |> Enum.reduce(MapSet.new(), fn {_, value_expr}, acc ->
      MapSet.union(acc, Elmc.Backend.CCodegen.VarAnalysis.free_vars(value_expr))
    end)
    |> MapSet.union(Elmc.Backend.CCodegen.VarAnalysis.free_vars(tail_expr))
    |> MapSet.intersection(MapSet.new(Map.keys(ctx.locals)))
    |> MapSet.to_list()
  end

  @spec drop_locals(Context.t(), [String.t()]) :: Context.t()

  defp drop_locals(ctx, names) when is_list(names) do
    locals = Map.drop(ctx.locals, names)
    %{ctx | locals: locals}
  end

  @spec declare_letrec_refs([String.t()], Context.t(), Builder.t()) ::
          {Context.t(), Builder.t()}

  defp declare_letrec_refs(names, ctx, b) when is_list(names) do
    Enum.reduce(names, {ctx, b}, fn name, {ctx_acc, b_acc} ->
      lambda_plan? = Map.get(ctx_acc, :lambda_plan, false)

      case {lambda_plan?, Context.letrec_ref(ctx_acc, name)} do
        {false, ref} when is_binary(ref) ->
          {ctx_acc, b_acc}

        _ ->
          {ref, b_next} = Builder.declare_letrec(b_acc, name)
          {Context.put_letrec_ref(ctx_acc, name, ref), b_next}
      end
    end)
  end

  @spec sync_letrec_outer_regs(%{optional(String.t()) => Types.reg() | nil}, Context.t(), Builder.t()) ::
          Builder.t()

  defp sync_letrec_outer_regs(reg_map, ctx, b) when is_map(reg_map) do
    Enum.reduce(reg_map, b, fn {name, reg}, b_acc ->
      with ref when is_binary(ref) <- Context.letrec_ref(ctx, name),
           reg when is_integer(reg) <- reg do
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

  @spec sync_letrec_forward_ref(String.t(), Context.t(), Types.reg(), Builder.t()) :: Builder.t()

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

  @spec bound_vars_in_expr_patterns(Types.expr() | term()) :: [String.t()]

  defp bound_vars_in_expr_patterns(expr) when is_map(expr) do
    do_bound_vars_in_expr_patterns(expr, MapSet.new()) |> MapSet.to_list()
  end

  defp bound_vars_in_expr_patterns(_), do: []

  @spec do_bound_vars_in_expr_patterns(term(), MapSet.t(String.t())) :: MapSet.t(String.t())

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

  @spec bound_vars_in_pattern(Types.pattern() | map() | term(), MapSet.t(String.t())) ::
          MapSet.t(String.t())

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

  @spec compile_let_block_sequential(
          [{String.t(), Types.expr()}],
          Types.expr(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_let_block_sequential(bindings, tail_expr, ctx, b) when is_list(bindings) do
    ctx = seed_let_inferred_fields(ctx, bindings, tail_expr)

    Enum.reduce_while(bindings, {:ok, ctx, b}, fn {name, value_expr}, {:ok, ctx_acc, b_acc} ->
      value_expr = maybe_packed_text_options_expr(value_expr)

      if Context.stream_mode?(ctx_acc) and
           Stream.eligible_expr?(value_expr, ctx_acc.decl_map, ctx_acc.module) do
        {:cont, {:ok, Context.put_stream_alias(ctx_acc, name, value_expr), b_acc}}
      else
        value_ctx = %{Context.for_branch_arm(ctx_acc) | stream_mode: false}

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
      end
    end)
    |> then(fn
      {:ok, ctx2, b2} -> compile(tail_expr, ctx2, b2)
      _ -> :unsupported
    end)
  end

  # Let-bound records (especially HOF results like `List.foldl` accumulators) are
  # not params, so ParamFieldInference on the function body never sees them.
  # Without seeding, `result.sum` falls back to field index 0.
  @spec seed_let_inferred_fields(Context.t(), list(), Types.expr()) :: Context.t()
  defp seed_let_inferred_fields(%Context{} = ctx, bindings, tail_expr)
       when is_list(bindings) and is_map(tail_expr) do
    names = Enum.map(bindings, &elem(&1, 0))

    from_literals =
      Enum.reduce(bindings, %{}, fn {name, value_expr}, acc ->
        case record_shape_fields_from_value(value_expr, ctx) do
          fields when is_list(fields) and fields != [] ->
            Map.put(acc, name, fields)

          _ ->
            acc
        end
      end)

    from_access =
      bindings
      |> nest_deferred_lets(tail_expr)
      |> ParamFieldInference.infer_names(names)

    # Prefer literal / fold-accumulator shapes (canonical alphabetical) over
    # access-order inference when both are available.
    merged = Map.merge(from_access, from_literals)

    if map_size(merged) == 0 do
      ctx
    else
      %{
        ctx
        | inferred_param_fields: Map.merge(ctx.inferred_param_fields, merged)
      }
    end
  end

  defp seed_let_inferred_fields(ctx, _, _), do: ctx

  @spec record_shape_fields_from_value(Types.expr(), Context.t()) :: [String.t()] | nil
  defp record_shape_fields_from_value(%{op: :record_literal, fields: fields}, ctx)
       when is_list(fields) do
    # Use the same canonical ordering as literal construction
    # (Record.canonicalize_literal_fields) rather than blindly alphabetizing —
    # named aliases registered in declaration order (e.g. MainResolveAndWalk.Options
    # `{paths, name}`) must keep that order here too, or field-index lookups for
    # this let-bound record (record_update, field_access) disagree with the
    # ELMC_FIELD_* layout used when the literal was built.
    fields
    |> Record.canonicalize_literal_fields(ctx)
    |> Enum.map(fn f -> Map.get(f, :name) || Map.get(f, :field) end)
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      names -> names
    end
  end

  # List.foldl / List.foldr return the accumulator type.
  defp record_shape_fields_from_value(%{op: :qualified_call, target: target, args: args} = expr, ctx)
       when is_binary(target) and is_list(args) do
    if String.ends_with?(target, ".foldl") or String.ends_with?(target, ".foldr") do
      case args do
        [_, acc, _] -> record_shape_fields_from_value(acc, ctx)
        _ -> nil
      end
    else
      alias_shape_fields_from_typed_expr(expr, ctx)
    end
  end

  defp record_shape_fields_from_value(%{op: :call, name: name, args: args} = expr, ctx)
       when is_binary(name) and is_list(args) do
    if name in ["foldl", "foldr"] do
      case args do
        [_, acc, _] -> record_shape_fields_from_value(acc, ctx)
        _ -> nil
      end
    else
      alias_shape_fields_from_typed_expr(expr, ctx)
    end
  end

  # `let next = case msg of … -> step …` — seed full Model fields from arm return
  # type so `next.best` is not access-inferred as singleton `{best}` → index 0.
  defp record_shape_fields_from_value(%{op: :case} = expr, ctx),
    do: alias_shape_fields_from_typed_expr(expr, ctx)

  defp record_shape_fields_from_value(%{op: :if} = expr, ctx),
    do: alias_shape_fields_from_typed_expr(expr, ctx)

  defp record_shape_fields_from_value(_, _ctx), do: nil

  @spec alias_shape_fields_from_typed_expr(Types.expr(), Context.t()) :: [String.t()] | nil

  defp alias_shape_fields_from_typed_expr(expr, ctx) when is_map(expr) do
    case TypedReturn.expr_type(expr, let_type_env(ctx)) do
      type when is_binary(type) -> alias_shape_fields_for_type(type, ctx)
      _ -> nil
    end
  end

  @spec alias_shape_fields_for_type(String.t(), Context.t()) :: [String.t()] | nil

  defp alias_shape_fields_for_type(type, ctx) when is_binary(type) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    ctor = type |> Host.normalize_type_name() |> String.split(~r/\s+/, parts: 2) |> hd()

    key =
      case String.split(ctor, ".") do
        parts when length(parts) >= 2 ->
          {mod_parts, [name]} = Enum.split(parts, -1)
          mod = Enum.join(mod_parts, ".")

          if Map.has_key?(shapes, {mod, name}),
            do: {mod, name},
            else: shape_key_by_record_name(shapes, name, ctx)

        _ ->
          shape_key_by_record_name(shapes, ctor, ctx)
      end

    case key do
      k when is_tuple(k) ->
        case Map.get(shapes, k) do
          fields when is_list(fields) and fields != [] -> Enum.map(fields, &to_string/1)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp shape_key_by_record_name(shapes, name, %Context{} = ctx)
       when is_map(shapes) and is_binary(name) do
    matches = Enum.filter(shapes, fn {{_mod, n}, _} -> n == name end)

    case matches do
      [{key, _}] ->
        key

      many when length(many) > 1 ->
        mod = ctx.module

        case Enum.find(many, fn {{m, _}, _} -> m == mod end) do
          {key, _} -> key
          _ -> elem(hd(many), 0)
        end

      _ ->
        nil
    end
  end

  defp shape_key_by_record_name(shapes, name, _ctx)
       when is_map(shapes) and is_binary(name) do
    case Enum.filter(shapes, fn {{_mod, n}, _} -> n == name end) do
      [{key, _}] -> key
      [first | _] -> elem(first, 0)
      _ -> nil
    end
  end

  @spec compile_letrec_value_bindings([{String.t(), Types.expr()}], Context.t(), Builder.t()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported

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

  @spec maybe_packed_text_options_expr(Types.expr()) :: Types.ir_expr()

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

  @spec maybe_put_local_type(Context.t(), String.t(), Types.expr(), Context.t()) :: Context.t()

  defp maybe_put_local_type(ctx, name, value_expr, parent_ctx) do
    case TypedReturn.expr_type(value_expr, let_type_env(parent_ctx)) do
      type when is_binary(type) -> Context.put_local_type(ctx, name, type)
      _ -> ctx
    end
  end

  @spec let_type_env(Context.t()) :: map()

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

  @spec let_param_var_types(Context.t() | term()) :: %{optional(String.t()) => String.t()}

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

  @spec compile_string_unary(String.t(), Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_string_unary("String.fromInt", arg, ctx, b) do
    arg_ctx = Context.for_branch_arm(ctx)

    with {:ok, arg_reg, b1} <- compile(arg, arg_ctx, b) do
      id =
        if peelable_int_reg?(arg_reg, b1, ctx) do
          :string_from_int
        else
          :string_from_int_value
        end

      compile_runtime_builtin(id, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @spec compile_qualified_unary(String.t(), Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_qualified_unary(target, arg, ctx, b) do
    case Map.get(@qualified_unary, target) do
      :debug_to_string ->
        # Arg must not write :fn_out — otherwise truncate_after_non_rc_tail_fn_out
        # drops the Debug.toString emit (CorpusHost quotes / Set.fromList prefix).
        arg_ctx = Context.for_branch_arm(ctx)

        with {:ok, arg_reg, b1} <- compile(arg, arg_ctx, b) do
          id =
            if debug_set_arg?(arg, ctx) do
              :debug_set_to_string
            else
              :debug_to_string
            end

          compile_runtime_builtin(id, [arg_reg], ctx, b1)
        else
          _ -> :unsupported
        end

      id when is_atom(id) and not is_nil(id) ->
        arg_ctx = Context.for_branch_arm(ctx)

        with {:ok, arg_reg, b1} <- compile(arg, arg_ctx, b) do
          compile_runtime_builtin(id, [arg_reg], ctx, b1)
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  @spec debug_set_arg?(Types.expr() | term(), Context.t()) :: boolean()

  defp debug_set_arg?(arg, ctx) do
    env = %{
      __module__: ctx.module || "Main",
      __function_name__: ctx.function_name,
      __var_types__: ctx.local_types,
      __program_decls__: ctx.decl_map
    }

    case Elmc.Backend.CCodegen.Native.TypedReturn.expr_type(arg, env) do
      type when is_binary(type) ->
        Elmc.Backend.CCodegen.TypeParsing.set_type?(type)

      _ ->
        case arg do
          %{op: :var, name: name} when is_binary(name) ->
            case Map.get(ctx.decl_map, {ctx.module, ctx.function_name}) do
              %{type: type, args: args} when is_binary(type) and is_list(args) ->
                with idx when is_integer(idx) <- Enum.find_index(args, &(&1 == name)),
                     param_type when is_binary(param_type) <-
                       Enum.at(Elmc.Backend.CCodegen.TypeParsing.function_arg_types(type), idx) do
                  Elmc.Backend.CCodegen.TypeParsing.set_type?(param_type)
                else
                  _ -> false
                end

              _ ->
                false
            end

          _ ->
            false
        end
    end
  end

  @spec compile_qualified_binary(atom(), Types.expr(), Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_qualified_binary(id, left, right, ctx, b) do
    with {:ok, [left_reg, right_reg], b1} <- compile_args([left, right], ctx, b) do
      compile_runtime_builtin(id, [left_reg, right_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @spec compile_qualified_ternary(
          atom(),
          Types.expr(),
          Types.expr(),
          Types.expr(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_qualified_ternary(id, a, b, c, ctx, builder) do
    with {:ok, [a_reg, b_reg, c_reg], b1} <- compile_args([a, b, c], ctx, builder) do
      compile_runtime_builtin(id, [a_reg, b_reg, c_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @spec compile_ternary_runtime(
          String.t(),
          Types.expr(),
          Types.expr(),
          Types.expr(),
          atom(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_ternary_runtime(_target, low, high, value, id, ctx, b) do
    with {:ok, [low_reg, high_reg, value_reg], b1} <- compile_args([low, high, value], ctx, b) do
      compile_runtime_builtin(id, [low_reg, high_reg, value_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @spec compile_field_values([map()], Context.t(), Builder.t()) ::
          {:ok, [Types.reg() | Types.result_slot()], Builder.t()} | :unsupported

  defp compile_field_values(fields, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)
    field_names = Enum.map(fields, &literal_field_name/1)
    types_by_name = literal_field_types_by_name(field_names)

    Enum.reduce_while(fields, {:ok, [], b}, fn field, {:ok, acc, b_acc} ->
      name = literal_field_name(field)
      expr = Map.get(field, :expr) || Map.get(field, :value)
      expected = Map.get(types_by_name, name)

      compile_result =
        case {expected, expr} do
          # Elm number polymorphism: `scale = 1` in a Float field must be TAG_FLOAT.
          # WASM otherwise boxes const_int via new_int → Int-in-Float-slot, and
          # later Basics.negate/as_float paths treat handle ids as scalars.
          {"Float", %{op: :int_literal, value: value} = lit}
          when is_integer(value) and not is_map_key(lit, :union_ctor) ->
            compile_runtime_builtin(:new_float, [], operand_ctx, b_acc, %{literal: value * 1.0})

          _ ->
            compile(expr, operand_ctx, b_acc)
        end

      case compile_result do
        {:ok, reg, b1} ->
          {kept, b2} =
            if is_integer(reg) do
              Builder.retain_reg_copy(b1, reg)
            else
              {reg, b1}
            end

          {:cont, {:ok, acc ++ [kept], b2}}

        _ ->
          {:halt, :unsupported}
      end
    end)
  end

  @spec literal_field_name(map()) :: String.t()

  defp literal_field_name(field) do
    (Map.get(field, :name) || Map.get(field, :field) || "") |> to_string()
  end

  # Resolve Float/Int/Bool per field when the literal's field set matches one or
  # more registered type-alias shapes. If several aliases share the field set
  # (Point3d / Direction3d / Vector3d all use {x,y,z}), keep a type only when
  # every match agrees — that still catches Float number-polymorphism.
  @spec literal_field_types_by_name([String.t()]) :: %{optional(String.t()) => String.t()}

  defp literal_field_types_by_name(field_names) when is_list(field_names) do
    name_set = MapSet.new(Enum.map(field_names, &to_string/1))
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    types = Process.get(:elmc_record_field_types, %{})

    matches =
      shapes
      |> Enum.filter(fn {_key, shape} ->
        is_list(shape) and MapSet.equal?(MapSet.new(Enum.map(shape, &to_string/1)), name_set)
      end)
      |> Enum.map(fn {key, _} -> Map.get(types, key, %{}) end)
      |> Enum.reject(&(&1 == %{}))

    case matches do
      [] ->
        %{}

      [only] ->
        Map.new(only, fn {k, v} -> {to_string(k), Host.normalize_type_name(v)} end)

      many ->
        keys =
          many
          |> Enum.map(fn m ->
            m |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()
          end)
          |> Enum.reduce(&MapSet.intersection/2)

        Enum.reduce(keys, %{}, fn name, acc ->
          agreed =
            many
            |> Enum.map(fn m ->
              Host.normalize_type_name(Map.get(m, name) || Map.get(m, to_string(name)))
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          case agreed do
            [type] when is_binary(type) and type != "" -> Map.put(acc, name, type)
            _ -> acc
          end
        end)
    end
  end

  @spec int_record_literal_fields?(list()) :: boolean()

  defp int_record_literal_fields?(fields) when is_list(fields) do
    # Prefer expr shape over unscoped field-name Int lookup: the same field name
    # can be Int in one record type and a Point/record in another.
    # Only use record_new_values_ints when every field is a known Int. Number
    # literals in Float records (Direction3d {x=0,y=0,z=1}, Transformation)
    # must go through new_float + record_new instead.
    field_names = Enum.map(fields, &literal_field_name/1)
    types_by_name = literal_field_types_by_name(field_names)

    exprs_ok? =
      Enum.all?(fields, fn field ->
        expr = Map.get(field, :expr) || Map.get(field, :value)
        # Typed Int fields may be bare vars (params/lets); literals/ops still required
        # when the registered field type is not known to be Int.
        # Field reads + Int arith (`labelPoint.x - 9`) are allowed only here — the
        # record being built already checked every field type is Int.
        int_record_expr?(expr) or match?(%{op: :var}, expr) or int_record_field_arith?(expr)
      end)

    typed_int? =
      types_by_name != %{} and
        Enum.all?(field_names, fn name -> Map.get(types_by_name, name) == "Int" end)

    # When {x,y} is Int in one alias and Float in another, type intersection is
    # empty. Int arith (`w // 2`, `cx + dx`) still proves the fields are Int —
    # unlike bare `0` literals or field reads, which must stay Float in
    # Direction3d/{x,y,z} and Vec2.
    proven_int_ops? =
      Enum.all?(fields, fn field ->
        expr = Map.get(field, :expr) || Map.get(field, :value)
        int_record_proven_arith?(expr)
      end)

    fields != [] and exprs_ok? and (typed_int? or proven_int_ops?)
  end

  # Top-level Int proof for untyped {x,y} literals. Bare field reads are not
  # enough — they may be Float. Nested field reads inside + / // are fine.
  @spec int_record_proven_arith?(map() | term()) :: boolean()

  defp int_record_proven_arith?(%{op: :call, name: name, args: args}) when is_list(args) do
    int_record_proven_call_args?(name, args)
  end

  defp int_record_proven_arith?(%{op: :qualified_call, target: target, args: args})
       when is_list(args) do
    int_call_target?(target) and int_record_proven_call_args?(call_target_short_name(target), args)
  end

  defp int_record_proven_arith?(%{op: op})
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
              :rem_vars
            ],
       do: true

  defp int_record_proven_arith?(_), do: false

  # `+`/`*`/`-`/`max`/`min` are Float as well as Int. Only idiv/mod/rem prove
  # Int when operands are field reads (Vec2 `{x = a.x + b.x}` must stay boxed).
  @spec int_record_proven_call_args?(String.t(), list()) :: boolean()

  defp int_record_proven_call_args?(name, args) when is_binary(name) and is_list(args) do
    operands_ok? = fn arg ->
      int_record_expr?(arg) or int_record_field_arith?(arg) or match?(%{op: :var}, arg)
    end

    cond do
      name in ["modBy", "remainderBy", "__idiv__"] ->
        Enum.all?(args, operands_ok?)

      # `+`/`*`/`-`/`max`/`min` are Float as well as Int. `a.x + b.x` (Vec2)
      # must stay boxed; `p0.x + ((p1.x - p0.x) * r) // 5` is Int because of `//`.
      name in ["max", "min", "__mul__", "__add__", "__sub__"] ->
        Enum.all?(args, operands_ok?) and Enum.any?(args, &int_record_int_only_operand?/1)

      true ->
        false
    end
  end

  defp int_record_proven_call_args?(_, _), do: false

  @spec int_record_int_only_operand?(map() | term()) :: boolean()

  defp int_record_int_only_operand?(expr),
    do: int_record_expr?(expr) or int_record_contains_idiv_or_mod?(expr)

  @spec int_record_contains_idiv_or_mod?(map() | term()) :: boolean()

  defp int_record_contains_idiv_or_mod?(%{op: :call, name: name, args: args}) when is_list(args) do
    name in ["modBy", "remainderBy", "__idiv__"] or
      Enum.any?(args, &int_record_contains_idiv_or_mod?/1)
  end

  defp int_record_contains_idiv_or_mod?(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    String.contains?(target, "modBy") or String.contains?(target, "remainderBy") or
      String.contains?(target, "__idiv__") or
      Enum.any?(args, &int_record_contains_idiv_or_mod?/1)
  end

  defp int_record_contains_idiv_or_mod?(%{op: op})
       when op in [:idiv_vars, :mod_vars, :rem_vars],
       do: true

  defp int_record_contains_idiv_or_mod?(_), do: false

  @spec call_target_short_name(String.t()) :: String.t()

  defp call_target_short_name(target) when is_binary(target) do
    case String.split(target, ".") do
      [] -> target
      parts -> Enum.at(parts, -1)
    end
  end

  # Int record literal field values like `labelPoint.x - 9` / `p.y`.
  @spec int_record_field_arith?(map() | term()) :: boolean()

  defp int_record_field_arith?(%{op: :field_access, field: field}) when is_binary(field), do: true

  defp int_record_field_arith?(%{op: :call, name: name, args: args}) when is_list(args) do
    name in ["max", "min", "modBy", "remainderBy", "__idiv__", "__mul__", "__add__", "__sub__"] and
      Enum.all?(args, fn arg ->
        int_record_expr?(arg) or int_record_field_arith?(arg) or match?(%{op: :var}, arg)
      end)
  end

  defp int_record_field_arith?(%{op: :qualified_call, target: target, args: args})
       when is_list(args) do
    int_call_target?(target) and
      Enum.all?(args, fn arg ->
        int_record_expr?(arg) or int_record_field_arith?(arg) or match?(%{op: :var}, arg)
      end)
  end

  defp int_record_field_arith?(%{op: op})
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

  defp int_record_field_arith?(_), do: false

  @spec int_record_shape?(list()) :: boolean()

  defp int_record_shape?(field_names) when is_list(field_names) do
    _ = field_names
    false
  end

  @spec int_record_expr?(map() | term()) :: boolean()

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

  # Point.x / Rect field reads used in Int record literals
  # (`{ x = labelPoint.x - 9, … }`). Keep this false for general
  # int_record_expr? — tuple2_ints_eligible? also calls it and must not treat
  # Maybe/Result record fields as ints.
  defp int_record_expr?(%{op: :field_access, arg: arg, field: field})
       when is_binary(field) and is_map(arg),
       do: int_record_expr?(arg)

  defp int_record_expr?(%{op: :field_access, arg: arg, field: field})
       when is_binary(field) and is_binary(arg),
       do: false

  defp int_record_expr?(_), do: false

  @spec int_call_target?(String.t()) :: boolean()

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

  @spec compile_runtime_call(Types.runtime_call_input() | map() | Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_runtime_call(%{function: "elmc_list_repeat", args: args}, ctx, b) do
    case fold_list_repeat_literals(args, ctx, b) do
      {:ok, reg, b1} ->
        {:ok, reg, b1}

      :error ->
        compile_runtime_call_default(%{function: "elmc_list_repeat", args: args}, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_concat"} = expr, ctx, b) do
    if Context.stream_mode?(ctx) do
      case Elmc.Backend.Plan.Lower.Stream.List.try_compile_runtime(expr, ctx, b) do
        {:ok, _, _} = ok -> ok
        :unsupported -> compile_runtime_call_default(expr, ctx, b)
      end
    else
      compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: function} = expr, ctx, b)
       when function in ["elmc_list_map", "elmc_list_concat_map", "elmc_list_indexed_map"] do
    if Context.stream_mode?(ctx) do
      case Elmc.Backend.Plan.Lower.Stream.List.try_compile_runtime(expr, ctx, b) do
        {:ok, _, _} = ok -> ok
        :unsupported -> compile_runtime_call_default(expr, ctx, b)
      end
    else
      compile_value_list_map(function, expr, ctx, b)
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

  defp compile_runtime_call(%{function: fun} = expr, ctx, b)
       when fun in ["elmc_tuple_map_first", "elmc_tuple_map_second", "elmc_tuple_map_both"] do
    case Elmc.Backend.Plan.Lower.TupleMap.try_compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.PebbleWatchTrig.try_compile_runtime_call(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_value_list_map("elmc_list_map", expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListCursor.try_compile_map(expr, ctx, b) do
      {:ok, reg, b1} ->
        {:ok, reg, b1}

      :unsupported ->
        case Elmc.Backend.Plan.Lower.ListRecord.try_compile_map(expr, ctx, b) do
          {:ok, reg, b1} -> {:ok, reg, b1}
          :unsupported -> compile_runtime_call_default(expr, ctx, b)
        end
    end
  end

  defp compile_value_list_map(_function, expr, ctx, b), do: compile_runtime_call_default(expr, ctx, b)

  @spec compile_runtime_call_default(map() | term(), Context.t(), Builder.t()) ::
          Types.compile_result()

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

  @spec compile_call_args([Types.expr()] | term(), Context.t(), Builder.t()) ::
          {:ok, [Types.reg()], Builder.t() | nil} | :unsupported

  defp compile_call_args(args, ctx, b) when is_list(args) do
    compile_args(args, ctx, b)
  end

  defp compile_call_args(_, _, _), do: {:ok, [], nil}

  @spec fold_list_repeat_literals([Types.expr()] | term(), Context.t(), Builder.t()) ::
          {:ok, Types.lower_result_slot(), Builder.t()} | :error

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

  @spec fold_list_repeat_count(Types.expr(), Context.t()) :: {:ok, integer()} | :error

  defp fold_list_repeat_count(%{op: :int_literal, value: count}, _ctx) when is_integer(count),
    do: {:ok, count}

  defp fold_list_repeat_count(expr, ctx) do
    ConstantInt.literal_value(expr, constant_int_env(ctx))
  end

  @spec fold_list_repeat_item(Types.expr(), Context.t()) :: {:ok, integer()} | :error

  defp fold_list_repeat_item(%{op: :int_literal, value: item}, _ctx) when is_integer(item),
    do: {:ok, item}

  defp fold_list_repeat_item(expr, ctx) do
    ConstantInt.literal_value(expr, constant_int_env(ctx))
  end

  @spec constant_int_env(Context.t()) :: Types.compile_env()

  defp constant_int_env(%Context{module: mod, decl_map: decl_map}) do
    %{
      __module__: mod,
      __program_decls__: decl_map,
      __literal_int_bindings__: %{}
    }
  end

  @doc false
  @spec compile_const_static_list(term(), Context.t(), Builder.t()) :: Types.compile_result()

  def compile_const_static_list(spec, ctx, b) do
    # Value/record-array list builders borrow elements and retain inside the runtime
    # (`elmc_list_from_values` / `elmc_list_from_record_array`). Do not retain-dup
    # + consume — that added a retain hop only so take-based builders could null
    # copies while originals stayed live.
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

  @spec static_list_instr(term(), Types.reg() | Types.result_slot()) ::
          {Types.instr_args(), Types.effects()}

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
    {%{kind: :values, regs: regs}, Types.fallible_effects(dest, regs, [])}
  end

  defp static_list_instr({:record_array, regs}, dest) when is_list(regs) do
    {%{kind: :record_array, regs: regs}, Types.fallible_effects(dest, regs, [])}
  end

  @doc false
  @borrow_view_builtins [:union_payload, :maybe_just_payload]

  @borrow_list_view_builtins [
    :list_head,
    :int_list_head_int,
    :int_list_head_boxed,
    :list_nth_int_at,
    :list_is_empty,
    :list_length
  ]

  @spec compile_runtime_builtin(
          atom(),
          [Types.reg()],
          Context.t(),
          Builder.t(),
          map()
        ) :: Types.compile_result()

  def compile_runtime_builtin(id, arg_regs, ctx, b, extra \\ %{}) do
    if id in @borrow_view_builtins do
      compile_borrow_view_builtin(id, arg_regs, ctx, b, extra)
    else
      compile_runtime_builtin_core(id, arg_regs, ctx, b, extra)
    end
  end

  @spec compile_borrow_view_builtin(
          atom(),
          [Types.reg()],
          Context.t(),
          Builder.t(),
          map()
        ) :: Types.compile_reg_result()

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
            effects: %{
              produces: {:owned, owned},
              consumes: [],
              borrows: arg_regs,
              fallible: false
            }
          })

        {:ok, owned, b2}
    end
  end

  @spec compile_runtime_builtin_core(
          atom(),
          [Types.reg()],
          Context.t(),
          Builder.t(),
          map()
        ) :: Types.compile_result()

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
          Builder.dup_all_regs_for_record_new_consume(b2, arg_regs)

        id in [:tuple2, :tuple2_take, :list_cons, :list_append, :cmd_batch, :sub_batch] ->
          # Named locals from pattern_bind (record_get / tuple_proj) would otherwise
          # stay as borrows — EpilogueRelease then frees them while they are nested
          # under the published result. Retain-dup named locals, then consume all args.
          Builder.dup_named_locals_for_consume(b2, arg_regs)

        id in @hof_consumes_last_operand ->
          # Runtime releases the last operand (elmc_maybe_and_then / result_and_then).
          # Retain-dup params and named locals so later borrows of the same value
          # (e.g. Maybe.map2 (andThen .a x) (map .b x)) do not read_after_consume.
          retain_last_hof_operand_if_borrowed(b2, arg_regs)

        true ->
          {arg_regs, b2}
      end

    {borrows, consumes} =
      cond do
        RuntimeBuiltins.retains_operand_result?(id) ->
          {arg_regs, []}

        id in @borrow_list_view_builtins and length(arg_regs) == 1 ->
          {arg_regs, []}

        id in [:record_new, :record_new_take, :record_new_values_ints] -> {[], arg_regs}
        id in [:tuple2, :tuple2_take] -> {[], arg_regs}
        id in [:list_cons, :list_append] -> {[], arg_regs}
        id in [:cmd_batch, :sub_batch] -> {[], arg_regs}
        id in [:debug_to_string, :debug_set_to_string] -> {[], arg_regs}
        id in [:char_from_code] -> {[], arg_regs}
        id in [:string_length_boxed] -> {arg_regs, []}
        id == :tuple2_ints -> {arg_regs, []}
        id in @hof_closure_last_arg ->
          case arg_regs do
            args when length(args) >= 1 ->
              {prefix, [last]} = Enum.split(args, -1)
              {borrows, prefix_consumes} = Builder.partition_call_args(b2a, prefix)

              if id in @hof_consumes_last_operand do
                # Runtime releases only the last operand (Maybe/Result). Keep the
                # callback as a borrow so emit releases it (transfer-null would leak).
                {borrows ++ prefix, [last]}
              else
                if Builder.borrow_arg?(b2a, last) do
                  {borrows ++ [last], prefix_consumes}
                else
                  {borrows, prefix_consumes ++ [last]}
                end
              end

            _ ->
              Builder.partition_call_args(b2a, arg_regs)
          end

        true ->
          Builder.partition_call_args(b2a, arg_regs)
      end

    result_aliases =
      if RuntimeBuiltins.retains_operand_result?(id) do
        RuntimeBuiltins.retains_operand_result_aliases(id, arg_regs)
      else
        []
      end

    effects =
      cond do
        is_integer(dest) and RuntimeBuiltins.retains_operand_result?(id) ->
          Types.retains_operand_effects(dest, borrows, result_aliases, consumes, fallible?)

        is_integer(dest) and fallible? ->
          Types.fallible_effects(dest, borrows, consumes)

        is_integer(dest) ->
          %{
            produces: {:owned, dest},
            consumes: consumes,
            borrows: borrows,
            result_aliases: [],
            fallible: false
          }

        RuntimeBuiltins.retains_operand_result?(id) ->
          %{
            produces: nil,
            consumes: consumes,
            borrows: borrows,
            result_aliases: result_aliases,
            fallible: fallible?
          }

        true ->
          %{produces: nil, consumes: consumes, borrows: borrows, result_aliases: [], fallible: fallible?}
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

  @spec dest_for_builtin(Context.t(), Builder.t()) ::
          {Types.reg() | Types.result_slot(), Builder.t()}

  defp dest_for_builtin(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end

  @spec compile_tuple2_pair(Types.expr(), Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_tuple2_pair(left, right, ctx, b) do
    operand_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, l, b1} <- compile(left, operand_ctx, b),
         {:ok, r, b2} <- compile(right, operand_ctx, b1) do
      # Prefer tuple2_ints when IR is int-shaped OR both compiled regs are already
      # native-int producers (e.g. Int params through `__add__`).
      if tuple2_ints_eligible?(left, right, ctx) or
           (native_int_reg_producer?(b2, l, ctx) and native_int_reg_producer?(b2, r, ctx)) do
        compile_runtime_builtin(:tuple2_ints, [l, r], ctx, b2)
      else
        compile_runtime_builtin(:tuple2, [l, r], ctx, b2)
      end
    else
      _ -> :unsupported
    end
  end

  defp native_int_reg_producer?(b, reg, ctx) when is_integer(reg) do
    block_instrs =
      Enum.flat_map(b.blocks, fn
        %{instrs: is} when is_list(is) -> is
        _ -> []
      end)

    current_instrs =
      case Map.get(b, :current_block) do
        %{instrs: is} when is_list(is) -> is
        _ -> []
      end

    case Enum.find(block_instrs ++ current_instrs, &(&1.dest == reg)) do
      %{op: op} when op in [:const_int, :int_arith, :record_get_int, :boxed_tag_peel] ->
        true

      %{op: :load_param, args: %{index: idx}} when is_integer(idx) ->
        native_int_param_index?(idx, ctx)

      %{op: :call_runtime, args: %{builtin: :new_int}} ->
        true

      _ ->
        false
    end
  end

  defp native_int_reg_producer?(_, _, _), do: false

  @spec tuple2_ints_eligible?(Types.expr(), Types.expr(), Context.t()) :: boolean()

  defp tuple2_ints_eligible?(left, right, ctx) do
    tuple2_int_pair_operand?(left, ctx) and tuple2_int_pair_operand?(right, ctx) and
      not render_op_boxed_payload?(left, right)
  end

  @spec tuple2_int_pair_operand?(Types.expr(), Context.t()) :: boolean()

  defp tuple2_int_pair_operand?(%{op: :int_literal, union_ctor: ctor}, _ctx) when is_binary(ctor),
    do: false

  defp tuple2_int_pair_operand?(expr, ctx) do
    int_record_expr?(expr) or
      (native_int_operand_expr?(expr, ctx) and not field_access_expr?(expr))
  end

  @spec field_access_expr?(map() | term()) :: boolean()

  defp field_access_expr?(%{op: :field_access}), do: true
  defp field_access_expr?(_), do: false

  @spec constructor_ref_arity(String.t(), Context.t()) :: non_neg_integer()

  defp constructor_ref_arity(target, ctx) when is_binary(target) do
    specs = Process.get(:elmc_union_constructor_payload_specs, %{})
    short = target |> String.split(".") |> Enum.at(-1)
    mod = ctx && Map.get(ctx, :module)

    keys =
      cond do
        String.contains?(target, ".") ->
          parts = String.split(target, ".")
          name = Enum.at(parts, -1)
          home = parts |> Enum.drop(-1) |> Enum.join(".")
          [{home, name}, {home, short}]

        is_binary(mod) ->
          [{mod, target}, {mod, short}]

        true ->
          []
      end

    # Multi-arg ctors (`OpaqueMeshNode Bounds DrawFunction`) must keep full
    # Elm arity so bare refs lower to arity-N partials, not a unary wrapper.
    case Enum.find_value(keys, &Map.get(specs, &1)) ||
           Enum.find_value(specs, fn
             {{_mod, name}, spec} when name == short and is_binary(spec) -> spec
             _ -> nil
           end) do
      spec when is_binary(spec) -> PebbleUtil.payload_arity_for_spec(spec)
      _ -> 0
    end
  end

  # Render-op tuples (pathFilled, pathOutline, group, …) carry boxed payloads; never
  # lower them to tuple2_ints even when the payload is a bare var in IR.
  @spec render_op_boxed_payload?(Types.expr(), Types.expr()) :: boolean()

  defp render_op_boxed_payload?(left, right) do
    render_op_kind_expr?(left) and boxed_payload_operand?(right)
  end

  @spec render_op_kind_expr?(map() | term()) :: boolean()

  defp render_op_kind_expr?(%{op: :c_int_expr, value: value}) when is_binary(value),
    do: String.starts_with?(value, "ELMC_RENDER_OP_")

  defp render_op_kind_expr?(_), do: false

  @spec boxed_payload_operand?(map() | term()) :: boolean()

  defp boxed_payload_operand?(%{op: op}) when op in [:var, :call, :qualified_call], do: true
  defp boxed_payload_operand?(_), do: false

  @spec native_int_operand_expr?(Types.expr() | term(), Context.t()) :: boolean()

  defp native_int_operand_expr?(%{op: op}, _ctx) when op in [:int_literal, :c_int_expr, :msg_tag_expr],
    do: true

  defp native_int_operand_expr?(%{op: :field_access}, _ctx), do: true

  defp native_int_operand_expr?(%{op: :var, name: name}, ctx) when is_binary(name) do
    case Enum.find_index(ctx.params, &(&1 == name)) do
      idx when is_integer(idx) -> native_int_param_index?(idx, ctx)
      _ -> false
    end
  end

  defp native_int_operand_expr?(%{op: op}, _ctx) when op in [:add_const, :sub_const, :add_vars, :sub_vars], do: true

  defp native_int_operand_expr?(%{op: :constructor_call, args: []}, _ctx), do: true

  defp native_int_operand_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, ctx),
    do: native_int_operand_expr?(then_expr, ctx) and native_int_operand_expr?(else_expr, ctx)

  defp native_int_operand_expr?(_, _ctx), do: false

  @spec peelable_int_reg?(Types.reg(), Builder.t(), Context.t()) :: boolean()

  def peelable_int_reg?(reg, b, ctx) when is_integer(reg) do
    instrs =
      Enum.flat_map(Map.get(b, :blocks, []), & &1.instrs) ++
        case Map.get(b, :current_block) do
          %{instrs: cur} when is_list(cur) -> cur
          _ -> []
        end

    case Enum.find(instrs, &(&1.dest == reg)) do
      %{op: op} when op in [:const_int, :int_arith, :record_get_int, :const_c_expr] ->
        true

      %{op: :phi, args: args} ->
        Map.get(args, :native_int_phi) == true

      %{op: :call_runtime, args: %{builtin: :new_int}} ->
        true

      %{op: :load_param, args: %{index: idx}} when is_integer(idx) ->
        native_int_param_index?(idx, ctx)

      %{op: :call_fn, args: %{module: mod, name: name}}
      when is_binary(mod) and is_binary(name) ->
        Elmc.Backend.C.Lower.NativeReturn.cached_kind({mod, name}) == :native_int

      _ ->
        false
    end
  end

  def peelable_int_reg?(_, _, _), do: false

  @spec native_int_param_index?(non_neg_integer(), Context.t()) :: boolean()

  defp native_int_param_index?(idx, ctx) do
    case Map.get(ctx.decl_map, {ctx.module, ctx.function_name}) do
      decl when is_map(decl) ->
        decl = %{decl | args: FunctionEmit.effective_decl_args(decl, ctx.module, ctx.decl_map)}
        Enum.at(FunctionCall.arg_kinds(decl, ctx.module, ctx.decl_map), idx) == :native_int

      _ ->
        false
    end
  end

  @spec port_decl_type(Context.t(), String.t()) :: String.t() | nil

  defp port_decl_type(ctx, name) do
    case Map.get(ctx.decl_map, {ctx.module || "Main", name}) do
      %{type: type} when is_binary(type) -> type
      decl when is_map(decl) -> Map.get(decl, :return_type)
      _ -> nil
    end
  end

  @spec compare_op_kind(String.t()) :: Types.compare_kind()

  defp compare_op_kind("__eq__"), do: :eq
  defp compare_op_kind("__neq__"), do: :neq
  defp compare_op_kind("__lt__"), do: :lt
  defp compare_op_kind("__lte__"), do: :lte
  defp compare_op_kind("__gt__"), do: :gt
  defp compare_op_kind("__gte__"), do: :gte
end
