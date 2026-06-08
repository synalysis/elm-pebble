defmodule Ide.PebbleToolchain.Emulator do
  @moduledoc false

  alias Ide.PebbleToolchain.Core

  defdelegate run_emulator(project_slug, opts), to: Core
  defdelegate stop_emulator(project_slug, opts \\ []), to: Core
  defdelegate emulator_logs_snapshot(emulator_target, cwd, seconds), to: Core
  defdelegate run_screenshot(project_slug, output_path, emulator_target), to: Core
  defdelegate run_emulator_control(project_slug, emulator_target, params), to: Core
  defdelegate supported_emulator_targets(), to: Core
end
