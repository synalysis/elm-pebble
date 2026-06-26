defmodule IdeWeb.WatchInteractives.Assigns do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerFlow.Types, as: FlowTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type mode :: :debugger | :emulator | atom()
  @type trigger_row :: SupportTypes.trigger_button_row()
  @type disabled_subscription :: DebuggerTypes.disabled_subscription()
  @type auto_fire_row :: FlowTypes.auto_fire_subscription_row()
  @type accel_control :: %{
          required(:trigger) => String.t(),
          required(:target) => String.t(),
          optional(:message) => String.t() | nil
        }

  @type t :: %{
          required(:id) => String.t(),
          required(:project) => Project.t(),
          optional(:debugger_state) => DebuggerTypes.runtime_state() | nil,
          optional(:mode) => mode(),
          optional(:watch_trigger_buttons) => [trigger_row()],
          optional(:disabled_subscriptions) => [disabled_subscription() | auto_fire_row()],
          optional(:running) => boolean(),
          optional(:class) => String.t() | nil
        }
end
