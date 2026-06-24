defmodule IdeWeb.WorkspaceLive.EmulatorPage.Assigns do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Emulator.Types, as: EmulatorTypes
  alias Ide.Projects.Project
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.DebuggerFlow.Types, as: FlowTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes
  alias IdeWeb.WorkspaceLive.PublishFlow

  @type flow_status :: :idle | :running | :ok | :error | atom()
  @type installation_status :: EmulatorTypes.installation_status()

  @type phoenix_form :: Phoenix.HTML.Form.t()
  @type screenshot_group :: PublishFlow.screenshot_group()

  @type t :: %{
          optional(:pane) => atom(),
          optional(:project) => Project.t() | nil,
          optional(:debug_mode) => boolean(),
          optional(:emulator_mode) => String.t(),
          optional(:selected_emulator_target) => String.t(),
          optional(:emulator_form) => phoenix_form(),
          optional(:emulator_targets) => [{String.t(), String.t()}],
          optional(:emulator_mode_options) => [{String.t(), String.t()}],
          optional(:emulator_installation_status) => installation_status(),
          optional(:emulator_stop_status) => flow_status(),
          optional(:pebble_build_status) => flow_status(),
          optional(:pebble_install_status) => flow_status(),
          optional(:external_emulator_running) => boolean(),
          optional(:debugger_state) => DebuggerTypes.runtime_state() | nil,
          optional(:debugger_watch_trigger_buttons) => [SupportTypes.trigger_button_row()],
          optional(:debugger_disabled_subscriptions) => [DebuggerTypes.disabled_subscription()],
          optional(:debugger_auto_fire_subscriptions) => [FlowTypes.auto_fire_subscription_row()],
          optional(:screenshots) => [Screenshots.screenshot()],
          optional(:screenshot_groups) => [screenshot_group()],
          optional(atom()) => term()
        }
end
