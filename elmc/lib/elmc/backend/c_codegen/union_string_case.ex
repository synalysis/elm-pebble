defmodule Elmc.Backend.CCodegen.UnionStringCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{ConstructorTagCase, CSource, FusionSupport, RcRuntimeEmit, Util}

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, subject, branches} <- parse_case(expr),
         param when is_binary(param) <- fusion_param_name(module_name, name, subject, decl_map),
         true <- ConstructorTagCase.branches?(branches),
         true <- union_string_case_eligible?(branches) do
      env = fusion_env(module_name, name, param)
      subject = %{op: :var, name: param}
      {core, _out, _} = ConstructorTagCase.compile(subject, branches, env, 0)
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

  defp parse_case(%{op: :case, subject: subject, branches: branches}),
    do: {:ok, subject, branches}

  defp parse_case(%{op: :let_in, in_expr: body}), do: parse_case(body)
  defp parse_case(_), do: :error

  defp union_string_case_eligible?(branches) when is_list(branches) do
    string_count =
      Enum.count(branches, fn branch ->
        match?({:string, _}, branch_string_spec(branch))
      end)

    string_count >= 2 and
      Enum.all?(branches, fn branch ->
        case branch_string_spec(branch) do
          {:string, _} -> true
          :zero -> true
          _ -> false
        end
      end)
  end

  defp branch_string_spec(%{expr: expr}), do: string_expr_spec(expr)

  defp string_expr_spec(%{op: :int_literal, value: 0}), do: :zero

  defp string_expr_spec(%{op: :string_literal, value: value}) when is_binary(value) do
    if String.contains?(value, <<0>>), do: :complex, else: {:string, value}
  end

  defp string_expr_spec(_), do: :complex

  defp subject_param_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp subject_param_name(_), do: "subject"

  defp fusion_param_name(module_name, name, subject, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: [param | _]} when is_binary(param) -> param
      _ -> subject_param_name(subject)
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
