defmodule Elmc.Backend.Wasm.Targets do
  @moduledoc false

  alias Elmc.Types

  @type target :: :c | :wasm

  @spec normalize(Types.compile_options() | keyword()) :: [target()]
  def normalize(opts) when is_list(opts), do: opts |> Map.new() |> normalize()

  def normalize(opts) when is_map(opts) do
    case Map.get(opts, :targets) do
      nil ->
        case Map.get(opts, :target) do
          nil -> [:c]
          target -> normalize_target_list(target)
        end

      targets when is_list(targets) ->
        targets
        |> Enum.map(&normalize_target/1)
        |> Enum.uniq()

      target ->
        normalize_target_list(target)
    end
  end

  @spec emit_wasm?(Types.compile_options() | keyword()) :: boolean()
  def emit_wasm?(opts), do: :wasm in normalize(opts)

  @spec emit_c?(Types.compile_options() | keyword()) :: boolean()
  def emit_c?(opts), do: :c in normalize(opts)

  @spec wasm_only?(Types.compile_options() | keyword()) :: boolean()
  def wasm_only?(opts), do: normalize(opts) == [:wasm]

  defp normalize_target_list(targets) when is_binary(targets) do
    targets
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&normalize_target/1)
    |> Enum.uniq()
  end

  defp normalize_target_list(targets) when is_list(targets) do
    Enum.map(targets, &normalize_target/1) |> Enum.uniq()
  end

  defp normalize_target_list(target), do: [normalize_target(target)]

  defp normalize_target(:wasm), do: :wasm
  defp normalize_target(:c), do: :c
  defp normalize_target("wasm"), do: :wasm
  defp normalize_target("c"), do: :c
  defp normalize_target(other), do: raise(ArgumentError, "unknown compile target #{inspect(other)}")
end
