defmodule Mix.Tasks.Ide.GenTemplatePreviews do
  @moduledoc """
  Generate static PNG previews for project templates.

      mix ide.gen_template_previews
      mix ide.gen_template_previews watchface-digital game-2048
  """

  use Mix.Task

  alias Ide.ProjectTemplatePreviews
  alias Ide.ProjectTemplates

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    templates =
      case args do
        [] -> ProjectTemplates.template_keys()
        keys -> keys
      end

    ProjectTemplatePreviews.generate_all!(templates)
    Mix.shell().info("Wrote #{length(templates)} template preview image(s) to #{ProjectTemplatePreviews.previews_dir()}")
  end
end
