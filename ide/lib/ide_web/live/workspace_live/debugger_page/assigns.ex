defmodule IdeWeb.WorkspaceLive.DebuggerPage.Assigns do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerPage.CompanionConfiguration
  alias IdeWeb.WorkspaceLive.DebuggerFlow.Types, as: FlowTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes
  alias IdeWeb.WorkspaceLive.ResourcesFlow

  @type bootstrap_status :: :idle | :starting | :running | :failed | atom() | String.t() | nil
  @type timeline_mode :: String.t()
  @type trigger_button :: SupportTypes.trigger_button_row()
  @type disabled_subscription :: DebuggerTypes.disabled_subscription()
  @type speaker_sample_row :: ResourcesFlow.speaker_sample_row()

  @type t :: %{
          optional(:pane) => atom(),
          optional(:project) => Project.t() | nil,
          optional(:debug_mode) => boolean(),
          optional(:companion_app_present) => boolean(),
          optional(:debugger_state) => DebuggerTypes.runtime_state() | nil,
          optional(:debugger_rows) => [SupportTypes.debugger_row()],
          optional(:debugger_selected_row) => SupportTypes.debugger_row() | nil,
          optional(:debugger_cursor_seq) => non_neg_integer() | nil,
          optional(:debugger_timeline_mode) => timeline_mode(),
          optional(:debugger_bootstrap_status) => bootstrap_status(),
          optional(:debugger_bootstrap_progress) => String.t() | nil,
          optional(:debugger_companion_bootstrap_status) => bootstrap_status(),
          optional(:debugger_companion_bootstrap_progress) => String.t() | nil,
          optional(:debugger_watch_runtime) => SupportTypes.execution_model(),
          optional(:debugger_companion_runtime) => SupportTypes.execution_model(),
          optional(:debugger_watch_view_runtime) => SupportTypes.execution_model(),
          optional(:debugger_watch_trigger_buttons) => [trigger_button()],
          optional(:debugger_companion_trigger_buttons) => [trigger_button()],
          optional(:debugger_auto_fire_subscriptions) => [FlowTypes.auto_fire_subscription_row()],
          optional(:debugger_disabled_subscriptions) => [disabled_subscription()],
          optional(:debugger_configuration_draft_values) => CompanionConfiguration.draft_values(),
          optional(:debugger_hovered_rendered_scope) => String.t() | nil,
          optional(:debugger_hovered_rendered_path) => String.t() | nil,
          optional(:debugger_trigger_modal_open) => boolean(),
          optional(:debugger_trigger_form) => Phoenix.HTML.Form.t(),
          optional(:speaker_samples) => [speaker_sample_row()],
          optional(atom()) => term()
        }
end
