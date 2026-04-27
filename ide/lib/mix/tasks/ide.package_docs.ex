defmodule Mix.Tasks.Ide.PackageDocs do
  @moduledoc """
  Exports Pebble internal package docs for the elm-pages website.
  """

  use Mix.Task

  alias Ide.PackageDocs.Exporter

  @shortdoc "Export Pebble package docs JSON"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    case Exporter.export(opts) do
      {:ok, result} ->
        Mix.shell().info("Wrote package docs to #{result.output_root}")

        Enum.each(result.packages, fn package ->
          Mix.shell().info(
            "  #{package.name} #{package.version}: #{length(package.modules)} modules"
          )
        end)

      {:error, reason} ->
        Mix.raise("Package docs export failed: #{inspect(reason)}")
    end
  end

  @spec parse_args([String.t()]) :: keyword()
  defp parse_args(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [output: :string],
        aliases: [o: :output]
      )

    case opts[:output] do
      nil -> []
      output -> [output_root: Path.expand(output)]
    end
  end
end
