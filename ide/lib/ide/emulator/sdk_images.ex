defmodule Ide.Emulator.SdkImages do
  @moduledoc false

  @default_sdk_version "4.9.169"

  @spec ensure_platform_images(String.t(), keyword()) :: :ok | {:error, term()}
  def ensure_platform_images(platform, opts \\ []) when is_binary(platform) do
    image_root = Keyword.fetch!(opts, :image_root)

    if images_present?(image_root, platform) do
      :ok
    else
      with :ok <- File.mkdir_p(image_root),
           {:ok, sdk_url} <- sdk_url(opts),
           {:ok, archive_path} <- download_sdk_archive(sdk_url),
           result <- extract_platform_images(archive_path, image_root, platform) do
        File.rm(archive_path)
        result
      end
    end
  end

  @spec images_present?(String.t(), String.t()) :: boolean()
  def images_present?(image_root, platform) do
    qemu_dir = Path.join([image_root, platform, "qemu"])
    micro = Path.join(qemu_dir, "qemu_micro_flash.bin")
    spi = Path.join(qemu_dir, "qemu_spi_flash.bin")

    File.exists?(micro) and (File.exists?(spi) or File.exists?(spi <> ".bz2"))
  end

  defp sdk_url(opts) do
    version = Keyword.get(opts, :sdk_version, @default_sdk_version)

    metadata_url =
      Keyword.get(opts, :metadata_url, "https://sdk.repebble.com/v1/files/sdk-core/#{version}")

    case Req.get(metadata_url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"url" => url}}} when is_binary(url) ->
        {:ok, url}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        with {:ok, %{"url" => url}} when is_binary(url) <- Jason.decode(body) do
          {:ok, url}
        else
          _ -> {:error, {:sdk_metadata_invalid, metadata_url}}
        end

      {:ok, %{status: status}} ->
        {:error, {:sdk_metadata_failed, metadata_url, status}}

      {:error, reason} ->
        {:error, {:sdk_metadata_failed, metadata_url, reason}}
    end
  end

  defp download_sdk_archive(url) do
    path =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-sdk-core-#{System.unique_integer([:positive])}.tar.gz"
      )

    case Req.get(url, into: File.stream!(path), receive_timeout: :infinity) do
      {:ok, %{status: 200}} ->
        {:ok, path}

      {:ok, %{status: status}} ->
        File.rm(path)
        {:error, {:sdk_download_failed, url, status}}

      {:error, reason} ->
        File.rm(path)
        {:error, {:sdk_download_failed, url, reason}}
    end
  end

  defp extract_platform_images(archive_path, image_root, platform) do
    wanted_path = "sdk-core/pebble/#{platform}/qemu"

    case System.cmd(
           "tar",
           ["xzf", archive_path, "-C", image_root, "--strip-components=2", wanted_path],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        if images_present?(image_root, platform) do
          :ok
        else
          {:error, {:sdk_images_missing_after_extract, platform}}
        end

      {output, exit_code} ->
        {:error, {:sdk_extract_failed, exit_code, output}}
    end
  end
end
