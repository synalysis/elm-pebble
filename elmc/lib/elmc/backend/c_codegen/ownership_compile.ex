defmodule Elmc.Backend.CCodegen.OwnershipCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @type operand_mode :: :borrow | :retain | :take
  @type use_site :: :call_arg | :compare | :record_update | :record_field | :return

  @spec operand_mode(Types.compile_env(), String.t(), use_site()) :: operand_mode()
  def operand_mode(env, ref, use_site) when is_binary(ref) do
    if borrow_ref?(env, ref, use_site), do: :borrow, else: :retain
  end

  @spec borrow_ref?(Types.compile_env(), String.t(), use_site()) :: boolean()
  def borrow_ref?(env, ref, _use_site) when is_binary(ref) do
    cond do
      EnvBindings.borrowed_arg_ref?(env, ref) ->
        true

      true ->
        false
    end
  end

  @spec release_if_owned(Types.compile_env(), String.t(), use_site()) :: String.t()
  def release_if_owned(env, ref, use_site) when is_binary(ref) do
    if operand_mode(env, ref, use_site) == :borrow or not boxed_release_var?(ref) do
      ""
    else
      ValueSlots.release_consumed(ref) <> "\n"
    end
  end

  defp boxed_release_var?(value) when is_binary(value) do
    Regex.match?(
      ~r/^(tmp_\d+|head_\d+|list_|rec_|call_|result_|arg_|current_|field_|item_|out_)/,
      value
    )
  end

  @doc """
  When a `borrow_arg` + `retain_result` function returns a borrowed `List` parameter
  as owned output, retain would alias the caller's spine and can create cycles in
  recursive list algorithms (for example 2048 `merge`). Copy to a fresh list instead.
  """
  @spec retain_owned_expr(Types.compile_env(), Types.binding_name(), String.t()) ::
          String.t() | nil
  def retain_owned_expr(env, name, source) when is_binary(name) and is_binary(source) do
    cond do
      tuple_projection = ValueSlots.tuple_projection_retain_c_expr(source) ->
        tuple_projection

      owned_projection_retain_expr = owned_projection_retain_expr(source) ->
        owned_projection_retain_expr

      Map.get(env, :__owned_list_result__, false) and
          copy_borrowed_list_for_result?(env, name, source) ->
        {:list_copy, source}

      true ->
        nil
    end
  end

  @spec owned_projection_retain_expr(String.t()) :: String.t() | nil
  def owned_projection_retain_expr(source) when is_binary(source) do
    case Regex.run(~r/^elmc_maybe_or_tuple_just_payload_borrow\((.+)\)$/s, source) do
      [_, maybe_ref] -> "elmc_maybe_or_tuple_just_payload(#{maybe_ref})"
      _ -> nil
    end
  end

  def owned_projection_retain_expr(_source), do: nil

  @spec copy_borrowed_list_for_result?(Types.compile_env(), Types.binding_name(), String.t()) ::
          boolean()
  defp copy_borrowed_list_for_result?(env, name, source) do
    retain_result_function?(env) and list_var?(env, name) and
      (EnvBindings.borrowed_arg_ref?(env, source) or EnvBindings.direct_param_ref?(env, source))
  end

  @spec retain_result_function?(Types.compile_env()) :: boolean()
  defp retain_result_function?(env) do
    module = Map.get(env, :__module__)
    fn_name = Map.get(env, :__function_name__)

    case Map.get(Map.get(env, :__program_decls__, %{}), {module, fn_name}) do
      %{ownership: ownership} when is_list(ownership) -> :retain_result in ownership
      _ -> false
    end
  end

  @spec list_var?(Types.compile_env(), Types.binding_name()) :: boolean()
  defp list_var?(env, name) do
    key = Host.binding_key(name)

    case get_in(env, [:__var_types__, key]) do
      "List" <> _ -> true
      _ -> false
    end
  end
end
