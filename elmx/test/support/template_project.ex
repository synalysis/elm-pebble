defmodule Elmx.TestSupport.TemplateProject do
  @moduledoc false

  alias Elmx.TestSupport.Types, as: SupportTypes

  @repo_root Path.expand("../../..", __DIR__)

  @representative_watch_templates ~w(
    watchface-yes
    watchface-analog
    watch_demo_drawing_showcase
    game-jump-n-run
    watchface-poke-battle
    starter
  )

  @representative_phone_templates ~w(
    watchface-yes
    watchface-tangram-time
    watchface-weather-animated
    watchface-tutorial-complete
    companion-demo-phone-status
    companion-demo-storage
    companion-demo-weather-env
    companion-demo-calendar
    companion-demo-settings
    companion-demo-geolocation
    companion-demo-websocket
    companion-demo-timeline
  )

  @template_dirs %{
    "starter" => "starter_watch",
    "app-minimal" => "app_minimal",
    "watchface-yes" => "watchface_yes",
    "watchface-analog" => "watchface_analog",
    "watchface-digital" => "watchface_digital",
    "watchface-minimal" => "watchface_minimal",
    "watchface-tangram-time" => "watchface_tangram_time",
    "watchface-weather-animated" => "watchface_weather_animated",
    "watchface-tutorial-complete" => "watchface_tutorial_complete",
    "watchface-poke-battle" => "watchface_poke_battle",
    "watchface-smoke-screen" => "watchface_smoke_screen",
    "watchface-color-shapes" => "watchface_color_shapes",
    "watch-demo-time" => "watch_demo_time",
    "watch-demo-touch" => "watch_demo_touch",
    "watch-demo-accel" => "watch_demo_accel",
    "watch-demo-vibes" => "watch_demo_vibes",
    "watch-demo-storage" => "watch_demo_storage",
    "watch-demo-health" => "watch_demo_health",
    "watch-demo-frame" => "watch_demo_frame",
    "watch_demo_drawing_showcase" => "watch_demo_drawing_showcase",
    "game-2048" => "game_2048",
    "game-elmtris" => "game_elmtris",
    "game-basic" => "game_basic",
    "game-jump-n-run" => "game_jump_n_run",
    "game-tiny-bird" => "game_tiny_bird",
    "companion-demo-phone-status" => "companion_demo_phone_status",
    "companion-demo-storage" => "companion_demo_storage",
    "companion-demo-weather-env" => "companion_demo_weather_env",
    "companion-demo-calendar" => "companion_demo_calendar",
    "companion-demo-settings" => "companion_demo_settings",
    "companion-demo-geolocation" => "companion_demo_geolocation",
    "companion-demo-websocket" => "companion_demo_websocket",
    "companion-demo-timeline" => "companion_demo_timeline",
    "companion-demo-protocol-matrix" => "companion_demo_protocol_matrix"
  }

  # Underscore dirs that elmx can scaffold for TEA playbook smoke (subset of
  # `Elmx.TeaPlaybook.enabled_names/0` with protocol/watch sources wired).
  @tea_playbook_templates ~w(
    watchface-digital
    watchface-minimal
    watchface-yes
    watchface-weather-animated
    game-2048
    game-elmtris
    companion-demo-protocol-matrix
    companion-demo-phone-status
    companion-demo-storage
    companion-demo-weather-env
    companion-demo-calendar
    companion-demo-settings
    companion-demo-geolocation
    companion-demo-websocket
    companion-demo-timeline
    watch-demo-time
    watch-demo-storage
  )

  @protocol_templates MapSet.new([
                        "watchface-yes",
                        "watchface-tangram-time",
                        "watchface-weather-animated",
                        "watchface-tutorial-complete",
                        "companion-demo-storage",
                        "companion-demo-phone-status",
                        "companion-demo-weather-env",
                        "companion-demo-calendar",
                        "companion-demo-settings",
                        "companion-demo-geolocation",
                        "companion-demo-websocket",
                        "companion-demo-timeline",
                        "companion-demo-protocol-matrix",
                        "starter"
                      ])

  @watch_bundled_sources [
    Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
    Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
    Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
    Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
  ]

  @phone_bundled_sources [
    Path.join(@repo_root, "packages/elm-pebble-companion-core/src"),
    Path.join(@repo_root, "packages/elm-pebble-companion-preferences/src"),
    Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
    Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
    Path.join(@repo_root, "ide/priv/internal_packages/phone-pebble-stubs/src")
  ]

  @spec representative_template_keys() :: [String.t()]
  def representative_template_keys, do: @representative_watch_templates

  @doc """
  Underscore template names used by `Elmx.TeaPlaybook` / elmc host smokes.
  """
  @spec tea_playbook_template_dirs() :: [String.t()]
  def tea_playbook_template_dirs do
    Enum.map(@tea_playbook_templates, &Map.fetch!(@template_dirs, &1))
  end

  @spec tea_playbook_template_keys() :: [String.t()]
  def tea_playbook_template_keys, do: @tea_playbook_templates

  @spec scaffold_playbook_template(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, SupportTypes.scaffold_error()}
  def scaffold_playbook_template(template_dir, opts \\ []) when is_binary(template_dir) do
    key =
      @template_dirs
      |> Enum.find_value(fn {k, dir} -> if dir == template_dir, do: k end)

    if is_binary(key) do
      scaffold_template(key, opts)
    else
      {:error, {:missing_template, template_dir}}
    end
  end

  @spec representative_phone_template_keys() :: [String.t()]
  def representative_phone_template_keys, do: @representative_phone_templates

  @spec repo_root() :: String.t()
  def repo_root, do: @repo_root

  @spec scaffold_template(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, SupportTypes.scaffold_error()}
  def scaffold_template(template_key, opts \\ []) when is_binary(template_key) do
    tmp =
      Keyword.get(opts, :tmpdir) ||
        Path.join(
          System.tmp_dir!(),
          "elmx-template-#{template_key}-#{System.unique_integer([:positive])}"
        )

    with {:ok, template_src} <- template_src(template_key) do
      File.mkdir_p!(tmp)
      copy_dir!(Path.join(template_src, "src"), Path.join(tmp, "src"))

      protocol_src = Path.join(template_src, "protocol/src")

      if MapSet.member?(@protocol_templates, template_key) and File.dir?(protocol_src) do
        copy_dir!(protocol_src, Path.join(tmp, "protocol/src"))
      end

      resources_src = Path.join(template_src, "resources")

      if File.dir?(resources_src) do
        copy_dir!(resources_src, Path.join(tmp, "resources"))
      end

      write_watch_elm_json!(tmp, template_key)
      {:ok, tmp}
    end
  end

  @spec scaffold_phone(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, SupportTypes.scaffold_error()}
  def scaffold_phone(template_key, opts \\ []) when is_binary(template_key) do
    tmp =
      Keyword.get(opts, :tmpdir) ||
        Path.join(
          System.tmp_dir!(),
          "elmx-phone-#{template_key}-#{System.unique_integer([:positive])}"
        )

    with {:ok, template_src} <- template_src(template_key) do
      phone_src = Path.join(template_src, "phone/src")
      protocol_src = Path.join(template_src, "protocol/src")

      unless File.exists?(Path.join(phone_src, "CompanionApp.elm")) do
        {:error, {:missing_phone, template_key}}
      else
        File.mkdir_p!(Path.join(tmp, "src"))
        copy_dir!(phone_src, Path.join(tmp, "src"))

        if File.dir?(protocol_src) do
          copy_dir!(protocol_src, Path.join(tmp, "protocol/src"))
        end

        write_phone_elm_json!(tmp, template_key)
        {:ok, tmp}
      end
    end
  end

  defp template_src(template_key) do
    dir_name = Map.fetch!(@template_dirs, template_key)
    path = Path.join(@repo_root, "ide/priv/project_templates/#{dir_name}")

    if File.dir?(path), do: {:ok, path}, else: {:error, {:missing_template, path}}
  end

  defp copy_dir!(from, to) do
    File.mkdir_p!(to)
    File.cp_r!(from, to)
  end

  defp write_watch_elm_json!(tmpdir, template_key) do
    sources =
      ["src"]
      |> maybe_add_protocol(template_key)
      |> Kernel.++(@watch_bundled_sources)

    deps = %{
      "elm/core" => "1.0.5",
      "elm/json" => "1.1.3",
      "elm/time" => "1.0.0"
    }

    deps =
      if template_key in ["game-jump-n-run", "watchface-poke-battle", "game-2048", "game-elmtris"],
        do: Map.put(deps, "elm/random", "1.0.0"),
        else: deps

    write_elm_json!(Path.join(tmpdir, "elm.json"), sources, deps)
  end

  defp write_phone_elm_json!(phone_dir, template_key) do
    sources = ["src", "protocol/src"] ++ @phone_bundled_sources

    deps = %{
      "elm/core" => "1.0.5",
      "elm/http" => "2.0.0",
      "elm/json" => "1.1.3",
      "elm/time" => "1.0.0"
    }

    {deps, indirect} =
      if template_key == "companion-demo-websocket" do
        {Map.put(deps, "mbr/elm-wss", "2.0.0"), %{"elm/bytes" => "1.0.8"}}
      else
        {deps, %{}}
      end

    write_elm_json!(Path.join(phone_dir, "elm.json"), sources, deps, indirect)
  end

  defp write_elm_json!(path, sources, deps, indirect \\ %{}) do
    elm_json = %{
      "type" => "application",
      "source-directories" => sources,
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => deps,
        "indirect" => indirect
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(path, Jason.encode!(elm_json, pretty: true))
  end

  defp maybe_add_protocol(sources, template_key) do
    if MapSet.member?(@protocol_templates, template_key),
      do: sources ++ ["protocol/src"],
      else: sources
  end
end
