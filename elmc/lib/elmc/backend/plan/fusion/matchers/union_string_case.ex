defmodule Elmc.Backend.Plan.Fusion.Matchers.UnionStringCase do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.Types

  alias Elmc.Backend.Plan.Fusion.Matchers.FusionSupport
  alias Elmc.Backend.CCodegen.{ConstructorTagCase, CSource, RcRuntimeEmit, Util}

  @spec try_emit(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
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

  @spec parse_case(map() | term()) :: Types.ir_expr()

  defp parse_case(%{op: :case, subject: subject, branches: branches}),
    do: {:ok, subject, branches}

  defp parse_case(%{op: :let_in, in_expr: body}), do: parse_case(body)
  defp parse_case(_), do: :error

  @spec union_string_case_eligible?(list()) :: boolean()

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

  @spec branch_string_spec(map()) :: Types.ir_expr()

  defp branch_string_spec(%{expr: expr}), do: string_expr_spec(expr)

  @spec string_expr_spec(map() | term()) :: Types.ir_expr()

  defp string_expr_spec(%{op: :int_literal, value: 0}), do: :zero

  defp string_expr_spec(%{op: :string_literal, value: value}) when is_binary(value) do
    if String.contains?(value, <<0>>), do: :complex, else: {:string, value}
  end

  defp string_expr_spec(_), do: :complex

  @spec subject_param_name(map() | term()) :: String.t() | nil

  defp subject_param_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp subject_param_name(name) when is_binary(name), do: name
  # Computed subjects are not function params — refuse fusion rather than inventing one.
  defp subject_param_name(_), do: nil

  @spec fusion_param_name(String.t(), String.t(), Types.expr(), Types.decl_map()) :: String.t() | nil

  defp fusion_param_name(module_name, name, subject, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: [param | _]} when is_binary(param) ->
        param

      %{args: args} when is_list(args) ->
        case subject_param_name(subject) do
          param when is_binary(param) ->
            if param in args, do: param, else: nil

          _ ->
            nil
        end

      _ ->
        subject_param_name(subject)
    end
  end

  @spec fusion_env(String.t(), String.t(), String.t()) :: Types.ir_expr()

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
          {:ok, :union_string_lut, Types.fusion_metadata()} | :error
  def extract_fusion_data(_module_name, _name, expr, _decl_map) do
    with {:ok, _subject, branches} <- parse_case(expr),
         true <- union_string_case_eligible?(branches),
         lut when map_size(lut) > 0 <- union_string_lut(branches) do
      {:ok, :union_string_lut, %{lut: lut}}
    else
      _ -> :error
    end
  end

  @spec union_string_lut(list()) :: Types.ir_expr()

  defp union_string_lut(branches) do
    Map.new(branches, fn branch ->
      tag = Map.get(branch.pattern, :tag)

      value =
        case branch_string_spec(branch) do
          {:string, text} -> text
          :zero -> ""
          _ -> nil
        end

      {tag, value}
    end)
    |> Enum.reject(fn {_tag, value} -> is_nil(value) end)
    |> Map.new()
  end
end
