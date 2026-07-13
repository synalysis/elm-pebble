defmodule Elmc.Backend.CCodegen.MaybeIntStringCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  alias Elmc.Backend.CCodegen.{
    CSource,
    EnvBindings,
    FusionSupport,
    Util
  }

  alias Elmc.Backend.CCodegen.Native.String, as: NativeStringMod

  @buf_size 22

  @spec try_emit(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, body} <- try_emit_with_default_append(module_name, name, expr, decl_map) do
      FusionSupport.ok_rc(body, [])
    else
      :error ->
        with param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
             {:ok, ^param, field, branches} <- parse_maybe_int_case(expr),
             {:ok, nothing_text} <- nothing_branch_text(branches),
             {:ok, int_var, format} <- parse_just_int_format(branches),
             field_macro when is_binary(field_macro) <- field_macro(module_name, name, param, field, decl_map) do
          core = emit_maybe_int_string_core(param, field_macro, int_var, nothing_text, format)
          c_prefix = Util.module_fn_name(module_name, name)

          body = """
          static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{param}) {
            RC Rc = RC_SUCCESS;
            CATCH_BEGIN
          #{CSource.indent(String.trim(core), 2)}
            CATCH_END
            return Rc;
          }
          """

          FusionSupport.ok_rc(body, [])
        else
          _ -> :error
        end
    end
  end

  defp try_emit_with_default_append(module_name, name, expr, decl_map) do
    with param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         {:ok, ^param, field, default, suffix} <- parse_maybe_with_default_append(expr),
         field_macro when is_binary(field_macro) <- field_macro(module_name, name, param, field, decl_map) do
      int_var = "level"
      suffix_lit = escape_snprintf_literal(suffix)

      core = """
      ElmcValue *maybe_val = elmc_record_get_index(#{param}, #{field_macro});
        elmc_int_t #{int_var} = elmc_maybe_with_default_int(#{default}, maybe_val);
        char #{int_var}_buf[#{@buf_size}];
        snprintf(#{int_var}_buf, sizeof(#{int_var}_buf), "%lld#{suffix_lit}", (long long)#{int_var});
        Rc = elmc_new_string(out, #{int_var}_buf);
        CHECK_RC(Rc);
      """

      c_prefix = Util.module_fn_name(module_name, name)

      body = """
      static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{param}) {
        RC Rc = RC_SUCCESS;
        CATCH_BEGIN
      #{CSource.indent(String.trim(core), 2)}
        CATCH_END
        return Rc;
      }
      """

      {:ok, body}
    else
      _ -> :error
    end
  end

  defp parse_maybe_with_default_append(expr) do
    with {:ok, left, right} <- append_parts(expr),
         {:ok, suffix} <- string_literal_suffix(right),
         {:ok, default, param, field} <- parse_with_default_int_field(left) do
      {:ok, param, field, default, suffix}
    else
      _ -> :error
    end
  end

  defp string_literal_suffix(%{op: :string_literal, value: value}) when is_binary(value) do
    if String.contains?(value, <<0>>), do: :error, else: {:ok, value}
  end

  defp string_literal_suffix(_), do: :error

  defp parse_with_default_int_field(%{op: :qualified_call, target: "String.fromInt", args: [inner]}),
    do: parse_with_default_int_field(inner)

  defp parse_with_default_int_field(%{op: :runtime_call, function: "elmc_string_from_int", args: [inner]}),
    do: parse_with_default_int_field(inner)

  defp parse_with_default_int_field(expr), do: parse_with_default_call(expr)

  defp parse_with_default_call(%{op: :qualified_call, target: "Maybe.withDefault", args: [default, maybe]}) do
    parse_with_default_args(default, maybe)
  end

  defp parse_with_default_call(%{op: :qualified_call, target: "Maybe.WithDefault", args: [default, maybe]}) do
    parse_with_default_args(default, maybe)
  end

  defp parse_with_default_call(%{op: :runtime_call, function: "elmc_maybe_with_default", args: [default, maybe]}) do
    parse_with_default_args(default, maybe)
  end

  defp parse_with_default_call(_), do: :error

  defp parse_with_default_args(default, maybe) do
    with %{op: :int_literal, value: value} when is_integer(value) <- default,
         {:ok, param, field} <- parse_maybe_field_source(maybe) do
      {:ok, value, param, field}
    else
      _ -> :error
    end
  end

  defp emit_maybe_int_string_core(param, field_macro, int_var, nothing_text, format) do
    default_lit = "\"#{Util.escape_c_string(nothing_text)}\""

    format_code =
      case format do
        {:plain, suffix} ->
          if suffix == "" do
            """
            snprintf(#{int_var}_buf, sizeof(#{int_var}_buf), "%lld", (long long)#{int_var});
            """
          else
            """
            snprintf(#{int_var}_buf, sizeof(#{int_var}_buf), "%lld#{escape_snprintf_literal(suffix)}", (long long)#{int_var});
            """
          end

        {:threshold, threshold, divisor, suffix} ->
            """
            if (#{int_var} >= #{threshold}) {
              snprintf(#{int_var}_buf, sizeof(#{int_var}_buf), "%lld#{escape_snprintf_literal(suffix)}", (long long)elmc_int_idiv(#{int_var}, #{divisor}));
            } else {
              snprintf(#{int_var}_buf, sizeof(#{int_var}_buf), "%lld", (long long)#{int_var});
            }
            """
      end

    """
    ElmcValue *maybe_val = elmc_record_get_index(#{param}, #{field_macro});
      if (elmc_maybe_is_nothing(maybe_val)) {
        Rc = elmc_new_string(out, #{default_lit});
        CHECK_RC(Rc);
      } else {
        elmc_int_t #{int_var} = elmc_as_int(elmc_maybe_just_payload(maybe_val));
        char #{int_var}_buf[#{@buf_size}];
    #{CSource.indent(String.trim(format_code), 2)}
        Rc = elmc_new_string(out, #{int_var}_buf);
        CHECK_RC(Rc);
      }
    """
  end

  defp parse_maybe_int_case(%{op: :let_in, value_expr: source, in_expr: %{op: :case, branches: branches}}) do
    case parse_maybe_field_source(source) do
      {:ok, param, field} -> {:ok, param, field, branches}
      :error -> :error
    end
  end

  defp parse_maybe_int_case(%{op: :case, subject: subject, branches: branches}) do
    case parse_maybe_field_source(subject) do
      {:ok, param, field} -> {:ok, param, field, branches}
      :error -> :error
    end
  end

  defp parse_maybe_int_case(_), do: :error

  defp parse_maybe_field_source(%{op: :field_access, arg: param, field: field})
       when is_binary(param) and is_binary(field),
       do: {:ok, param, field}

  defp parse_maybe_field_source(%{op: :field_access, arg: %{op: :var, name: param}, field: field})
       when is_binary(param) and is_binary(field),
       do: {:ok, param, field}

  defp parse_maybe_field_source(_), do: :error

  defp parse_just_int_format(branches) do
    case Enum.find(branches, &just_branch?/1) do
      %{pattern: %{bind: var}, expr: expr} when is_binary(var) ->
        parse_just_int_expr(expr, var)

      %{pattern: %{arg_pattern: %{kind: :var, name: var}}, expr: expr} when is_binary(var) ->
        parse_just_int_expr(expr, var)

      %{pattern: %{arg_pattern: %{kind: :var, bind: var}}, expr: expr} when is_binary(var) ->
        parse_just_int_expr(expr, var)

      _ ->
        :error
    end
  end

  defp just_branch?(%{pattern: %{kind: :constructor, name: name}}) when name in ["Just", "Maybe.Just"],
    do: true

  defp just_branch?(_), do: false

  defp parse_just_int_expr(expr, var) do
    with {:ok, threshold, divisor, suffix} <- parse_threshold_format(expr, var) do
      {:ok, var, {:threshold, threshold, divisor, suffix}}
    else
      :error ->
        with {:ok, suffix} <- parse_plain_suffix_format(expr, var) do
          {:ok, var, suffix}
        else
          :error ->
            if parse_plain_from_int(expr, var) == :ok do
              {:ok, var, {:plain, ""}}
            else
              :error
            end
        end
    end
  end

  defp parse_threshold_format(expr, var) do
    with {:ok, threshold} <- parse_ge_threshold(expr, var),
         {:ok, divisor, suffix} <- parse_threshold_suffix_arm(Map.fetch!(expr, :then_expr), var) do
      if parse_plain_from_int(Map.fetch!(expr, :else_expr), var) == :ok do
        {:ok, threshold, divisor, suffix}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp parse_ge_threshold(%{op: :if, cond: cond}, var) do
    ge_compare_threshold(cond, var)
  end

  defp parse_ge_threshold(%{op: :compare, kind: kind, left: %{op: :var, name: name}, right: %{op: :int_literal, value: threshold}}, var)
       when name == var and kind in [:ge, :gte, :geq],
       do: {:ok, threshold}

  defp parse_ge_threshold(_, _), do: :error

  defp ge_compare_threshold(
         %{op: :if,
           cond: %{op: :compare, kind: :gt, left: %{op: :var, name: left}, right: %{op: :int_literal, value: threshold}},
           then_expr: %{op: :constructor_call, target: "True"},
           else_expr: %{op: :compare, kind: :eq, left: %{op: :var, name: right}, right: %{op: :int_literal, value: threshold2}}},
         var
       )
       when left == var and right == var and threshold == threshold2,
       do: {:ok, threshold}

  defp ge_compare_threshold(_, _), do: :error

  defp parse_threshold_suffix_arm(expr, var) do
    with {:ok, left, right} <- append_parts(expr),
         {:ok, "", suffix, int_expr} <- NativeStringMod.int_suffix_parts(left, right, int_env(var)),
         true <- int_expr_references_var?(int_expr, var),
         {:ok, divisor} <- idiv_divisor(int_expr, var) do
      {:ok, divisor, suffix}
    else
      _ -> :error
    end
  end

  defp parse_plain_suffix_format(expr, var) do
    with {:ok, left, right} <- append_parts(expr),
         {:ok, "", suffix, int_expr} <- NativeStringMod.int_suffix_parts(left, right, int_env(var)),
         true <- int_expr == %{op: :var, name: var} or int_expr_references_var?(int_expr, var),
         false <- String.contains?(suffix, <<0>>) do
      if int_expr == %{op: :var, name: var} do
        {:ok, {:plain, suffix}}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp parse_plain_from_int(%{op: :qualified_call, target: "String.fromInt", args: [%{op: :var, name: var}]}, var),
    do: :ok

  defp parse_plain_from_int(%{op: :runtime_call, function: "elmc_string_from_int", args: [%{op: :var, name: var}]}, var),
    do: :ok

  defp parse_plain_from_int(_, _), do: :error

  defp idiv_divisor(%{op: :call, name: "__idiv__", args: [%{op: :var, name: var}, %{op: :int_literal, value: divisor}]}, var)
       when is_integer(divisor),
       do: {:ok, divisor}

  defp idiv_divisor(%{op: :call, name: "__idiv__", args: [left, %{op: :int_literal, value: divisor}]}, var)
       when is_integer(divisor) do
    if int_expr_references_var?(left, var), do: {:ok, divisor}, else: :error
  end

  defp idiv_divisor(_, _), do: :error

  defp int_expr_references_var?(%{op: :var, name: name}, var), do: name == var

  defp int_expr_references_var?(%{op: op, var: name}, var) when op in [:add_const, :sub_const] and is_binary(name),
    do: name == var

  defp int_expr_references_var?(%{args: args}, var) when is_list(args),
    do: Enum.any?(args, &int_expr_references_var?(&1, var))

  defp int_expr_references_var?(%{left: left, right: right}, var),
    do: int_expr_references_var?(left, var) or int_expr_references_var?(right, var)

  defp int_expr_references_var?(_, _), do: false

  defp int_env(var), do: EnvBindings.put_native_int_binding(%{}, var, var)

  defp append_parts(%{op: :call, name: "__append__", args: [left, right]}), do: {:ok, left, right}

  defp append_parts(%{op: :runtime_call, function: fun, args: [left, right]})
       when fun in ["elmc_string_append", "elmc_append", "elmc_string_concat"],
       do: {:ok, left, right}

  defp append_parts(%{op: :qualified_call, target: target, args: [left, right]})
       when target in ["Basics.append", "String.append", "++"],
       do: {:ok, left, right}

  defp append_parts(_), do: :error

  defp nothing_branch_text(branches) do
    case Enum.find(branches, &nothing_branch?/1) do
      %{expr: %{op: :string_literal, value: value}} when is_binary(value) ->
        if String.contains?(value, <<0>>), do: :error, else: {:ok, value}

      _ ->
        :error
    end
  end

  defp nothing_branch?(%{pattern: %{kind: :constructor, name: name}}) when name in ["Nothing", "Maybe.Nothing"],
    do: true

  defp nothing_branch?(_), do: false

  defp field_macro(module_name, fn_name, _param, field, decl_map) do
    with {:ok, model_type} <- record_param_type(module_name, fn_name, decl_map),
         macro when is_binary(macro) <- FusionSupport.field_macro(module_name, model_type, field) do
      macro
    else
      _ -> nil
    end
  end

  defp record_param_type(module_name, fn_name, decl_map) do
    case Map.get(decl_map, {module_name, fn_name}) do
      %{type: type} when is_binary(type) ->
        case String.split(type, " -> ") do
          [arg, _] -> {:ok, type_basename(arg)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp type_basename(type) when is_binary(type) do
    type |> String.split(".") |> List.last()
  end

  defp fusion_param_name(module_name, name, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: [param | _]} when is_binary(param) -> param
      _ -> nil
    end
  end

  defp escape_snprintf_literal(""), do: ""

  defp escape_snprintf_literal(literal) do
    literal |> Util.escape_c_string() |> String.replace("%", "%%")
  end

  @doc false
  @spec extract_fusion_data(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, :maybe_int_string, Types.fusion_metadata()} | :error
  def extract_fusion_data(module_name, name, expr, decl_map) do
    case extract_default_append_fusion(module_name, name, expr, decl_map) do
      {:ok, data} ->
        {:ok, :maybe_int_string, data}

      :error ->
        case extract_maybe_case_fusion(module_name, name, expr, decl_map) do
          {:ok, data} -> {:ok, :maybe_int_string, data}
          :error -> :error
        end
    end
  end

  defp extract_default_append_fusion(module_name, name, expr, decl_map) do
    with param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         {:ok, ^param, field, default, suffix} <- parse_maybe_with_default_append(expr),
         {:ok, model_type} <- record_param_type(module_name, name, decl_map),
         idx when is_integer(idx) <- FusionSupport.field_index(module_name, model_type, field) do
      {:ok, %{mode: :default_append, field: idx, default: default, suffix: suffix}}
    else
      _ -> :error
    end
  end

  defp extract_maybe_case_fusion(module_name, name, expr, decl_map) do
    with param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         {:ok, ^param, field, branches} <- parse_maybe_int_case(expr),
         {:ok, nothing_text} <- nothing_branch_text(branches),
         {:ok, _int_var, format} <- parse_just_int_format(branches),
         {:ok, model_type} <- record_param_type(module_name, name, decl_map),
         idx when is_integer(idx) <- FusionSupport.field_index(module_name, model_type, field) do
      {:ok,
       %{
         mode: :maybe_case,
         field: idx,
         nothing: nothing_text,
         format: wire_format(format)
       }}
    else
      _ -> :error
    end
  end

  defp wire_format({:plain, suffix}), do: %{kind: :plain, suffix: suffix}

  defp wire_format({:threshold, threshold, divisor, suffix}),
    do: %{kind: :threshold, threshold: threshold, divisor: divisor, suffix: suffix}
end
