defmodule Ide.Emulator.SdkImages do
  @moduledoc false

  @default_sdk_version "4.9.169"
  @download_server "https://sdk.repebble.com"

  @spec ensure_platform_images(String.t(), keyword()) :: :ok | {:error, term()}
  def ensure_platform_images(platform, opts \\ []) when is_binary(platform) do
    image_root = Keyword.fetch!(opts, :image_root)

    if images_present?(image_root, platform) do
      :ok
    else
      with :ok <- File.mkdir_p(image_root),
           {:ok, archive_path, cleanup?} <- sdk_archive(opts),
           result <- extract_platform_images(archive_path, image_root, platform) do
        cleanup_archive(archive_path, cleanup?)
        result
      end
    end
  end

  @spec ensure_sdk_core(String.t(), keyword()) :: :ok | {:error, term()}
  def ensure_sdk_core(sdk_root, opts \\ []) when is_binary(sdk_root) do
    if sdk_core_present?(sdk_root) do
      ensure_sdk_runtime_env(sdk_root, opts)
    else
      with :ok <- File.mkdir_p(sdk_root),
           {:ok, archive_path, cleanup?} <- sdk_archive(opts),
           :ok <- extract_sdk_core(archive_path, sdk_root),
           result <- ensure_sdk_runtime_env(sdk_root, opts) do
        cleanup_archive(archive_path, cleanup?)
        result
      end
    end
  end

  @spec sdk_core_present?(String.t()) :: boolean()
  def sdk_core_present?(sdk_root) do
    File.exists?(Path.join(sdk_root, "sdk-core/manifest.json")) and
      File.dir?(Path.join(sdk_root, "sdk-core/pebble"))
  end

  @spec sdk_python_env_present?(String.t()) :: boolean()
  def sdk_python_env_present?(sdk_root) do
    requirements = Path.join(sdk_root, "sdk-core/requirements.txt")
    venv_python = Path.join(sdk_root, ".venv/bin/python")

    not File.exists?(requirements) or File.exists?(venv_python)
  end

  @spec sdk_node_modules_present?(String.t()) :: boolean()
  def sdk_node_modules_present?(sdk_root) do
    package_json = Path.join(sdk_root, "sdk-core/package.json")
    node_modules = Path.join(sdk_root, "node_modules")

    not File.exists?(package_json) or File.dir?(node_modules)
  end

  @spec ensure_toolchain(String.t(), keyword()) :: :ok | {:error, term()}
  def ensure_toolchain(sdk_root, opts \\ []) when is_binary(sdk_root) do
    if toolchain_present?(sdk_root) do
      :ok
    else
      with :ok <- File.mkdir_p(sdk_root),
           {:ok, archive_path, cleanup?, platform_name} <- toolchain_archive(opts),
           result <- extract_toolchain(archive_path, sdk_root, platform_name) do
        cleanup_archive(archive_path, cleanup?)
        result
      end
    end
  end

  @spec toolchain_present?(String.t()) :: boolean()
  def toolchain_present?(sdk_root) do
    File.exists?(Path.join(sdk_root, "toolchain/bin/qemu-pebble")) and
      File.exists?(Path.join(sdk_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-gcc"))
  end

  @spec images_present?(String.t(), String.t()) :: boolean()
  def images_present?(image_root, platform) do
    qemu_dir = Path.join([image_root, platform, "qemu"])
    micro = Path.join(qemu_dir, "qemu_micro_flash.bin")
    spi = Path.join(qemu_dir, "qemu_spi_flash.bin")

    File.exists?(micro) and (File.exists?(spi) or File.exists?(spi <> ".bz2"))
  end

  defp sdk_archive(opts) do
    case Keyword.get(opts, :archive_path) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path),
          do: {:ok, path, false},
          else: {:error, {:sdk_archive_not_found, path}}

      _ ->
        with {:ok, sdk_url} <- sdk_url(opts),
             {:ok, archive_path} <- download_sdk_archive(sdk_url) do
          {:ok, archive_path, true}
        end
    end
  end

  defp ensure_sdk_python_env(sdk_root, opts) do
    venv_python = Path.join(sdk_root, ".venv/bin/python")
    requirements = Path.join(sdk_root, "sdk-core/requirements.txt")

    cond do
      not File.exists?(requirements) ->
        :ok

      File.exists?(venv_python) ->
        :ok

      uv = System.find_executable("uv") ->
        python = Keyword.get(opts, :python, "3.13")

        with {:ok, _venv_output} <-
               run_command(uv, [
                 "venv",
                 "--python",
                 python,
                 Path.dirname(Path.dirname(venv_python))
               ]),
             {:ok, _pip_output} <-
               run_command(uv, ["pip", "install", "--python", venv_python, "-r", requirements]) do
          :ok
        end

      python = System.find_executable("python3") || System.find_executable("python") ->
        with {:ok, _venv_output} <-
               run_command(python, ["-m", "venv", Path.dirname(Path.dirname(venv_python))]),
             {:ok, _pip_output} <-
               run_command(venv_python, ["-m", "pip", "install", "-r", requirements]) do
          :ok
        end

      true ->
        {:error, :python_not_found}
    end
  end

  defp ensure_sdk_runtime_env(sdk_root, opts) do
    with :ok <- ensure_sdk_python_env(sdk_root, opts),
         :ok <- ensure_sdk_node_modules(sdk_root) do
      :ok
    end
  end

  defp ensure_sdk_node_modules(sdk_root) do
    source_package_json = Path.join(sdk_root, "sdk-core/package.json")
    target_package_json = Path.join(sdk_root, "package.json")
    node_modules = Path.join(sdk_root, "node_modules")

    cond do
      not File.exists?(source_package_json) ->
        :ok

      File.dir?(node_modules) ->
        :ok

      npm = System.find_executable("npm") ->
        with :ok <- File.cp(source_package_json, target_package_json),
             :ok <- File.mkdir_p(node_modules),
             {:ok, _output} <- run_command(npm, ["install", "--silent"], cd: sdk_root) do
          :ok
        end

      true ->
        {:error, :npm_not_found}
    end
  end

  defp toolchain_archive(opts) do
    case Keyword.get(opts, :toolchain_archive_path) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path) do
          {:ok, path, false, toolchain_platform_name(opts)}
        else
          {:error, {:toolchain_archive_not_found, path}}
        end

      _ ->
        with {:ok, url, platform_name} <- toolchain_url(opts),
             {:ok, archive_path} <- download_sdk_archive(url) do
          {:ok, archive_path, true, platform_name}
        end
    end
  end

  defp sdk_url(opts) do
    version = Keyword.get(opts, :sdk_version, @default_sdk_version)

    metadata_url =
      Keyword.get(opts, :metadata_url, "#{@download_server}/v1/files/sdk-core/#{version}")

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

  defp toolchain_url(opts) do
    version = Keyword.get(opts, :sdk_version, @default_sdk_version)
    platform_name = toolchain_platform_name(opts)

    arch_url = "#{@download_server}/releases/#{version}/toolchain-#{platform_name}.tar.gz"
    fallback_name = toolchain_os_name(opts)
    fallback_url = "#{@download_server}/releases/#{version}/toolchain-#{fallback_name}.tar.gz"

    case Req.head(arch_url, receive_timeout: 30_000) do
      {:ok, %{status: 200}} -> {:ok, arch_url, platform_name}
      _ -> {:ok, fallback_url, fallback_name}
    end
  end

  defp toolchain_platform_name(opts) do
    "#{toolchain_os_name(opts)}-#{toolchain_arch_name(opts)}"
  end

  defp toolchain_os_name(opts) do
    case Keyword.get(opts, :os_name) do
      name when name in ["linux", "mac"] ->
        name

      _ ->
        case :os.type() do
          {:unix, :darwin} -> "mac"
          _ -> "linux"
        end
    end
  end

  defp toolchain_arch_name(opts) do
    case Keyword.get(opts, :arch_name) do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        arch = :erlang.system_info(:system_architecture) |> List.to_string()

        cond do
          String.contains?(arch, "aarch64") -> "aarch64"
          String.contains?(arch, "arm64") -> "arm64"
          true -> "x86_64"
        end
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

  defp extract_sdk_core(archive_path, sdk_root) do
    case System.cmd("tar", ["xzf", archive_path, "-C", sdk_root], stderr_to_stdout: true) do
      {_output, 0} ->
        if sdk_core_present?(sdk_root) do
          :ok
        else
          {:error, {:sdk_core_missing_after_extract, sdk_root}}
        end

      {output, exit_code} ->
        {:error, {:sdk_extract_failed, exit_code, output}}
    end
  end

  defp extract_toolchain(archive_path, sdk_root, platform_name) do
    toolchain_root = Path.join(sdk_root, "toolchain")
    _ = File.rm_rf(toolchain_root)

    temp_root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-toolchain-#{System.unique_integer([:positive])}"
      )

    try do
      with :ok <- File.mkdir_p(toolchain_root),
           :ok <- File.mkdir_p(temp_root) do
        case System.cmd("tar", ["xzf", archive_path, "-C", temp_root], stderr_to_stdout: true) do
          {_output, 0} ->
            with {:ok, source_root} <- extracted_toolchain_root(temp_root, platform_name),
                 :ok <- copy_toolchain_contents(source_root, toolchain_root) do
              if toolchain_present?(sdk_root) do
                :ok
              else
                {:error, {:toolchain_missing_after_extract, sdk_root}}
              end
            end

          {output, exit_code} ->
            {:error, {:toolchain_extract_failed, exit_code, output}}
        end
      end
    after
      File.rm_rf(temp_root)
    end
  end

  defp extracted_toolchain_root(temp_root, platform_name) do
    exact = Path.join(temp_root, "toolchain-#{platform_name}")

    cond do
      File.dir?(exact) ->
        {:ok, exact}

      root = first_toolchain_root(temp_root) ->
        {:ok, root}

      true ->
        {:error, {:toolchain_root_not_found, temp_root}}
    end
  end

  defp first_toolchain_root(temp_root) do
    temp_root
    |> File.ls!()
    |> Enum.find_value(fn entry ->
      path = Path.join(temp_root, entry)

      if String.starts_with?(entry, "toolchain-") and File.dir?(path) do
        path
      end
    end)
  end

  defp copy_toolchain_contents(source_root, toolchain_root) do
    source_root
    |> File.ls!()
    |> Enum.each(fn entry ->
      File.cp_r!(Path.join(source_root, entry), Path.join(toolchain_root, entry))
    end)

    :ok
  rescue
    error -> {:error, {:toolchain_copy_failed, Exception.message(error)}}
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

  defp cleanup_archive(path, true), do: File.rm(path)
  defp cleanup_archive(_path, false), do: :ok

  defp run_command(command, args, opts \\ []) do
    case System.cmd(command, args, Keyword.merge([stderr_to_stdout: true], opts)) do
      {_output, 0} ->
        {:ok, ""}

      {output, exit_code} ->
        {:error,
         %{command: Enum.join([command | args], " "), exit_code: exit_code, output: output}}
    end
  end
end
