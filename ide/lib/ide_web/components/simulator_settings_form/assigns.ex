defmodule IdeWeb.SimulatorSettingsForm.Assigns do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects.Project
  alias Ide.SimulatorSettings

  @type mode :: :debugger | :emulator | atom()
  @type settings_group :: {atom(), String.t(), [SimulatorSettings.field_spec()]}
  @type settings_values :: SimulatorSettings.display_values()

  @type t :: %{
          required(:id) => String.t(),
          required(:project) => Project.t(),
          optional(:debugger_state) => DebuggerTypes.runtime_state() | nil,
          optional(:mode) => mode(),
          optional(:param_prefix) => String.t(),
          optional(:change_event) => String.t(),
          optional(:class) => String.t() | nil,
          optional(:description) => String.t() | nil,
          optional(:group_columns) => pos_integer(),
          optional(:groups) => [settings_group()],
          optional(:settings) => settings_values(),
          optional(:empty?) => boolean()
        }
end
