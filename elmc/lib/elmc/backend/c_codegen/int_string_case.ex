defmodule Elmc.Backend.CCodegen.IntStringCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  alias Elmc.Backend.CCodegen.{
    CSource,
    EnvBindings,
    FusionSupport,
    Native.IntCase,
    RcRuntimeEmit,
    Util
  }

  @spec try_emit(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, branches} <- parse_int_string_case(expr),
         param when is_binary(param) <- fusion_param_name(module_name, name, decl_map),
         int_branches = int_case_branches(branches),
         true <- IntCase.branches?(int_branches),
         true <- int_string_lut_eligible?(int_branches) do
      env =
        module_name
        |> fusion_env(name, param)
        |> EnvBindings.put_native_int_binding(param, param)

      subject = %{op: :var, name: param}
      {core, _out, _} = IntCase.compile(subject, int_branches, env, 0)
      c_prefix = Util.module_fn_name(module_name, name)

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

  defp parse_int_string_case(%{op: :case, branches: branches}) when is_list(branches),
    do: {:ok, branches}

  defp parse_int_string_case(%{op: :let_in, in_expr: body}), do: parse_int_string_case(body)
  defp parse_int_string_case(_), do: :error

  defp int_case_branches(branches) do
    Enum.map(branches, fn branch ->
      %{branch | pattern: int_pattern(branch.pattern)}
    end)
  end

  defp int_pattern(%{kind: :int} = pattern), do: pattern
  defp int_pattern(%{kind: :wildcard} = pattern), do: pattern
  defp int_pattern(_), do: %{kind: :wildcard}

  defp int_string_lut_eligible?(branches) do
    explicit =
      Enum.count(branches, fn
        %{pattern: %{kind: :int, value: _}, expr: %{op: :string_literal, value: value}}
        when is_binary(value) ->
          not String.contains?(value, <<0>>)

        _ ->
          false
      end)

    explicit >= 3 and
      Enum.all?(branches, fn %{expr: expr} ->
        match?(%{op: :string_literal, value: v} when is_binary(v), expr)
      end)
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

  @doc false
  @spec extract_fusion_data(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, :int_string_lut, Types.fusion_metadata()} | :error
  def extract_fusion_data(_module_name, _name, expr, _decl_map) do
    with {:ok, branches} <- parse_int_string_case(expr),
         int_branches = int_case_branches(branches),
         true <- IntCase.branches?(int_branches),
         true <- int_string_lut_eligible?(int_branches),
         {lut, default} <- int_string_lut(int_branches) do
      data = if default, do: %{lut: lut, default: default}, else: %{lut: lut}
      {:ok, :int_string_lut, data}
    else
      _ -> :error
    end
  end

  defp int_string_lut(branches) do
    lut =
      for %{pattern: %{kind: :int, value: key}, expr: %{op: :string_literal, value: text}} <- branches,
          into: %{} do
        {key, text}
      end

    default =
      Enum.find_value(branches, fn
        %{pattern: %{kind: :wildcard}, expr: %{op: :string_literal, value: text}} -> text
        _ -> nil
      end)

    if map_size(lut) > 0, do: {lut, default}, else: :error
  end
end
