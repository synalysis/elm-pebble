defmodule Ide.StoreAssets do
  @moduledoc """
  App Store listing graphics stored in the project workspace (`store_assets/`).
  """

  @assets_dir "store_assets"
  @icon_small_filename "icon_small.png"
  @icon_large_filename "icon_large.png"
  @icon_small {80, 80}
  @icon_large {144, 144}
  @banner {720, 320}

  @type icon_key :: :icon_small | :icon_large
  @type icon_spec :: %{
          key: icon_key(),
          filename: String.t(),
          width: pos_integer(),
          height: pos_integer()
        }

  @type store_asset_error ::
          :invalid_icon_key
          | :invalid_png
          | {:invalid_dimensions,
             %{expected: {pos_integer(), pos_integer()}, actual: {pos_integer(), pos_integer()}}}
          | File.posix()

  @icon_specs [
    %{
      key: :icon_small,
      filename: @icon_small_filename,
      width: elem(@icon_small, 0),
      height: elem(@icon_small, 1)
    },
    %{
      key: :icon_large,
      filename: @icon_large_filename,
      width: elem(@icon_large, 0),
      height: elem(@icon_large, 1)
    }
  ]

  @spec assets_dir() :: String.t()
  def assets_dir, do: @assets_dir

  @spec icon_specs() :: [icon_spec()]
  def icon_specs, do: @icon_specs

  @spec size_label(icon_key()) :: String.t()
  def size_label(key) when key in [:icon_small, :icon_large] do
    %{width: width, height: height} = Enum.find(@icon_specs, &(&1.key == key))
    size_label(width, height)
  end

  @spec size_label(pos_integer(), pos_integer()) :: String.t()
  def size_label(width, height) when width > 0 and height > 0,
    do: "#{width}×#{height} px"

  @spec required_sizes_summary() :: String.t()
  def required_sizes_summary do
    @icon_specs
    |> Enum.map_join(" and ", fn spec ->
      "#{size_label(spec.width, spec.height)} (#{human_name(spec.key)})"
    end)
  end

  @spec human_name(icon_key()) :: String.t()
  def human_name(:icon_small), do: "small icon"
  def human_name(:icon_large), do: "large icon"

  @spec api_field_name(icon_key()) :: String.t()
  def api_field_name(:icon_small), do: "iconSmall"
  def api_field_name(:icon_large), do: "iconLarge"

  @spec banner_size_label() :: String.t()
  def banner_size_label, do: size_label(elem(@banner, 0), elem(@banner, 1))

  @spec root_path(String.t()) :: String.t()
  def root_path(workspace_root) when is_binary(workspace_root),
    do: Path.join(workspace_root, @assets_dir)

  @spec icon_path(String.t(), icon_key()) :: String.t()
  def icon_path(workspace_root, key)
      when is_binary(workspace_root) and key in [:icon_small, :icon_large] do
    filename =
      case key do
        :icon_small -> @icon_small_filename
        :icon_large -> @icon_large_filename
      end

    Path.join(root_path(workspace_root), filename)
  end

  @spec public_path(icon_key()) :: String.t()
  def public_path(:icon_small), do: @icon_small_filename
  def public_path(:icon_large), do: @icon_large_filename

  @spec status(String.t()) :: map()
  def status(workspace_root) when is_binary(workspace_root) do
    Enum.reduce(@icon_specs, %{}, fn spec, acc ->
      path = Path.join(root_path(workspace_root), spec.filename)

      Map.put(acc, spec.key, icon_status(path, spec))
    end)
  end

  @spec icons_uploaded?(String.t() | map()) :: boolean()
  def icons_uploaded?(workspace_root) when is_binary(workspace_root) do
    workspace_root |> publish_icon_paths() |> map_size() > 0
  end

  def icons_uploaded?(store_assets) when is_map(store_assets) do
    Enum.any?(store_assets, fn {_key, info} ->
      is_map(info) and Map.get(info, :present) == true
    end)
  end

  @doc """
  True when a watchapp can request Rebble `iconPrompt` generation (no icons uploaded yet).
  """
  @spec ai_graphics_available?(String.t() | map()) :: boolean()
  def ai_graphics_available?(workspace_root_or_assets) do
    not icons_uploaded?(workspace_root_or_assets)
  end

  @spec publish_icon_paths(String.t()) :: %{optional(icon_key()) => String.t()}
  def publish_icon_paths(workspace_root) when is_binary(workspace_root) do
    @icon_specs
    |> Enum.reduce(%{}, fn spec, acc ->
      path = Path.join(root_path(workspace_root), spec.filename)

      if File.regular?(path) do
        Map.put(acc, spec.key, path)
      else
        acc
      end
    end)
  end

  @spec save_icon(String.t(), icon_key(), String.t()) :: :ok | {:error, store_asset_error()}
  def save_icon(workspace_root, key, source_path)
      when is_binary(workspace_root) and key in [:icon_small, :icon_large] and
             is_binary(source_path) do
    case Enum.find(@icon_specs, &(&1.key == key)) do
      nil ->
        {:error, :invalid_icon_key}

      spec ->
        with :ok <- validate_png_dimensions(source_path, spec),
             :ok <- File.mkdir_p(root_path(workspace_root)),
             dest = Path.join(root_path(workspace_root), spec.filename),
             :ok <- File.cp(source_path, dest) do
          :ok
        end
    end
  end

  @spec validate_png_dimensions(String.t(), icon_spec() | icon_key()) ::
          :ok | {:error, store_asset_error()}
  def validate_png_dimensions(source_path, key) when key in [:icon_small, :icon_large] do
    spec = Enum.find(@icon_specs, &(&1.key == key))
    validate_png_dimensions(source_path, spec)
  end

  def validate_png_dimensions(source_path, %{width: width, height: height})
      when is_binary(source_path) do
    case png_dimensions(source_path) do
      {:ok, ^width, ^height} ->
        :ok

      {:ok, actual_w, actual_h} ->
        {:error,
         {:invalid_dimensions, %{expected: {width, height}, actual: {actual_w, actual_h}}}}

      :error ->
        {:error, :invalid_png}
    end
  end

  @spec png_dimensions(String.t()) :: {:ok, non_neg_integer(), non_neg_integer()} | :error
  def png_dimensions(path) when is_binary(path) do
    with {:ok,
          <<0x89, "PNG\r\n", 0x1A, "\n", _len::32, "IHDR", width::32, height::32, _::binary>>} <-
           File.read(path) do
      {:ok, width, height}
    else
      _ -> :error
    end
  end

  defp icon_status(path, spec) do
    base = %{
      key: spec.key,
      filename: spec.filename,
      width: spec.width,
      height: spec.height,
      path: path,
      present: false
    }

    if File.regular?(path) do
      case png_dimensions(path) do
        {:ok, width, height} ->
          Map.merge(base, %{
            present: true,
            actual_width: width,
            actual_height: height,
            valid: width == spec.width and height == spec.height
          })

        :error ->
          Map.merge(base, %{present: true, valid: false})
      end
    else
      base
    end
  end
end
