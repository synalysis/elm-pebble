defmodule Ide.ProjectTemplatePreviews do
  @moduledoc """
  Static preview screenshots for project templates in the create-project picker.
  """

  alias Ide.Debugger
  alias Ide.Mcp.DebuggerTemplateCorpus
  alias Ide.ProjectTemplates
  alias Ide.Projects
  alias Ide.ProjectTemplatePreviews.Svg
  alias IdeWeb.WorkspaceLive.DebuggerPage.BitmapHydration
  alias IdeWeb.WorkspaceLive.DebuggerPage.Preview
  alias IdeWeb.WorkspaceLive.DebuggerPreview

  @preview_scale 2

  @previews_relative "static/images/template-previews"

  @doc """
  Directory under `priv/static` where template preview PNGs are stored.
  """
  @spec previews_dir() :: String.t()
  def previews_dir, do: Path.expand("../../priv/#{@previews_relative}", __DIR__)

  @doc """
  Absolute filesystem path for a template preview PNG.
  """
  @spec screenshot_path(String.t()) :: String.t()
  def screenshot_path(template_key) when is_binary(template_key) do
    Path.join(previews_dir(), "#{template_key}.png")
  end

  @doc """
  Public URL for a template preview PNG.
  """
  @spec screenshot_url(String.t()) :: String.t()
  def screenshot_url(template_key), do: ProjectTemplates.preview_image_url(template_key)

  @doc false
  @spec screenshot_available?(String.t()) :: boolean()
  def screenshot_available?(template_key) when is_binary(template_key) do
    File.regular?(screenshot_path(template_key))
  end

  @doc """
  Generates preview PNGs for all templates (or the given subset).
  """
  @spec generate_all!([String.t()]) :: :ok
  def generate_all!(template_keys \\ ProjectTemplates.template_keys()) do
    File.mkdir_p!(previews_dir())

    Enum.each(template_keys, fn template_key ->
      IO.puts("Generating template preview for #{template_key}...")
      generate!(template_key)
    end)

    :ok
  end

  @doc """
  Bootstraps a template in the debugger and writes its preview PNG.
  """
  @spec generate!(String.t()) :: :ok
  def generate!(template_key) when is_binary(template_key) do
    unless template_key in ProjectTemplates.template_keys() do
      raise ArgumentError, "unknown template #{inspect(template_key)}"
    end

    case DebuggerTemplateCorpus.run_template(template_key, cleanup: false) do
      {:ok, %{project: project}} ->
        write_preview_for_project!(template_key, project)

      {:error, reason} ->
        raise "could not bootstrap template #{template_key}: #{inspect(reason)}"
    end
  end

  defp write_preview_for_project!(template_key, project) do
    slug = project.slug

    try do
      case Debugger.snapshot(slug, event_limit: 200) do
        {:ok, state} ->
          runtime = Map.get(state, :watch) || %{}
          tree = Preview.preview_tree(runtime)
          color_mode = Preview.watch_color_mode(runtime)

          svg_ops =
            tree
            |> DebuggerPreview.svg_ops(runtime)
            |> DebuggerPreview.resolve_bitmap_svg_ops(project)
            |> BitmapHydration.hydrate_svg_ops(project, color_mode)
            |> DebuggerPreview.hydrate_animation_svg_ops(project)
            |> DebuggerPreview.hydrate_vector_svg_ops(project)

          {width, height} = DebuggerPreview.screen_dimensions(runtime, tree)
          screen_round? = DebuggerPreview.screen_round?(runtime, tree)

          svg =
            Svg.document(svg_ops, width, height,
              round: screen_round?
            )

          write_png!(svg, screenshot_path(template_key))

        {:error, reason} ->
          raise "could not generate preview for #{template_key}: #{inspect(reason)}"
      end
    after
      _ = Projects.delete_project(project)
    end
  end

  @spec write_png!(String.t(), String.t()) :: :ok
  defp write_png!(svg, output_path) when is_binary(svg) and is_binary(output_path) do
    tmp_svg =
      Path.join(
        System.tmp_dir!(),
        "template-preview-#{System.unique_integer([:positive])}.svg"
      )

    width =
      case Regex.run(~r/viewBox="0 0 (\d+) (\d+)"/, svg) do
        [_, w, _] -> String.to_integer(w) * @preview_scale
        _ -> 288
      end

    :ok = File.write(tmp_svg, svg)

    case System.cmd("rsvg-convert", ["-w", Integer.to_string(width), "-o", output_path, tmp_svg],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        File.rm(tmp_svg)
        :ok

      {output, status} ->
        File.rm(tmp_svg)
        raise "rsvg-convert failed (#{status}): #{output}"
    end
  end
end
