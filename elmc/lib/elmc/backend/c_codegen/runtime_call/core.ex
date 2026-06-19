defmodule Elmc.Backend.CCodegen.RuntimeCall.Core do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.CodegenListHelpers
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.ListLoopCodegen
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ImmortalStaticList
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.Native.Float, as: NativeFloat
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Native.TypedReturn, as: NativeTypedReturn
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.VarAnalysis

  @float_unary_functions ~w(
    elmc_basics_to_float elmc_basics_sin elmc_basics_cos elmc_basics_tan
    elmc_basics_sqrt elmc_basics_abs elmc_basics_negate
  )a

  @min_list_append_concat_segments 3
  @compare_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)

  @retaining_runtime_functions MapSet.new(~w(elmc_list_cons))

  @spec flatten_append_ir(Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          Types.ir_expr()
  def flatten_append_ir(left, right, env \\ %{}) do
    append_expr = %{op: :runtime_call, function: "elmc_append", args: [left, right]}

    case collect_append_segments(append_expr) do
      {:ok, segments} when length(segments) >= @min_list_append_concat_segments ->
        if list_append_concat_segments?(segments, env) do
          %{
            op: :runtime_call,
            function: "elmc_list_concat",
            args: [%{op: :list_literal, items: segments}]
          }
        else
          append_expr
        end

      _ ->
        append_expr
    end
  end

  @spec compile(Types.ir_runtime_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env, counter) do
    append_expr = %{op: :runtime_call, function: "elmc_append", args: [left, right]}

    cond do
      NativeString.expr?(left, env) and NativeString.expr?(right, env) ->
        compile_native_append(left, right, env, counter)

      true ->
        {:ok, segments} = collect_append_segments(append_expr)

        if length(segments) >= @min_list_append_concat_segments and
             list_append_concat_segments?(segments, env) do
          compile_list_concat(segments, env, counter)
        else
          compile_generic(append_expr, env, counter)
        end
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: function,
          args: [predicate, list]
        } = expr,
        env,
        counter
      )
      when function in ["elmc_list_all", "elmc_list_any"] do
    case compile_list_bool_expr(function, predicate, list, env, counter) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      :error ->
        compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_map",
          args: [lambda, list]
        } = expr,
        env,
        counter
      ) do
    case two_arg_lambda(lambda) do
      {:ok, left, right, body} ->
        case compile_list_map_tuple2_native_int_cursor_loop(left, right, body, list, env, counter) do
          {:ok, code, out, counter} -> {code, out, counter}
          :error -> compile_generic(expr, env, counter)
        end

      :error ->
        case lambda do
          %{op: :lambda, args: [arg], body: body} when is_binary(arg) ->
            case unwrap_tuple2_lambda_body(body, arg) do
              {:ok, left, right, inner} ->
                case compile_list_map_tuple2_native_int_cursor_loop(
                       left,
                       right,
                       inner,
                       list,
                       env,
                       counter
                     ) do
                  {:ok, code, out, counter} -> {code, out, counter}
                  :error -> compile_generic(expr, env, counter)
                end

              :error ->
                case compile_list_map_int_range_loop(arg, body, list, env, counter) do
                  {:ok, code, out, counter} ->
                    {code, out, counter}

                  :error ->
                    case compile_list_map_native_int_cursor_loop(arg, body, list, env, counter) do
                      {:ok, code, out, counter} ->
                        {code, out, counter}

                      :error ->
                        {:ok, code, out, counter} =
                          compile_list_map_boxed_cursor_loop(arg, body, list, env, counter)

                        {code, out, counter}
                    end
                end
            end

          _ ->
            compile_generic(expr, env, counter)
        end
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_indexed_map",
          args: [%{op: :lambda} = lambda, list]
        } = expr,
        env,
        counter
      ) do
    with {:ok, index_arg, item_arg, body} <- two_arg_lambda(lambda),
         {:ok, code, out, counter} <-
           compile_list_indexed_map_int_loop(index_arg, item_arg, body, list, env, counter) do
      {code, out, counter}
    else
      _ ->
        with {:ok, index_arg, item_arg, body} <- two_arg_lambda(lambda),
             {:ok, code, out, counter} <-
               compile_list_indexed_map_boxed_cursor_loop(
                 index_arg,
                 item_arg,
                 body,
                 list,
                 env,
                 counter
               ) do
          {code, out, counter}
        else
          _ -> compile_generic(expr, env, counter)
        end
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_foldl",
          args: [lambda, acc, list]
        } = expr,
        env,
        counter
      ) do
    case normalize_foldl_lambda(lambda) do
      {:ok, item_arg, acc_arg, body} ->
        case compile_list_foldl_int_range_loop(
               item_arg,
               acc_arg,
               body,
               acc,
               list,
               env,
               counter,
               false
             ) do
          {:ok, code, out, counter} ->
            {code, out, counter}

          :error ->
            {:ok, code, out, counter} =
              compile_list_foldl_list_cursor_loop(
                item_arg,
                acc_arg,
                body,
                acc,
                list,
                env,
                counter
              )

            {code, out, counter}
        end

      :error ->
        compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_filter",
          args: [predicate, list]
        } = expr,
        env,
        counter
      ) do
    case compile_list_filter_expr(predicate, list, env, counter) do
      {:ok, code, out, counter} -> {code, out, counter}
      :error -> compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_filter_map",
          args: [lambda, list]
        } = expr,
        env,
        counter
      ) do
    case compile_list_filter_map_expr(lambda, list, env, counter) do
      {:ok, code, out, counter} -> {code, out, counter}
      :error -> compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_repeat",
          args: [n, value]
        },
        env,
        counter
      ) do
    {:ok, code, out, counter} = compile_list_repeat_int(n, value, env, counter)
    {code, out, counter}
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_length",
          args: [list]
        },
        env,
        counter
      ) do
    {:ok, code, out, counter} = compile_list_length_int(list, env, counter)
    {code, out, counter}
  end

  def compile(
        %{
          op: :runtime_call,
          function: function,
          args: [count, list]
        } = expr,
        env,
        counter
      )
      when function in ["elmc_list_take", "elmc_list_drop"] do
    if NativeInt.expr?(count, env) do
      compile_list_slice_int(function, count, list, env, counter)
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_reverse",
          args: [list_expr]
        } = expr,
        env,
        counter
      ) do
    case compile_list_reverse_expr(list_expr, env, counter) do
      {:ok, code, out, counter} -> {code, out, counter}
      :error -> compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_concat",
          args: [lists_expr]
        } = expr,
        env,
        counter
      ) do
    case compile_list_concat_expr(lists_expr, env, counter) do
      {:ok, code, out, counter} -> {code, out, counter}
      :error -> compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
        env,
        counter
      ) do
    NativeInt.compile_boxed(%{op: :call, name: "modBy", args: [base, value]}, env, counter)
  end

  def compile(
        %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
        env,
        counter
      ) do
    NativeInt.compile_boxed(%{op: :call, name: "remainderBy", args: [base, value]}, env, counter)
  end

  def compile(
        %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr,
        env,
        counter
      ) do
    if NativeInt.expr?(value, env) do
      {value_code, value_ref, counter} = Host.compile_native_int_expr(value, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
        #{value_code}
          #{RcRuntimeEmit.assign_or_fusion(env, out, "elmc_string_from_native_int", value_ref)}
      """

      {code, out, next}
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{op: :runtime_call, function: function, args: [left, right]} = expr,
        env,
        counter
      )
      when function in ["elmc_basics_min", "elmc_basics_max"] do
    if NativeInt.expr?(left, env) and NativeInt.expr?(right, env) do
      NativeInt.compile_boxed(
        %{op: :call, name: NativeInt.native_min_max_name(function), args: [left, right]},
        env,
        counter
      )
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{op: :runtime_call, function: function, args: [value]} = expr,
        env,
        counter
      )
      when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    cond do
      NativeInt.expr?(value, env) ->
        NativeInt.compile_boxed(
          %{op: :call, name: NativeInt.native_unary_int_name(function), args: [value]},
          env,
          counter
        )

      NativeFloat.expr?(expr, env) ->
        NativeFloat.compile_boxed(expr, env, counter)

      true ->
        compile_generic(expr, env, counter)
    end
  end

  def compile(%{op: :runtime_call, function: function, args: [value]} = expr, env, counter)
      when function in @float_unary_functions do
    if NativeFloat.expr?(value, env) do
      NativeFloat.compile_boxed(expr, env, counter)
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_nth_int_default_boxed",
          args: [list, index, default_val]
        },
        env,
        counter
      ) do
    case ImmortalStaticList.static_immortal_int_list(list, env) do
      {:ok, spec} ->
        {index_code, index_ref, counter} =
          if NativeInt.expr?(index, env) do
            Host.compile_native_int_expr(index, env, counter)
          else
            Host.compile_expr(index, env, counter)
          end

        {default_code, default_ref, counter} = Host.compile_expr(default_val, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        code =
          ImmortalStaticList.compile_static_int_list_nth_boxed(
            spec,
            index_code,
            index_ref,
            default_code,
            default_ref,
            out
          )

        {code, out, next}

      :error ->
        compile_generic(
          %{
            op: :runtime_call,
            function: "elmc_list_nth_int_default_boxed",
            args: [list, index, default_val]
          },
          env,
          counter
        )
    end
  end

  def compile(%{op: :runtime_call, function: "elmc_debug_to_string", args: [value]}, env, counter) do
    function =
      if debug_set_value?(value, env) do
        "elmc_debug_set_to_string"
      else
        "elmc_debug_to_string"
      end

    compile_generic(%{op: :runtime_call, function: function, args: [value]}, env, counter)
  end

  def compile(%{op: :runtime_call, function: function, args: args}, env, counter) do
    compile_generic(%{op: :runtime_call, function: function, args: args}, env, counter)
  end

  @spec compile_native_append(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp collect_append_segments(expr) do
    case unwrap_append(expr) do
      {:append, left, right} ->
        with {:ok, left_segments} <- collect_append_segments(left),
             {:ok, right_segments} <- collect_append_segments(right) do
          {:ok, left_segments ++ right_segments}
        end

      {:leaf, leaf} ->
        {:ok, [leaf]}
    end
  end

  defp unwrap_append(%{op: :runtime_call, function: "elmc_append", args: [left, right]}),
    do: {:append, left, right}

  defp unwrap_append(%{op: :call, name: "__append__", args: [left, right]}),
    do: {:append, left, right}

  defp unwrap_append(expr), do: {:leaf, expr}

  defp list_append_concat_segments?(segments, env) do
    Enum.all?(segments, fn segment ->
      not NativeString.expr?(segment, env) and not NativeString.boxed_expr?(segment, env)
    end)
  end

  defp compile_list_concat(segments, env, counter) do
    case compile_list_concat_segments_flatten(segments, env, counter) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      :error ->
        compile_generic(
          %{
            op: :runtime_call,
            function: "elmc_list_concat",
            args: [%{op: :list_literal, items: segments}]
          },
          env,
          counter
        )
    end
  end

  @spec compile_list_concat_segments_flatten(
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defp compile_list_concat_segments_flatten(segments, env, counter) do
    cond do
      Enum.all?(segments, &NativeString.expr?(&1, env)) ->
        compile_string_concat_segments(segments, env, counter)

      Enum.all?(segments, &NativeString.boxed_expr?(&1, env)) ->
        compile_boxed_string_append_chain(segments, env, counter)

      list_append_concat_segments?(segments, env) ->
        {segment_code, segment_vars, counter} =
          Enum.reduce(segments, {"", [], counter}, fn segment, {code_acc, vars_acc, c} ->
            {code, var, c2} = Host.compile_expr(segment, env, c)
            {code_acc <> code, vars_acc ++ [var], c2}
          end)

        next = counter + 1
        out = "tmp_#{next}"
        segments_array = "list_concat_segments_#{next}"
        call_args = Enum.join(segment_vars, ", ")

        releases =
          segment_vars
          |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

        code = """
        #{segment_code}
          ElmcValue *#{segments_array}[#{length(segment_vars)}] = { #{call_args} };
          #{RcRuntimeEmit.assign_call(env, out, "elmc_list_concat_array", "#{segments_array}, #{length(segment_vars)}")}
          #{releases}
          #{DebugProbes.append_probe(env, "elmc_list_concat_array", out, next)}
        """

        {:ok, code, out, next}

      true ->
        :error
    end
  end

  defp compile_string_concat_segments(segments, env, counter) do
    {segment_code, segment_boxes, segment_releases, counter} =
      Enum.reduce(segments, {"", [], [], counter}, fn segment, {code_acc, boxes_acc, releases_acc, c} ->
        {code, ref, releases, c2} = NativeString.compile_expr(segment, env, c)
        next = c2 + 1
        box = "string_segment_#{next}"

        assign = RcRuntimeEmit.assign_or_fusion(env, box, "elmc_new_string", ref)

        {code_acc <>
           """
           #{code}
             #{assign}
           """, boxes_acc ++ [box], releases_acc ++ releases ++ [box], next}
      end)

    [first_box | rest_boxes] = segment_boxes

    {fold_code, out_ref, temp_refs} =
      Enum.reduce(rest_boxes, {"", first_box, []}, fn box, {code_acc, acc_ref, temps} ->
        acc_var = "string_concat_acc_#{counter + length(temps) + 1}"

        assign =
          RcRuntimeEmit.assign_or_fusion(env, acc_var, "elmc_string_append", "#{acc_ref}, #{box}")

        {code_acc <>
           """
             #{assign}
           """, acc_var, temps ++ [acc_var]}
      end)

    next = counter + max(length(segments), 1)

    releases =
      (segment_releases ++ segment_boxes ++ temp_refs)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == out_ref))
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{segment_code}#{fold_code}
      #{releases}
      #{DebugProbes.append_probe(env, "elmc_string_concat", out_ref, next)}
    """

    {:ok, code, out_ref, next}
  end

  defp compile_boxed_string_append_chain(segments, env, counter) do
    {segment_code, segment_vars, counter} =
      Enum.reduce(segments, {"", [], counter}, fn segment, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(segment, env, c)
        {code_acc <> code, vars_acc ++ [var], c2}
      end)

    [first | rest] = segment_vars

    {fold_code, out_ref, counter} =
      Enum.reduce(rest, {"", first, counter}, fn var, {code_acc, acc_ref, c} ->
        next = c + 1
        out = "tmp_#{next}"

        fold =
          """
            ElmcValue *#{out} = elmc_append(#{acc_ref}, #{var});
          """

        {code_acc <> fold, out, next}
      end)

    releases =
      segment_vars
      |> Enum.reject(&(&1 == out_ref))
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{segment_code}#{fold_code}
      #{releases}
      #{DebugProbes.append_probe(env, "elmc_append", out_ref, counter)}
    """

    {:ok, code, out_ref, counter}
  end

  defp compile_native_append(left, right, env, counter) do
    {left_code, left_ref, left_cleanup, counter} = NativeString.compile_expr(left, env, counter)

    {right_code, right_ref, right_cleanup, counter} =
      NativeString.compile_expr(right, env, counter)

    next = counter + 1
    out = "tmp_#{next}"

    releases =
      (left_cleanup ++ right_cleanup)
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    assign =
      RcRuntimeEmit.assign_or_fusion(env, out, "elmc_string_append_native", "#{left_ref}, #{right_ref}")

    code = """
    #{left_code}#{right_code}
      #{assign}
      #{releases}
      #{DebugProbes.append_probe(env, "elmc_append", out, next)}
    """

    {code, out, next}
  end

  defp compile_list_bool_expr(function, predicate, list, env, counter) do
    with {:ok, arg, body} <- normalize_list_bool_predicate(predicate),
         {:ok, code, out, counter} <-
           compile_list_bool_body_loop(function, arg, body, list, env, counter) do
      {:ok, code, out, counter}
    else
      :error ->
        case two_arg_lambda(predicate) do
          {:ok, left, right, body} ->
            compile_list_bool_tuple2_loop(function, left, right, body, list, env, counter)

          :error ->
            :error
        end
    end
  end

  defp normalize_list_bool_predicate(%{op: :lambda, args: [arg], body: body})
       when is_binary(arg),
       do: {:ok, arg, body}

  defp normalize_list_bool_predicate(%{op: :call, name: op, args: [fixed]})
       when op in @compare_ops,
       do: {:ok, "__item", %{op: :call, name: op, args: [fixed, %{op: :var, name: "__item"}]}}

  defp normalize_list_bool_predicate(%{
         op: :lambda,
         args: ["__right"],
         body: %{op: :call, name: op, args: [fixed, %{op: :var, name: "__right"}]}
       })
       when op in @compare_ops,
       do: {:ok, "__item", %{op: :call, name: op, args: [fixed, %{op: :var, name: "__item"}]}}

  defp normalize_list_bool_predicate(_predicate), do: :error

  defp compile_list_bool_body_loop(function, arg, body, list, env, counter) do
    case unwrap_tuple2_lambda_body(body, arg) do
      {:ok, left, right, inner} ->
        compile_list_bool_tuple2_loop(function, left, right, inner, list, env, counter)

      :error ->
        compile_list_bool_loop(function, arg, body, list, env, counter)
    end
  end

  defp compile_list_bool_tuple2_loop(function, left, right, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0, do: Host.substitute_expr(body, substitutions), else: body

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_hof_cursor_#{next}"
    node = "list_hof_node_#{next}"
    head = "list_hof_head_#{next}"
    dx = "list_hof_dx_#{next}"
    dy = "list_hof_dy_#{next}"
    result = "list_hof_result_#{next}"
    out = "tmp_#{next}"

    body_env =
      env
      |> EnvBindings.put_native_int_binding(left, dx)
      |> EnvBindings.put_native_int_binding(right, dy)
      |> EnvBindings.put_boxed_int_binding(left, false)
      |> EnvBindings.put_boxed_int_binding(right, false)
      |> augment_zero_arg_int_constants(body)

    if NativeBool.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeBool.compile_expr(body, body_env, next)
      {initial, break_condition, break_value} = list_loop_polarity(function, body_ref)

      code = """
      #{list_code}
        #{ListLoopCodegen.runtime_source_comment_line(function)}
        bool #{result} = #{initial};
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
          ElmcValue *#{left}_tuple = elmc_tuple_first(#{head});
          const elmc_int_t #{dx} = elmc_as_int(#{left}_tuple);
          elmc_release(#{left}_tuple);
          ElmcValue *#{right}_tuple = elmc_tuple_second(#{head});
          const elmc_int_t #{dy} = elmc_as_int(#{right}_tuple);
          elmc_release(#{right}_tuple);
      #{indent_loop_body(body_code)}
          if (#{break_condition}) {
            #{result} = #{break_value};
            break;
          }
          #{cursor} = #{node}->tail;
        }
        #{RcRuntimeEmit.assign_call(env, out, "elmc_new_bool", result)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  @spec compile_list_bool_loop(
          String.t(),
          String.t(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defp compile_list_filter_expr(predicate, list, env, counter) do
    with {:ok, arg, body} <- normalize_list_bool_predicate(predicate),
         {:ok, code, out, counter} <-
           compile_list_filter_body_loop(arg, body, list, env, counter) do
      {:ok, code, out, counter}
    else
      :error ->
        case two_arg_lambda(predicate) do
          {:ok, left, right, body} ->
            compile_list_filter_tuple2_loop(left, right, body, list, env, counter)

          :error ->
            :error
        end
    end
  end

  defp compile_list_filter_body_loop(arg, body, list, env, counter) do
    case unwrap_tuple2_lambda_body(body, arg) do
      {:ok, left, right, inner} ->
        compile_list_filter_tuple2_loop(left, right, inner, list, env, counter)

      :error ->
        compile_list_filter_loop(arg, body, list, env, counter)
    end
  end

  defp compile_list_filter_loop(arg, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_filter_cursor_#{loop_id}"
    node = "list_filter_node_#{loop_id}"
    head = "list_filter_head_#{loop_id}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(loop_id)

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)

    if NativeBool.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeBool.compile_expr(body, body_env, loop_id)
      counter = counter + 1
      out = "tmp_#{counter}"

      code = """
      #{list_code}
      #{forward_init}
        #{ListLoopCodegen.runtime_source_comment_line("elmc_list_filter")}
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
      #{indent_loop_body(body_code)}
          if (#{body_ref}) {
      #{ListLoopCodegen.emit_forward_list_append(loop_id, head, env: env)}
          }
          #{cursor} = #{node}->tail;
        }
      #{ListLoopCodegen.finalize_forward_cursor_list(loop_id, out)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp compile_list_filter_tuple2_loop(left, right, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0, do: Host.substitute_expr(body, substitutions), else: body

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_filter_cursor_#{loop_id}"
    node = "list_filter_node_#{loop_id}"
    head = "list_filter_head_#{loop_id}"
    dx = "list_filter_dx_#{loop_id}"
    dy = "list_filter_dy_#{loop_id}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(loop_id)

    body_env =
      env
      |> EnvBindings.put_native_int_binding(left, dx)
      |> EnvBindings.put_native_int_binding(right, dy)
      |> EnvBindings.put_boxed_int_binding(left, false)
      |> EnvBindings.put_boxed_int_binding(right, false)
      |> augment_zero_arg_int_constants(body)

    if NativeBool.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeBool.compile_expr(body, body_env, loop_id)
      counter = counter + 1
      out = "tmp_#{counter}"

      code = """
      #{list_code}
      #{forward_init}
        #{ListLoopCodegen.runtime_source_comment_line("elmc_list_filter")}
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
          ElmcValue *#{left}_tuple = elmc_tuple_first(#{head});
          const elmc_int_t #{dx} = elmc_as_int(#{left}_tuple);
          elmc_release(#{left}_tuple);
          ElmcValue *#{right}_tuple = elmc_tuple_second(#{head});
          const elmc_int_t #{dy} = elmc_as_int(#{right}_tuple);
          elmc_release(#{right}_tuple);
      #{indent_loop_body(body_code)}
          if (#{body_ref}) {
      #{ListLoopCodegen.emit_forward_list_append(loop_id, head, env: env)}
          }
          #{cursor} = #{node}->tail;
        }
      #{ListLoopCodegen.finalize_forward_cursor_list(loop_id, out)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp compile_list_filter_map_expr(%{op: :lambda, args: [arg], body: body}, list, env, counter)
       when is_binary(arg) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    case filter_map_if_pattern(body) do
      {:ok, cond, just_value, :skip_on_true} ->
        compile_list_filter_map_if_loop(arg, cond, just_value, :skip_on_true, list, env, counter)

      {:ok, cond, just_value, :keep_on_true} ->
        compile_list_filter_map_if_loop(arg, cond, just_value, :keep_on_true, list, env, counter)

      :error ->
        compile_list_filter_map_boxed_loop(arg, body, list, env, counter)
    end
  end

  defp compile_list_filter_map_expr(_lambda, _list, _env, _counter), do: :error

  defp filter_map_if_pattern(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}) do
    cond do
      nothing_branch?(then_expr) ->
        case just_branch(else_expr) do
          {:ok, value} -> {:ok, cond, value, :skip_on_true}
          :error -> :error
        end

      nothing_branch?(else_expr) ->
        case just_branch(then_expr) do
          {:ok, value} -> {:ok, cond, value, :keep_on_true}
          :error -> :error
        end

      true ->
        :error
    end
  end

  defp filter_map_if_pattern(_body), do: :error

  defp nothing_branch?(%{op: :constructor_call, target: target, args: []})
       when target in ["Nothing", "Maybe.Nothing"],
       do: true

  defp nothing_branch?(%{op: :int_literal, value: 0}), do: true
  defp nothing_branch?(_expr), do: false

  defp just_branch(%{op: :constructor_call, target: target, args: [value]})
       when target in ["Just", "Maybe.Just"],
       do: {:ok, value}

  defp just_branch(%{op: :tuple2, left: %{op: :int_literal, value: 1}, right: value}),
    do: {:ok, value}

  defp just_branch(_expr), do: :error

  defp compile_list_filter_map_if_loop(arg, cond, just_value, polarity, list, env, counter) do
    with {:ok, range_code, first_ref, last_ref, counter} <- range_bounds(list, env, counter) do
      loop_id = counter + 1
      item_var = "list_filter_map_i_#{loop_id}"
      step_var = "list_filter_map_step_#{loop_id}"
      rev = "list_filter_map_rev_#{loop_id}"
      cons = "list_filter_map_cons_#{loop_id}"

      body_env =
        env
        |> EnvBindings.put_native_int_binding(arg, item_var)
        |> EnvBindings.put_boxed_int_binding(arg, false)

      {cond_code, cond_ref, counter} = NativeBool.compile_expr(cond, body_env, loop_id)
      {just_code, just_var, counter} = Host.compile_expr(just_value, body_env, counter)
      counter = counter + 1
      out = "tmp_#{counter}"

      keep_cond =
        case polarity do
          :skip_on_true -> "!(#{cond_ref})"
          :keep_on_true -> cond_ref
        end

      loop_body = """
      #{indent_loop_body(cond_code)}
            if (#{keep_cond}) {
      #{indent_loop_body(just_code)}
              #{RcRuntimeEmit.fusion_assign(cons, "elmc_list_cons", "#{just_var} ? #{just_var} : elmc_int_zero(), #{rev}", env)}
              elmc_release(#{just_var});
              elmc_release(#{rev});
              #{rev} = #{cons};
            }
      """

      code = """
      #{range_code}
        #{ListLoopCodegen.runtime_source_comment_line("elmc_list_filter_map")}
        ElmcValue *#{rev} = elmc_list_nil();
      #{ListLoopCodegen.emit_descending_int_range_loop(first_ref, last_ref, item_var, step_var, loop_body)}
        ElmcValue *#{out} = #{rev};
      """

      {:ok, code, out, counter}
    else
      _ ->
        compile_list_filter_map_if_list_loop(arg, cond, just_value, polarity, list, env, counter)
    end
  end

  defp compile_list_filter_map_if_list_loop(arg, cond, just_value, polarity, list, env, counter) do
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_filter_map_cursor_#{loop_id}"
    node = "list_filter_map_node_#{loop_id}"
    head = "list_filter_map_head_#{loop_id}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(loop_id)

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, cond, head)
      |> maybe_put_native_int_arg(arg, just_value, head)

    {cond_code, cond_ref, counter} = NativeBool.compile_expr(cond, body_env, loop_id)
    {just_code, just_var, counter} = Host.compile_expr(just_value, body_env, counter)
    counter = counter + 1
    out = "tmp_#{counter}"

    keep_cond =
      case polarity do
        :skip_on_true -> "!(#{cond_ref})"
        :keep_on_true -> cond_ref
      end

    code = """
    #{list_code}
    #{forward_init}
      #{ListLoopCodegen.runtime_source_comment_line("elmc_list_filter_map", 6)}
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head} = #{node}->head;
    #{indent_loop_body(cond_code)}
        if (#{keep_cond}) {
    #{indent_loop_body(just_code)}
    #{ListLoopCodegen.emit_forward_list_append(loop_id, "#{just_var} ? #{just_var} : elmc_int_zero()", owned: true, env: env)}
          elmc_release(#{just_var});
        }
        #{cursor} = #{node}->tail;
      }
    #{ListLoopCodegen.finalize_forward_cursor_list(loop_id, out)}
      elmc_release(#{list_var});
    """

    {:ok, code, out, counter}
  end

  defp compile_list_filter_map_boxed_loop(arg, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_filter_map_cursor_#{loop_id}"
    node = "list_filter_map_node_#{loop_id}"
    head = "list_filter_map_head_#{loop_id}"
    maybe_var = "list_filter_map_maybe_#{loop_id}"
    payload = "list_filter_map_payload_#{loop_id}"
    keep_flag = "list_filter_map_keep_#{loop_id}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(loop_id)

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)

    {body_code, body_var, counter} = Host.compile_expr(body, body_env, loop_id)
    counter = counter + 1
    out = "tmp_#{counter}"

    code = """
    #{list_code}
    #{forward_init}
      #{ListLoopCodegen.runtime_source_comment_line("elmc_list_filter_map", 6)}
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head} = #{node}->head;
    #{indent_loop_body(body_code)}
        ElmcValue *#{maybe_var} = #{body_var};
        ElmcValue *#{payload} = NULL;
        int #{keep_flag} = 0;
        if (#{maybe_var} && #{maybe_var}->tag == ELMC_TAG_MAYBE && #{maybe_var}->payload != NULL) {
          ElmcMaybe *#{maybe_var}_m = (ElmcMaybe *)#{maybe_var}->payload;
          if (#{maybe_var}_m->is_just && #{maybe_var}_m->value) {
            #{payload} = #{maybe_var}_m->value;
            #{keep_flag} = 1;
          }
        } else if (#{maybe_var} && #{maybe_var}->tag == ELMC_TAG_TUPLE2 && #{maybe_var}->payload != NULL) {
          ElmcTuple2 *#{maybe_var}_t = (ElmcTuple2 *)#{maybe_var}->payload;
          if (#{maybe_var}_t->first && elmc_as_int(#{maybe_var}_t->first) == 1 && #{maybe_var}_t->second) {
            #{payload} = #{maybe_var}_t->second;
            #{keep_flag} = 1;
          }
        }
        if (#{keep_flag}) {
    #{ListLoopCodegen.emit_forward_list_append(loop_id, payload, env: env)}
        }
        elmc_release(#{body_var});
        #{cursor} = #{node}->tail;
      }
    #{ListLoopCodegen.finalize_forward_cursor_list(loop_id, out)}
      elmc_release(#{list_var});
    """

    {:ok, code, out, counter}
  end

  defp compile_list_indexed_map_boxed_cursor_loop(
         index_arg,
         item_arg,
         body,
         list,
         env,
         counter
       ) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_indexed_map_cursor_#{loop_id}"
    node = "list_indexed_map_node_#{loop_id}"
    item_head = "list_indexed_map_head_#{loop_id}"
    index_var = "list_indexed_map_index_#{loop_id}"
    item_value = "list_indexed_map_item_#{loop_id}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(loop_id)

    body_env =
      env
      |> Map.put(item_arg, item_head)
      |> EnvBindings.put_native_int_binding(item_arg, "elmc_as_int(#{item_head})")
      |> EnvBindings.put_boxed_int_binding(item_arg, false)
      |> EnvBindings.put_native_int_binding(index_arg, index_var)
      |> EnvBindings.put_boxed_int_binding(index_arg, false)

    {body_code, body_var, counter} = Host.compile_expr(body, body_env, loop_id)
    counter = counter + 1
    out = "tmp_#{counter}"

    code = """
    #{list_code}
    #{forward_init}
      #{ListLoopCodegen.runtime_source_comment_line("elmc_list_indexed_map", 6)}
      ElmcValue *#{cursor} = #{list_var};
      elmc_int_t #{index_var} = 0;
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{item_head} = #{node}->head;
    #{indent_loop_body(body_code)}
        ElmcValue *#{item_value} = #{body_var} ? elmc_retain(#{body_var}) : elmc_int_zero();
        elmc_release(#{body_var});
    #{ListLoopCodegen.emit_forward_list_append(loop_id, item_value, owned: true, env: env)}
        #{index_var} += 1;
        #{cursor} = #{node}->tail;
      }
    #{ListLoopCodegen.finalize_forward_cursor_list(loop_id, out)}
      elmc_release(#{list_var});
    """

    {:ok, code, out, counter}
  end

  defp compile_list_bool_loop(function, arg, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_hof_cursor_#{next}"
    node = "list_hof_node_#{next}"
    head = "list_hof_head_#{next}"
    result = "list_hof_result_#{next}"
    out = "tmp_#{next}"

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)

    if NativeBool.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeBool.compile_expr(body, body_env, next)
      {initial, break_condition, break_value} = list_loop_polarity(function, body_ref)

      code = """
      #{list_code}
        #{ListLoopCodegen.runtime_source_comment_line(function)}
        bool #{result} = #{initial};
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
      #{indent_loop_body(body_code)}
          if (#{break_condition}) {
            #{result} = #{break_value};
            break;
          }
          #{cursor} = #{node}->tail;
        }
        #{RcRuntimeEmit.assign_call(env, out, "elmc_new_bool", result)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp maybe_put_native_int_arg(env, arg, body, head) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})
    usage = Host.native_int_usage(arg, body, module_name, decl_map)

    trial_env =
      env
      |> EnvBindings.put_native_int_binding(arg, "elmc_as_int(#{head})")
      |> EnvBindings.put_boxed_int_binding(arg, false)

    if usage.total > 0 and usage.boxed == 0 and
         (NativeInt.expr?(body, trial_env) or NativeBool.expr?(body, trial_env)) do
      trial_env
    else
      env
    end
  end

  defp list_loop_polarity("elmc_list_all", body_ref), do: {"true", "!(#{body_ref})", "false"}
  defp list_loop_polarity("elmc_list_any", body_ref), do: {"false", body_ref, "true"}

  defp indent_loop_body(code), do: CSource.indent(code, 4)

  defp two_arg_lambda(%{args: [left, right], body: body})
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp two_arg_lambda(%{args: [left], body: %{op: :lambda, args: [right], body: body}})
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp two_arg_lambda(_lambda), do: :error

  defp compile_list_map_tuple2_native_int_cursor_loop(left, right, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0, do: Host.substitute_expr(body, substitutions), else: body

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_map_cursor_#{next}"
    node = "list_map_node_#{next}"
    head = "list_map_head_#{next}"
    dx = "list_map_dx_#{next}"
    dy = "list_map_dy_#{next}"
    item_value = "list_map_item_#{next}"
    out = "tmp_#{next}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(next)

    body_env =
      env
      |> EnvBindings.put_native_int_binding(left, dx)
      |> EnvBindings.put_native_int_binding(right, dy)
      |> EnvBindings.put_boxed_int_binding(left, false)
      |> EnvBindings.put_boxed_int_binding(right, false)
      |> augment_zero_arg_int_constants(body)

    if NativeInt.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

      code = """
      #{list_code}
      #{forward_init}
        #{ListLoopCodegen.runtime_source_comment_line("elmc_list_map")}
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
          ElmcValue *#{left}_tuple = elmc_tuple_first(#{head});
          const elmc_int_t #{dx} = elmc_as_int(#{left}_tuple);
          elmc_release(#{left}_tuple);
          ElmcValue *#{right}_tuple = elmc_tuple_second(#{head});
          const elmc_int_t #{dy} = elmc_as_int(#{right}_tuple);
          elmc_release(#{right}_tuple);
      #{indent_loop_body(body_code)}
          #{RcRuntimeEmit.assign_or_fusion(env, item_value, "elmc_new_int", body_ref)}
      #{ListLoopCodegen.emit_forward_list_append(next, item_value, owned: true, env: env)}
          #{cursor} = #{node}->tail;
        }
      #{ListLoopCodegen.finalize_forward_cursor_list(next, out)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp compile_list_map_native_int_cursor_loop(arg, body, list, env, counter) do
    case unwrap_tuple2_lambda_body(body, arg) do
      {:ok, left, right, inner} ->
        compile_list_map_tuple2_native_int_cursor_loop(left, right, inner, list, env, counter)

      :error ->
        {body, substitutions} = Host.unwrap_let_chain(body, %{})

        body =
          if map_size(substitutions) > 0,
            do: Host.substitute_expr(body, substitutions),
            else: body

        compile_list_map_single_native_int_cursor_loop(arg, body, list, env, counter)
    end
  end

  defp unwrap_tuple2_lambda_body(
         %{
           op: :let_in,
           name: left,
           value_expr: first,
           in_expr: %{
             op: :let_in,
             name: right,
             value_expr: second,
             in_expr: inner
           }
         },
         tuple_arg
       ) do
    if tuple_first_of_var?(first, tuple_arg) and tuple_second_of_var?(second, tuple_arg) do
      {:ok, left, right, inner}
    else
      :error
    end
  end

  defp unwrap_tuple2_lambda_body(_, _), do: :error

  defp tuple_first_of_var?(expr, var) do
    case expr do
      %{op: :tuple_first_expr, arg: %{op: :var, name: ^var}} ->
        true

      %{op: :qualified_call, target: target, args: [%{op: :var, name: ^var}]}
      when target in ["Tuple.first", "Basics.first"] ->
        true

      %{op: :runtime_call, function: "elmc_tuple_first", args: [%{op: :var, name: ^var}]} ->
        true

      _ ->
        false
    end
  end

  defp tuple_second_of_var?(expr, var) do
    case expr do
      %{op: :tuple_second_expr, arg: %{op: :var, name: ^var}} ->
        true

      %{op: :qualified_call, target: target, args: [%{op: :var, name: ^var}]}
      when target in ["Tuple.second", "Basics.second"] ->
        true

      %{op: :runtime_call, function: "elmc_tuple_second", args: [%{op: :var, name: ^var}]} ->
        true

      _ ->
        false
    end
  end

  defp compile_list_map_single_native_int_cursor_loop(arg, body, list, env, counter) do
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_map_cursor_#{next}"
    node = "list_map_node_#{next}"
    head = "list_map_head_#{next}"
    item_value = "list_map_item_#{next}"
    out = "tmp_#{next}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(next)

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)
      |> augment_zero_arg_int_constants(body)

    if NativeInt.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

      code = """
      #{list_code}
      #{forward_init}
        #{ListLoopCodegen.runtime_source_comment_line("elmc_list_map")}
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
      #{indent_loop_body(body_code)}
          #{RcRuntimeEmit.assign_or_fusion(env, item_value, "elmc_new_int", body_ref)}
      #{ListLoopCodegen.emit_forward_list_append(next, item_value, owned: true, env: env)}
          #{cursor} = #{node}->tail;
        }
      #{ListLoopCodegen.finalize_forward_cursor_list(next, out)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp compile_list_map_boxed_cursor_loop(arg, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_map_cursor_#{loop_id}"
    node = "list_map_node_#{loop_id}"
    head = "list_map_head_#{loop_id}"
    item_value = "list_map_item_#{loop_id}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(loop_id)

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)

    {body_code, body_var, counter} = Host.compile_expr(body, body_env, loop_id)
    counter = counter + 1
    out = "tmp_#{counter}"

    code = """
    #{list_code}
    #{forward_init}
      #{ListLoopCodegen.runtime_source_comment_line("elmc_list_map", 6)}
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head} = #{node}->head;
    #{indent_loop_body(body_code)}
        ElmcValue *#{item_value} = #{body_var} ? elmc_retain(#{body_var}) : elmc_int_zero();
        elmc_release(#{body_var});
    #{ListLoopCodegen.emit_forward_list_append(loop_id, item_value, owned: true, env: env)}
        #{cursor} = #{node}->tail;
      }
    #{ListLoopCodegen.finalize_forward_cursor_list(loop_id, out)}
      elmc_release(#{list_var});
    """

    {:ok, code, out, counter}
  end

  defp augment_zero_arg_int_constants(env, body) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    VarAnalysis.used_vars(body)
    |> Enum.reduce(env, fn name, acc ->
      case Map.get(decl_map, {module_name, name}) do
        %{args: [], expr: %{op: :int_literal, value: value}} ->
          EnvBindings.put_native_int_binding(
            acc,
            name,
            ConstantInt.format_annotated_int(value, name)
          )

        _ ->
          acc
      end
    end)
  end

  defp compile_list_map_int_range_loop(arg, body, list, env, counter) do
    with {:ok, range_code, first_ref, last_ref, counter} <- range_bounds(list, env, counter) do
      loop_id = counter + 1
      item_var = "list_map_i_#{loop_id}"
      step_var = "list_map_step_#{loop_id}"
      item_value = "list_map_item_#{loop_id}"
      rev = "list_map_rev_#{loop_id}"
      cons = "list_map_cons_#{loop_id}"

      body_env =
        env
        |> EnvBindings.put_native_int_binding(arg, item_var)
        |> EnvBindings.put_boxed_int_binding(arg, false)
        |> Map.put(:__rc_catch__, false)

      loop_env =
        if Map.get(env, :__rc_required__, false),
          do: env,
          else: Map.put(env, :__rc_catch__, false)

      if NativeInt.expr?(body, body_env) do
        {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, loop_id)
        counter = counter + 1
        out = "tmp_#{counter}"

        loop_body = """
        #{indent_loop_body(body_code)}
              #{RcRuntimeEmit.assign_call(loop_env, item_value, "elmc_new_int", body_ref)}
              #{RcRuntimeEmit.fusion_assign(cons, "elmc_list_cons", "#{item_value}, #{rev}", loop_env)}
              elmc_release(#{item_value});
              elmc_release(#{rev});
              #{rev} = #{cons};
        """

        code = """
        #{range_code}
          #{ListLoopCodegen.runtime_source_comment_line("elmc_list_map")}
          ElmcValue *#{rev} = elmc_list_nil();
        #{ListLoopCodegen.emit_descending_int_range_loop(first_ref, last_ref, item_var, step_var, loop_body)}
          ElmcValue *#{out} = #{rev};
        """

        {:ok, code, out, counter}
      else
        :error
      end
    else
      :error -> :error
    end
  end

  defp compile_list_indexed_map_int_loop(index_arg, item_arg, body, list, env, counter) do
    case compile_list_indexed_replace_int(index_arg, item_arg, body, list, env, counter) do
      {:ok, _code, _out, _counter} = ok ->
        ok

      :error ->
        compile_list_indexed_map_int_loop_body(index_arg, item_arg, body, list, env, counter)
    end
  end

  defp compile_list_indexed_replace_int(index_arg, item_arg, body, list, env, counter) do
    with {:ok, target_expr, value_expr} <- indexed_replace_int_pattern(index_arg, item_arg, body),
         true <- NativeInt.expr?(value_expr, env) do
      {target_code, target_ref, counter} = NativeInt.compile_expr(target_expr, env, counter)
      {value_code, value_ref, counter} = NativeInt.compile_expr(value_expr, env, counter)

      {list_code, list_var, counter, list_passthrough?} =
        FunctionCallCompile.compile_call_operand_inner(list, env, counter, borrow_args?: true)

      next = counter + 1
      out = "tmp_#{next}"
      list_release = if list_passthrough?, do: "", else: "elmc_release(#{list_var});"

      code = """
      #{target_code}#{value_code}#{list_code}
        ElmcValue *#{out} = elmc_list_replace_nth_int(#{list_var}, #{target_ref}, #{value_ref});
        #{list_release}
      """

      {:ok, code, out, next}
    else
      _ -> :error
    end
  end

  defp indexed_replace_int_pattern(index_arg, item_arg, %{
         op: :if,
         cond: %{op: :compare, kind: :eq, left: left, right: right},
         then_expr: then_expr,
         else_expr: %{op: :var, name: else_name}
       })
       when else_name == item_arg do
    indexed_replace_target(index_arg, left, right, then_expr)
  end

  defp indexed_replace_int_pattern(index_arg, item_arg, %{
         op: :if,
         cond: %{op: :compare, kind: :eq, left: left, right: right},
         then_expr: %{op: :var, name: then_name},
         else_expr: else_expr
       })
       when then_name == item_arg do
    indexed_replace_target(index_arg, left, right, else_expr)
  end

  defp indexed_replace_int_pattern(_index_arg, _item_arg, _body), do: :error

  defp indexed_replace_target(index_arg, %{op: :var, name: index_arg}, target_expr, value_expr),
    do: {:ok, target_expr, value_expr}

  defp indexed_replace_target(index_arg, target_expr, %{op: :var, name: index_arg}, value_expr),
    do: {:ok, target_expr, value_expr}

  defp indexed_replace_target(_index_arg, _left, _right, _value_expr), do: :error

  defp compile_list_indexed_map_int_loop_body(index_arg, item_arg, body, list, env, counter) do
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_indexed_map_cursor_#{next}"
    node = "list_indexed_map_node_#{next}"
    item_head = "list_indexed_map_head_#{next}"
    index_var = "list_indexed_map_index_#{next}"
    item_value = "list_indexed_map_item_#{next}"
    out = "tmp_#{next}"
    {forward_init, _forward_head} = ListLoopCodegen.emit_forward_list_init(next)

    body_env =
      env
      |> Map.put(item_arg, item_head)
      |> EnvBindings.put_native_int_binding(item_arg, "elmc_as_int(#{item_head})")
      |> EnvBindings.put_boxed_int_binding(item_arg, false)
      |> EnvBindings.put_native_int_binding(index_arg, index_var)
      |> EnvBindings.put_boxed_int_binding(index_arg, false)

    if NativeInt.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

      code = """
      #{list_code}
      #{forward_init}
        #{ListLoopCodegen.runtime_source_comment_line("elmc_list_indexed_map")}
        ElmcValue *#{cursor} = #{list_var};
        elmc_int_t #{index_var} = 0;
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{item_head} = #{node}->head;
      #{indent_loop_body(body_code)}
          #{RcRuntimeEmit.assign_or_fusion(env, item_value, "elmc_new_int", body_ref)}
      #{ListLoopCodegen.emit_forward_list_append(next, item_value, owned: true, env: env)}
          #{index_var} += 1;
          #{cursor} = #{node}->tail;
        }
      #{ListLoopCodegen.finalize_forward_cursor_list(next, out)}
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp normalize_foldl_lambda(%{op: :lambda, args: [left, right], body: body})
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp normalize_foldl_lambda(%{
         op: :lambda,
         args: [left],
         body: %{op: :lambda, args: [right], body: body}
       })
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp normalize_foldl_lambda(%{op: :lambda, args: [item], body: body}) when is_binary(item) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    case body do
      %{op: :lambda, args: [acc], body: inner} when is_binary(acc) ->
        {:ok, item, acc, inner}

      _ ->
        :error
    end
  end

  defp normalize_foldl_lambda(_lambda), do: :error

  defp compile_list_foldl_list_cursor_loop(item_arg, acc_arg, body, acc, list, env, counter) do
    case unwrap_tuple2_lambda_body(body, item_arg) do
      {:ok, left, right, inner} ->
        compile_list_foldl_tuple2_list_cursor_loop(
          left,
          right,
          inner,
          acc_arg,
          acc,
          list,
          env,
          counter
        )

      :error ->
        compile_list_foldl_single_item_list_cursor_loop(
          item_arg,
          acc_arg,
          body,
          acc,
          list,
          env,
          counter
        )
    end
  end

  defp compile_list_foldl_single_item_list_cursor_loop(
         item_arg,
         acc_arg,
         body,
         acc,
         list,
         env,
         counter
       ) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {acc_code, acc_var, counter} = Host.compile_expr(acc, env, counter)
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_foldl_cursor_#{loop_id}"
    node = "list_foldl_node_#{loop_id}"
    head = "list_foldl_head_#{loop_id}"
    acc_ref = "list_foldl_acc_#{loop_id}"

    body_env =
      env
      |> Map.put(item_arg, head)
      |> maybe_put_native_int_arg(item_arg, body, head)
      |> Map.put(acc_arg, acc_ref)

    {body_code, body_var, counter} = Host.compile_expr(body, body_env, loop_id)
    counter = counter + 1
    out = "tmp_#{counter}"

    code = """
    #{acc_code}#{list_code}
      #{ListLoopCodegen.runtime_source_comment_line("elmc_list_foldl", 2)}
      ElmcValue *#{acc_ref} = #{acc_var} ? elmc_retain(#{acc_var}) : elmc_list_nil();
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head} = #{node}->head;
    #{indent_loop_body(body_code)}
        elmc_release(#{acc_ref});
        #{acc_ref} = #{body_var} ? elmc_retain(#{body_var}) : elmc_list_nil();
        elmc_release(#{body_var});
        #{cursor} = #{node}->tail;
      }
      ElmcValue *#{out} = #{acc_ref};
      elmc_release(#{list_var});
      elmc_release(#{acc_var});
    """

    {:ok, code, out, counter}
  end

  defp compile_list_foldl_tuple2_list_cursor_loop(
         left,
         right,
         body,
         acc_arg,
         acc,
         list,
         env,
         counter
       ) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {acc_code, acc_var, counter} = Host.compile_expr(acc, env, counter)
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    loop_id = counter + 1
    cursor = "list_foldl_cursor_#{loop_id}"
    node = "list_foldl_node_#{loop_id}"
    head = "list_foldl_head_#{loop_id}"
    dx = "list_foldl_dx_#{loop_id}"
    dy = "list_foldl_dy_#{loop_id}"
    acc_ref = "list_foldl_acc_#{loop_id}"

    body_env =
      env
      |> EnvBindings.put_native_int_binding(left, dx)
      |> EnvBindings.put_native_int_binding(right, dy)
      |> EnvBindings.put_boxed_int_binding(left, false)
      |> EnvBindings.put_boxed_int_binding(right, false)
      |> Map.put(acc_arg, acc_ref)
      |> augment_zero_arg_int_constants(body)

    {body_code, body_var, counter} = Host.compile_expr(body, body_env, loop_id)
    counter = counter + 1
    out = "tmp_#{counter}"

    code = """
    #{acc_code}#{list_code}
      #{ListLoopCodegen.runtime_source_comment_line("elmc_list_foldl", 2)}
      ElmcValue *#{acc_ref} = #{acc_var} ? elmc_retain(#{acc_var}) : elmc_list_nil();
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head} = #{node}->head;
        ElmcValue *#{left}_tuple = elmc_tuple_first(#{head});
        const elmc_int_t #{dx} = elmc_as_int(#{left}_tuple);
        elmc_release(#{left}_tuple);
        ElmcValue *#{right}_tuple = elmc_tuple_second(#{head});
        const elmc_int_t #{dy} = elmc_as_int(#{right}_tuple);
        elmc_release(#{right}_tuple);
    #{indent_loop_body(body_code)}
        elmc_release(#{acc_ref});
        #{acc_ref} = #{body_var} ? elmc_retain(#{body_var}) : elmc_list_nil();
        elmc_release(#{body_var});
        #{cursor} = #{node}->tail;
      }
      ElmcValue *#{out} = #{acc_ref};
      elmc_release(#{list_var});
      elmc_release(#{acc_var});
    """

    {:ok, code, out, counter}
  end

  @spec compile_list_reverse_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defp compile_list_reverse_expr(list_expr, env, counter) do
    case unwrap_reverse_foldl_range(list_expr) do
      {:ok, item_arg, acc_arg, body, acc, range} ->
        compile_list_foldl_int_range_loop(item_arg, acc_arg, body, acc, range, env, counter, true)

      :error ->
        :error
    end
  end

  @spec unwrap_reverse_foldl_range(Types.ir_expr()) ::
          {:ok, Types.binding_name(), Types.binding_name(), Types.ir_expr(), Types.ir_expr(),
           Types.ir_expr()}
          | :error
  defp unwrap_reverse_foldl_range(%{
         op: :runtime_call,
         function: "elmc_list_foldl",
         args: [lambda, acc, range]
       }) do
    reverse_foldl_range_args(lambda, acc, range)
  end

  defp unwrap_reverse_foldl_range(%{
         op: :qualified_call,
         target: target,
         args: [lambda, acc, range]
       })
       when target in ["List.foldl", "Elm.Kernel.List.foldl"] do
    reverse_foldl_range_args(lambda, acc, range)
  end

  defp unwrap_reverse_foldl_range(_expr), do: :error

  defp reverse_foldl_range_args(lambda, acc, range) do
    case normalize_foldl_lambda(lambda) do
      {:ok, item_arg, acc_arg, body} -> {:ok, item_arg, acc_arg, body, acc, range}
      :error -> :error
    end
  end

  defp compile_list_foldl_int_range_loop(
         item_arg,
         acc_arg,
         body,
         acc,
         list,
         env,
         counter,
         descending?
       ) do
    with {:ok, range_code, first_ref, last_ref, counter} <- range_bounds(list, env, counter) do
      loop_id = counter + 1
      item_var = "list_foldl_i_#{loop_id}"
      step_var = "list_foldl_step_#{loop_id}"
      acc_var = "list_foldl_acc_#{loop_id}"

      body_env_int_acc =
        env
        |> EnvBindings.put_native_int_binding(item_arg, item_var)
        |> EnvBindings.put_boxed_int_binding(item_arg, false)
        |> EnvBindings.put_native_int_binding(acc_arg, acc_var)
        |> EnvBindings.put_boxed_int_binding(acc_arg, false)

      cond do
        NativeInt.expr?(acc, env) and NativeInt.expr?(body, body_env_int_acc) ->
          {acc_code, acc_ref, _counter} = NativeInt.compile_expr(acc, env, counter)
          {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env_int_acc, loop_id)
          counter = counter + 1
          out = "tmp_#{counter}"

          code = """
          #{range_code}#{acc_code}
            #{ListLoopCodegen.runtime_source_comment_line("elmc_list_foldl", 4)}
            elmc_int_t #{acc_var} = #{acc_ref};
            if (#{first_ref} <= #{last_ref}) {
              elmc_int_t #{step_var} = 1;
              for (elmc_int_t #{item_var} = #{first_ref}; ; #{item_var} += #{step_var}) {
          #{indent_loop_body(body_code)}
                #{acc_var} = #{body_ref};
                if (#{item_var} == #{last_ref}) break;
              }
            }
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_int", acc_var)}
          """

          {:ok, code, out, counter}

        true ->
          {acc_code, acc_init_var, _counter} = Host.compile_expr(acc, env, counter)

          body_env =
            env
            |> EnvBindings.put_native_int_binding(item_arg, item_var)
            |> EnvBindings.put_boxed_int_binding(item_arg, false)
            |> Map.put(acc_arg, acc_var)

          {body, substitutions} = Host.unwrap_let_chain(body, %{})

          body =
            if map_size(substitutions) > 0 do
              Host.substitute_expr(body, substitutions)
            else
              body
            end

          {body_code, body_var, counter} = Host.compile_expr(body, body_env, loop_id)
          counter = counter + 1
          out = "tmp_#{counter}"

          loop_body = """
          #{indent_loop_body(body_code)}
                elmc_release(#{acc_var});
                #{acc_var} = #{body_var} ? elmc_retain(#{body_var}) : elmc_list_nil();
                elmc_release(#{body_var});
          """

          range_loop =
            if descending? do
              ListLoopCodegen.emit_descending_int_range_loop(
                first_ref,
                last_ref,
                item_var,
                step_var,
                loop_body
              )
            else
              ListLoopCodegen.emit_ascending_int_range_loop(
                first_ref,
                last_ref,
                item_var,
                step_var,
                loop_body
              )
            end

          code = """
          #{range_code}#{acc_code}
            #{ListLoopCodegen.runtime_source_comment_line("elmc_list_foldl", 4)}
            ElmcValue *#{acc_var} = #{acc_init_var} ? elmc_retain(#{acc_init_var}) : elmc_list_nil();
          #{range_loop}
            ElmcValue *#{out} = #{acc_var};
            elmc_release(#{acc_init_var});
          """

          {:ok, code, out, counter}
      end
    else
      _ -> :error
    end
  end

  defp range_bounds(
         %{op: :runtime_call, function: "elmc_list_range", args: [first, last]},
         env,
         counter
       ) do
    {first_code, first_ref, counter} = NativeInt.compile_expr(first, env, counter)
    {last_code, last_ref, counter} = NativeInt.compile_expr(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp range_bounds(%{op: :qualified_call, target: target, args: [first, last]}, env, counter)
       when target in ["List.range", "Elm.Kernel.List.range"] do
    {first_code, first_ref, counter} = NativeInt.compile_expr(first, env, counter)
    {last_code, last_ref, counter} = NativeInt.compile_expr(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp range_bounds(%{op: :call, name: "range", args: [first, last]}, env, counter) do
    {first_code, first_ref, counter} = NativeInt.compile_expr(first, env, counter)
    {last_code, last_ref, counter} = NativeInt.compile_expr(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp range_bounds(_expr, _env, _counter), do: :error

  defp compile_list_repeat_int(n, value, env, counter) do
    case unwrap_list_repeat_expr(value) do
      {:ok, inner_n, inner_value} ->
        with {:ok, inner_code, inner_var, counter} <-
               compile_list_repeat_int(inner_n, inner_value, env, counter) do
          compile_list_repeat_from_value(n, inner_code, inner_var, env, counter)
        end

      :error ->
        case compile_list_repeat_static_int_array(n, value, env, counter) do
          {:ok, code, out, counter} ->
            {:ok, code, out, counter}

          :error ->
            {value_code, value_ref, counter} = compile_repeat_element(value, env, counter)
            compile_list_repeat_from_value(n, value_code, value_ref, env, counter)
        end
    end
  end

  defp compile_list_repeat_static_int_array(n, value, env, counter) do
    with {:ok, count} <- ConstantInt.literal_value(n, env),
         true <- count > 0 and count <= 32,
         {:ok, int_value} <- ConstantInt.literal_value(value, env),
         false <- int_value == 0 do
      next = counter + 1
      out = "tmp_#{next}"
      values_name = "list_repeat_int_values_#{next}"

      values =
        1..count
        |> Enum.map(fn _ -> Integer.to_string(int_value) end)
        |> Enum.join(", ")

      code = """
        static const elmc_int_t #{values_name}[#{count}] = { #{values} };
        ElmcValue *#{out} = elmc_list_from_int_array_take(#{values_name}, #{count});
      """

      {:ok, code, out, next}
    else
      _ -> :error
    end
  end

  @type int_loop_count :: {:ok, String.t(), String.t(), Types.compile_counter(), String.t() | nil}

  @spec compile_int_loop_count(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          int_loop_count | :error
  defp compile_int_loop_count(n, env, counter) do
    case constant_int_loop_count(n, env, counter) do
      {:ok, _, _, _, _} = ok ->
        ok

      :error ->
        case native_int_loop_count(n, env, counter) do
          {:ok, _, _, _, _} = ok ->
            ok

          :error ->
            {code, var, c} = Host.compile_expr(n, env, counter)
            {:ok, code, "elmc_as_int(#{var})", c, var}
        end
    end
  end

  @spec native_int_loop_count(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          int_loop_count() | :error
  defp native_int_loop_count(%{op: :var, name: name}, env, counter)
       when is_binary(name) or is_atom(name) do
    cond do
      is_binary(ref = EnvBindings.hybrid_loop_native_ref(env, name)) ->
        {:ok, "", ref, counter, nil}

      is_binary(ref = EnvBindings.native_int_binding(env, name)) ->
        {:ok, "", ref, counter, nil}

      true ->
        :error
    end
  end

  defp native_int_loop_count(n, env, counter) do
    if NativeInt.expr?(n, env) do
      {code, ref, c} = NativeInt.compile_expr(n, env, counter)
      {:ok, code, ref, c, nil}
    else
      :error
    end
  end

  @spec constant_int_loop_count(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          int_loop_count | :error
  defp constant_int_loop_count(expr, env, counter) do
    case ConstantInt.literal_value(expr, env) do
      {:ok, value} -> {:ok, "", Integer.to_string(value), counter, nil}
      :error -> :error
    end
  end

  defp compile_repeat_element(%{op: :int_literal, value: 0}, _env, counter),
    do: {"", "elmc_int_zero()", counter}

  defp compile_repeat_element(value, env, counter) do
    if NativeInt.expr?(value, env) do
      {code, ref, c} = NativeInt.compile_expr(value, env, counter)
      next = c + 1
      var = "tmp_#{next}"
      alloc = RcRuntimeEmit.assign_call(env, var, "elmc_new_int", ref)
      {code <> "\n  " <> alloc, var, next}
    else
      {code, var, c} = Host.compile_expr(value, env, counter)
      {code, "#{var} ? elmc_retain(#{var}) : elmc_int_zero()", c}
    end
  end

  defp compile_list_repeat_from_value(n, value_code, value_ref, env, counter) do
    with {:ok, count_code, count_ref, counter, count_var} <-
           compile_int_loop_count(n, env, counter) do
      compile_list_repeat_from_count(
        count_code,
        count_ref,
        count_var,
        value_code,
        value_ref,
        counter,
        env
      )
    end
  end

  @spec compile_list_repeat_from_count(
          String.t(),
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          Types.compile_counter(),
          Types.compile_env()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()}
  defp compile_list_repeat_from_count(
         count_code,
         count_ref,
         count_var,
         value_code,
         value_ref,
         counter,
         env
       ) do
    with {:ok, _n} <- immortal_zero_repeat_count(count_ref, count_var),
         true <- value_ref == "elmc_int_zero()" do
      compile_list_repeat_immortal_zeros(count_code, count_ref, count_var, value_code, counter)
    else
      _ ->
        compile_list_repeat_inline_loop(
          count_code,
          count_ref,
          count_var,
          value_code,
          value_ref,
          counter,
          env
        )
    end
  end

  defp immortal_zero_repeat_count(count_ref, nil) do
    case Integer.parse(count_ref) do
      {n, ""} when n > 0 and n <= 32 -> {:ok, n}
      _ -> :error
    end
  end

  defp immortal_zero_repeat_count(_count_ref, _count_var), do: :error

  defp compile_list_repeat_immortal_zeros(count_code, count_ref, count_var, value_code, counter) do
    count_release =
      if is_binary(count_var) do
        "  elmc_release(#{count_var});\n"
      else
        ""
      end

    next = counter + 1
    out = "tmp_#{next}"
    sym = "elmc_zero_list_#{out}"

    code = """
    #{count_code}#{value_code}
      ElmcValue *#{out};
      {
        enum { ELMC_ZERO_N = #{count_ref} };
        static struct {
          ElmcValue value;
          ElmcCons cons;
        } #{sym}_cells[ELMC_ZERO_N];
        static int #{sym}_ready = 0;
        while (#{sym}_ready < ELMC_ZERO_N) {
          int i = #{sym}_ready++;
          ElmcCons *cell_cons = &#{sym}_cells[i].cons;
          ElmcValue *cell_value = &#{sym}_cells[i].value;
          cell_cons->head = elmc_int_zero();
          cell_cons->tail = (i == 0) ? elmc_list_nil() : &#{sym}_cells[i - 1].value;
          cell_value->rc = ELMC_RC_IMMORTAL;
          cell_value->tag = ELMC_TAG_LIST;
          cell_value->payload = cell_cons;
          cell_value->scalar = ELMC_LIST_CELL_SCALAR;
        }
        #{out} = &#{sym}_cells[ELMC_ZERO_N - 1].value;
      }
    #{count_release}
    """

    {:ok, code, out, next}
  end

  defp compile_list_repeat_inline_loop(
         count_code,
         count_ref,
         count_var,
         value_code,
         value_ref,
         counter,
         env
       ) do
    value_release =
      if value_ref =~ ~r/^tmp_\d+$/ do
        "  elmc_release(#{value_ref});\n"
      else
        ""
      end

    count_release =
      if is_binary(count_var) do
        "  elmc_release(#{count_var});\n"
      else
        ""
      end

    loop_id = counter + 1

    {:inline, inline_code, inline_out} =
      CodegenListHelpers.repeat_codegen(count_ref, value_ref, loop_id, env)

    code = """
    #{count_code}#{value_code}
    #{inline_code}#{value_release}#{count_release}
    """

    {:ok, code, inline_out, counter}
  end

  @spec compile_int_sub_list_length(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def compile_int_sub_list_length(left, right, env, counter) do
    with {:ok, list} <- ListLoopCodegen.unwrap_list_length_expr(right),
         {:ok, left_code, left_ref, counter} <-
           ConstantInt.compile_native_operand(left, env, counter) do
      case ImmortalStaticList.static_length(list, env) do
        {:ok, count} ->
          counter = counter + 1
          out = "tmp_#{counter}"

          code = """
          #{left_code}\
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_int", "#{left_ref} - #{count}")}
          """

          {:ok, code, out, counter}

        :error ->
          {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
          loop_id = counter + 1
          {length_code, count} = ListLoopCodegen.emit_length_native_count(list_var, loop_id)
          counter = counter + 1
          out = "tmp_#{counter}"

          code = """
          #{left_code}#{list_code}
          #{length_code}
            #{RecordCompile.release_list_operand_code(env, list_var)}\
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_int", "#{left_ref} - #{count}")}
          """

          {:ok, code, out, counter}
      end
    else
      _ -> :error
    end
  end

  defp compile_list_length_int(list, env, counter) do
    case ImmortalStaticList.static_length(list, env) do
      {:ok, count} ->
        counter = counter + 1
        out = "tmp_#{counter}"
        length_ref = ImmortalStaticList.format_static_length(count, list, env)
        {:ok, RcRuntimeEmit.assign_call(env, out, "elmc_new_int", length_ref) <> "\n", out, counter}

      :error ->
        {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
        loop_id = counter + 1
        {length_code, count} = ListLoopCodegen.emit_length_native_count(list_var, loop_id)
        counter = counter + 1
        out = "tmp_#{counter}"

        code = """
        #{list_code}
        #{length_code}
          #{RcRuntimeEmit.assign_call(env, out, "elmc_new_int", count)}
          #{RecordCompile.release_list_operand_code(env, list_var)}\
        """

        {:ok, code, out, counter}
    end
  end

  defp compile_list_slice_int(function, count, list, env, counter) do
    {count_code, count_ref, counter} = Host.compile_native_int_expr(count, env, counter)

    {list_code, list_ref, counter, borrowed?} =
      FunctionCallCompile.compile_call_operand_inner(list, env, counter, borrow_args?: true)

    next = counter + 1
    out = "tmp_#{next}"
    native_function = "#{function}_int"

    release =
      if borrowed? do
        ""
      else
        "elmc_release(#{list_ref});"
      end

    assign =
      RcRuntimeEmit.assign_or_fusion(env, out, native_function, "#{count_ref}, #{list_ref}")

    code = """
    #{count_code}
    #{list_code}
      #{assign}
      #{release}
      #{Host.face_ops_append_probe(env, native_function, out, next)}
    """

    {code, out, next}
  end

  defp compile_list_concat_expr(lists_expr, env, counter) do
    lists_expr = unwrap_concat_lists_arg(lists_expr)

    case unwrap_concat_append_repeat(lists_expr) do
      {:ok, n, item, rest} ->
        compile_concat_repeat_append_flatten(n, item, rest, env, counter)

      :error ->
        case concat_literal_segments(lists_expr) do
          {:ok, segments} when length(segments) >= 2 ->
            compile_list_concat_segments_flatten(segments, env, counter)

          _ ->
            case collect_append_segments(lists_expr) do
              {:ok, segments} when length(segments) >= @min_list_append_concat_segments ->
                compile_list_concat(segments, env, counter)

              _ ->
                :error
            end
        end
    end
  end

  defp concat_literal_segments(%{op: :list_literal, items: items})
       when is_list(items) and length(items) >= 2,
       do: {:ok, items}

  defp concat_literal_segments(_expr), do: :error

  defp unwrap_concat_lists_arg(%{op: :list_literal, items: [single]}), do: single
  defp unwrap_concat_lists_arg(expr), do: expr

  defp unwrap_concat_append_repeat(expr) do
    case unwrap_append_pair(expr) do
      {:ok, left, right} ->
        case unwrap_list_repeat_expr(left) do
          {:ok, n, item} -> {:ok, n, item, right}
          :error -> :error
        end

      :error ->
        :error
    end
  end

  defp unwrap_append_pair(%{op: :runtime_call, function: "elmc_append", args: [left, right]}),
    do: {:ok, left, right}

  defp unwrap_append_pair(%{op: :call, name: "__append__", args: [left, right]}),
    do: {:ok, left, right}

  defp unwrap_append_pair(_expr), do: :error

  defp unwrap_list_repeat_expr(%{
         op: :runtime_call,
         function: "elmc_list_repeat",
         args: [n, item]
       }),
       do: {:ok, n, item}

  defp unwrap_list_repeat_expr(%{op: :qualified_call, target: target, args: [n, item]})
       when target in ["List.repeat", "Elm.Kernel.List.repeat"],
       do: {:ok, n, item}

  defp unwrap_list_repeat_expr(%{op: :call, name: "repeat", args: [n, item]}),
    do: {:ok, n, item}

  defp unwrap_list_repeat_expr(_expr), do: :error

  @spec compile_concat_repeat_append_flatten(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defp compile_concat_repeat_append_flatten(n, item, rest, env, counter) do
    {:ok, count_code, count_ref, counter, count_var} = compile_int_loop_count(n, env, counter)
    {:ok, item_code, item_var, counter} = compile_concat_item(item, env, counter)

    {rest_code, rest_var, counter} = Host.compile_expr(rest, env, counter)
    loop_id = counter + 1
    flatten_id = loop_id + 1
    counter = counter + 1
    out = "tmp_#{counter}"
    tail_slot = "list_flatten_tail_#{flatten_id}"

    count_release =
      if is_binary(count_var), do: "  elmc_release(#{count_var});\n", else: ""

    {:inline, repeat_code, repeat_out} =
      CodegenListHelpers.repeat_codegen(count_ref, item_var, loop_id, env)

    failed = "list_flatten_failed_#{flatten_id}"

    flatten_repeat =
      emit_flatten_row_lists(repeat_out, out, tail_slot, failed, "#{flatten_id}_repeat", 4, env)

    flatten_rest =
      emit_flatten_row_lists(rest_var, out, tail_slot, failed, "#{flatten_id}_rest", 4, env)

    code = """
    #{count_code}#{item_code}#{rest_code}
    #{repeat_code}
      elmc_release(#{item_var});
      ElmcValue *#{out} = NULL;
      ElmcValue **#{tail_slot} = NULL;
      bool #{failed} = false;
      // List.concat
    #{flatten_repeat}
    #{flatten_rest}
      if (!#{out}) #{out} = elmc_list_nil();
      elmc_release(#{repeat_out});
      elmc_release(#{rest_var});
    #{count_release}
    """

    {:ok, code, out, counter}
  end

  defp emit_flatten_row_lists(rows_var, out_var, tail_slot_var, failed_var, loop_suffix, indent, env) do
    outer = "list_flatten_outer_#{loop_suffix}"
    inner = "list_flatten_inner_#{loop_suffix}"
    row = "list_flatten_row_#{loop_suffix}"
    cell = "list_flatten_cell_#{loop_suffix}"
    pad = String.duplicate(" ", indent)
    pad_inner = String.duplicate(" ", indent + 2)

    """
    #{pad}for (ElmcValue *#{outer} = #{rows_var}; !#{failed_var} && #{outer} && #{outer}->tag == ELMC_TAG_LIST && #{outer}->payload != NULL; #{outer} = ((ElmcCons *)#{outer}->payload)->tail) {
    #{pad}  ElmcValue *#{row} = ((ElmcCons *)#{outer}->payload)->head;
    #{pad}  for (ElmcValue *#{inner} = #{row}; !#{failed_var} && #{inner} && #{inner}->tag == ELMC_TAG_LIST && #{inner}->payload != NULL; #{inner} = ((ElmcCons *)#{inner}->payload)->tail) {
    #{pad_inner}#{RcRuntimeEmit.list_cons_retain_assign(cell, "((ElmcCons *)#{inner}->payload)->head, elmc_list_nil()", env, return_on_fail?: false)}
    #{pad_inner}if (!#{cell}) {
    #{pad_inner}  elmc_release(#{out_var});
    #{pad_inner}  #{out_var} = elmc_list_nil();
    #{pad_inner}  #{tail_slot_var} = NULL;
    #{pad_inner}  #{failed_var} = true;
    #{pad_inner}  break;
    #{pad_inner}}
    #{pad_inner}if (#{tail_slot_var}) {
    #{pad_inner}  elmc_release(*#{tail_slot_var});
    #{pad_inner}  *#{tail_slot_var} = #{cell};
    #{pad_inner}} else {
    #{pad_inner}  #{out_var} = #{cell};
    #{pad_inner}}
    #{pad_inner}#{tail_slot_var} = &((ElmcCons *)#{cell}->payload)->tail;
    #{pad}  }
    #{pad}}
    """
  end

  defp compile_concat_item(item, env, counter) do
    case unwrap_list_repeat_expr(item) do
      {:ok, n, inner} ->
        {:ok, code, var, c} = compile_list_repeat_int(n, inner, env, counter)
        {:ok, code, var, c}

      :error ->
        {code, var, c} = Host.compile_expr(item, env, counter)
        {:ok, code, var, c}
    end
  end

  @spec compile_generic(
          %{
            required(:op) => :runtime_call,
            required(:function) => String.t(),
            required(:args) => [Types.ir_expr()]
          },
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_generic(%{op: :runtime_call, function: function, args: args}, env, counter) do
    operand_env = Map.delete(env, :__into_out__)

    compile_operand =
      if MapSet.member?(@retaining_runtime_functions, function) do
        &FunctionCallCompile.compile_retaining_call_operand/3
      else
        fn expr, inner_env, c ->
          FunctionCallCompile.compile_call_operand_inner(expr, inner_env, c, borrow_args?: true)
        end
      end

    {arg_code, arg_vars, arg_borrowed?, counter} =
      Enum.reduce(args, {"", [], [], counter}, fn arg_expr,
                                                  {code_acc, vars_acc, borrowed_acc, c} ->
        {code, var, c2, borrowed?} = compile_operand.(arg_expr, operand_env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], borrowed_acc ++ [borrowed?], c2}
      end)

    {arg_code, arg_vars, counter, suffix_cons_take?} =
      maybe_copy_list_cons_suffix_tail(env, function, arg_vars, arg_code, counter)

    {out, next} = CaseCompile.fresh_var(counter, env)
    call_args = Enum.join(arg_vars, ", ")

    cons_take_transfer? =
      suffix_cons_take? or
        (function == "elmc_list_cons" and not RcRuntimeEmit.rc_mode?(env) and
           not Enum.any?(arg_borrowed?))

    releases =
      arg_vars
      |> Enum.zip(arg_borrowed?)
      |> Enum.reject(fn {_var, borrowed?} -> borrowed? end)
      |> Enum.reject(fn {_var, _borrowed?} -> cons_take_transfer? end)
      |> Enum.map_join("\n  ", fn {var, _borrowed?} -> "elmc_release(#{var});" end)

    assign =
      cond do
        suffix_cons_take? ->
          "ElmcValue *#{out} = elmc_list_cons_take(#{call_args});"

        function == "elmc_list_cons" and Enum.any?(arg_borrowed?) ->
          RcRuntimeEmit.list_cons_retain_assign(out, call_args, env)

        true ->
          RcRuntimeEmit.assign_call(env, out, function, call_args)
      end

    code = """
    #{arg_code}
      #{assign}
      #{releases}
      #{Host.face_ops_append_probe(env, function, out, next)}
    """

    {code, out, next}
  end

  @spec maybe_copy_list_cons_suffix_tail(
          Types.compile_env(),
          String.t(),
          [String.t()],
          String.t(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], Types.compile_counter(), boolean()}
  defp maybe_copy_list_cons_suffix_tail(env, "elmc_list_cons", [head, tail], arg_code, counter) do
    if EnvBindings.list_suffix_ref?(env, tail) do
      {copy, next} = CaseCompile.fresh_var(counter, env)

      copy_code =
        """
        ElmcValue *#{copy} = #{tail} ? elmc_list_copy_take(#{tail}) : elmc_int_zero();
        """
        |> String.trim()

      {arg_code <> "\n  " <> copy_code, [head, copy], next, true}
    else
      {arg_code, [head, tail], counter, false}
    end
  end

  defp maybe_copy_list_cons_suffix_tail(_env, _function, arg_vars, arg_code, counter),
    do: {arg_code, arg_vars, counter, false}

  defp debug_set_value?(value, env) do
    case NativeTypedReturn.expr_type(value, env) do
      type when is_binary(type) ->
        TypeParsing.set_type?(type) or debug_set_function_param?(value, env)

      _ ->
        debug_set_function_param?(value, env)
    end
  end

  defp debug_set_function_param?(%{op: :var, name: name}, env) when is_binary(name) do
    module = Map.get(env, :__module__, "Main")
    fn_name = Map.get(env, :__function_name__)

    case Map.get(Map.get(env, :__program_decls__, %{}), {module, fn_name}) do
      %{type: type, args: args} when is_binary(type) and is_list(args) ->
        with idx when is_integer(idx) <- Enum.find_index(args, &(&1 == name)),
             param_type when is_binary(param_type) <- Enum.at(TypeParsing.function_arg_types(type), idx) do
          TypeParsing.set_type?(param_type)
        else
          _ -> false
        end

      %{type: type} when is_binary(type) ->
        case TypeParsing.function_arg_types(type) do
          [param_type] -> TypeParsing.set_type?(param_type)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp debug_set_function_param?(_value, _env), do: false
end
