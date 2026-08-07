defmodule Mix.Tasks.Ide.TextParity do
  @moduledoc """
  Compare debugger SVG text ink to emulator PNG reference crops.

      mix ide.text_parity yes
      mix ide.text_parity yes_emery
  """

  use Mix.Task

  alias Ide.Debugger.TextParity

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    Mix.Task.run("app.start")

    fixture_key =
      case args do
        [] -> "yes_emery"
        [key | _] -> key
      end

    case TextParity.compare_fixture(fixture_key) do
      {:ok, report} ->
        Mix.shell().info(TextParity.format_report(report))
        :ok

      {:error, reason} ->
        Mix.raise("text parity failed for #{fixture_key}: #{inspect(reason)}")
    end
  end
end
