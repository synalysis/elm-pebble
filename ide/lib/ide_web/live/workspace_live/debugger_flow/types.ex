defmodule IdeWeb.WorkspaceLive.DebuggerFlow.Types do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes

  @type wire_input :: String.t() | integer() | boolean() | nil
  @type wire_value :: DebuggerTypes.wire_value()

  @type wire_map :: %{
          optional(atom()) => wire_value(),
          optional(String.t()) => wire_value()
        }

  @typedoc """
  Phoenix form source for the debugger trigger injection modal.

  String keys include `target`, `trigger`, `trigger_display`, `message_constructor`,
  `payload_kind`, `payload`, `message`, `result`, `error_message`, `companion_fields`, etc.
  """
  @type trigger_form_source :: wire_map()

  @typedoc """
  Companion preference field row in a trigger form (`companion_fields` list entries).
  """
  @type companion_field_entry :: wire_map()

  @type configuration_value :: wire_input() | boolean()
  @type configuration_form_values :: %{String.t() => configuration_value()}

  @type subscription_toggle_attrs :: %{
          optional(:target) => String.t() | nil,
          optional(:trigger) => String.t() | nil,
          optional(:enabled) => wire_input(),
          optional(String.t()) => wire_input()
        }

  @type auto_fire_subscription_row :: %{
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(atom()) => wire_value(),
          optional(String.t()) => wire_value()
        }
end
