defmodule Elmx.Runtime.Pebble.SpecialValues do
  @moduledoc false

  alias Elmx.Runtime.Pebble.KernelTargets
  alias Elmx.Runtime.Pebble.SpecialValues.Companion
  alias Elmx.Runtime.Pebble.SpecialValues.Http
  alias Elmx.Runtime.Pebble.SpecialValues.Json
  alias Elmx.Runtime.Pebble.SpecialValues.Platform
  alias Elmx.Runtime.Pebble.SpecialValues.Ui
  alias Elmx.Runtime.Pebble.SpecialValues.Watch
  alias Elmx.Types

  @dispatchers [Json, Ui, Companion, Http, Platform, Watch]

  @doc """
  Rewrites qualified-call IR to runtime-call nodes (mirrors `elmc` `special_value_from_target/2`).
  """
  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.rewrite_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    rewrite_qualified(canonical_target(target), args)
  end

  # Elm `import Cmd` / `import Sub` shorthands → platform modules (avoid bare `Cmd`/`Sub` keys).
  @spec canonical_target(String.t()) :: String.t()
  def canonical_target("Cmd." <> rest), do: "Platform.Cmd." <> rest
  def canonical_target("Sub." <> rest), do: "Platform.Sub." <> rest
  def canonical_target("Evts." <> rest), do: "Pebble.Events." <> rest
  def canonical_target("Ui." <> rest), do: "Pebble.Ui." <> rest
  def canonical_target("List." <> rest), do: "Elm.Kernel.List." <> rest
  def canonical_target(target) when is_binary(target), do: target

  @spec dispatchers() :: [module()]
  def dispatchers, do: @dispatchers

  defp rewrite_qualified(target, args) do
    case dispatch_rewrite(target, args) do
      {:ok, _} = ok ->
        ok

      :error ->
        kernel_targets_rewrite(target, args)
    end
  end

  defp dispatch_rewrite(target, args) do
    Enum.reduce_while(@dispatchers, :error, fn mod, :error ->
      case mod.rewrite(target, args) do
        :unmatched -> {:cont, :error}
        {:ok, _} = ok -> {:halt, ok}
        :error -> {:halt, :error}
      end
    end)
  end

  defp kernel_targets_rewrite(target, args) do
    if kernel_target?(target) do
      KernelTargets.rewrite(target, args)
    else
      :error
    end
  end

  defp kernel_target?(target) when is_binary(target) do
    String.starts_with?(target, "Elm.Kernel.PebbleWatch.") or
      String.starts_with?(target, "Elm.Kernel.PebblePhone.")
  end
end
