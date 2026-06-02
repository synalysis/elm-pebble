defmodule Ide.Emulator.Session.RuntimeSetup do
  @moduledoc false

  alias Ide.Emulator.SdkImages
  alias Ide.Emulator.Session.{Bins, Config, Qemu}
  alias Ide.Emulator.Types
  alias Ide.WatchModels

  @spec runtime_status(String.t() | nil) :: Types.runtime_status()
  def runtime_status(platform \\ nil) do
    platform = normalize_platform(platform)
    sdk_root = Bins.preferred_sdk_root()
    sdk_toolchain_root = Bins.sdk_version_root(Config.config(:sdk_core_version, "4.9.169"))

    components = [
      component(
        :embedded_emulator,
        "Embedded emulator",
        Config.enabled?(),
        if(Config.enabled?(), do: "enabled", else: "disabled by configuration"),
        false
      ),
      command_component(:pebble_cli, "Pebble CLI", Bins.pebble_bin(), true),
      component(
        :pebble_sdk_python_env,
        "Pebble SDK Python env",
        SdkImages.sdk_python_env_present?(sdk_root),
        Path.join(sdk_root, ".venv"),
        true
      ),
      component(
        :pebble_sdk_node_modules,
        "Pebble SDK JS dependencies",
        SdkImages.sdk_node_modules_present?(sdk_root),
        Path.join(sdk_root, "node_modules"),
        true
      ),
      component(
        :pebble_arm_gcc,
        "Pebble ARM GCC",
        File.exists?(
          Path.join(sdk_toolchain_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-gcc")
        ),
        Path.join(sdk_toolchain_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-gcc"),
        true
      ),
      qemu_component(Bins.qemu_bin()),
      command_component(:pypkjs, "pypkjs bridge", Bins.pypkjs_bin(), true),
      component(
        :qemu_micro_flash,
        "QEMU micro flash image",
        Qemu.micro_flash_present?(platform),
        Qemu.image_dir(platform),
        true
      ),
      component(
        :qemu_spi_flash,
        "QEMU SPI flash image",
        Qemu.spi_flash_available?(platform),
        Qemu.image_dir(platform),
        true
      )
    ]

    missing = Enum.filter(components, &(&1.status == :missing))

    %{
      status: if(missing == [], do: :ok, else: :warning),
      platform: platform,
      components: components,
      missing: missing,
      installable: Enum.any?(missing, & &1.installable)
    }
  end

  @spec install_runtime_dependencies(String.t() | nil) ::
          {:ok, Types.install_dependencies_result()}
  def install_runtime_dependencies(platform \\ nil) do
    platform = normalize_platform(platform)
    before_status = runtime_status(platform)

    steps =
      before_status.missing
      |> Enum.map(& &1.id)
      |> Enum.uniq()
      |> Enum.flat_map(&install_steps_for_component(&1, platform))
      |> Enum.uniq_by(& &1.name)

    results = run_install_steps(steps)
    after_status = runtime_status(platform)

    {:ok,
     %{
       platform: platform,
       before: before_status,
       after: after_status,
       results: results,
       output: render_install_results(results, after_status)
     }}
  end

  defp component_missing_detail(%{label: label, detail: detail})
       when is_binary(label) and is_binary(detail) do
    "#{label}: #{detail}"
  end

  defp component_missing_detail(%{label: label}) when is_binary(label), do: label
  defp component_missing_detail(component), do: inspect(component)

  defp component(id, label, true, detail, installable),
    do: %{id: id, label: label, status: :ok, detail: detail, installable: installable}

  defp component(id, label, _present, detail, installable),
    do: %{id: id, label: label, status: :missing, detail: detail, installable: installable}

  defp command_component(id, label, {:ok, path}, installable),
    do: component(id, label, true, path, installable)

  defp command_component(id, label, {:error, reason}, installable),
    do: component(id, label, false, inspect(reason), installable)

  defp qemu_component({:ok, path}) do
    case Qemu.health(path) do
      :ok ->
        component(:qemu, "Pebble QEMU", true, path, true)

      {:error, detail} ->
        component(:qemu, "Pebble QEMU", false, detail, false)
    end
  end

  defp qemu_component({:error, reason}) do
    component(:qemu, "Pebble QEMU", false, inspect(reason), true)
  end

  defp install_steps_for_component(id, platform)
       when id in [:qemu, :qemu_micro_flash, :qemu_spi_flash] do
    [
      %{name: :pebble_tool, fun: &install_pebble_tool/0},
      %{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end},
      %{name: :qemu_images, fun: fn -> install_qemu_images(platform) end}
    ]
  end

  defp install_steps_for_component(:pypkjs, _platform) do
    [%{name: :pebble_tool, fun: &install_pebble_tool/0}]
  end

  defp install_steps_for_component(:pebble_cli, _platform) do
    [%{name: :pebble_tool, fun: &install_pebble_tool/0}]
  end

  defp install_steps_for_component(:pebble_sdk_python_env, _platform) do
    [%{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end}]
  end

  defp install_steps_for_component(:pebble_sdk_node_modules, _platform) do
    [%{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end}]
  end

  defp install_steps_for_component(:pebble_arm_gcc, _platform) do
    [
      %{name: :pebble_tool, fun: &install_pebble_tool/0},
      %{name: :pebble_sdk, fun: fn -> install_pebble_sdk() end}
    ]
  end

  defp install_steps_for_component(_id, _platform), do: []

  defp run_install_steps(steps) do
    Enum.reduce_while(steps, [], fn step, results ->
      result = run_install_step(step)
      results = results ++ [result]

      case result.status do
        :ok -> {:cont, results}
        :error -> {:halt, results}
      end
    end)
  end

  defp run_install_step(%{name: name, fun: fun}) do
    case fun.() do
      {:ok, output} -> %{name: name, status: :ok, output: output}
      {:error, reason} -> %{name: name, status: :error, output: inspect(reason)}
    end
  rescue
    error -> %{name: name, status: :error, output: Exception.message(error)}
  end

  defp install_pebble_sdk do
    version = Config.config(:sdk_core_version, "4.9.169")
    sdk_root = Bins.sdk_version_root(version)
    preferred_root = Bins.preferred_sdk_root()

    opts =
      [
        sdk_version: version,
        python: pebble_tool_python()
      ]
      |> maybe_put_metadata_url(Config.config(:sdk_core_metadata_url, nil))
      |> maybe_put_archive_path(Config.config(:sdk_core_archive_path, nil))
      |> maybe_put_toolchain_archive_path(Config.config(:sdk_toolchain_archive_path, nil))

    case ensure_sdk_roots_with_toolchain([sdk_root, preferred_root], opts) do
      :ok -> {:ok, "Pebble SDK #{version} is available in #{sdk_root}."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_sdk_roots_with_toolchain(roots, opts) do
    roots
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn root, :ok ->
      case ensure_sdk_with_toolchain(root, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_sdk_with_toolchain(sdk_root, opts) do
    with :ok <- SdkImages.ensure_sdk_core(sdk_root, opts),
         :ok <- SdkImages.ensure_toolchain(sdk_root, opts) do
      :ok
    end
  end

  defp install_qemu_images(platform) do
    image_root = Qemu.preferred_image_root()

    opts =
      [
        image_root: image_root,
        sdk_version: Config.config(:sdk_core_version, "4.9.169")
      ]
      |> maybe_put_metadata_url(Config.config(:sdk_core_metadata_url, nil))
      |> maybe_put_archive_path(Config.config(:sdk_core_archive_path, nil))

    case SdkImages.ensure_platform_images(platform, opts) do
      :ok -> {:ok, "QEMU images are available in #{Path.join(image_root, platform)}."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp install_pebble_tool do
    cond do
      uv = System.find_executable("uv") ->
        install_pebble_tool_with_uv(uv)

      pipx = System.find_executable("pipx") ->
        case pebble_tool_python_bin() do
          {:ok, python} ->
            run_command(pipx, ["install", "--force", "--python", python, "pebble-tool"])

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        {:error, :uv_or_pipx_not_found}
    end
  end

  defp install_pebble_tool_with_uv(uv) do
    tool_args = ["tool", "install", "--force", "--python", pebble_tool_python(), "pebble-tool"]

    case run_command(uv, tool_args) do
      {:ok, output} ->
        {:ok, output}

      {:error, %{output: output} = reason} ->
        if uv_python_missing?(output) do
          install_uv_python_and_retry_tool(uv, tool_args)
        else
          {:error, reason}
        end
    end
  end

  defp install_uv_python_and_retry_tool(uv, tool_args) do
    with {:ok, python_output} <- run_command(uv, ["python", "install", pebble_tool_python()]),
         {:ok, tool_output} <- run_command(uv, tool_args) do
      {:ok, String.trim(python_output <> "\n" <> tool_output)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp uv_python_missing?(output) when is_binary(output) do
    String.contains?(output, "No interpreter found for Python") and
      String.contains?(output, "uv python install")
  end

  defp uv_python_missing?(_output), do: false

  defp pebble_tool_python do
    case Config.config(:pebble_tool_python, "3.13") do
      python when is_binary(python) and python != "" -> python
      _ -> "3.13"
    end
  end

  defp pebble_tool_python_bin do
    pebble_tool_python_candidates()
    |> Enum.find_value(fn candidate ->
      resolve_python_candidate(candidate)
    end)
    |> case do
      {:ok, path} -> {:ok, path}
      nil -> {:error, {:compatible_python_not_found, pebble_tool_python_candidates()}}
    end
  end

  defp resolve_python_candidate("/" <> _ = candidate) do
    if Bins.executable_file?(candidate), do: {:ok, candidate}
  end

  defp resolve_python_candidate(candidate) do
    case System.find_executable(candidate) do
      nil -> nil
      path -> {:ok, path}
    end
  end

  defp pebble_tool_python_candidates do
    configured = pebble_tool_python()

    cond do
      String.starts_with?(configured, "/") ->
        [configured]

      String.starts_with?(configured, "python") ->
        [configured]

      true ->
        ["python#{configured}", configured]
    end
  end

  defp run_command(command, args) do
    {output, exit_code} = System.cmd(command, args, stderr_to_stdout: true)

    if exit_code == 0 do
      {:ok, output}
    else
      {:error, %{command: Enum.join([command | args], " "), exit_code: exit_code, output: output}}
    end
  end

  defp render_install_results(results, after_status) do
    result_lines =
      Enum.map(results, fn result ->
        "[#{result.status}] #{result.name}\n#{String.trim(result.output || "")}"
      end)

    missing_lines =
      after_status.missing
      |> Enum.map(&"- #{&1.label}: #{&1.detail}")

    """
    #{Enum.join(result_lines, "\n\n")}

    Current status: #{after_status.status}
    #{if missing_lines == [], do: "All embedded emulator dependencies are present.", else: "Still missing:\n" <> Enum.join(missing_lines, "\n")}
    """
    |> String.trim()
  end

  defp maybe_download_qemu_images(platform) do
    image_root = Qemu.preferred_image_root()

    cond do
      Config.config(:download_images, true) != true ->
        :ok

      Enum.any?(Qemu.image_roots(), &SdkImages.images_present?(&1, platform)) ->
        :ok

      true ->
        opts =
          [
            image_root: image_root,
            sdk_version: Config.config(:sdk_core_version, "4.9.169")
          ]
          |> maybe_put_metadata_url(Config.config(:sdk_core_metadata_url, nil))
          |> maybe_put_archive_path(Config.config(:sdk_core_archive_path, nil))

        SdkImages.ensure_platform_images(platform, opts)
    end
  end

  defp maybe_put_metadata_url(opts, url) when is_binary(url) and url != "",
    do: Keyword.put(opts, :metadata_url, url)

  defp maybe_put_metadata_url(opts, _url), do: opts

  defp maybe_put_archive_path(opts, path) when is_binary(path) and path != "",
    do: Keyword.put(opts, :archive_path, path)

  defp maybe_put_archive_path(opts, _path), do: opts

  defp maybe_put_toolchain_archive_path(opts, path) when is_binary(path) and path != "",
    do: Keyword.put(opts, :toolchain_archive_path, path)

  defp maybe_put_toolchain_archive_path(opts, _path), do: opts

  @spec normalize_platform(String.t() | nil) :: String.t()
  def normalize_platform(platform) when is_binary(platform) do
    platform = platform |> String.downcase() |> String.trim()

    if platform in WatchModels.ordered_ids() do
      platform
    else
      WatchModels.default_id()
    end
  end

  def normalize_platform(_), do: WatchModels.default_id()

  @spec validate_runtime_requirements(String.t()) :: :ok | {:error, Types.session_error()}
  def validate_runtime_requirements(platform) do
    cond do
      not Config.enabled?() ->
        {:error, :embedded_emulator_disabled}

      Config.config(:validate_runtime, true) == false ->
        :ok

      true ->
        case maybe_download_qemu_images(platform) do
          :ok ->
            missing =
              platform
              |> runtime_status()
              |> Map.fetch!(:missing)
              |> Enum.map(&component_missing_detail/1)

            case missing do
              [] -> :ok
              missing -> {:error, {:embedded_emulator_unavailable, Enum.reverse(missing)}}
            end

          {:error, reason} ->
            {:error, {:embedded_emulator_image_download_failed, reason}}
        end
    end
  end
end
