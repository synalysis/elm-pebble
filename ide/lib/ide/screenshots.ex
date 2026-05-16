defmodule Ide.Screenshots do
  @moduledoc """
  Boundary for screenshot capture/storage services.
  """

  alias Ide.PebbleToolchain

  @type project_slug :: String.t()
  @type opts :: keyword()
  @type screenshot :: %{
          filename: String.t(),
          emulator_target: String.t(),
          url: String.t(),
          absolute_path: String.t(),
          captured_at: String.t()
        }
  @type capture_result :: %{
          screenshot: screenshot(),
          output: String.t(),
          exit_code: integer(),
          command: String.t(),
          cwd: String.t()
        }
  @type capture_all_result :: %{
          results: [{String.t(), {:ok, capture_result()} | {:error, term()}}],
          captured: [screenshot()],
          failed: [{String.t(), term()}],
          close_result: {:ok, PebbleToolchain.command_result()} | {:error, term()} | nil
        }

  @callback list(project_slug(), opts()) :: {:ok, [screenshot()]} | {:error, term()}
  @callback list_grouped_by_emulator(project_slug(), opts()) ::
              {:ok, [{String.t(), [screenshot()]}]} | {:error, term()}
  @callback latest(project_slug(), opts()) :: {:ok, screenshot() | nil} | {:error, term()}
  @callback capture(project_slug(), opts()) :: {:ok, capture_result()} | {:error, term()}
  @callback capture_all_targets(project_slug(), opts()) ::
              {:ok, capture_all_result()} | {:error, term()}
  @callback delete(project_slug(), String.t(), String.t(), opts()) :: :ok | {:error, term()}
  @callback delete_target(project_slug(), String.t(), opts()) :: :ok | {:error, term()}

  @doc """
  Captures a screenshot from the configured emulator target.
  """
  @spec capture(project_slug(), opts()) :: {:ok, capture_result()} | {:error, term()}
  def capture(project_slug, opts) do
    with {:ok, storage_root} <- storage_root(),
         emulator_target <- Keyword.get(opts, :emulator_target, configured_emulator_target()) do
      target_dir = Path.join([storage_root, project_slug, emulator_target])
      :ok = File.mkdir_p(target_dir)

      filename = "shot-#{timestamp()}.png"
      absolute_path = Path.join(target_dir, filename)

      case PebbleToolchain.run_screenshot(project_slug, absolute_path, emulator_target) do
        {:ok, result} ->
          {:ok,
           %{
             screenshot: build_entry(project_slug, emulator_target, absolute_path),
             output: result.output,
             exit_code: result.exit_code,
             command: result.command,
             cwd: result.cwd
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Stores a browser-captured PNG under the same project/target screenshot storage.
  """
  @spec store_png(project_slug(), String.t(), binary()) :: {:ok, screenshot()} | {:error, term()}
  def store_png(project_slug, emulator_target, png) when is_binary(png) do
    with {:ok, storage_root} <- storage_root(),
         {:ok, emulator_target} <- normalize_emulator_target(emulator_target),
         true <- png_signature?(png) do
      target_dir = Path.join([storage_root, project_slug, emulator_target])
      :ok = File.mkdir_p(target_dir)

      absolute_path = Path.join(target_dir, "shot-#{timestamp()}.png")

      case File.write(absolute_path, png) do
        :ok -> {:ok, build_entry(project_slug, emulator_target, absolute_path)}
        {:error, reason} -> {:error, {:write_failed, reason}}
      end
    else
      false -> {:error, :invalid_png}
      error -> error
    end
  end

  @doc """
  Captures screenshots for all supported emulator targets.
  """
  @spec capture_all_targets(project_slug(), opts()) ::
          {:ok, capture_all_result()} | {:error, term()}
  def capture_all_targets(project_slug, opts) do
    targets = PebbleToolchain.supported_emulator_targets()
    boot_wait_ms = max(Keyword.get(opts, :boot_wait_ms, 2_500), 0)
    close_afterwards = Keyword.get(opts, :close_emulator_afterwards, true)
    install_timeout_ms = max(Keyword.get(opts, :install_timeout_ms, 45_000), 1_000)
    screenshot_timeout_ms = max(Keyword.get(opts, :screenshot_timeout_ms, 20_000), 1_000)
    screenshot_retries = max(Keyword.get(opts, :screenshot_retries, 3), 1)
    retry_delay_ms = max(Keyword.get(opts, :retry_delay_ms, 1_500), 0)

    progress = Keyword.get(opts, :progress)

    with {:ok, package_path} <- resolve_package_path(project_slug, opts) do
      maybe_progress(
        progress,
        {:phase, "Preparing screenshot capture for #{length(targets)} targets..."}
      )

      results =
        Enum.with_index(targets, 1)
        |> Enum.map(fn {target, index} ->
          maybe_progress(progress, {:phase, "[#{index}/#{length(targets)}] #{target}"})
          maybe_progress(progress, {:target, target, :cleanup_before})
          _ = stop_emulator_safe(project_slug, progress, target, :cleanup_before)
          maybe_progress(progress, {:target, target, :installing})

          result =
            with {:ok, _install_result} <-
                   timed_step(
                     fn ->
                       PebbleToolchain.run_emulator(project_slug,
                         emulator_target: target,
                         package_path: package_path,
                         logs_snapshot_seconds: 1
                       )
                     end,
                     install_timeout_ms
                   ),
                 :ok <- wait_for_app_load(boot_wait_ms),
                 maybe_progress(progress, {:target, target, :capturing}),
                 {:ok, shot} <-
                   capture_with_retries(
                     project_slug,
                     target,
                     screenshot_timeout_ms,
                     screenshot_retries,
                     retry_delay_ms,
                     progress
                   ) do
              maybe_progress(progress, {:target, target, :ok})
              maybe_progress(progress, {:target, target, :captured, shot.screenshot})
              {:ok, shot}
            else
              {:error, reason} ->
                maybe_progress(progress, {:target, target, :error, reason})
                {:error, reason}
            end

          maybe_progress(progress, {:target, target, :cleanup_after})
          _ = stop_emulator_safe(project_slug, progress, target, :cleanup_after)
          {target, result}
        end)

      close_result =
        if close_afterwards do
          maybe_progress(progress, {:phase, "Stopping emulator processes..."})
          result = stop_emulator_safe(project_slug, progress, "all", :final_close)
          maybe_progress(progress, {:close, result})
          result
        else
          nil
        end

      captured =
        results
        |> Enum.flat_map(fn
          {_target, {:ok, result}} -> [result.screenshot]
          _ -> []
        end)

      failed =
        results
        |> Enum.flat_map(fn
          {target, {:error, reason}} -> [{target, reason}]
          _ -> []
        end)

      maybe_progress(
        progress,
        {:phase, "Capture complete: #{length(captured)} succeeded, #{length(failed)} failed."}
      )

      {:ok, %{results: results, captured: captured, failed: failed, close_result: close_result}}
    end
  end

  @doc """
  Deletes a single screenshot by emulator target and filename.
  """
  @spec delete(project_slug(), String.t(), String.t(), opts()) :: :ok | {:error, term()}
  def delete(project_slug, emulator_target, filename, _opts \\ []) do
    with {:ok, root} <- storage_root(),
         {:ok, filename} <- normalize_filename(filename),
         {:ok, emulator_target} <- normalize_emulator_target(emulator_target) do
      path = Path.join([root, project_slug, emulator_target, filename])

      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, {:delete_failed, reason}}
      end
    end
  end

  @doc """
  Deletes all screenshots under one emulator target folder.
  """
  @spec delete_target(project_slug(), String.t(), opts()) :: :ok | {:error, term()}
  def delete_target(project_slug, emulator_target, _opts \\ []) do
    with {:ok, root} <- storage_root(),
         {:ok, emulator_target} <- normalize_emulator_target(emulator_target) do
      dir = Path.join([root, project_slug, emulator_target])

      case File.rm_rf(dir) do
        {:ok, _} -> :ok
        {:error, reason, _} -> {:error, {:delete_target_failed, reason}}
      end
    end
  end

  @doc """
  Lists screenshots for a project, newest first.
  """
  @spec list(project_slug(), opts()) :: {:ok, [screenshot()]} | {:error, term()}
  def list(project_slug, _opts) do
    with {:ok, root} <- storage_root() do
      project_dir = Path.join(root, project_slug)

      case File.ls(project_dir) do
        {:ok, entries} ->
          legacy_files =
            entries
            |> Enum.filter(&file_name_image?/1)
            |> Enum.map(&Path.join(project_dir, &1))
            |> Enum.map(&build_entry(project_slug, "unknown", &1))

          grouped_files =
            entries
            |> Enum.filter(&File.dir?(Path.join(project_dir, &1)))
            |> Enum.flat_map(fn emulator_target ->
              emulator_dir = Path.join(project_dir, emulator_target)

              case File.ls(emulator_dir) do
                {:ok, files} ->
                  files
                  |> Enum.filter(&file_name_image?/1)
                  |> Enum.map(&Path.join(emulator_dir, &1))
                  |> Enum.map(&build_entry(project_slug, emulator_target, &1))

                _ ->
                  []
              end
            end)

          entries =
            (legacy_files ++ grouped_files)
            |> Enum.sort_by(&mtime_sort(&1.absolute_path), :desc)

          {:ok, entries}

        {:error, :enoent} ->
          {:ok, []}

        {:error, reason} ->
          {:error, {:list_failed, reason}}
      end
    end
  end

  @doc """
  Lists screenshots grouped by emulator target.
  """
  @spec list_grouped_by_emulator(project_slug(), opts()) ::
          {:ok, [{String.t(), [screenshot()]}]} | {:error, term()}
  def list_grouped_by_emulator(project_slug, opts) do
    case list(project_slug, opts) do
      {:ok, screenshots} ->
        grouped =
          screenshots
          |> Enum.group_by(& &1.emulator_target)
          |> Enum.sort_by(fn {target, _} -> target end)

        {:ok, grouped}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns latest screenshot for a project.
  """
  @spec latest(project_slug(), opts()) :: {:ok, screenshot() | nil} | {:error, term()}
  def latest(project_slug, opts) do
    case list(project_slug, opts) do
      {:ok, [head | _]} -> {:ok, head}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec build_entry(term(), term(), term()) :: term()
  defp build_entry(project_slug, emulator_target, absolute_path) do
    filename = Path.basename(absolute_path)

    %{
      filename: filename,
      emulator_target: emulator_target,
      absolute_path: absolute_path,
      url: public_url(project_slug, emulator_target, filename),
      captured_at: format_mtime(absolute_path)
    }
  end

  @spec storage_root() :: term()
  defp storage_root do
    path =
      Application.get_env(:ide, Ide.Screenshots, [])
      |> Keyword.get(:storage_root)

    if is_binary(path) do
      {:ok, path}
    else
      {:error, :screenshots_storage_not_configured}
    end
  end

  @spec public_url(term(), term(), term()) :: term()
  defp public_url(project_slug, emulator_target, filename) do
    prefix =
      Application.get_env(:ide, Ide.Screenshots, [])
      |> Keyword.get(:public_prefix, "/screenshots")

    "#{prefix}/#{project_slug}/#{emulator_target}/#{filename}"
  end

  @spec mtime_sort(term()) :: term()
  defp mtime_sort(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> {{1970, 1, 1}, {0, 0, 0}}
    end
  end

  @spec format_mtime(term()) :: term()
  defp format_mtime(path) do
    case File.stat(path) do
      {:ok, stat} ->
        case NaiveDateTime.from_erl(stat.mtime) do
          {:ok, ndt} -> NaiveDateTime.to_string(ndt)
          _ -> "unknown"
        end

      _ ->
        "unknown"
    end
  end

  @spec configured_emulator_target() :: term()
  defp configured_emulator_target do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_target, "basalt")
  end

  @spec file_name_image?(term()) :: term()
  defp file_name_image?(name) do
    String.ends_with?(name, [".png", ".jpg", ".jpeg", ".gif", ".webp"])
  end

  defp png_signature?(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: true
  defp png_signature?(_), do: false

  @spec timestamp() :: term()
  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace(["-", ":", "T", "Z"], "")
  end

  @spec maybe_progress(term(), term()) :: term()
  defp maybe_progress(progress, payload) when is_function(progress, 1), do: progress.(payload)
  defp maybe_progress(_progress, _payload), do: :ok

  @spec timed_step(term(), term()) :: term()
  defp timed_step(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, value}} -> {:ok, value}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, other} -> {:error, {:unexpected_step_result, other}}
      {:exit, reason} -> {:error, {:task_exit, reason}}
      nil -> {:error, :timeout}
    end
  end

  @spec stop_emulator_safe(term(), term(), term(), term()) :: term()
  defp stop_emulator_safe(project_slug, progress, target, phase) do
    case timed_step(fn -> PebbleToolchain.stop_emulator(project_slug, force: true) end, 12_000) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        maybe_progress(progress, {:target, target, :cleanup_error, phase, reason})
        {:error, reason}
    end
  end

  @spec capture_with_retries(term(), term(), term(), term(), term(), term()) :: term()
  defp capture_with_retries(
         project_slug,
         target,
         screenshot_timeout_ms,
         retries,
         retry_delay_ms,
         progress
       ) do
    Enum.reduce_while(1..retries, {:error, :timeout}, fn attempt, _acc ->
      maybe_progress(progress, {:target, target, :capture_attempt, attempt, retries})

      case timed_step(
             fn -> capture(project_slug, emulator_target: target) end,
             screenshot_timeout_ms
           ) do
        {:ok, shot} ->
          {:halt, {:ok, shot}}

        {:error, reason} ->
          maybe_progress(progress, {:target, target, :capture_retry, attempt, retries, reason})

          if attempt < retries do
            _ = wait_for_app_load(retry_delay_ms)
            {:cont, {:error, reason}}
          else
            {:halt, {:error, reason}}
          end
      end
    end)
  end

  @spec wait_for_app_load(term()) :: term()
  defp wait_for_app_load(ms) when is_integer(ms) and ms >= 0 do
    Process.sleep(ms)
    :ok
  end

  @spec resolve_package_path(term(), term()) :: term()
  defp resolve_package_path(_project_slug, opts) do
    provided = Keyword.get(opts, :package_path)

    cond do
      is_binary(provided) and provided != "" and File.exists?(provided) ->
        {:ok, Path.expand(provided)}

      true ->
        workspace_root = Keyword.get(opts, :workspace_root)
        target_type = Keyword.get(opts, :target_type, "app")
        project_name = Keyword.get(opts, :project_name, "project")

        with workspace when is_binary(workspace) <- workspace_root,
             workspace <- String.trim(workspace),
             false <- workspace == "",
             {:ok, build_result} <-
               PebbleToolchain.package("screenshot-capture",
                 workspace_root: workspace,
                 target_type: target_type,
                 project_name: project_name
               ) do
          {:ok, build_result.artifact_path}
        else
          _ -> {:error, :package_path_required}
        end
    end
  end

  @spec normalize_filename(term()) :: term()
  defp normalize_filename(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :filename_required}
      Path.basename(trimmed) != trimmed -> {:error, :invalid_filename}
      true -> {:ok, trimmed}
    end
  end

  defp normalize_filename(_), do: {:error, :filename_required}

  @spec normalize_emulator_target(term()) :: term()
  defp normalize_emulator_target(target) when is_binary(target) do
    trimmed = String.trim(target)

    cond do
      trimmed == "" -> {:error, :emulator_target_required}
      Path.basename(trimmed) != trimmed -> {:error, :invalid_emulator_target}
      true -> {:ok, trimmed}
    end
  end

  defp normalize_emulator_target(_), do: {:error, :emulator_target_required}
end
