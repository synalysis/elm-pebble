defmodule Ide.ProjectTemplates do
  @moduledoc """
  Project template scaffolding for new IDE projects.
  """

  alias Ide.InternalPackages
  alias Ide.CompanionProtocolGenerator

  @template_keys ~w(starter watchface-digital watchface-analog watchface-tutorial-complete watchface-yes game-basic game-tiny-bird game-greeneys-run game-2048)

  @doc """
  Returns available template keys.
  """
  @spec template_keys() :: [String.t()]
  def template_keys, do: @template_keys

  @doc """
  Resolves the implied project target for a template key.
  """
  @spec target_type_for_template(String.t()) :: String.t()
  def target_type_for_template(template)
      when template in [
             "watchface-digital",
             "watchface-analog",
             "watchface-tutorial-complete",
             "watchface-yes"
           ],
      do: "watchface"

  def target_type_for_template(_template), do: "app"

  @doc """
  Returns select options for template pickers.
  """
  @spec options() :: [{String.t(), String.t()}]
  def options do
    [
      {"Starter (watch, protocol, phone)", "starter"},
      {"Watchface: Digital (watch-only)", "watchface-digital"},
      {"Watchface: Analog (watch-only)", "watchface-analog"},
      {"Watchface tutorial: Complete", "watchface-tutorial-complete"},
      {"Watchface: YES (watch, protocol, phone)", "watchface-yes"},
      {"Game: Basic", "game-basic"},
      {"Game: Tiny Bird", "game-tiny-bird"},
      {"Game: Greeney's Run", "game-greeneys-run"},
      {"Game: 2048", "game-2048"}
    ]
  end

  @doc """
  Applies a selected template to a project workspace.
  """
  @spec apply_template(String.t(), String.t()) :: :ok | {:error, term()}
  def apply_template(template, workspace_path) when template in @template_keys do
    case template do
      "starter" ->
        seed_multi_root_workspace(workspace_path)

      "watchface-digital" ->
        seed_watch_only_workspace(workspace_path, "watchface_digital")

      "watchface-analog" ->
        seed_watch_only_workspace(workspace_path, "watchface_analog")

      "watchface-tutorial-complete" ->
        seed_watchface_tutorial_workspace(workspace_path)

      "watchface-yes" ->
        seed_yes_watchface_workspace(workspace_path)

      "game-basic" ->
        seed_watch_only_workspace(workspace_path, "game_basic")

      "game-tiny-bird" ->
        seed_watch_only_workspace(workspace_path, "game_tiny_bird")

      "game-greeneys-run" ->
        seed_watch_only_workspace(workspace_path, "game_greeneys_run")

      "game-2048" ->
        seed_watch_only_workspace(workspace_path, "game_2048")
    end
  end

  def apply_template(template, _workspace_path), do: {:error, {:unknown_template, template}}

  @doc """
  Ensures the default companion protocol root exists without overwriting user-authored
  protocol types.
  """
  @spec ensure_protocol_shared(String.t()) :: :ok | {:error, term()}
  def ensure_protocol_shared(workspace_path) when is_binary(workspace_path) do
    source_dir = Path.join(repo_root(), "shared/elm")
    target_dir = Path.join(workspace_path, "protocol/src")
    protocol_root = Path.join(workspace_path, "protocol")
    protocol_types = Path.join(target_dir, "Companion/Types.elm")
    protocol_watch = Path.join(target_dir, "Companion/Watch.elm")
    protocol_internal = Path.join(target_dir, "Companion/Internal.elm")

    elm_json = %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    with :ok <- File.mkdir_p(Path.dirname(protocol_types)),
         :ok <- copy_file_if_missing(Path.join(source_dir, "Companion/Types.elm"), protocol_types),
         :ok <- copy_file_if_missing(Path.join(source_dir, "Companion/Watch.elm"), protocol_watch),
         :ok <-
           CompanionProtocolGenerator.generate_elm_internal(protocol_types, protocol_internal),
         :ok <- write_json_if_missing(Path.join(protocol_root, "elm.json"), elm_json) do
      :ok
    end
  end

  @doc """
  Adds the default companion app scaffolding to an existing watch project.
  """
  @spec ensure_companion_app(String.t()) :: :ok | {:error, term()}
  def ensure_companion_app(workspace_path) when is_binary(workspace_path) do
    with :ok <- ensure_protocol_shared(workspace_path),
         :ok <- ensure_phone_companion(workspace_path),
         :ok <- ensure_phone_companion_source_dirs(workspace_path),
         :ok <- ensure_watch_protocol_source_dir(workspace_path) do
      :ok
    end
  end

  @spec ensure_phone_companion_source_dirs(String.t()) :: :ok | {:error, term()}
  def ensure_phone_companion_source_dirs(workspace_path) when is_binary(workspace_path) do
    elm_json_path = Path.join([workspace_path, "phone", "elm.json"])
    target_dir = Path.join(workspace_path, "phone/src")

    with {:ok, content} <- File.read(elm_json_path),
         {:ok, %{} = decoded} <- Jason.decode(content) do
      source_dirs =
        decoded
        |> Map.get("source-directories", ["src"])
        |> List.wrap()

      next_dirs =
        source_dirs
        |> reject_phone_obsolete_source_dirs()
        |> then(fn dirs ->
          Enum.reduce(phone_source_directory_additions(workspace_path), dirs, fn dir, acc ->
            if dir in acc, do: acc, else: acc ++ [dir]
          end)
        end)

      next_decoded =
        decoded
        |> Map.put("source-directories", next_dirs)
        |> remove_phone_obsolete_dependencies()

      with :ok <- remove_obsolete_phone_runtime_sources(target_dir) do
        if next_decoded == decoded do
          :ok
        else
          File.write(elm_json_path, Jason.encode!(next_decoded, pretty: true))
        end
      end
    else
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_phone_elm_json}
    end
  end

  @spec seed_multi_root_workspace(term()) :: term()
  defp seed_multi_root_workspace(workspace_path) do
    with :ok <- seed_watch_fixture(workspace_path),
         :ok <- seed_protocol_shared(workspace_path),
         :ok <- seed_phone_companion(workspace_path) do
      :ok
    end
  end

  @spec seed_watchface_tutorial_workspace(term()) :: term()
  defp seed_watchface_tutorial_workspace(workspace_path) do
    with :ok <- seed_protocol_shared(workspace_path),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_watchface_tutorial_phone(workspace_path),
         :ok <- seed_watch_only_workspace(workspace_path, "watchface_tutorial_complete") do
      :ok
    end
  end

  @spec seed_yes_watchface_workspace(term()) :: term()
  defp seed_yes_watchface_workspace(workspace_path) do
    with :ok <- seed_yes_protocol(workspace_path),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_yes_phone(workspace_path),
         :ok <- seed_watch_only_workspace(workspace_path, "watchface_yes") do
      :ok
    end
  end

  @spec seed_yes_protocol(term()) :: term()
  defp seed_yes_protocol(workspace_path) do
    source_dir = Path.join(ide_root(), "priv/project_templates/watchface_yes/protocol/src")
    target_dir = Path.join(workspace_path, "protocol/src")
    protocol_root = Path.join(workspace_path, "protocol")

    elm_json = %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    protocol_types = Path.join(target_dir, "Companion/Types.elm")
    protocol_internal = Path.join(target_dir, "Companion/Internal.elm")

    with :ok <- replace_dir(source_dir, target_dir),
         :ok <-
           CompanionProtocolGenerator.generate_elm_internal(protocol_types, protocol_internal),
         :ok <-
           File.write(Path.join(protocol_root, "elm.json"), Jason.encode!(elm_json, pretty: true)) do
      :ok
    end
  end

  @spec seed_yes_phone(term()) :: term()
  defp seed_yes_phone(workspace_path) do
    source = Path.join(ide_root(), "priv/project_templates/watchface_yes/phone/src")
    target = Path.join(workspace_path, "phone/src")

    with :ok <-
           copy_file(Path.join(source, "CompanionApp.elm"), Path.join(target, "CompanionApp.elm")),
         :ok <-
           copy_file(
             Path.join(source, "CompanionPreferences.elm"),
             Path.join(target, "CompanionPreferences.elm")
           ),
         :ok <- Ide.PebblePreferences.ensure_generated_bridge(Path.join(workspace_path, "phone")) do
      :ok
    end
  end

  @spec seed_watchface_tutorial_phone(term()) :: term()
  defp seed_watchface_tutorial_phone(workspace_path) do
    source = Path.join(ide_root(), "priv/project_templates/watchface_tutorial_complete/phone/src")
    target = Path.join(workspace_path, "phone/src")

    with :ok <-
           copy_file(Path.join(source, "CompanionApp.elm"), Path.join(target, "CompanionApp.elm")),
         :ok <-
           copy_file(
             Path.join(source, "CompanionPreferences.elm"),
             Path.join(target, "CompanionPreferences.elm")
           ),
         :ok <- Ide.PebblePreferences.ensure_generated_bridge(Path.join(workspace_path, "phone")) do
      :ok
    end
  end

  @spec seed_watch_only_workspace(term(), term()) :: term()
  defp seed_watch_only_workspace(workspace_path, watchface_template_dir) do
    watch_root = Path.join(workspace_path, "watch")

    elm_json = %{
      "type" => "application",
      "source-directories" => watch_source_directories(watchface_template_dir),
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => watch_direct_dependencies(watchface_template_dir),
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    with :ok <- File.mkdir_p(watch_root),
         :ok <-
           File.write(Path.join(watch_root, "elm.json"), Jason.encode!(elm_json, pretty: true)),
         :ok <-
           copy_file(
             Path.join(ide_root(), "priv/project_templates/starter_watch/index.html"),
             Path.join(watch_root, "index.html")
           ),
         :ok <-
           replace_dir(
             Path.join(ide_root(), "priv/project_templates/#{watchface_template_dir}/src"),
             Path.join(watch_root, "src")
           ),
         :ok <- maybe_copy_template_resources(workspace_path, watchface_template_dir) do
      :ok
    end
  end

  @spec maybe_copy_template_resources(term(), term()) :: term()
  defp maybe_copy_template_resources(workspace_path, template_dir) do
    source = Path.join(ide_root(), "priv/project_templates/#{template_dir}/resources")

    if File.dir?(source) do
      replace_dir(source, Path.join(workspace_path, "watch/resources"))
    else
      :ok
    end
  end

  @spec watch_direct_dependencies(String.t()) :: map()
  defp watch_direct_dependencies(template_dir) do
    deps = %{
      "elm/core" => "1.0.5",
      "elm/json" => "1.1.3",
      "elm/time" => "1.0.0"
    }

    if template_dir == "game_2048" do
      Map.put(deps, "elm/random", "1.0.0")
    else
      deps
    end
  end

  @spec watch_source_directories(term()) :: [String.t()]
  defp watch_source_directories(template_dir)
       when template_dir in ["watchface_tutorial_complete", "watchface_yes"] do
    [
      "src",
      "../protocol/src",
      InternalPackages.pebble_elm_src_abs(),
      InternalPackages.elm_time_elm_src_abs()
    ]
  end

  defp watch_source_directories(_template_dir) do
    ["src"] ++ InternalPackages.watchface_elm_json_extra_source_dirs_abs()
  end

  @spec seed_watch_fixture(term()) :: term()
  defp seed_watch_fixture(workspace_path) do
    template_root = Path.join(ide_root(), "priv/project_templates/starter_watch")
    watch_root = Path.join(workspace_path, "watch")

    elm_json = %{
      "type" => "application",
      "source-directories" => watch_with_protocol_source_directories(),
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    with :ok <- File.mkdir_p(watch_root),
         :ok <-
           File.write(Path.join(watch_root, "elm.json"), Jason.encode!(elm_json, pretty: true)),
         :ok <-
           copy_file(Path.join(template_root, "index.html"), Path.join(watch_root, "index.html")),
         :ok <- replace_dir(Path.join(template_root, "src"), Path.join(watch_root, "src")) do
      :ok
    end
  end

  @spec watch_with_protocol_source_directories() :: [String.t()]
  defp watch_with_protocol_source_directories do
    [
      "src",
      "../protocol/src",
      InternalPackages.pebble_elm_src_abs(),
      InternalPackages.elm_time_elm_src_abs(),
      InternalPackages.elm_random_elm_src_abs()
    ]
  end

  @spec seed_protocol_shared(term()) :: term()
  defp seed_protocol_shared(workspace_path) do
    ensure_protocol_shared(workspace_path)
  end

  @spec seed_phone_companion(term()) :: term()
  defp seed_phone_companion(workspace_path) do
    source_dir = Path.join(ide_root(), "priv/pebble_app_template/src/elm")
    target_dir = Path.join(workspace_path, "phone/src")
    phone_root = Path.join(workspace_path, "phone")

    elm_json = %{
      "type" => "application",
      "source-directories" => phone_source_directories(),
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/http" => "2.0.0",
          "elm/json" => "1.1.3"
        },
        "indirect" => %{
          "elm/bytes" => "1.0.8",
          "elm/file" => "1.0.5",
          "elm/time" => "1.0.0"
        }
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    with :ok <- replace_dir(source_dir, target_dir),
         :ok <- remove_generated_phone_protocol_internal(target_dir),
         :ok <- remove_obsolete_phone_runtime_sources(target_dir),
         :ok <-
           File.write(Path.join(phone_root, "elm.json"), Jason.encode!(elm_json, pretty: true)) do
      :ok
    end
  end

  @spec ensure_phone_companion(String.t()) :: :ok | {:error, term()}
  defp ensure_phone_companion(workspace_path) do
    phone_root = Path.join(workspace_path, "phone")

    if File.exists?(Path.join(phone_root, "elm.json")) do
      ensure_phone_companion_entrypoint(workspace_path)
    else
      seed_phone_companion(workspace_path)
    end
  end

  @spec ensure_phone_companion_entrypoint(String.t()) :: :ok | {:error, term()}
  defp ensure_phone_companion_entrypoint(workspace_path) do
    source_dir = Path.join(ide_root(), "priv/pebble_app_template/src/elm")
    target_dir = Path.join(workspace_path, "phone/src")

    copy_file_if_missing(
      Path.join(source_dir, "CompanionApp.elm"),
      Path.join(target_dir, "CompanionApp.elm")
    )
  end

  @spec phone_source_directories() :: [String.t()]
  defp phone_source_directories do
    [
      "src",
      "../protocol/src",
      InternalPackages.shared_elm_companion_abs(),
      InternalPackages.pebble_companion_core_elm_src_abs(),
      InternalPackages.pebble_companion_preferences_elm_src_abs()
    ]
  end

  @spec phone_source_directory_additions(String.t()) :: [String.t()]
  defp phone_source_directory_additions(_workspace_path) do
    [
      "../protocol/src",
      InternalPackages.shared_elm_companion_abs(),
      InternalPackages.pebble_companion_core_elm_src_abs(),
      InternalPackages.pebble_companion_preferences_elm_src_abs()
    ]
  end

  @spec reject_phone_obsolete_source_dirs([term()]) :: [term()]
  defp reject_phone_obsolete_source_dirs(source_dirs) when is_list(source_dirs) do
    obsolete = MapSet.new(phone_obsolete_source_dirs())

    Enum.reject(source_dirs, fn dir ->
      is_binary(dir) and MapSet.member?(obsolete, Path.expand(dir))
    end)
  end

  @spec phone_obsolete_source_dirs() :: [String.t()]
  defp phone_obsolete_source_dirs do
    [
      InternalPackages.phone_pebble_stubs_elm_src_abs(),
      InternalPackages.elm_random_elm_src_abs(),
      InternalPackages.pebble_elm_src_abs()
    ]
    |> Enum.map(&Path.expand/1)
  end

  @spec remove_phone_obsolete_dependencies(map()) :: map()
  defp remove_phone_obsolete_dependencies(%{} = elm_json) do
    case get_in(elm_json, ["dependencies", "direct"]) do
      %{} = deps ->
        next_deps =
          deps
          |> Map.delete("elm-pebble/elm-watch")

        put_in(elm_json, ["dependencies", "direct"], next_deps)

      _ ->
        elm_json
    end
  end

  @spec ensure_watch_protocol_source_dir(String.t()) :: :ok | {:error, term()}
  defp ensure_watch_protocol_source_dir(workspace_path) do
    elm_json_path = Path.join([workspace_path, "watch", "elm.json"])

    with {:ok, content} <- File.read(elm_json_path),
         {:ok, %{} = decoded} <- Jason.decode(content) do
      source_dirs =
        decoded
        |> Map.get("source-directories", ["src"])
        |> List.wrap()

      if "../protocol/src" in source_dirs do
        :ok
      else
        next_dirs = insert_after_src(source_dirs, "../protocol/src")
        next = Map.put(decoded, "source-directories", next_dirs)
        File.write(elm_json_path, Jason.encode!(next, pretty: true))
      end
    else
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_watch_elm_json}
    end
  end

  @spec insert_after_src([term()], String.t()) :: [term()]
  defp insert_after_src(source_dirs, new_dir) do
    case Enum.split_while(source_dirs, &(&1 != "src")) do
      {prefix, ["src" | rest]} -> prefix ++ ["src", new_dir] ++ rest
      {_prefix, []} -> [new_dir | source_dirs]
    end
  end

  @spec remove_generated_phone_protocol_internal(String.t()) :: :ok | {:error, term()}
  defp remove_generated_phone_protocol_internal(target_dir) when is_binary(target_dir) do
    case File.rm(Path.join(target_dir, "Companion/Internal.elm")) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec remove_obsolete_phone_runtime_sources(String.t()) :: :ok | {:error, term()}
  defp remove_obsolete_phone_runtime_sources(target_dir) when is_binary(target_dir) do
    case File.rm_rf(Path.join(target_dir, "Pebble/Companion")) do
      {:ok, _removed} ->
        _ = File.rmdir(Path.join(target_dir, "Pebble"))
        :ok

      {:error, reason, _path} ->
        {:error, reason}
    end
  end

  @spec replace_dir(term(), term()) :: term()
  defp replace_dir(source, target) do
    _ = File.rm_rf(target)
    File.mkdir_p(Path.dirname(target))

    case File.cp_r(source, target) do
      {:ok, _} -> :ok
      {:error, reason, _path} -> {:error, reason}
    end
  end

  @spec copy_file(term(), term()) :: term()
  defp copy_file(source, target) do
    with :ok <- File.mkdir_p(Path.dirname(target)),
         :ok <- File.cp(source, target) do
      :ok
    end
  end

  @spec copy_file_if_missing(String.t(), String.t()) :: :ok | {:error, term()}
  defp copy_file_if_missing(source, target) do
    if File.exists?(target) do
      :ok
    else
      copy_file(source, target)
    end
  end

  @spec write_json_if_missing(String.t(), map()) :: :ok | {:error, term()}
  defp write_json_if_missing(path, payload) do
    if File.exists?(path) do
      :ok
    else
      with :ok <- File.mkdir_p(Path.dirname(path)) do
        File.write(path, Jason.encode!(payload, pretty: true))
      end
    end
  end

  @spec ide_root() :: term()
  defp ide_root do
    Path.expand("../..", __DIR__)
  end

  @spec repo_root() :: term()
  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
