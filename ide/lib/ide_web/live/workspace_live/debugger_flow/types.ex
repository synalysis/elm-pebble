defmodule IdeWeb.WorkspaceLive.DebuggerFlow.Types do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.Types, as: WebTypes

  @type wire_input :: String.t() | integer() | boolean() | nil
  @type wire_value :: DebuggerTypes.wire_value()
  @type wire_map :: DebuggerTypes.wire_map()
  @type live_event_params :: WebTypes.wire_params()

  @typedoc """
  Phoenix form source for the debugger trigger injection modal.

  String keys include `target`, `trigger`, `trigger_display`, `message_constructor`,
  `payload_kind`, `payload`, `message`, `result`, `error_message`, `companion_fields`, etc.
  """
  @type trigger_form_source :: DebuggerTypes.companion_injection_form_data()

  @typedoc """
  Companion preference field row in a trigger form (`companion_fields` list entries).
  """
  @type companion_field_entry :: DebuggerTypes.companion_injection_field_entry()

  @type configuration_value :: wire_input() | boolean()
  @type configuration_form_values :: %{String.t() => configuration_value()}

  @type subscription_toggle_attrs :: %{
          optional(:target) => String.t() | nil,
          optional(:trigger) => String.t() | nil,
          optional(:enabled) => wire_input(),
          optional(String.t()) => wire_input()
        }

  @typedoc "Per-subscription auto-fire selection (`target` / `trigger` string keys)."
  @type auto_fire_subscription_row :: %{
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(String.t()) => String.t()
        }
end
