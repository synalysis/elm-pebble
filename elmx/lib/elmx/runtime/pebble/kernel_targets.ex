defmodule Elmx.Runtime.Pebble.KernelTargets do
  @moduledoc """
  Lowers `Elm.Kernel.PebbleWatch` / `Elm.Kernel.PebblePhone` qualified calls to runtime IR nodes.
  """

  alias Elmx.Runtime.Pebble.Subscriptions
  alias Elmx.Types

  @watch_prefix "Elm.Kernel.PebbleWatch."
  @phone_prefix "Elm.Kernel.PebblePhone."

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.rewrite_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    cond do
      String.starts_with?(target, @watch_prefix) ->
        rewrite_watch(String.replace_prefix(target, @watch_prefix, ""), target, args)

      String.starts_with?(target, @phone_prefix) ->
        {:ok, %{op: :runtime_call, function: kernel_phone_function(target), args: args}}

      true ->
        :error
    end
  end

  defp rewrite_watch("none", _target, _args), do: {:ok, %{op: :cmd_none}}

  defp rewrite_watch("onFrame", _target, args),
    do: {:ok, %{op: :runtime_call, function: "elmx_frame_every", args: args}}

  defp rewrite_watch("on" <> _rest, target, args) do
    case Subscriptions.mask(target) do
      nil -> :error
      _ -> {:ok, %{op: :runtime_call, function: "elmx_subscription_call", args: [target_string_ir(target) | args]}}
    end
  end

  defp rewrite_watch(_name, target, args) do
    {:ok, %{op: :runtime_call, function: kernel_watch_function(target), args: args}}
  end

  @spec kernel_watch_function(String.t()) :: String.t()
  def kernel_watch_function(target) when is_binary(target) do
    target
    |> String.replace_prefix(@watch_prefix, "")
    |> Macro.underscore()
    |> then(&("elmx_kernel_pebble_watch_" <> &1))
  end

  @spec kernel_phone_function(String.t()) :: String.t()
  def kernel_phone_function(target) when is_binary(target) do
    target
    |> String.replace_prefix(@phone_prefix, "")
    |> Macro.underscore()
    |> then(&("elmx_kernel_pebble_phone_" <> &1))
  end

  defp target_string_ir(target) when is_binary(target), do: %{op: :string_literal, value: target}
end
