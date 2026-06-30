defmodule Elmc.Backend.CCodegen.Native.String do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.StaticString
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @fused_literal_int_buf_size 96

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_string_compile_result()
  def compile_expr(expr, env, counter) do
    compile_expr_impl(StaticString.fold_append_literals(expr), env, counter)
  end

  defp compile_expr_impl(%{op: :string_literal, value: value}, _env, counter) do
    {"", "\"#{Util.escape_c_string(value)}\"", [], counter}
  end

  defp compile_expr_impl(%{op: :var, name: name} = expr, env, counter) do
    case EnvBindings.native_string_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, [], counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            next = counter + 1
            out = "native_string_#{next}"
            {value_lines, value_cleanup} = value_code(expr, env, source, out)
            {value_lines, out, value_cleanup, next}

          _ ->
            compile_fallback(expr, env, counter)
        end
    end
  end

  defp compile_expr_impl(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr} = expr,
        env,
        counter
      ) do
    if expr?(then_expr, env) and expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = Host.compile_native_bool_expr(cond_expr, env, counter)

      case cond_ref do
        "1" ->
          {then_code, then_ref, then_cleanup, counter} = compile_expr(then_expr, env, counter)
          {cond_code <> then_code, then_ref, then_cleanup, counter}

        "0" ->
          {else_code, else_ref, else_cleanup, counter} = compile_expr(else_expr, env, counter)
          {cond_code <> else_code, else_ref, else_cleanup, counter}

        _ ->
          {then_code, then_ref, _then_cleanup, counter} = compile_expr(then_expr, env, counter)
          {else_code, else_ref, _else_cleanup, counter} = compile_expr(else_expr, env, counter)
          next = counter + 1
          out = "native_string_if_#{next}"

          code = """
          #{cond_code}#{then_code}#{else_code}
            const char *#{out} = #{cond_ref} ? #{then_ref} : #{else_ref};
          """

          {code, out, [], next}
      end
    else
      compile_fallback(expr, env, counter)
    end
  end

  defp compile_expr_impl(%{op: :qualified_call, target: target, args: args} = expr, env, counter) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> compile_fallback(expr, env, counter)
      rewritten -> compile_expr(rewritten, env, counter)
    end
  end

  defp compile_expr_impl(
        %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr,
        env,
        counter
      ) do
    if Host.native_int_expr?(value, env) do
      {value_code, value_ref, counter} = Host.compile_native_int_expr(value, env, counter)
      next = counter + 1
      buffer = "native_string_buf_#{next}"
      out = "native_string_#{next}"

      code = """
      #{value_code}
        char #{buffer}[32];
        snprintf(#{buffer}, sizeof(#{buffer}), "%lld", (long long)#{value_ref});
        const char *#{out} = #{buffer};
      """

      {code, out, [], next}
    else
      compile_fallback(expr, env, counter)
    end
  end

  defp compile_expr_impl(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]} = expr,
        env,
        counter
      ) do
    case try_compile_literal_int_append(left, right, env, counter) do
      {:ok, fuse_code, buf_ref, counter} ->
        next = counter + 1
        out = "native_string_#{next}"

        code = """
        #{fuse_code}
          const char *#{out} = #{buf_ref};
        """

        {code, out, [], next}

      :error ->
        if expr?(left, env) and expr?(right, env) do
          {left_code, left_ref, left_cleanup, counter} = compile_expr(left, env, counter)
          {right_code, right_ref, right_cleanup, counter} = compile_expr(right, env, counter)
          next = counter + 1
          buffer = "native_string_buf_#{next}"
          out = "native_string_#{next}"

          code = """
          #{left_code}#{right_code}
            char #{buffer}[96];
            int #{buffer}_i = 0;
            const char *#{buffer}_left = #{left_ref};
            while (#{buffer}_left && #{buffer}_left[#{buffer}_i] && #{buffer}_i < (int)sizeof(#{buffer}) - 1) {
              #{buffer}[#{buffer}_i] = #{buffer}_left[#{buffer}_i];
              #{buffer}_i++;
            }
            const char *#{buffer}_right = #{right_ref};
            int #{buffer}_right_i = 0;
            while (#{buffer}_right && #{buffer}_right[#{buffer}_right_i] && #{buffer}_i < (int)sizeof(#{buffer}) - 1) {
              #{buffer}[#{buffer}_i] = #{buffer}_right[#{buffer}_right_i];
              #{buffer}_i++;
              #{buffer}_right_i++;
            }
            #{buffer}[#{buffer}_i] = '\\0';
            const char *#{out} = #{buffer};
          """

          {code, out, left_cleanup ++ right_cleanup, next}
        else
          compile_fallback(expr, env, counter)
        end
    end
  end

  defp compile_expr_impl(%{op: :call, name: "__append__", args: [left, right]}, env, counter) do
    compile_expr(
      %{op: :runtime_call, function: "elmc_append", args: [left, right]},
      env,
      counter
    )
  end

  defp compile_expr_impl(expr, env, counter), do: compile_fallback(expr, env, counter)

  @spec try_compile_literal_int_append(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def try_compile_literal_int_append(left, right, env, counter) do
    with {:ok, prefix, suffix, int_expr} <- literal_int_append_parts(left, right, env) do
      {value_code, value_ref, counter} = Host.compile_native_int_expr(int_expr, env, counter)
      next = counter + 1
      buffer = "native_string_buf_#{next}"
      format = fused_int_snprintf_format(prefix, suffix)

      code = """
      #{value_code}
        char #{buffer}[#{@fused_literal_int_buf_size}];
        snprintf(#{buffer}, sizeof(#{buffer}), #{format}, (long long)#{value_ref});
      """

      {:ok, code, buffer, next}
    else
      _ -> :error
    end
  end

  @spec try_compile_snprintf_concat(
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def try_compile_snprintf_concat(segments, env, counter) when is_list(segments) and length(segments) >= 2 do
    with {:ok, classified} <- classify_snprintf_segments(segments, env),
         buf_size when is_integer(buf_size) <- fused_snprintf_buf_size(classified),
         {:ok, segment_code, snprintf_args, cleanup, counter} <-
           compile_snprintf_segment_args(classified, env, counter) do
      {out, counter} =
        case RcRuntimeEmit.append_out_target(env) do
          slot when is_binary(slot) -> {slot, counter}
          _ ->
            next = counter + 1
            {"tmp_#{next}", next}
        end

      buffer_counter = counter + 1
      buffer = "native_string_buf_#{buffer_counter}"
      format = fused_snprintf_format(classified)

      snprintf_args_line =
        Enum.map_join(snprintf_args, ", ", fn
          {:int, ref} -> "(long long)#{ref}"
          {:boxed_int, ref} -> "(long long)elmc_as_int(#{ref})"
          {:cstr, ref} -> ref
        end)

      assign =
        RcRuntimeEmit.assign_call(
          env,
          out,
          "elmc_new_string",
          buffer
        )

      releases =
        cleanup
        |> Enum.map_join("\n  ", &ValueSlots.release_stmt/1)

      code = """
      #{segment_code}
        char #{buffer}[#{buf_size}];
        snprintf(#{buffer}, sizeof(#{buffer}), #{format}, #{snprintf_args_line});
        #{assign}
        #{releases}
      """

      {:ok, code, out, buffer_counter}
    else
      _ -> :error
    end
  end

  def try_compile_snprintf_concat(_segments, _env, _counter), do: :error

  defp classify_snprintf_segments(segments, env) do
    Enum.reduce_while(segments, {:ok, []}, fn segment, {:ok, acc} ->
      case classify_snprintf_segment(segment, env) do
        {:ok, kind} -> {:cont, {:ok, acc ++ [kind]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp classify_snprintf_segment(%{op: :string_literal, value: value}, _env),
    do: {:ok, {:literal, value}}

  defp classify_snprintf_segment(expr, env) do
    case unwrap_string_from_int(expr, env) do
      {:ok, value} ->
        cond do
          Host.native_int_expr?(value, env) -> {:ok, {:int, value}}
          true -> {:ok, {:boxed_int, value}}
        end

      :error ->
        cond do
          expr?(expr, env) -> {:ok, {:cstr, expr}}
          boxed_expr?(expr, env) -> {:ok, {:boxed_cstr, expr}}
          true -> :error
        end
    end
  end

  defp fused_snprintf_format(classified) do
    classified
    |> Enum.map_join("", fn
      {:literal, text} -> escape_snprintf_literal(text)
      {:int, _} -> "%lld"
      {:boxed_int, _} -> "%lld"
      {:cstr, _} -> "%s"
      {:boxed_cstr, _} -> "%s"
    end)
    |> then(&"\"#{&1}\"")
  end

  # Snprintf uses C-string %s semantics (stops at NUL) and a fixed stack buffer — only fuse
  # when the estimated result fits. Long or many dynamic segments fall back to append.
  defp fused_snprintf_buf_size(classified) do
    format_len =
      classified
      |> Enum.map(fn
        {:literal, text} -> byte_size(text)
        {:int, _} -> 21
        {:boxed_int, _} -> 21
        {:cstr, _} -> 32
        {:boxed_cstr, _} -> 32
      end)
      |> Enum.sum()

    if format_len > @fused_literal_int_buf_size, do: :error, else: format_len
  end

  defp compile_snprintf_segment_args(classified, env, counter) do
    Enum.reduce_while(classified, {:ok, "", [], [], counter}, fn
      {:literal, _}, {:ok, code_acc, args_acc, cleanup_acc, c} ->
        {:cont, {:ok, code_acc, args_acc, cleanup_acc, c}}

      {:int, expr}, {:ok, code_acc, args_acc, cleanup_acc, c} ->
        {value_code, value_ref, c2} = Host.compile_native_int_expr(expr, env, c)
        {:cont, {:ok, code_acc <> value_code, args_acc ++ [{:int, value_ref}], cleanup_acc, c2}}

      {:boxed_int, expr}, {:ok, code_acc, args_acc, cleanup_acc, c} ->
        {value_code, value_ref, c2} = Host.compile_expr(expr, env, c)

        {:cont,
         {:ok, code_acc <> value_code, args_acc ++ [{:boxed_int, value_ref}], cleanup_acc ++ [value_ref],
          c2}}

      {:cstr, expr}, {:ok, code_acc, args_acc, cleanup_acc, c} ->
        {segment_code, cstr_ref, segment_cleanup, c2} = compile_expr(expr, env, c)
        {:cont, {:ok, code_acc <> segment_code, args_acc ++ [{:cstr, cstr_ref}], cleanup_acc ++ segment_cleanup, c2}}

      {:boxed_cstr, expr}, {:ok, code_acc, args_acc, cleanup_acc, c} ->
        {boxed_code, boxed_ref, c2} = Host.compile_expr(expr, env, c)
        next = c2 + 1
        cstr_ref = "snprintf_cstr_#{next}"

        extract =
          if native_string_call_expr?(expr, env) do
            "const char *#{cstr_ref} = (const char *)#{boxed_ref}->payload;"
          else
            """
            const char *#{cstr_ref} =
              (#{boxed_ref} && #{boxed_ref}->tag == ELMC_TAG_STRING && #{boxed_ref}->payload)
                ? (const char *)#{boxed_ref}->payload
                : "";
            """
          end

        {:cont,
         {:ok, code_acc <> boxed_code <> extract, args_acc ++ [{:cstr, cstr_ref}],
          cleanup_acc ++ [boxed_ref], next}}

      _, _ ->
        {:halt, :error}
    end)
  end

  defp literal_int_append_parts(left, right, env) do
    case left do
      %{op: :string_literal, value: prefix} ->
        case native_int_string_operand(right, env) do
          {:ok, int_expr} -> {:ok, prefix, "", int_expr}
          :error -> :error
        end

      _ ->
        case right do
          %{op: :string_literal, value: suffix} ->
            case native_int_string_operand(left, env) do
              {:ok, int_expr} -> {:ok, "", suffix, int_expr}
              :error -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp native_int_string_operand(expr, env) do
    case unwrap_string_from_int(expr, env) do
      {:ok, value} ->
        if Host.native_int_expr?(value, env), do: {:ok, value}, else: :error

      :error ->
        :error
    end
  end

  defp unwrap_string_from_int(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         _env
       ),
       do: {:ok, value}

  defp unwrap_string_from_int(%{op: :qualified_call, target: target, args: args}, env) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> :error
      rewritten -> unwrap_string_from_int(rewritten, env)
    end
  end

  defp unwrap_string_from_int(_, _), do: :error

  defp fused_int_snprintf_format(prefix, suffix) do
    "\"#{escape_snprintf_literal(prefix)}%lld#{escape_snprintf_literal(suffix)}\""
  end

  defp escape_snprintf_literal(""), do: ""

  defp escape_snprintf_literal(literal) do
    literal |> Util.escape_c_string() |> String.replace("%", "%%")
  end

  @spec expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def expr?(%{op: :string_literal}, _env), do: true

  def expr?(%{op: :var, name: name} = expr, env)
      when is_binary(name) or is_atom(name),
      do:
        is_binary(EnvBindings.native_string_binding(env, name)) or
          EnvBindings.boxed_string_binding?(env, name) or
          TypedReturn.string_expr?(expr, env) or
          TypedReturn.expr_type(expr, env) == "String"

  def expr?(%{op: :runtime_call, function: "elmc_string_from_char", args: [_]}, _env), do: true

  def expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: expr?(then_expr, env) and expr?(else_expr, env)

  def expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> TypedReturn.string_expr?(%{op: :qualified_call, target: target, args: args}, env)
      rewritten -> expr?(rewritten, env)
    end
  end

  def expr?(%{op: :runtime_call, function: "elmc_string_from_int", args: [value]}, env),
    do: Host.native_int_expr?(value, env)

  def expr?(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env),
    do: expr?(left, env) and expr?(right, env)

  def expr?(%{op: :call, name: "__append__", args: [left, right]}, env),
    do: expr?(left, env) and expr?(right, env)

  def expr?(%{op: :call} = expr, env), do: TypedReturn.string_expr?(expr, env)

  def expr?(_expr, _env), do: false

  @spec boxed_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def boxed_expr?(%{op: :string_literal}, _env), do: true

  def boxed_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: boxed_expr?(then_expr, env) and boxed_expr?(else_expr, env)

  def boxed_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do:
      EnvBindings.boxed_string_binding?(env, name) or
        TypedReturn.string_expr?(%{op: :var, name: name}, env) or
        TypedReturn.expr_type(%{op: :var, name: name}, env) == "String"

  def boxed_expr?(%{op: :runtime_call, function: "elmc_string_from_char", args: [_]}, _env),
    do: true

  def boxed_expr?(%{op: :runtime_call, function: "elmc_string_from_int", args: [value]}, env),
    do: Host.native_int_expr?(value, env)

  def boxed_expr?(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env),
    do: expr?(left, env) and expr?(right, env)

  def boxed_expr?(expr, env), do: TypedReturn.string_expr?(expr, env)

  @spec boxed_non_null_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def boxed_non_null_expr?(%{op: :int_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :string_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :char_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :float_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :compare}, _env), do: true

  def boxed_non_null_expr?(%{op: :call, name: name, args: [_left, _right]}, _env)
      when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"],
      do: true

  def boxed_non_null_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: boxed_non_null_expr?(then_expr, env) and boxed_non_null_expr?(else_expr, env)

  def boxed_non_null_expr?(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil ->
        Host.qualified_builtin_operator_member?(Host.normalize_special_target(target), [
          "__eq__",
          "__neq__",
          "__lt__",
          "__lte__",
          "__gt__",
          "__gte__"
        ]) and length(args || []) == 2

      rewritten ->
        boxed_non_null_expr?(rewritten, env)
    end
  end

  def boxed_non_null_expr?(%{op: :constructor_call, target: target, args: args}, env)
      when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> false
      rewritten -> boxed_non_null_expr?(rewritten, env)
    end
  end

  def boxed_non_null_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: EnvBindings.boxed_int_binding?(env, name) or EnvBindings.boxed_string_binding?(env, name)

  def boxed_non_null_expr?(
        %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
        env
      ),
      do: Host.native_int_expr?(value, env)

  def boxed_non_null_expr?(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]},
        env
      ),
      do: expr?(left, env) and expr?(right, env)

  def boxed_non_null_expr?(_expr, _env), do: false

  @spec compile_fallback(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_string_compile_result()
  defp compile_fallback(expr, env, counter) do
    {code, var, counter} = Host.compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_string_#{next}"
    {value_lines, value_cleanup} = value_code(expr, env, var, out)

    {
      """
      #{code}
      #{value_lines}
      """,
      out,
      [var | value_cleanup],
      next
    }
  end

  @spec value_code(Types.ir_expr(), Types.compile_env(), String.t(), String.t()) ::
          {String.t(), [String.t()]}
  defp value_code(expr, env, var, out) do
    cond do
      native_string_call_expr?(expr, env) ->
        {
          """
            const char *#{out} = (const char *)#{var}->payload;
          """,
          []
        }

      TypedReturn.string_expr?(expr, env) ->
        boxed = "#{out}_boxed"

        {
          """
            ElmcValue *#{boxed} = NULL;
            const char *#{out} = "";
            if (#{var} && #{var}->tag == ELMC_TAG_STRING && #{var}->payload) {
              #{out} = (const char *)#{var}->payload;
            } else if (#{var} && #{var}->tag == ELMC_TAG_LIST) {
              #{RcRuntimeEmit.check_rc_take(boxed, "elmc_string_from_list", var)}
              #{out} = (#{boxed} && #{boxed}->payload) ? (const char *)#{boxed}->payload : "";
            }
          """,
          [boxed]
        }

      true ->
        {
          """
            const char *#{out} =
              (#{var} && #{var}->tag == ELMC_TAG_STRING && #{var}->payload)
                ? (const char *)#{var}->payload
                : "";
          """,
          []
        }
    end
  end

  defp native_string_call_expr?(expr, env) do
    case expr do
      %{op: :call} -> TypedReturn.string_expr?(expr, env)
      %{op: :qualified_call} -> TypedReturn.string_expr?(expr, env)
      _ -> false
    end
  end
end
