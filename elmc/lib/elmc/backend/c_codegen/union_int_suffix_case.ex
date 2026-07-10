defmodule Elmc.Backend.CCodegen.UnionIntSuffixCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{
    ConstructorTagCase,
    CSource,
    EnvBindings,
    FusionSupport,
    Host,
    IntLiteralRef,
    Native.Int,
    RcRuntimeEmit,
    Util
  }

  alias Elmc.Backend.CCodegen.Native.String, as: NativeStringMod

  @buf_size 22

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    case try_emit_maybe_union_suffix(module_name, name, expr, decl_map) do
      {:ok, _, _, :rc_native} = ok ->
        ok

      :error ->
        try_emit_direct_union_suffix(module_name, name, expr, decl_map)
    end
  end

  defp try_emit_direct_union_suffix(module_name, name, expr, decl_map) do
    with {:ok, _subject, branches} <- parse_case(expr),
         param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         true <- ConstructorTagCase.branches?(branches),
         true <- union_int_suffix_eligible?(branches),
         {:ok, branch_specs} <- branch_specs(branches) do
      env = fusion_env(module_name, name, param)
      core = emit_native_suffix_switch(param, branch_specs, env)
      {:ok, emit_rc_native_helper(module_name, name, param, core)}
    else
      _ -> :error
    end
    |> case do
      {:ok, {:ok, _, _, :rc_native} = ok} -> ok
      :error -> :error
    end
  end

  defp try_emit_maybe_union_suffix(module_name, name, expr, decl_map) do
    with param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         {:ok, source, branches} <- parse_maybe_union_case(expr),
         true <- param_matches_source?(param, source),
         {:ok, nothing_text} <- nothing_branch_text(branches),
         {:ok, branch_specs} <- maybe_union_branch_specs(branches),
         {:ok, core} <-
           emit_maybe_union_core(module_name, param, source, nothing_text, branch_specs, name, decl_map) do
      emit_rc_native_helper(module_name, name, param, core)
    else
      _ -> :error
    end
  end

  defp emit_rc_native_helper(module_name, name, param, core) do
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
  end

  defp emit_native_suffix_switch(subject_ref, branch_specs, env) do
    tag_ref = "case_msg_tag_1"
    payload_ref = "elmc_as_int(elmc_union_payload(#{subject_ref}))"

    branch_code =
      branch_specs
      |> Enum.map(fn {pattern, prefix, suffix, int_expr} ->
        label = case_label(pattern, env)
        {:ok, payload_var} = payload_var(pattern)

        branch_env =
          env
          |> EnvBindings.put_native_int_binding(payload_var, payload_ref)

        {value_code, value_ref, _} = Int.compile_expr(int_expr, branch_env, 0)
        format = snprintf_format(prefix, suffix)
        buf = "native_suffix_buf_#{Map.get(pattern, :tag, 0)}"

        """
        #{label}: {
        #{CSource.indent(String.trim(value_code), 2)}
          char #{buf}[#{@buf_size}];
          snprintf(#{buf}, sizeof(#{buf}), #{format}, (long long)#{value_ref});
          Rc = elmc_new_string(out, #{buf});
          CHECK_RC(Rc);
          break;
        }
        """
        |> String.trim_trailing()
        |> CSource.indent(2)
      end)
      |> Enum.join("\n")

    """
    const int #{tag_ref} = #{message_tag_expr(subject_ref)};
      switch (#{tag_ref}) {
    #{branch_code}
      }
    """
  end

  defp branch_specs(branches) do
    specs =
      Enum.map(branches, fn branch ->
        with {:ok, var} <- payload_var(branch.pattern),
             {:ok, prefix, suffix, int_expr} <- parse_suffix_append(branch.expr, var) do
          {:ok, {branch.pattern, prefix, suffix, int_expr}}
        else
          _ -> :error
        end
      end)

    if Enum.all?(specs, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(specs, fn {:ok, spec} -> spec end)}
    else
      :error
    end
  end

  defp union_int_suffix_eligible?(branches) when is_list(branches) do
    length(branches) >= 2 and
      Enum.all?(branches, fn branch ->
        match?({:ok, _}, payload_var(branch.pattern)) and
          match?({:ok, _, _, _}, parse_suffix_append(branch.expr, elem(payload_var(branch.pattern), 1)))
      end)
  end

  defp union_int_suffix_eligible?(_), do: false

  defp parse_suffix_append(expr, payload_var) do
    suffix_env =
      %{}
      |> EnvBindings.put_native_int_binding(payload_var, payload_var)

    case append_parts(expr) do
      {:ok, left, right} ->
        case NativeStringMod.int_suffix_parts(left, right, suffix_env) do
          {:ok, prefix, suffix, int_expr} ->
            if int_expr_references_payload?(int_expr, payload_var) do
              {:ok, prefix, suffix, int_expr}
            else
              :error
            end

          :error ->
            :error
        end

      :error ->
        :error
    end
  end

  defp append_parts(%{op: :call, name: "__append__", args: [left, right]}),
    do: {:ok, left, right}

  defp append_parts(%{op: :runtime_call, function: fun, args: [left, right]})
       when fun in ["elmc_string_append", "elmc_append", "elmc_string_concat"],
       do: {:ok, left, right}

  defp append_parts(%{op: :qualified_call, target: target, args: [left, right]})
       when target in ["Basics.append", "String.append", "++"],
       do: {:ok, left, right}

  defp append_parts(%{op: :call, name: name, args: [left, right]})
       when name in ["append", "++"],
       do: {:ok, left, right}

  defp append_parts(_), do: :error

  defp int_expr_references_payload?(%{op: :var, name: name}, payload_var),
    do: name == payload_var

  defp int_expr_references_payload?(expr, payload_var) do
    Host.native_int_expr?(expr, %{payload_var_name() => payload_var}) and
      subtree_references_var?(expr, payload_var)
  end

  defp subtree_references_var?(%{op: :var, name: name}, payload_var), do: name == payload_var

  defp subtree_references_var?(%{op: op, var: name}, payload_var)
       when op in [:add_const, :sub_const] and is_binary(name),
       do: name == payload_var

  defp subtree_references_var?(%{args: args}, payload_var) when is_list(args),
    do: Enum.any?(args, &subtree_references_var?(&1, payload_var))

  defp subtree_references_var?(%{left: left, right: right}, payload_var),
    do: subtree_references_var?(left, payload_var) or subtree_references_var?(right, payload_var)

  defp subtree_references_var?(%{arg: arg}, payload_var),
    do: subtree_references_var?(arg, payload_var)

  defp subtree_references_var?(_, _), do: false

  defp payload_var(%{kind: :constructor, bind: name}) when is_binary(name),
    do: {:ok, name}

  defp payload_var(%{kind: :constructor, arg_pattern: %{kind: :var, name: name}}) when is_binary(name),
    do: {:ok, name}

  defp payload_var(%{kind: :constructor, arg_pattern: %{kind: :var, bind: name}}) when is_binary(name),
    do: {:ok, name}

  defp payload_var(_), do: :error

  defp payload_var_name, do: "__union_payload_int__"

  defp snprintf_format(prefix, suffix) do
    "\"#{escape_snprintf_literal(prefix)}%lld#{escape_snprintf_literal(suffix)}\""
  end

  defp escape_snprintf_literal(""), do: ""

  defp escape_snprintf_literal(literal) do
    literal |> Util.escape_c_string() |> String.replace("%", "%%")
  end

  defp message_tag_expr(subject_ref) do
    "(#{subject_ref} && (#{subject_ref})->tag == ELMC_TAG_INT ? elmc_as_int(#{subject_ref}) : " <>
      "(#{subject_ref} && (#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL ? " <>
      "elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) : -1))"
  end

  defp case_label(%{kind: :constructor, tag: tag} = pattern, env) when is_integer(tag) do
    ref =
      pattern
      |> Map.get(:resolved_name)
      |> case do
        name when is_binary(name) ->
          IntLiteralRef.ref(%{op: :int_literal, value: tag, union_ctor: name}, env)

        _ ->
          nil
      end

    "case #{ref || Integer.to_string(tag)}"
  end

  defp parse_case(%{op: :case, subject: _subject, branches: branches}),
    do: {:ok, nil, branches}

  defp parse_case(%{op: :let_in, in_expr: body}), do: parse_case(body)
  defp parse_case(_), do: :error

  defp parse_maybe_union_case(%{op: :let_in, value_expr: source, in_expr: %{op: :case, branches: branches}}) do
    case parse_maybe_union_source(source) do
      {:ok, parsed_source} -> {:ok, parsed_source, branches}
      :error -> :error
    end
  end

  defp parse_maybe_union_case(_), do: :error

  defp parse_maybe_union_source(%{op: :qualified_call, target: "Maybe.map", args: [lam, src]}) do
    with %{op: :lambda, body: %{op: :field_access, field: inner_field}} <- lam,
         true <- is_binary(inner_field),
         {:ok, param, outer_field} <- param_field_access(src) do
      {:ok, {:map_field, param, outer_field, inner_field}}
    else
      _ -> :error
    end
  end

  defp parse_maybe_union_source(%{op: :field_access, arg: param, field: field})
       when is_binary(param) and is_binary(field) do
    {:ok, {:maybe_field, param, field}}
  end

  defp parse_maybe_union_source(_), do: :error

  defp param_field_access(%{op: :field_access, arg: %{op: :var, name: param}, field: field})
       when is_binary(param) and is_binary(field),
       do: {:ok, param, field}

  defp param_field_access(%{op: :field_access, arg: param, field: field})
       when is_binary(param) and is_binary(field),
       do: {:ok, param, field}

  defp param_field_access(_), do: :error

  defp param_matches_source?(param, {:map_field, param, _, _}), do: true
  defp param_matches_source?(param, {:maybe_field, param, _}), do: true
  defp param_matches_source?(_, _), do: false

  defp nothing_branch_text(branches) do
    case Enum.find(branches, &maybe_nothing_branch?/1) do
      %{expr: %{op: :string_literal, value: value}} when is_binary(value) ->
        if String.contains?(value, <<0>>), do: :error, else: {:ok, value}

      _ ->
        :error
    end
  end

  defp maybe_nothing_branch?(%{pattern: %{kind: :constructor, name: name}})
       when name in ["Nothing", "Maybe.Nothing"],
       do: true

  defp maybe_nothing_branch?(_), do: false

  defp maybe_union_branch_specs(branches) do
    specs =
      Enum.flat_map(branches, fn branch ->
        case maybe_union_branch_spec(branch) do
          {:ok, spec} -> [{:ok, spec}]
          :skip -> []
          :error -> [:error]
        end
      end)

    union_specs = Enum.filter(specs, &match?({:ok, _}, &1))

    if specs == [:error] or union_specs == [] do
      :error
    else
      {:ok, Enum.map(union_specs, fn {:ok, spec} -> spec end)}
    end
  end

  defp maybe_union_branch_spec(%{pattern: %{kind: :constructor, name: name}}) when name in ["Nothing", "Maybe.Nothing"],
    do: :skip

  defp maybe_union_branch_spec(%{pattern: pattern, expr: expr}) do
    with {:ok, inner_pattern} <- just_union_pattern(pattern),
         {:ok, var} <- payload_var(inner_pattern),
         {:ok, prefix, suffix, int_expr} <- parse_suffix_append(expr, var) do
      {:ok, {inner_pattern, prefix, suffix, int_expr}}
    else
      _ -> :error
    end
  end

  defp maybe_union_branch_spec(_), do: :error

  defp just_union_pattern(%{
         kind: :constructor,
         name: name,
         arg_pattern: %{kind: :constructor} = inner
       })
       when name in ["Just", "Maybe.Just"],
       do: {:ok, inner}

  defp just_union_pattern(_), do: :error

  defp emit_maybe_union_core(module_name, param, source, nothing_text, branch_specs, fn_name, decl_map) do
    env = fusion_env(module_name, fn_name, param)
    union_switch = emit_native_suffix_switch("union_val", branch_specs, env)
    default_lit = "\"#{Util.escape_c_string(nothing_text)}\""

    case source do
      {:map_field, ^param, outer_field, inner_field} ->
        with {:ok, model_type} <- record_param_type(module_name, fn_name, decl_map),
             outer_macro when is_binary(outer_macro) <-
               FusionSupport.field_macro(module_name, model_type, outer_field),
             {:ok, inner_type} <- nested_record_type_name(module_name, model_type, outer_field),
             inner_macro when is_binary(inner_macro) <-
               FusionSupport.field_macro(module_name, inner_type, inner_field) do
          {:ok,
           """
           ElmcValue *outer_maybe = elmc_record_get_index(#{param}, #{outer_macro});
             if (elmc_maybe_is_nothing(outer_maybe)) {
               Rc = elmc_new_string(out, #{default_lit});
               CHECK_RC(Rc);
             } else {
               ElmcValue *outer = elmc_maybe_just_payload(outer_maybe);
               ElmcValue *union_val = elmc_record_get_index(outer, #{inner_macro});
           #{CSource.indent(String.trim(union_switch), 2)}
             }
           """}
        else
          _ -> :error
        end

      {:maybe_field, ^param, field} ->
        with {:ok, model_type} <- record_param_type(module_name, fn_name, decl_map),
             field_macro when is_binary(field_macro) <-
               FusionSupport.field_macro(module_name, model_type, field) do
          {:ok,
           """
           ElmcValue *union_val = elmc_record_get_index(#{param}, #{field_macro});
             if (elmc_maybe_is_nothing(union_val)) {
               Rc = elmc_new_string(out, #{default_lit});
               CHECK_RC(Rc);
             } else {
               union_val = elmc_maybe_just_payload(union_val);
           #{CSource.indent(String.trim(union_switch), 2)}
             }
           """}
        else
          _ -> :error
        end
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

  defp nested_record_type_name(module_name, parent_type, field) do
    field_types =
      Process.get(:elmc_record_field_types, %{})
      |> Map.get({module_name, parent_type}, %{})

    case Map.get(field_types, field) do
      type when is_binary(type) ->
        type
        |> String.replace_prefix("Maybe ", "")
        |> type_basename()
        |> then(&{:ok, &1})

      _ ->
        :error
    end
  end

  defp type_basename(type) when is_binary(type) do
    type
    |> String.split(".")
    |> List.last()
  end

  defp fusion_param_name(module_name, name, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: [param | _]} when is_binary(param) -> param
      _ -> nil
    end
  end

  defp fusion_env(module_name, name, param) when is_binary(param) do
    %{
      :__rc_required__ => true,
      :__rc_catch__ => true,
      :__function_tail_compile__ => true,
      :__into_out__ => RcRuntimeEmit.function_out_ref(),
      :__module__ => module_name,
      :__function_name__ => name,
      :__function_args__ => [param],
      param => param
    }
  end
end
