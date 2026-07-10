defmodule Elmc.Backend.CCodegen.MaybeWithDefaultPickSlot do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{CSource, FusionSupport, Util}

  @pick_slot_names ~w(pickSlot)

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         {:ok, model_var, default_tag, pick_mod, pick_name, slots_expr} <- parse(expr, module_name),
         true <- model_var == param do
      slots_call = emit_slots_expr(module_name, slots_expr, param)
      pick_callee = Util.module_fn_name(pick_mod, pick_name)
      c_prefix = Util.module_fn_name(module_name, name)

      core = """
      ElmcValue *maybe_pick = NULL;
        Rc = #{pick_callee}(&maybe_pick, #{param}, #{slots_call});
        CHECK_RC(Rc);
        elmc_int_t tag = elmc_maybe_with_default_int(#{default_tag}, maybe_pick);
        Rc = elmc_new_int(out, tag);
        CHECK_RC(Rc);
      """

      body = """
      static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{param}) {
        RC Rc = RC_SUCCESS;
        CATCH_BEGIN
      #{CSource.indent(String.trim(core), 2)}
        CATCH_END
        return Rc;
      }
      """

      FusionSupport.ok_rc(body, [{pick_mod, pick_name}, slots_callee(slots_expr, module_name)])
    else
      _ -> :error
    end
  end

  defp parse(expr, module_name) do
    case parse_with_default(expr) do
      {:ok, _model, _default, _pick_mod, _pick_name, _slots} = ok ->
        ok

      :error ->
        parse_case_default(expr, module_name)
    end
  end

  defp parse_with_default(%{op: :qualified_call, target: "Maybe.withDefault", args: [default, pick_call]}) do
    with {:ok, default_tag} <- default_ctor_tag(default),
         {:ok, model_var, pick_mod, pick_name, slots_expr} <- parse_pick_slot_call(pick_call) do
      {:ok, model_var, default_tag, pick_mod, pick_name, slots_expr}
    end
  end

  defp parse_with_default(_), do: :error

  defp parse_case_default(
         %{
           op: :case,
           subject: subject,
           branches: [
             %{pattern: %{kind: :constructor, name: just_name} = just_pat, expr: just_expr},
             %{pattern: %{kind: :constructor, name: nothing_name}, expr: default_expr}
           ]
         },
         _module_name
       ) do
    with true <- just_ctor?(just_name),
         true <- nothing_ctor?(nothing_name),
         {:ok, model_var, pick_mod, pick_name, slots_expr} <- parse_pick_slot_subject(subject),
         {:ok, default_tag} <- default_ctor_tag(default_expr),
         true <- wildcard_just?(just_expr) or var_expr?(just_expr, model_var) or payload_var_just?(just_pat) do
      {:ok, model_var, default_tag, pick_mod, pick_name, slots_expr}
    else
      _ -> :error
    end
  end

  defp parse_case_default(%{op: :let_in, in_expr: body}, module_name),
    do: parse_case_default(body, module_name)

  defp parse_case_default(_, _), do: :error

  defp just_ctor?(name), do: short_name(name) == "Just"
  defp nothing_ctor?(name), do: short_name(name) == "Nothing"

  defp wildcard_just?(%{op: :var}), do: true
  defp wildcard_just?(_), do: false

  defp payload_var_just?(%{arg_pattern: %{kind: :var}}), do: true
  defp payload_var_just?(_), do: false

  defp var_expr?(%{op: :var, name: name}, name), do: true
  defp var_expr?(_, _), do: false

  defp parse_pick_slot_call(expr), do: parse_pick_slot_subject(expr)

  defp parse_pick_slot_subject(%{op: :qualified_call, target: target, args: [model, slots]})
       when is_binary(target) do
  parse_pick_slot_target(target, model, slots)
  end

  defp parse_pick_slot_subject(%{op: :call, target: {mod, name}, args: [model, slots]})
       when is_binary(mod) and is_binary(name) do
    if short_name(name) in @pick_slot_names do
      with %{op: :var, name: model_var} <- model do
        {:ok, model_var, mod, name, slots}
      end
    else
      :error
    end
  end

  defp parse_pick_slot_subject(%{op: :call, name: name, args: [model, slots]}) when is_binary(name) do
    if short_name(name) in @pick_slot_names do
      with %{op: :var, name: model_var} <- model do
        {:ok, model_var, "Main", name, slots}
      end
    else
      :error
    end
  end

  defp parse_pick_slot_subject(_), do: :error

  defp parse_pick_slot_target(target, model, slots) do
    if short_name(target) in @pick_slot_names do
      with %{op: :var, name: model_var} <- model,
           {mod, name} <- callee_module_name(target) do
        {:ok, model_var, mod, name, slots}
      end
    else
      :error
    end
  end

  defp callee_module_name(target) do
    case String.split(target, ".", parts: 2) do
      [mod, name] -> {mod, name}
      [name] -> {"Main", name}
    end
  end

  defp default_ctor_tag(%{op: :int_literal, value: tag, union_ctor: ctor}) when is_integer(tag) do
    {:ok, ctor_tag_literal(tag, ctor)}
  end

  defp default_ctor_tag(%{op: :constructor_call, target: target, args: []}) when is_binary(target) do
    lookup_ctor_tag(target)
  end

  defp default_ctor_tag(%{op: :qualified_call, target: target, args: []}) when is_binary(target) do
    lookup_ctor_tag(target)
  end

  defp default_ctor_tag(%{op: :var, name: name}) when is_binary(name) do
    lookup_ctor_tag(name)
  end

  defp default_ctor_tag(_), do: :error

  defp lookup_ctor_tag(name) when is_binary(name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    case Map.get(tags, name) || Map.get(tags, short_name(name)) do
      tag when is_integer(tag) -> {:ok, Integer.to_string(tag)}
      _ -> :error
    end
  end

  defp ctor_tag_literal(tag, ctor) when is_binary(ctor) do
    case lookup_ctor_tag(ctor) do
      {:ok, lit} -> lit
      :error -> Integer.to_string(tag)
    end
  end

  defp ctor_tag_literal(tag, _), do: Integer.to_string(tag)

  defp emit_slots_expr(module_name, slots_expr, model_param) do
    case slots_expr do
      %{op: :qualified_call, target: target, args: [%{op: :var, name: ^model_param}]} ->
        {mod, name} = callee_module_name(target)
        "#{Util.module_fn_name(mod, name)}(#{model_param})"

      %{op: :call, target: {mod, name}, args: [%{op: :var, name: ^model_param}]} ->
        "#{Util.module_fn_name(mod, name)}(#{model_param})"

      %{op: :call, name: name, args: [%{op: :var, name: ^model_param}]} ->
        "#{Util.module_fn_name(module_name, name)}(#{model_param})"

      _ ->
        "NULL"
    end
  end

  defp slots_callee(%{op: :qualified_call, target: target, args: _}, _module_name) do
    callee_module_name(target)
  end

  defp slots_callee(%{op: :call, target: {mod, name}, args: _}, _module_name), do: {mod, name}

  defp slots_callee(%{op: :call, name: name, args: _}, module_name), do: {module_name, name}

  defp slots_callee(_, module_name), do: {module_name, "slots"}

  defp fusion_param_name(module_name, name, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: [param | _]} when is_binary(param) -> param
      _ -> nil
    end
  end

  defp short_name(name), do: name |> String.split(".") |> List.last()
end
