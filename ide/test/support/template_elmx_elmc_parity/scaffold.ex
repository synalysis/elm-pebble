defmodule Ide.Test.TemplateElmxElmcParity.Scaffold do
  @moduledoc false

  alias Ide.CompanionProtocolGenerator
  alias Ide.InternalPackages
  alias Ide.Paths
  alias Ide.ProjectTemplates

  @repo_root Path.expand("../../../..", __DIR__)

  @protocol_templates MapSet.new([
                        "watchface-yes",
                        "watchface-tangram-time",
                        "watchface-weather-animated",
                        "watchface-tutorial-complete",
                        "companion-demo-storage",
                        "companion-demo-weather-env",
                        "companion-demo-calendar",
                        "companion-demo-geolocation",
                        "companion-demo-settings",
                        "companion-demo-websocket",
                        "companion-demo-timeline",
                        "companion-demo-phone-status",
                        "companion-demo-protocol-matrix",
                        "starter"
                      ])

  @spec repo_root() :: String.t()
  def repo_root, do: @repo_root

  @spec scaffold!(String.t(), keyword()) :: String.t()
  def scaffold!(template_key, opts \\ []) when is_binary(template_key) do
    tmp =
      Keyword.get(opts, :tmpdir) ||
        Path.join(
          System.tmp_dir!(),
          "ide-template-parity-#{template_key}-#{System.unique_integer([:positive])}"
        )

    with {:ok, template_src} <- ProjectTemplates.template_priv_root(template_key) do
      File.mkdir_p!(tmp)
      copy_dir!(Path.join(template_src, "src"), Path.join(tmp, "src"))

      if MapSet.member?(@protocol_templates, template_key) do
        ensure_protocol!(tmp, template_src)
      end

      resources_src = Path.join(template_src, "resources")

      if File.dir?(resources_src) do
        copy_dir!(resources_src, Path.join(tmp, "resources"))
      end

      write_watch_elm_json!(tmp, template_key)
      tmp
    else
      {:error, reason} ->
        raise ArgumentError, "failed to scaffold #{template_key}: #{inspect(reason)}"
    end
  end

  @spec protocol_dir?(String.t()) :: boolean()
  def protocol_dir?(project_dir) when is_binary(project_dir) do
    File.dir?(Path.join(project_dir, "protocol/src/Companion/Types.elm"))
  end

  @spec phone_to_watch_path(String.t()) :: String.t() | nil
  def phone_to_watch_path(project_dir) when is_binary(project_dir) do
    path = Path.join(project_dir, "protocol/src/Companion/Types.elm")
    if File.exists?(path), do: path, else: nil
  end

  defp ensure_protocol!(tmpdir, template_src) do
    protocol_src = Path.join(template_src, "protocol/src")
    protocol_dir = Path.join(tmpdir, "protocol/src")

    cond do
      File.dir?(protocol_src) ->
        copy_dir!(protocol_src, protocol_dir)
        generate_companion_internal!(tmpdir)

      true ->
        seed_bundled_protocol!(tmpdir)
    end
  end

  defp seed_bundled_protocol!(tmpdir) do
    source_dir = Paths.bundled_elm_path("shared-elm", "shared/elm")
    target_dir = Path.join(tmpdir, "protocol/src")
    companion_dir = Path.join(target_dir, "Companion")

    File.mkdir_p!(companion_dir)
    File.cp!(Path.join(source_dir, "Companion/Types.elm"), Path.join(companion_dir, "Types.elm"))
    File.cp!(Path.join(source_dir, "Companion/Watch.elm"), Path.join(companion_dir, "Watch.elm"))
    generate_companion_internal!(tmpdir)
  end

  defp generate_companion_internal!(project_dir) do
    types_path = Path.join(project_dir, "protocol/src/Companion/Types.elm")
    internal_path = Path.join(project_dir, "protocol/src/Companion/Internal.elm")

    if File.exists?(types_path) do
      CompanionProtocolGenerator.generate_elm_internal(types_path, internal_path)
    end
  end

  defp copy_dir!(from, to) do
    File.mkdir_p!(to)
    File.cp_r!(from, to)
  end

  defp write_watch_elm_json!(tmpdir, template_key) do
    sources = watch_source_directories(template_key)

    deps = %{
      "elm/core" => "1.0.5",
      "elm/json" => "1.1.3",
      "elm/time" => "1.0.0"
    }

    deps =
      if template_key in ["game-jump-n-run", "game-elmtris", "watchface-poke-battle"],
        do: Map.put(deps, "elm/random", "1.0.0"),
        else: deps

    write_elm_json!(Path.join(tmpdir, "elm.json"), sources, deps)
  end

  defp write_elm_json!(path, sources, deps) do
    elm_json = %{
      "type" => "application",
      "source-directories" => sources,
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => deps,
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(path, Jason.encode!(elm_json, pretty: true))
  end

  defp watch_source_directories(template_key) do
    extras =
      if MapSet.member?(@protocol_templates, template_key) do
        [
          InternalPackages.pebble_elm_src_abs(),
          InternalPackages.elm_time_elm_src_abs(),
          InternalPackages.elm_random_elm_src_abs()
        ]
      else
        InternalPackages.watchface_elm_json_extra_source_dirs_abs()
      end

    ["src"]
    |> maybe_add_protocol(template_key)
    |> Kernel.++(extras)
  end

  defp maybe_add_protocol(sources, template_key) do
    if MapSet.member?(@protocol_templates, template_key),
      do: sources ++ ["protocol/src"],
      else: sources
  end
end
