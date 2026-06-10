defmodule Elmc.Backend.CCodegen.OwnershipCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Types

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
      "elmc_release(#{ref});\n"
    end
  end

  defp boxed_release_var?(value) when is_binary(value) do
    Regex.match?(
      ~r/^(tmp_\d+|head_\d+|list_|rec_|call_|result_|arg_|current_|field_|item_|out_)/,
      value
    )
  end
end
