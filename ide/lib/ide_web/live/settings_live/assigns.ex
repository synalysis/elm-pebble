defmodule IdeWeb.SettingsLive.Assigns do
  @moduledoc false

  alias Ide.Emulator.Types, as: EmulatorTypes
  alias Ide.GitHub.AuthFlow
  alias Ide.GitHub.Types, as: GitHubTypes
  alias Ide.Settings

  @type flow_status :: :idle | :running | :ok | :error | atom()
  @type emulator_installation_status :: EmulatorTypes.installation_status()
  @type github_status :: AuthFlow.status()
  @type settings :: Settings.values()
  @type info_message :: :clear_info_flash | {:github_poll, String.t()}
  @type github_flow_state :: GitHubTypes.device_flow_payload()
  @type phoenix_form :: Phoenix.HTML.Form.t()

  @type t :: %{
          optional(:page_title) => String.t(),
          optional(:return_to) => String.t(),
          optional(:github_status) => github_status(),
          optional(:github_oauth_ready) => boolean(),
          optional(:github_flow) => github_flow_state() | nil,
          optional(:emulator_targets) => [{String.t(), String.t()}],
          optional(:selected_emulator_target) => String.t(),
          optional(:emulator_installation_status) => emulator_installation_status() | nil,
          optional(:emulator_dependency_install_status) => flow_status(),
          optional(:emulator_dependency_install_output) => String.t() | nil,
          optional(:settings) => settings(),
          optional(:form) => phoenix_form(),
          optional(atom()) => term()
        }
end
