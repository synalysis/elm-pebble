defmodule Ide.ProjectTemplates do
  @moduledoc """
  Project template scaffolding for new IDE projects.
  """

  alias Ide.CompanionProtocolGenerator
  alias Ide.InternalPackages
  alias Ide.Paths
  alias Ide.PebbleToolchain
  alias Ide.ProjectTemplates.Types, as: TemplateTypes
  alias Ide.Resources.ResourceStore

  @type workspace_path :: String.t()
  @type template_dir_name :: String.t()
  @type seed_result :: :ok | {:error, template_error()}
  @type wire_target_platforms :: [String.t()] | String.t() | nil | boolean() | number()
  @type template_error ::
          {:unknown_template, String.t()}
          | {:missing_template_asset, String.t()}
          | :invalid_phone_elm_json
          | :invalid_watch_elm_json
          | {:missing_union, String.t()}
          | File.posix()
          | Jason.EncodeError.t()

  @template_keys ~w(starter app-minimal watchface-minimal watchface-digital watchface-smoke-screen watchface-color-shapes watchface-analog watchface-tutorial-complete watchface-yes watchface-tangram-time watchface-weather-animated watchface-poke-battle companion-demo-phone-status companion-demo-protocol-matrix companion-demo-weather-env companion-demo-calendar companion-demo-geolocation companion-demo-storage companion-demo-settings companion-demo-websocket companion-demo-timeline watch-demo-accel watch-demo-vibes watch-demo-data-log watch-demo-app-focus watch-demo-compass watch-demo-dictation watch-demo-health watch-demo-light watch-demo-watch-info watch-demo-drawing-showcase watch-demo-speaker watch-demo-storage watch-demo-launch watch-demo-screen-change watch-demo-system watch-demo-unobstructed watch-demo-wakeup watch-demo-frame watch-demo-time watch-demo-log game-basic game-tiny-bird game-jump-n-run game-2048 game-elmtris)

  @template_dirs %{
    "starter" => "starter_watch",
    "app-minimal" => "app_minimal",
    "watchface-minimal" => "watchface_minimal",
    "watchface-digital" => "watchface_digital",
    "watchface-smoke-screen" => "watchface_smoke_screen",
    "watchface-color-shapes" => "watchface_color_shapes",
    "watchface-analog" => "watchface_analog",
    "watchface-tutorial-complete" => "watchface_tutorial_complete",
    "watchface-yes" => "watchface_yes",
    "watchface-tangram-time" => "watchface_tangram_time",
    "watchface-weather-animated" => "watchface_weather_animated",
    "watchface-poke-battle" => "watchface_poke_battle",
    "companion-demo-phone-status" => "companion_demo_phone_status",
    "companion-demo-protocol-matrix" => "companion_demo_protocol_matrix",
    "companion-demo-weather-env" => "companion_demo_weather_env",
    "companion-demo-calendar" => "companion_demo_calendar",
    "companion-demo-geolocation" => "companion_demo_geolocation",
    "companion-demo-storage" => "companion_demo_storage",
    "companion-demo-settings" => "companion_demo_settings",
    "companion-demo-websocket" => "companion_demo_websocket",
    "companion-demo-timeline" => "companion_demo_timeline",
    "watch-demo-accel" => "watch_demo_accel",
    "watch-demo-vibes" => "watch_demo_vibes",
    "watch-demo-data-log" => "watch_demo_data_log",
    "watch-demo-app-focus" => "watch_demo_app_focus",
    "watch-demo-compass" => "watch_demo_compass",
    "watch-demo-dictation" => "watch_demo_dictation",
    "watch-demo-health" => "watch_demo_health",
    "watch-demo-light" => "watch_demo_light",
    "watch-demo-watch-info" => "watch_demo_watch_info",
    "watch-demo-drawing-showcase" => "watch_demo_drawing_showcase",
    "watch-demo-speaker" => "watch_demo_speaker",
    "watch-demo-storage" => "watch_demo_storage",
    "watch-demo-launch" => "watch_demo_launch",
    "watch-demo-screen-change" => "watch_demo_screen_change",
    "watch-demo-system" => "watch_demo_system",
    "watch-demo-unobstructed" => "watch_demo_unobstructed",
    "watch-demo-wakeup" => "watch_demo_wakeup",
    "watch-demo-frame" => "watch_demo_frame",
    "watch-demo-time" => "watch_demo_time",
    "watch-demo-log" => "watch_demo_log",
    "game-basic" => "game_basic",
    "game-tiny-bird" => "game_tiny_bird",
    "game-jump-n-run" => "game_jump_n_run",
    "game-2048" => "game_2048",
    "game-elmtris" => "game_elmtris"
  }

  @doc """
  Returns available template keys.
  """
  @spec template_keys() :: [String.t()]
  def template_keys, do: @template_keys

  @doc """
  Absolute path to `priv/project_templates/<dir>` for a template key.
  """
  @spec template_priv_root(String.t()) ::
          {:ok, String.t()} | {:error, {:unknown_template, String.t()}}
  def template_priv_root(template_key) when is_binary(template_key) do
    case Map.fetch(@template_dirs, template_key) do
      {:ok, dir} ->
        {:ok, Paths.priv_path(Path.join("project_templates", dir))}

      :error ->
        {:error, {:unknown_template, template_key}}
    end
  end

  @doc """
  Resolves the implied project target for a template key.
  """
  @spec target_type_for_template(String.t()) :: String.t()
  def target_type_for_template(template)
      when template in [
             "watchface-minimal",
             "watchface-digital",
             "watchface-smoke-screen",
             "watchface-color-shapes",
             "watchface-analog",
             "watchface-tutorial-complete",
             "watchface-yes",
             "watchface-tangram-time",
             "watchface-weather-animated",
             "watchface-poke-battle",
             "companion-demo-phone-status",
             "companion-demo-weather-env",
             "companion-demo-calendar",
             "companion-demo-geolocation"
           ],
      do: "watchface"

  def target_type_for_template(_template), do: "app"

  @companion_templates ~w(
    starter
    watchface-tutorial-complete
    watchface-yes
    watchface-tangram-time
    watchface-weather-animated
  )

  @doc """
  Whether a template seeds a phone companion app (protocol + phone roots).
  """
  @spec companion_for_template(String.t()) :: boolean()
  def companion_for_template(template) when template in @companion_templates, do: true
  def companion_for_template("companion-demo-" <> _), do: true
  def companion_for_template(_template), do: false

  @doc """
  Returns picker categories with templates filtered by `target` and `companion`.

  `target` is `"all"`, `"watchface"`, or `"app"`.
  `companion` is `"all"`, `"with"`, or `"without"`.
  """
  @spec filter_picker_categories([TemplateTypes.picker_category()], String.t(), String.t()) :: [
          TemplateTypes.picker_category()
        ]
  def filter_picker_categories(categories, target \\ "all", companion \\ "all") do
    categories
    |> Enum.map(fn category ->
      templates =
        Enum.filter(category.templates, fn template ->
          picker_target_matches?(template.target_type, target) and
            picker_companion_matches?(template.has_companion, companion)
        end)

      Map.put(category, :templates, templates)
    end)
    |> Enum.reject(&(Enum.empty?(&1.templates)))
  end

  @doc """
  Default Pebble target platforms to enable for new projects created from `template`.

  Reads optional `priv/project_templates/<dir>/template.json` with:

      { "target_platforms": ["basalt", "chalk", ...] }

  Templates without metadata enable every supported platform.
  """
  @spec target_platforms_for_template(String.t()) :: [String.t()]
  def target_platforms_for_template(template) when template in @template_keys do
    template
    |> load_template_metadata()
    |> Map.get("target_platforms")
    |> normalize_target_platforms()
  end

  def target_platforms_for_template(_template), do: default_target_platforms()

  @doc """
  Default `release_defaults` map for a newly created project from `template`.
  """
  @spec default_release_defaults(String.t()) :: TemplateTypes.release_defaults()
  def default_release_defaults(template) when is_binary(template) do
    %{"target_platforms" => target_platforms_for_template(template)}
  end

  @doc """
  Returns template metadata for automation and MCP consumers.
  """
  @spec catalog() :: [TemplateTypes.catalog_entry()]
  def catalog do
    Enum.map(options(), fn {label, key} ->
      %{
        key: key,
        label: label,
        target_type: target_type_for_template(key),
        has_companion: companion_for_template(key)
      }
    end)
  end

  @category_order ~w(starter watchface companion watch_demo game)

  @category_labels %{
    "starter" => "Starter",
    "watchface" => "Watchfaces",
    "companion" => "Companion demos",
    "watch_demo" => "Watch demos",
    "game" => "Games"
  }

  @doc """
  Returns project templates grouped for the create-project picker UI.
  """
  @spec picker_categories() :: [TemplateTypes.picker_category()]
  def picker_categories do
    @category_order
    |> Enum.map(fn category_id ->
      templates =
        options()
        |> Enum.filter(fn {_label, key} -> category_for_key(key) == category_id end)
        |> Enum.map(&picker_entry/1)

      %{
        id: category_id,
        label: Map.fetch!(@category_labels, category_id),
        templates: templates
      }
    end)
    |> Enum.reject(&(Enum.empty?(&1.templates)))
  end

  @doc """
  Public URL for a template preview screenshot in the create-project picker.
  """
  @spec preview_image_url(String.t()) :: String.t()
  def preview_image_url(template_key) when is_binary(template_key) do
    "/images/template-previews/#{template_key}.png"
  end

  @doc """
  Returns the short display title for a template key (as shown in the create-project picker).
  """
  @spec picker_title(String.t()) :: String.t()
  def picker_title(template_key) when is_binary(template_key) do
    case Enum.find(options(), fn {_label, key} -> key == template_key end) do
      {label, _} -> parse_picker_label(label).title
      nil -> template_key
    end
  end

  @doc """
  Returns select options for template pickers.
  """
  @spec options() :: [{String.t(), String.t()}]
  def options do
    [
      {"Starter (watch, protocol, phone)", "starter"},
      {"Minimal app (watch-only)", "app-minimal"},
      {"Watchface: Minimal (watch-only)", "watchface-minimal"},
      {"Watchface: Digital (watch-only)", "watchface-digital"},
      {"Watchface: Smoke screen (checkerboard, emulator debug)", "watchface-smoke-screen"},
      {"Watchface: Color shapes (radial fill debug)", "watchface-color-shapes"},
      {"Watchface: Analog (watch-only)", "watchface-analog"},
      {"Watchface tutorial: Complete", "watchface-tutorial-complete"},
      {"Watchface: YES (watch, protocol, phone)", "watchface-yes"},
      {"Watchface: Tangram Time (watch, protocol, phone)", "watchface-tangram-time"},
      {"Watchface: Weather Animated (watch, protocol, phone, vectors)",
       "watchface-weather-animated"},
      {"Watchface: Poke Battle (watch-only, health steps)", "watchface-poke-battle"},
      {"Companion demo: Phone status (battery, locale, network, notifications)",
       "companion-demo-phone-status"},
      {"Companion demo: Protocol matrix (AppMessage wire types)", "companion-demo-protocol-matrix"},
      {"Companion demo: Weather & environment", "companion-demo-weather-env"},
      {"Companion demo: Calendar", "companion-demo-calendar"},
      {"Companion demo: Geolocation (lat/long watchface)", "companion-demo-geolocation"},
      {"Companion demo: Storage & preferences (app)", "companion-demo-storage"},
      {"Companion demo: Settings & lifecycle (app)", "companion-demo-settings"},
      {"Companion demo: WebSocket (app)", "companion-demo-websocket"},
      {"Companion demo: Timeline (app)", "companion-demo-timeline"},
      {"Watch demo: Accelerometer (app)", "watch-demo-accel"},
      {"Watch demo: Custom vibes (app)", "watch-demo-vibes"},
      {"Watch demo: Data logging (app)", "watch-demo-data-log"},
      {"Watch demo: App focus (app)", "watch-demo-app-focus"},
      {"Watch demo: Compass (app, aplite)", "watch-demo-compass"},
      {"Watch demo: Dictation (app, mic models)", "watch-demo-dictation"},
      {"Watch demo: Health (app, Time+)", "watch-demo-health"},
      {"Watch demo: Backlight (app)", "watch-demo-light"},
      {"Watch demo: Watch info (app)", "watch-demo-watch-info"},
      {"Watch demo: Drawing showcase (all render ops)", "watch-demo-drawing-showcase"},
      {"Watch demo: Speaker (tones, notes, tracks)", "watch-demo-speaker"},
      {"Watch demo: Storage (read/write/maxSize)", "watch-demo-storage"},
      {"Watch demo: Launch context (quick launch)", "watch-demo-launch"},
      {"Watch demo: Screen change (onScreenChange)", "watch-demo-screen-change"},
      {"Watch demo: System (battery, connection)", "watch-demo-system"},
      {"Watch demo: Unobstructed area (round)", "watch-demo-unobstructed"},
      {"Watch demo: Wakeup scheduling", "watch-demo-wakeup"},
      {"Watch demo: Frame loop (atFps)", "watch-demo-frame"},
      {"Watch demo: Time & timezone", "watch-demo-time"},
      {"Watch demo: Log codes (debug builds)", "watch-demo-log"},
      {"Game: Basic", "game-basic"},
      {"Game: Tiny Bird", "game-tiny-bird"},
      {"Game: Jump'n Run", "game-jump-n-run"},
      {"Game: 2048", "game-2048"},
      {"Game: Elmtris (Tetris)", "game-elmtris"}
    ]
  end

  @doc """
  Seeds a minimal phone + protocol workspace for debugger inline phone compiles
  (session-only reloads without a persisted project row).
  """
  @spec seed_ephemeral_phone_compile_workspace(String.t()) :: :ok | {:error, template_error()}
  def seed_ephemeral_phone_compile_workspace(workspace_path) when is_binary(workspace_path) do
    with :ok <- seed_template_protocol(workspace_path, "companion_demo_phone_status"),
         :ok <- seed_phone_companion(workspace_path) do
      :ok
    end
  end

  @doc """
  Applies a selected template to a project workspace.
  """
  @spec apply_template(String.t(), String.t()) :: :ok | {:error, template_error()}
  def apply_template(template, workspace_path) when template in @template_keys do
    case template do
      "starter" ->
        seed_multi_root_workspace(workspace_path)

      "app-minimal" ->
        seed_watch_only_workspace(workspace_path, "app_minimal")

      "watchface-minimal" ->
        seed_watch_only_workspace(workspace_path, "watchface_minimal")

      "watchface-digital" ->
        seed_watch_only_workspace(workspace_path, "watchface_digital")

      "watchface-smoke-screen" ->
        seed_watch_only_workspace(workspace_path, "watchface_smoke_screen")

      "watchface-color-shapes" ->
        seed_watch_only_workspace(workspace_path, "watchface_color_shapes")

      "watchface-analog" ->
        seed_watch_only_workspace(workspace_path, "watchface_analog")

      "watchface-tutorial-complete" ->
        seed_watchface_tutorial_workspace(workspace_path)

      "watchface-yes" ->
        seed_yes_watchface_workspace(workspace_path)

      "watchface-tangram-time" ->
        seed_tangram_time_watchface_workspace(workspace_path)

      "watchface-weather-animated" ->
        seed_weather_animated_watchface_workspace(workspace_path)

      "watchface-poke-battle" ->
        seed_watch_only_workspace(workspace_path, "watchface_poke_battle")

      "companion-demo-phone-status" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_phone_status")

      "companion-demo-protocol-matrix" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_protocol_matrix")

      "companion-demo-weather-env" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_weather_env")

      "companion-demo-calendar" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_calendar")

      "companion-demo-storage" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_storage")

      "companion-demo-settings" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_settings")

      "companion-demo-websocket" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_websocket")

      "companion-demo-timeline" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_timeline")

      "companion-demo-geolocation" ->
        seed_companion_demo_workspace(workspace_path, "companion_demo_geolocation")

      "watch-demo-accel" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_accel")

      "watch-demo-vibes" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_vibes")

      "watch-demo-data-log" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_data_log")

      "watch-demo-app-focus" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_app_focus")

      "watch-demo-compass" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_compass")

      "watch-demo-dictation" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_dictation")

      "watch-demo-health" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_health")

      "watch-demo-light" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_light")

      "watch-demo-watch-info" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_watch_info")

      "watch-demo-drawing-showcase" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_drawing_showcase")

      "watch-demo-speaker" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_speaker")

      "watch-demo-storage" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_storage")

      "watch-demo-launch" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_launch")

      "watch-demo-screen-change" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_screen_change")

      "watch-demo-system" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_system")

      "watch-demo-unobstructed" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_unobstructed")

      "watch-demo-wakeup" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_wakeup")

      "watch-demo-frame" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_frame")

      "watch-demo-time" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_time")

      "watch-demo-log" ->
        seed_watch_only_workspace(workspace_path, "watch_demo_log")

      "game-basic" ->
        seed_watch_only_workspace(workspace_path, "game_basic")

      "game-tiny-bird" ->
        seed_watch_only_workspace(workspace_path, "game_tiny_bird")

      "game-jump-n-run" ->
        seed_watch_only_workspace(workspace_path, "game_jump_n_run")

      "game-2048" ->
        seed_watch_only_workspace(workspace_path, "game_2048")

      "game-elmtris" ->
        seed_watch_only_workspace(workspace_path, "game_elmtris")
    end
  end

  def apply_template(template, _workspace_path), do: {:error, {:unknown_template, template}}

  @doc """
  Ensures the default companion protocol root exists without overwriting user-authored
  protocol types.
  """
  @spec ensure_protocol_shared(String.t()) :: :ok | {:error, template_error()}
  def ensure_protocol_shared(workspace_path) when is_binary(workspace_path) do
    source_dir = Paths.bundled_elm_path("shared-elm", "shared/elm")
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
  @spec ensure_companion_app(String.t()) :: :ok | {:error, template_error()}
  def ensure_companion_app(workspace_path) when is_binary(workspace_path) do
    with :ok <- ensure_protocol_shared(workspace_path),
         :ok <- ensure_phone_companion(workspace_path),
         :ok <- ensure_phone_companion_source_dirs(workspace_path),
         :ok <- ensure_watch_protocol_source_dir(workspace_path) do
      :ok
    end
  end

  @doc """
  Ensures Elm compiler roots exist for debugger/build flows.

  Recreates missing `elm.json` files when source trees are present and applies
  watch/protocol source-directory fixes for companion projects.
  """
  @spec ensure_compiler_roots(String.t(), [String.t()]) :: :ok | {:error, template_error()}
  def ensure_compiler_roots(workspace_path, _source_roots \\ ~w(watch protocol phone))
      when is_binary(workspace_path) do
    with :ok <- ensure_watch_compiler_root(workspace_path),
         :ok <- ensure_protocol_compiler_root(workspace_path),
         :ok <- ensure_phone_compiler_root(workspace_path),
         :ok <- ensure_watch_protocol_source_dir(workspace_path),
         :ok <- ensure_phone_companion_source_dirs(workspace_path) do
      :ok
    end
  end

  @spec ensure_watch_compiler_root(String.t()) :: :ok | {:error, template_error()}
  defp ensure_watch_compiler_root(workspace_path) do
    ensure_root_elm_json(
      Path.join(workspace_path, "watch"),
      watch_compiler_elm_json_template(workspace_path),
      Path.join(workspace_path, "watch/src/Main.elm")
    )
  end

  @spec ensure_protocol_compiler_root(String.t()) :: :ok | {:error, template_error()}
  defp ensure_protocol_compiler_root(workspace_path) do
    ensure_root_elm_json(
      Path.join(workspace_path, "protocol"),
      protocol_elm_json_template(),
      Path.join(workspace_path, "protocol/src/Companion/Types.elm")
    )
  end

  @spec ensure_phone_compiler_root(String.t()) :: :ok | {:error, template_error()}
  defp ensure_phone_compiler_root(workspace_path) do
    ensure_root_elm_json(
      Path.join(workspace_path, "phone"),
      phone_elm_json_template(),
      Path.join(workspace_path, "phone/src/CompanionApp.elm")
    )
  end

  @spec ensure_root_elm_json(String.t(), TemplateTypes.elm_json(), String.t()) ::
          :ok | {:error, template_error()}
  defp ensure_root_elm_json(root_path, template, marker_source_path) do
    elm_json_path = Path.join(root_path, "elm.json")

    cond do
      File.exists?(elm_json_path) ->
        :ok

      File.exists?(marker_source_path) ->
        with :ok <- File.mkdir_p(root_path),
             :ok <- File.write(elm_json_path, Jason.encode!(template, pretty: true)) do
          :ok
        end

      true ->
        :ok
    end
  end

  @spec watch_compiler_elm_json_template(String.t()) :: TemplateTypes.elm_json()
  defp watch_compiler_elm_json_template(workspace_path) when is_binary(workspace_path) do
    protocol_marker = Path.join(workspace_path, "protocol/src/Companion/Types.elm")

    source_directories =
      if File.exists?(protocol_marker) do
        watch_with_protocol_source_directories()
      else
        ["src"] ++ InternalPackages.watchface_elm_json_extra_source_dirs_abs()
      end

    watch_elm_json_template(source_directories)
  end

  @spec watch_elm_json_template([String.t()]) :: TemplateTypes.elm_json()
  defp watch_elm_json_template(source_directories) when is_list(source_directories) do
    %{
      "type" => "application",
      "source-directories" => source_directories,
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
  end

  @spec protocol_elm_json_template() :: TemplateTypes.elm_json()
  defp protocol_elm_json_template do
    %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }
  end

  @spec phone_elm_json_template() :: TemplateTypes.elm_json()
  defp phone_elm_json_template do
    %{
      "type" => "application",
      "source-directories" => phone_source_directories(),
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/http" => "2.0.0",
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{
          "elm/bytes" => "1.0.8",
          "elm/file" => "1.0.5"
        }
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }
  end

  @spec ensure_phone_companion_source_dirs(String.t()) :: :ok | {:error, template_error()}
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

  @spec seed_multi_root_workspace(workspace_path()) :: seed_result()
  defp seed_multi_root_workspace(workspace_path) do
    with :ok <- seed_watch_fixture(workspace_path),
         :ok <- seed_protocol_shared(workspace_path),
         :ok <- seed_phone_companion(workspace_path) do
      :ok
    end
  end

  @spec seed_watchface_tutorial_workspace(workspace_path()) :: seed_result()
  defp seed_watchface_tutorial_workspace(workspace_path) do
    with :ok <- seed_protocol_shared(workspace_path),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_watchface_tutorial_phone(workspace_path),
         :ok <- seed_watch_only_workspace(workspace_path, "watchface_tutorial_complete") do
      :ok
    end
  end

  @spec seed_yes_watchface_workspace(workspace_path()) :: seed_result()
  defp seed_yes_watchface_workspace(workspace_path) do
    with :ok <- seed_yes_protocol(workspace_path),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_yes_phone(workspace_path),
         :ok <- seed_watch_only_workspace(workspace_path, "watchface_yes") do
      :ok
    end
  end

  @spec seed_tangram_time_watchface_workspace(workspace_path()) :: seed_result()
  defp seed_tangram_time_watchface_workspace(workspace_path) do
    with :ok <- seed_tangram_time_protocol(workspace_path),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_tangram_time_phone(workspace_path),
         :ok <- seed_watch_only_workspace(workspace_path, "watchface_tangram_time") do
      :ok
    end
  end

  @spec seed_weather_animated_watchface_workspace(workspace_path()) :: seed_result()
  defp seed_weather_animated_watchface_workspace(workspace_path) do
    with :ok <- seed_weather_animated_protocol(workspace_path),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_weather_animated_phone(workspace_path),
         :ok <- seed_watch_only_workspace(workspace_path, "watchface_weather_animated") do
      :ok
    end
  end

  @spec seed_companion_demo_workspace(workspace_path(), template_dir_name()) :: seed_result()
  defp seed_companion_demo_workspace(workspace_path, template_dir) do
    with :ok <- seed_template_protocol(workspace_path, template_dir),
         :ok <- seed_phone_companion(workspace_path),
         :ok <- seed_companion_demo_phone(workspace_path, template_dir),
         :ok <- seed_watch_only_workspace(workspace_path, template_dir) do
      :ok
    end
  end

  @spec seed_companion_demo_phone(workspace_path(), template_dir_name()) :: seed_result()
  defp seed_companion_demo_phone(workspace_path, template_dir) do
    source = Paths.priv_path("project_templates/#{template_dir}/phone/src")
    target = Path.join(workspace_path, "phone/src")

    copy_file(Path.join(source, "CompanionApp.elm"), Path.join(target, "CompanionApp.elm"))
  end

  @spec seed_yes_protocol(workspace_path()) :: seed_result()
  defp seed_yes_protocol(workspace_path) do
    source_dir = Paths.priv_path("project_templates/watchface_yes/protocol/src")
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

  @spec seed_tangram_time_protocol(workspace_path()) :: seed_result()
  defp seed_tangram_time_protocol(workspace_path) do
    seed_template_protocol(workspace_path, "watchface_tangram_time")
  end

  @spec seed_weather_animated_protocol(workspace_path()) :: seed_result()
  defp seed_weather_animated_protocol(workspace_path) do
    seed_template_protocol(workspace_path, "watchface_weather_animated")
  end

  @spec seed_template_protocol(workspace_path(), template_dir_name()) :: seed_result()
  defp seed_template_protocol(workspace_path, template_dir) do
    source_dir = Paths.priv_path("project_templates/#{template_dir}/protocol/src")
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

  @spec seed_yes_phone(workspace_path()) :: seed_result()
  defp seed_yes_phone(workspace_path) do
    source = Paths.priv_path("project_templates/watchface_yes/phone/src")
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

  @spec seed_tangram_time_phone(workspace_path()) :: seed_result()
  defp seed_tangram_time_phone(workspace_path) do
    source = Paths.priv_path("project_templates/watchface_tangram_time/phone/src")
    target = Path.join(workspace_path, "phone/src")

    copy_file(Path.join(source, "CompanionApp.elm"), Path.join(target, "CompanionApp.elm"))
  end

  @spec seed_weather_animated_phone(workspace_path()) :: seed_result()
  defp seed_weather_animated_phone(workspace_path) do
    source = Paths.priv_path("project_templates/watchface_weather_animated/phone/src")
    target = Path.join(workspace_path, "phone/src")

    copy_file(Path.join(source, "CompanionApp.elm"), Path.join(target, "CompanionApp.elm"))
  end

  @spec seed_watchface_tutorial_phone(workspace_path()) :: seed_result()
  defp seed_watchface_tutorial_phone(workspace_path) do
    source = Paths.priv_path("project_templates/watchface_tutorial_complete/phone/src")
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

  @spec seed_watch_only_workspace(workspace_path(), template_dir_name()) :: seed_result()
  defp seed_watch_only_workspace(workspace_path, watchface_template_dir) do
    watch_root = Path.join(workspace_path, "watch")

    elm_json =
      watch_elm_json_template(watch_source_directories(watchface_template_dir))
      |> put_in(["dependencies", "direct"], watch_direct_dependencies(watchface_template_dir))

    with :ok <- File.mkdir_p(watch_root),
         :ok <-
           File.write(Path.join(watch_root, "elm.json"), Jason.encode!(elm_json, pretty: true)),
         :ok <-
           copy_file(
             Paths.priv_path("project_templates/starter_watch/index.html"),
             Path.join(watch_root, "index.html")
           ),
         :ok <-
           replace_dir(
             Paths.priv_path("project_templates/#{watchface_template_dir}/src"),
             Path.join(watch_root, "src")
           ),
         :ok <- maybe_copy_template_resources(workspace_path, watchface_template_dir) do
      :ok
    end
  end

  @spec maybe_copy_template_resources(workspace_path(), template_dir_name()) :: seed_result()
  defp maybe_copy_template_resources(workspace_path, template_dir) do
    source = Paths.priv_path("project_templates/#{template_dir}/resources")
    target = Path.join(workspace_path, "watch/resources")

    if File.dir?(source) do
      Ide.Projects.WorkspaceMerge.merge_tree(source, target)
    else
      :ok
    end
  end

  @doc """
  Replaces bundled watch resources in an existing workspace from a template key
  and regenerates `Pebble.Ui.Resources`.
  """
  @spec sync_bundled_resources(workspace_path(), String.t()) :: seed_result()
  def sync_bundled_resources(workspace_path, template_key)
      when is_binary(workspace_path) and is_binary(template_key) do
    case Map.fetch(@template_dirs, template_key) do
      {:ok, template_dir} ->
        with :ok <- maybe_copy_template_resources(workspace_path, template_dir),
             :ok <- ResourceStore.ensure_generated_workspace(workspace_path) do
          :ok
        end

      :error ->
        {:error, {:unknown_template, template_key}}
    end
  end

  @spec watch_direct_dependencies(String.t()) :: TemplateTypes.dependency_map()
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

  @spec watch_source_directories(template_dir_name()) :: [String.t()]
  defp watch_source_directories(template_dir)
       when template_dir in [
              "watchface_tutorial_complete",
              "watchface_yes",
              "watchface_tangram_time",
              "watchface_weather_animated",
              "companion_demo_phone_status",
              "companion_demo_protocol_matrix",
              "companion_demo_weather_env",
              "companion_demo_calendar",
              "companion_demo_geolocation",
              "companion_demo_storage",
              "companion_demo_settings",
              "companion_demo_websocket",
              "companion_demo_timeline"
            ] do
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

  @spec seed_watch_fixture(workspace_path()) :: seed_result()
  defp seed_watch_fixture(workspace_path) do
    template_root = Paths.priv_path("project_templates/starter_watch")
    watch_root = Path.join(workspace_path, "watch")

    elm_json = watch_elm_json_template(watch_with_protocol_source_directories())

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

  @spec seed_protocol_shared(workspace_path()) :: seed_result()
  defp seed_protocol_shared(workspace_path) do
    ensure_protocol_shared(workspace_path)
  end

  @spec seed_phone_companion(workspace_path()) :: seed_result()
  defp seed_phone_companion(workspace_path) do
    source_dir = Paths.priv_path("pebble_app_template/src/elm")
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
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{
          "elm/bytes" => "1.0.8",
          "elm/file" => "1.0.5"
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

  @spec ensure_phone_companion(String.t()) :: :ok | {:error, template_error()}
  defp ensure_phone_companion(workspace_path) do
    phone_root = Path.join(workspace_path, "phone")

    if File.exists?(Path.join(phone_root, "elm.json")) do
      ensure_phone_companion_entrypoint(workspace_path)
    else
      seed_phone_companion(workspace_path)
    end
  end

  @spec ensure_phone_companion_entrypoint(String.t()) :: :ok | {:error, template_error()}
  defp ensure_phone_companion_entrypoint(workspace_path) do
    source_dir = Paths.priv_path("pebble_app_template/src/elm")
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
      InternalPackages.pebble_companion_core_elm_src_abs(),
      InternalPackages.pebble_companion_preferences_elm_src_abs()
    ]
  end

  @spec phone_source_directory_additions(String.t()) :: [String.t()]
  defp phone_source_directory_additions(_workspace_path) do
    [
      "../protocol/src",
      InternalPackages.pebble_companion_core_elm_src_abs(),
      InternalPackages.pebble_companion_preferences_elm_src_abs()
    ]
  end

  @spec reject_phone_obsolete_source_dirs([String.t()]) :: [String.t()]
  defp reject_phone_obsolete_source_dirs(source_dirs) when is_list(source_dirs) do
    obsolete = MapSet.new(phone_obsolete_source_dirs())

    Enum.reject(source_dirs, fn dir ->
      is_binary(dir) and
        (MapSet.member?(obsolete, Path.expand(dir)) or legacy_build_bundled_companion_dir?(dir))
    end)
  end

  @spec legacy_build_bundled_companion_dir?(String.t()) :: boolean()
  defp legacy_build_bundled_companion_dir?(dir) when is_binary(dir) do
    expanded = Path.expand(dir)

    String.contains?(expanded, "/_build/") and
      String.contains?(expanded, "/priv/bundled_elm/pebble-companion-")
  end

  @spec phone_obsolete_source_dirs() :: [String.t()]
  defp phone_obsolete_source_dirs do
    repo = Ide.Paths.repo_root()

    [
      InternalPackages.phone_pebble_stubs_elm_src_abs(),
      InternalPackages.elm_random_elm_src_abs(),
      InternalPackages.pebble_elm_src_abs(),
      Ide.Paths.bundled_elm_path("shared-elm-companion", "shared/elm-companion"),
      Path.join(repo, "packages/elm-pebble-companion-core/src"),
      Path.join(repo, "packages/elm-pebble-companion-preferences/src")
    ]
    |> Enum.map(&Path.expand/1)
  end

  @spec remove_phone_obsolete_dependencies(TemplateTypes.elm_json()) :: TemplateTypes.elm_json()
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

  @spec ensure_watch_protocol_source_dir(String.t()) :: :ok | {:error, template_error()}
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

  @spec insert_after_src([String.t()], String.t()) :: [String.t()]
  defp insert_after_src(source_dirs, new_dir) do
    case Enum.split_while(source_dirs, &(&1 != "src")) do
      {prefix, ["src" | rest]} -> prefix ++ ["src", new_dir] ++ rest
      {_prefix, []} -> [new_dir | source_dirs]
    end
  end

  @spec remove_generated_phone_protocol_internal(String.t()) :: :ok | {:error, template_error()}
  defp remove_generated_phone_protocol_internal(target_dir) when is_binary(target_dir) do
    case File.rm(Path.join(target_dir, "Companion/Internal.elm")) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec remove_obsolete_phone_runtime_sources(String.t()) :: :ok | {:error, template_error()}
  defp remove_obsolete_phone_runtime_sources(target_dir) when is_binary(target_dir) do
    case File.rm_rf(Path.join(target_dir, "Pebble/Companion")) do
      {:ok, _removed} ->
        _ = File.rmdir(Path.join(target_dir, "Pebble"))
        :ok

      {:error, reason, _path} ->
        {:error, reason}
    end
  end

  @spec replace_dir(String.t(), String.t()) :: seed_result()
  defp replace_dir(source, target) do
    if File.exists?(source) do
      _ = File.rm_rf(target)
      File.mkdir_p(Path.dirname(target))

      case File.cp_r(source, target) do
        {:ok, _} -> :ok
        {:error, reason, _path} -> {:error, reason}
      end
    else
      {:error, {:missing_template_asset, source}}
    end
  end

  @spec copy_file(String.t(), String.t()) :: seed_result()
  defp copy_file(source, target) do
    if File.exists?(source) do
      with :ok <- File.mkdir_p(Path.dirname(target)),
           :ok <- File.cp(source, target) do
        :ok
      end
    else
      {:error, {:missing_template_asset, source}}
    end
  end

  @spec copy_file_if_missing(String.t(), String.t()) :: :ok | {:error, template_error()}
  defp copy_file_if_missing(source, target) do
    if File.exists?(target) do
      :ok
    else
      copy_file(source, target)
    end
  end

  @spec write_json_if_missing(String.t(), TemplateTypes.elm_json()) ::
          :ok | {:error, template_error()}
  defp write_json_if_missing(path, payload) do
    if File.exists?(path) do
      :ok
    else
      with :ok <- File.mkdir_p(Path.dirname(path)) do
        File.write(path, Jason.encode!(payload, pretty: true))
      end
    end
  end

  @spec template_dir(String.t()) :: String.t() | nil
  defp template_dir(template), do: Map.get(@template_dirs, template)

  @spec category_for_key(String.t()) :: String.t()
  defp category_for_key("starter"), do: "starter"
  defp category_for_key("app-minimal"), do: "starter"
  defp category_for_key("watchface-" <> _), do: "watchface"
  defp category_for_key("companion-demo-" <> _), do: "companion"
  defp category_for_key("watch-demo-" <> _), do: "watch_demo"
  defp category_for_key("game-" <> _), do: "game"
  defp category_for_key(_), do: "starter"

  @spec picker_entry({String.t(), String.t()}) :: TemplateTypes.picker_entry()
  defp picker_entry({label, key}) do
    parsed = parse_picker_label(label)

    %{
      key: key,
      title: parsed.title,
      description: parsed.description,
      target_type: target_type_for_template(key),
      has_companion: companion_for_template(key),
      screenshot_url: preview_image_url(key)
    }
  end

  @spec parse_picker_label(String.t()) :: %{title: String.t(), description: String.t() | nil}
  defp parse_picker_label(label) when is_binary(label) do
    rest =
      case String.split(label, ": ", parts: 2) do
        [_category, body] -> body
        [body] -> body
      end

    case Regex.run(~r/^(.*?)(?: \((.+)\))?$/, rest) do
      [_, title, description] when is_binary(description) and description != "" ->
        %{title: String.trim(title), description: String.trim(description)}

      [_, title] ->
        %{title: String.trim(title), description: nil}

      _ ->
        %{title: String.trim(rest), description: nil}
    end
  end

  @spec picker_target_matches?(String.t(), String.t()) :: boolean()
  defp picker_target_matches?(_target_type, "all"), do: true
  defp picker_target_matches?(target_type, filter), do: target_type == filter

  @spec picker_companion_matches?(boolean(), String.t()) :: boolean()
  defp picker_companion_matches?(_has_companion, "all"), do: true
  defp picker_companion_matches?(true, "with"), do: true
  defp picker_companion_matches?(false, "without"), do: true
  defp picker_companion_matches?(_, _), do: false

  @spec load_template_metadata(String.t()) :: TemplateTypes.template_metadata()
  defp load_template_metadata(template) do
    case template_dir(template) do
      nil ->
        %{}

      dir ->
        path = Paths.priv_path("project_templates/#{dir}/template.json")

        if File.exists?(path) do
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, %{} = metadata} -> metadata
                _ -> %{}
              end

            _ ->
              %{}
          end
        else
          %{}
        end
    end
  end

  @spec default_target_platforms() :: [String.t()]
  defp default_target_platforms do
    PebbleToolchain.supported_emulator_targets()
  end

  @spec normalize_target_platforms(wire_target_platforms()) :: [String.t()]
  defp normalize_target_platforms(platforms) when is_list(platforms) do
    allowed = MapSet.new(default_target_platforms())

    platforms
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> case do
      [] -> default_target_platforms()
      normalized -> normalized
    end
  end

  defp normalize_target_platforms(_), do: default_target_platforms()
end
