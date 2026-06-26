defmodule Ide.Debugger.Types.CompanionInjectionForm do
  @moduledoc false

  alias Ide.Debugger.Types

  @typedoc "Companion preference field row in a trigger form (`companion_fields` list entries)."
  @type companion_field_entry :: %{
          optional(String.t()) => Types.wire_scalar() | boolean() | integer()
        }

  @typedoc """
  Debugger trigger injection modal form source (string keys).

  Includes `target`, `trigger`, `message_constructor`, `payload_kind`, `companion_fields`,
  dynamic `companion_field_*` entries, and submit result fields.
  """
  @type t :: %{
          optional(String.t()) => Types.wire_input() | [companion_field_entry()]
        }
end
