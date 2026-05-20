defmodule Ide.ScreenshotDimensions do
  @moduledoc """
  Canonical App Store screenshot dimensions per Pebble platform.

  These sizes match listing validation in `IdeWeb.WorkspaceLive.PublishFlow` and
  the Rebble developer portal. Emulator framebuffer size may differ (for example
  Gabbro runs at 180×180 in QEMU but store screenshots must be 260×260).
  """

  alias Ide.Png

  @store_dimensions %{
    "aplite" => {144, 168},
    "basalt" => {144, 168},
    "diorite" => {144, 168},
    "flint" => {144, 168},
    "chalk" => {180, 180},
    "emery" => {200, 228},
    "gabbro" => {260, 260}
  }

  @doc """
  Returns `{width, height}` required for App Store screenshots of `platform`, if known.
  """
  @spec store_dimensions(String.t()) :: {pos_integer(), pos_integer()} | nil
  def store_dimensions(platform) do
    platform
    |> normalize_platform()
    |> then(&Map.get(@store_dimensions, &1))
  end

  @doc """
  Human-readable size label for UI copy, e.g. `"144×168 px"`.
  """
  @spec store_size_label(String.t()) :: String.t() | nil
  def store_size_label(platform) do
    case store_dimensions(platform) do
      {width, height} -> "#{width}×#{height} px"
      nil -> nil
    end
  end

  @doc """
  Returns whether `path` is a PNG with exact store dimensions for `platform`.
  """
  @spec valid_store_file?(String.t(), String.t()) :: boolean()
  def valid_store_file?(platform, path) when is_binary(platform) and is_binary(path) do
    case {store_dimensions(platform), Png.dimensions(path)} do
      {{width, height}, {:ok, width, height}} -> true
      _ -> false
    end
  end

  @doc """
  Normalizes PNG bytes to the store dimensions for `platform`.

  Passes through unchanged when the platform is unknown or dimensions already match.
  Upscales/downscales with nearest-neighbor sampling when they differ.
  """
  @spec normalize_for_store(binary(), String.t()) :: {:ok, binary()} | {:error, term()}
  def normalize_for_store(png, platform) when is_binary(png) do
    case store_dimensions(platform) do
      nil ->
        {:ok, png}

      {expected_w, expected_h} ->
        Png.fit(png, expected_w, expected_h)
    end
  end

  @doc """
  Returns a list of `{platform, {width, height}}` for every known store target.
  """
  @spec all_store_dimensions() :: [{String.t(), {pos_integer(), pos_integer()}}]
  def all_store_dimensions do
    Enum.sort(@store_dimensions)
  end

  defp normalize_platform(platform) do
    platform
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
