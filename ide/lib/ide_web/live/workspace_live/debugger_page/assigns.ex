defmodule IdeWeb.WorkspaceLive.DebuggerPage.Assigns do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes
  alias IdeWeb.WorkspaceLive.ResourcesFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type bootstrap_status :: SocketAssigns.bootstrap_status()
  @type timeline_mode :: String.t()
  @type trigger_button :: SupportTypes.trigger_button_row()
  @type disabled_subscription :: DebuggerTypes.disabled_subscription()
  @type speaker_sample_row :: ResourcesFlow.speaker_sample_row()
  @type t :: SocketAssigns.t()

  @type view_preview_assigns :: %{
          required(:runtime) => SupportTypes.execution_model(),
          optional(:project) => Project.t() | nil,
          optional(:title) => String.t(),
          optional(:fill) => boolean(),
          optional(:show_watch_buttons) => boolean(),
          optional(:watch_trigger_buttons) => [trigger_button()],
          optional(:disabled_subscriptions) => [disabled_subscription()],
          optional(:hover_scope) => String.t() | nil,
          optional(:hovered_rendered_scope) => String.t() | nil,
          optional(:hovered_rendered_path) => String.t() | nil
        }
end
