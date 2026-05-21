defmodule Ide.EmulatorSupport do
  @moduledoc """
  Declares supported emulator mode combinations for each watch target.
  """

  alias Ide.Auth
  alias Ide.PebbleToolchain

  @mode_options [
    %{id: "embedded", label: "Embedded in IDE"},
    %{id: "external", label: "External Pebble emulator"},
    %{id: "wasm", label: "WASM in browser"}
  ]

  @target_mode_ids %{
    "aplite" => ~w(embedded external wasm),
    "basalt" => ~w(embedded external wasm),
    "chalk" => ~w(embedded external),
    "diorite" => ~w(embedded external wasm),
    "emery" => ~w(embedded external wasm),
    "flint" => ~w(embedded external wasm),
    "gabbro" => ~w(embedded external)
  }

  @spec supported_targets() :: [String.t()]
  def supported_targets do
    allowed = MapSet.new(Map.keys(@target_mode_ids))

    PebbleToolchain.supported_emulator_targets()
    |> Enum.filter(&MapSet.member?(allowed, &1))
  end

  @doc """
  True when the Pebble SDK external emulator mode is available (disabled in public IDE modes).
  """
  @spec external_mode_enabled?() :: boolean()
  def external_mode_enabled?, do: not Auth.public_mode?()

  @spec allowed_mode_ids() :: [String.t()]
  def allowed_mode_ids do
    ~w(embedded external wasm)
    |> without_external_unless_enabled()
  end

  @spec supported_modes(String.t() | nil) :: [String.t()]
  def supported_modes(target) when is_binary(target) do
    @target_mode_ids
    |> Map.get(String.trim(target), default_modes())
    |> without_external_unless_enabled()
    |> Enum.filter(&mode_known?/1)
  end

  def supported_modes(_), do: default_modes()

  @spec mode_options(String.t() | nil) :: [{String.t(), String.t()}]
  def mode_options(target) do
    modes = MapSet.new(supported_modes(target))

    @mode_options
    |> Enum.filter(&MapSet.member?(modes, &1.id))
    |> Enum.map(&{&1.label, &1.id})
  end

  @spec supported?(String.t() | nil, String.t() | nil) :: boolean()
  def supported?(target, mode) when is_binary(mode) do
    String.trim(mode) in supported_modes(target)
  end

  def supported?(_target, _mode), do: false

  @spec normalize_target(String.t() | nil) :: String.t()
  def normalize_target(target) when is_binary(target) do
    target = String.trim(target)
    targets = supported_targets()
    default = default_target()

    cond do
      target in targets -> target
      default in targets -> default
      targets != [] -> hd(targets)
      true -> default
    end
  end

  def normalize_target(_), do: normalize_target(default_target())

  @spec normalize_mode(String.t() | nil, String.t() | nil) :: String.t()
  def normalize_mode(target, mode) when is_binary(mode) do
    normalized = String.trim(mode)

    if supported?(target, normalized) do
      normalized
    else
      default_mode(target)
    end
  end

  def normalize_mode(target, _), do: default_mode(target)

  @spec combinations() :: [%{target: String.t(), modes: [String.t()]}]
  def combinations do
    Enum.map(supported_targets(), fn target ->
      %{target: target, modes: supported_modes(target)}
    end)
  end

  defp default_modes, do: without_external_unless_enabled(~w(embedded external wasm))

  defp without_external_unless_enabled(modes) do
    if external_mode_enabled?(), do: modes, else: Enum.reject(modes, &(&1 == "external"))
  end

  defp default_mode(target) do
    target
    |> supported_modes()
    |> List.first()
    |> Kernel.||("embedded")
  end

  defp default_target do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_target, "basalt")
  end

  defp mode_known?(mode), do: Enum.any?(@mode_options, &(&1.id == mode))
end
