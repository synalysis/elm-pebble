defmodule Ide.Screenshots do
  @moduledoc """
  Boundary for screenshot capture/storage services.
  """

  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Projects.Project

  @type project_slug :: String.t()
  @type project_ref :: Project.t() | project_slug()
  @type opts :: keyword()
  @type screenshot :: %{
          filename: String.t(),
          emulator_target: String.t(),
          url: String.t(),
          absolute_path: String.t(),
          captured_at: String.t(),
          mime_type: String.t()
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
  @spec capture(project_ref(), opts()) :: {:ok, capture_result()} | {:error, term()}
  def capture(%Project{} = project, opts), do: capture(project.slug, Keyword.put(opts, :project, project))

  def capture(project_slug, opts) when is_binary(project_slug) do
    with {:ok, project_dir} <- project_storage_dir(project_slug, opts),
         emulator_target <- Keyword.get(opts, :emulator_target, configured_emulator_target()) do
      target_dir = Path.join(project_dir, emulator_target)
      :ok = File.mkdir_p(target_dir)

      filename = screenshot_filename(emulator_target)
      absolute_path = Path.join(target_dir, filename)

      with {:ok, result} <-
             PebbleToolchain.run_screenshot(project_slug, absolute_path, emulator_target),
           :ok <- ensure_successful_screenshot(result, absolute_path),
           :ok <- write_metadata(absolute_path, "image/png") do
        entry = build_entry(project_slug, emulator_target, absolute_path, opts)

        {:ok,
         %{
           screenshot: entry,
           output: result.output,
           exit_code: result.exit_code,
           command: result.command,
           cwd: result.cwd
         }}
      else
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Stores a browser-captured PNG under the same project/target screenshot storage.
  """
  @spec store_png(project_ref(), String.t(), binary(), opts()) ::
          {:ok, screenshot()} | {:error, term()}
  def store_png(project_ref, emulator_target, png, opts \\ [])

  def store_png(%Project{} = project, emulator_target, png, opts),
    do: store_png(project.slug, emulator_target, png, Keyword.put(opts, :project, project))

  def store_png(project_slug, emulator_target, png, opts) when is_binary(png) do
    with {:ok, project_dir} <- project_storage_dir(project_slug, opts),
         {:ok, emulator_target} <- normalize_emulator_target(emulator_target),
         true <- png_signature?(png) do
      target_dir = Path.join(project_dir, emulator_target)
      :ok = File.mkdir_p(target_dir)

      absolute_path = Path.join(target_dir, screenshot_filename(emulator_target))

      with :ok <- File.write(absolute_path, png),
           :ok <- write_metadata(absolute_path, "image/png") do
        {:ok, build_entry(project_slug, emulator_target, absolute_path, opts)}
      else
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
  @spec capture_all_targets(project_ref(), opts()) ::
          {:ok, capture_all_result()} | {:error, term()}
  def capture_all_targets(%Project{} = project, opts),
    do: capture_all_targets(project.slug, Keyword.put(opts, :project, project))

  def capture_all_targets(project_slug, opts) when is_binary(project_slug) do
    capture_opts = Keyword.take(opts, [:project])
    targets = capture_targets(Keyword.get(opts, :targets))
    boot_wait_ms = max(Keyword.get(opts, :boot_wait_ms, 2_500), 0)
    close_afterwards = Keyword.get(opts, :close_emulator_afterwards, true)
    install_timeout_ms = max(Keyword.get(opts, :install_timeout_ms, 45_000), 1_000)
    screenshot_timeout_ms = max(Keyword.get(opts, :screenshot_timeout_ms, 20_000), 1_000)
    screenshot_retries = max(Keyword.get(opts, :screenshot_retries, 3), 1)
    retry_delay_ms = max(Keyword.get(opts, :retry_delay_ms, 1_500), 0)

    progress = Keyword.get(opts, :progress)

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
          with {:ok, package_path} <- resolve_capture_package_path(project_slug, target, opts),
               {:ok, _install_result} <-
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
                   progress,
                   capture_opts
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

  @doc """
  Deletes a single screenshot by emulator target and filename.
  """
  @spec delete(project_ref(), String.t(), String.t(), opts()) :: :ok | {:error, term()}
  def delete(project_ref, emulator_target, filename, opts \\ [])

  def delete(%Project{} = project, emulator_target, filename, opts),
    do: delete(project.slug, emulator_target, filename, Keyword.put(opts, :project, project))

  def delete(project_slug, emulator_target, filename, opts) do
    with {:ok, root} <- project_storage_dir(project_slug, opts),
         {:ok, filename} <- normalize_filename(filename),
         {:ok, emulator_target} <- normalize_emulator_target(emulator_target) do
      path = Path.join([root, emulator_target, filename])

      case File.rm(path) do
        :ok ->
          _ = File.rm(metadata_path(path))
          :ok

        {:error, :enoent} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, {:delete_failed, reason}}
      end
    end
  end

  @doc """
  Deletes all screenshots under one emulator target folder.
  """
  @spec delete_target(project_ref(), String.t(), opts()) :: :ok | {:error, term()}
  def delete_target(project_ref, emulator_target, opts \\ [])

  def delete_target(%Project{} = project, emulator_target, opts),
    do: delete_target(project.slug, emulator_target, Keyword.put(opts, :project, project))

  def delete_target(project_slug, emulator_target, opts) do
    with {:ok, root} <- project_storage_dir(project_slug, opts),
         {:ok, emulator_target} <- normalize_emulator_target(emulator_target) do
      dir = Path.join(root, emulator_target)

      case File.rm_rf(dir) do
        {:ok, _} -> :ok
        {:error, reason, _} -> {:error, {:delete_target_failed, reason}}
      end
    end
  end

  @doc """
  Lists screenshots for a project, newest first.
  """
  @spec list(project_ref(), opts()) :: {:ok, [screenshot()]} | {:error, term()}
  def list(project_ref, opts \\ [])

  def list(%Project{} = project, opts), do: list(project.slug, Keyword.put(opts, :project, project))

  def list(project_slug, opts) when is_binary(project_slug) do
    with {:ok, project_dir} <- project_storage_dir(project_slug, opts) do
      case File.ls(project_dir) do
        {:ok, entries} ->
          legacy_files =
            entries
            |> Enum.filter(&file_name_image?/1)
            |> Enum.map(&Path.join(project_dir, &1))
            |> Enum.map(&build_entry(project_slug, "unknown", &1, opts))

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
                  |> Enum.map(&build_entry(project_slug, emulator_target, &1, opts))

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

  @spec build_entry(term(), term(), term(), opts()) :: term()
  defp build_entry(project_slug, emulator_target, absolute_path, opts) do
    filename = Path.basename(absolute_path)
    metadata = read_metadata(absolute_path)

    %{
      filename: filename,
      emulator_target: emulator_target,
      absolute_path: absolute_path,
      url: public_url(project_slug, emulator_target, filename, opts),
      captured_at: Map.get(metadata, "captured_at") || format_mtime(absolute_path),
      mime_type: Map.get(metadata, "mime_type") || mime_type_from_filename(filename)
    }
  end

  @spec screenshot_filename(String.t()) :: String.t()
  defp screenshot_filename(emulator_target) do
    "#{emulator_target}_shot_#{timestamp()}.png"
  end

  @spec write_metadata(String.t(), String.t()) :: :ok | {:error, term()}
  defp write_metadata(absolute_path, mime_type) when is_binary(absolute_path) do
    metadata = %{
      schema_version: 1,
      mime_type: mime_type,
      captured_at: format_mtime(absolute_path)
    }

    case Jason.encode(metadata) do
      {:ok, json} -> File.write(metadata_path(absolute_path), json)
      {:error, reason} -> {:error, {:metadata_encode_failed, reason}}
    end
  end

  @spec read_metadata(String.t()) :: map()
  defp read_metadata(absolute_path) do
    with {:ok, json} <- File.read(metadata_path(absolute_path)),
         {:ok, metadata} when is_map(metadata) <- Jason.decode(json) do
      metadata
    else
      _ -> %{}
    end
  end

  @spec metadata_path(String.t()) :: String.t()
  defp metadata_path(absolute_path), do: absolute_path <> ".json"

  @spec mime_type_from_filename(String.t()) :: String.t()
  defp mime_type_from_filename(filename) when is_binary(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/png"
    end
  end

  @spec project_storage_dir(project_slug(), opts()) :: {:ok, String.t()} | {:error, term()}
  defp project_storage_dir(project_slug, opts) do
    case Keyword.get(opts, :project) do
      %Project{} = project ->
        dir = Projects.screenshots_path(project)
        :ok = File.mkdir_p(dir)
        maybe_migrate_legacy_screenshots!(project)
        {:ok, dir}

      _ ->
        legacy_storage_root()
        |> case do
          {:ok, root} ->
            dir = Path.join(root, project_slug)
            File.mkdir_p(dir)
            {:ok, dir}

          error ->
            error
        end
    end
  end

  @spec legacy_storage_root() :: {:ok, String.t()} | {:error, term()}
  defp legacy_storage_root do
    path =
      Application.get_env(:ide, Ide.Screenshots, [])
      |> Keyword.get(:storage_root)

    if is_binary(path) do
      {:ok, path}
    else
      {:error, :screenshots_storage_not_configured}
    end
  end

  @spec maybe_migrate_legacy_screenshots!(Project.t()) :: :ok
  defp maybe_migrate_legacy_screenshots!(%Project{} = project) do
    dest = Projects.screenshots_path(project)

    with {:ok, legacy_root} <- legacy_storage_root(),
         legacy_dir = Path.join(legacy_root, project.slug),
         true <- File.dir?(legacy_dir),
         false <- workspace_screenshots_present?(dest) do
      case File.cp_r(legacy_dir, dest) do
        {:ok, _} -> :ok
        {:error, _, _} -> :ok
      end
    else
      _ -> :ok
    end

    :ok
  end

  @spec workspace_screenshots_present?(String.t()) :: boolean()
  defp workspace_screenshots_present?(dir) do
    case File.ls(dir) do
      {:ok, []} -> false
      {:ok, _} -> true
      {:error, :enoent} -> false
      {:error, _} -> true
    end
  end

  @spec public_url(term(), term(), term(), opts()) :: term()
  defp public_url(project_slug, emulator_target, filename, opts) do
    case Keyword.get(opts, :project) do
      %Project{slug: slug} ->
        "/projects/#{slug}/screenshots/#{emulator_target}/#{filename}"

      _ ->
        prefix =
          Application.get_env(:ide, Ide.Screenshots, [])
          |> Keyword.get(:public_prefix, "/screenshots")

        "#{prefix}/#{project_slug}/#{emulator_target}/#{filename}"
    end
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

  @spec ensure_successful_screenshot(term(), String.t()) :: :ok | {:error, term()}
  defp ensure_successful_screenshot(%{status: :ok} = result, path) do
    with true <- File.exists?(path),
         {:ok, data} <- File.read(path),
         true <- png_signature?(data) do
      :ok
    else
      false -> {:error, {:screenshot_file_missing_or_invalid, result}}
      {:error, reason} -> {:error, {:screenshot_read_failed, reason, result}}
    end
  end

  defp ensure_successful_screenshot(result, _path),
    do: {:error, {:pebble_screenshot_failed, result}}

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

  @spec capture_with_retries(term(), term(), term(), term(), term(), term(), opts()) :: term()
  defp capture_with_retries(
         project_slug,
         target,
         screenshot_timeout_ms,
         retries,
         retry_delay_ms,
         progress,
         capture_opts
       ) do
    Enum.reduce_while(1..retries, {:error, :timeout}, fn attempt, _acc ->
      maybe_progress(progress, {:target, target, :capture_attempt, attempt, retries})

      case timed_step(
             fn ->
               capture(project_slug, Keyword.merge([emulator_target: target], capture_opts))
             end,
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
             false <- workspace == "" do
          package_opts =
            [
              workspace_root: workspace,
              target_type: target_type,
              project_name: project_name
            ]
            |> maybe_put_target_platforms(Keyword.get(opts, :target_platforms))

          case PebbleToolchain.package("screenshot-capture", package_opts) do
            {:ok, build_result} -> {:ok, build_result.artifact_path}
            {:error, reason} -> {:error, reason}
          end
        else
          _ -> {:error, :package_path_required}
        end
    end
  end

  @spec resolve_capture_package_path(term(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp resolve_capture_package_path(project_slug, target, opts) do
    case Keyword.get(opts, :package_path) do
      path when is_binary(path) and path != "" ->
        resolve_package_path(project_slug, opts)

      _ ->
        resolve_package_path(project_slug, Keyword.put(opts, :target_platforms, [target]))
    end
  end

  @spec maybe_put_target_platforms(keyword(), term()) :: keyword()
  defp maybe_put_target_platforms(opts, platforms) when is_list(platforms),
    do: Keyword.put(opts, :target_platforms, platforms)

  defp maybe_put_target_platforms(opts, _platforms), do: opts

  @spec capture_targets(term()) :: [String.t()]
  defp capture_targets(targets) when is_list(targets) do
    allowed = PebbleToolchain.supported_emulator_targets()
    allowed_set = MapSet.new(allowed)

    targets
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed_set, &1))
    |> Enum.uniq()
    |> case do
      [] -> allowed
      normalized -> normalized
    end
  end

  defp capture_targets(_targets), do: PebbleToolchain.supported_emulator_targets()

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

  @doc false
  @spec normalize_filename_public(String.t()) :: {:ok, String.t()} | {:error, term()}
  def normalize_filename_public(name), do: normalize_filename(name)

  @doc false
  @spec normalize_emulator_target_public(String.t()) :: {:ok, String.t()} | {:error, term()}
  def normalize_emulator_target_public(target), do: normalize_emulator_target(target)

  @doc false
  @spec mime_type_for_path(String.t()) :: String.t()
  def mime_type_for_path(path), do: mime_type_from_filename(Path.basename(path))
end
