defmodule Ide.PebbleToolchain.Build do
  @moduledoc false

  alias Ide.PebbleToolchain.Command
  alias Ide.PebbleToolchain.Types

  @type project_slug :: Types.project_slug()
  @type opts :: Types.opts()
  @type command_result :: Types.command_result()
  @type toolchain_error :: Types.toolchain_error()

  @doc """
  Runs `pebble build` for a prepared Pebble app directory.
  """
  @spec build(project_slug(), opts()) :: {:ok, command_result()} | {:error, toolchain_error()}
  def build(_project_slug, opts) do
    case Keyword.get(opts, :app_root) do
      app_root when is_binary(app_root) and app_root != "" ->
        Command.run_pebble(["build"], cwd: app_root, env: Command.build_env(opts))

      _ ->
        Command.run_pebble(["build"], env: Command.build_env(opts))
    end
  end
end
