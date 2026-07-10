defmodule Elmc.Backend.CCodegen.UnionIntCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{
    ConstructorTagCase,
    CSource,
    EnvBindings,
    Fusion,
    FusionSupport,
    IntLiteralRef,
    RcRuntimeEmit,
    Util
  }

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, _subject, branches} <- parse_case(expr),
         param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         true <- ConstructorTagCase.branches?(branches),
         true <- union_int_case_eligible?(branches) do
      env =
        module_name
        |> fusion_env(name, param)
        |> EnvBindings.put_native_int_binding(param, param)

      core = emit_native_int_tag_switch(branches, env, param)
      c_prefix = Util.module_fn_name(module_name, name)
      Fusion.register_union_int_lut(module_name, name, union_int_lut(branches))

      body = """
      static RC #{c_prefix}_native(ElmcValue **out, elmc_int_t #{param}) {
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

  defp emit_native_int_tag_switch(branches, env, param) do
    int_scratch = "case_int_1"
    exhaustive? = Enum.all?(branches, fn %{pattern: pattern} -> not match?(%{kind: :wildcard}, pattern) end)

    branch_code =
      branches
      |> Enum.map(fn branch ->
        {:slot, ref} = branch_int_spec(branch, env)
        label = case_label(branch.pattern, env)

        """
        #{label}: {
          #{int_scratch} = #{ref};
          break;
        }
        """
        |> String.trim_trailing()
        |> CSource.indent(2)
      end)
      |> Enum.join("\n")

    default_case =
      if exhaustive? do
        ""
      else
        """
        default:
          #{int_scratch} = 0;
          break;
        """
        |> String.trim()
        |> CSource.indent(2)
      end

    post_box =
      if exhaustive? do
        "Rc = elmc_new_int(out, #{int_scratch});\nCHECK_RC(Rc);"
      else
        """
        if (#{int_scratch} >= 0) {
          Rc = elmc_new_int(out, #{int_scratch});
          CHECK_RC(Rc);
        }
        """
        |> String.trim()
      end

    {int_decl, int_init} =
      if exhaustive? do
        {"elmc_int_t #{int_scratch};", "  #{int_scratch} = 0;"}
      else
        {"elmc_int_t #{int_scratch} = -1;", ""}
      end

    """
    #{int_decl}
    #{int_init}
      switch (#{param}) {
    #{branch_code}
    #{default_case}
      }
    #{post_box}
    """
  end

  defp case_label(%{kind: :wildcard}, _env), do: "default"

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

  defp branch_int_spec(%{expr: expr}, env) do
    int_expr_spec(expr, env)
  end

  defp parse_case(%{op: :case, subject: subject, branches: branches}),
    do: {:ok, subject, branches}

  defp parse_case(%{op: :let_in, in_expr: body}), do: parse_case(body)
  defp parse_case(_), do: :error

  defp union_int_case_eligible?(branches) when is_list(branches) do
    int_count = Enum.count(branches, &int_literal_branch?/1)
    int_count >= 2 and Enum.all?(branches, &int_literal_branch?/1)
  end

  defp int_literal_branch?(%{expr: %{op: :int_literal, value: value}}) when is_integer(value), do: true
  defp int_literal_branch?(_), do: false

  defp union_int_lut(branches) do
    Map.new(branches, fn %{pattern: %{tag: tag}, expr: %{op: :int_literal, value: wire}} ->
      {tag, wire}
    end)
  end

  defp int_expr_spec(%{op: :int_literal, value: value} = expr, env)
       when is_integer(value) do
    {:slot, IntLiteralRef.ref(expr, env)}
  end

  defp int_expr_spec(_expr, _env), do: :complex

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
