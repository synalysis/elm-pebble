defmodule Ide.PebbleToolchain.Emulator do
  @moduledoc false

  alias Ide.PebbleToolchain.Package

  defdelegate run_emulator(project_slug, opts), to: Package
  defdelegate stop_emulator(project_slug, opts \\ []), to: Package
  defdelegate emulator_logs_snapshot(emulator_target, cwd, seconds), to: Package
  defdelegate run_screenshot(project_slug, output_path, emulator_target), to: Package
  defdelegate run_emulator_control(project_slug, emulator_target, params), to: Package
  defdelegate supported_emulator_targets(), to: Package
end
