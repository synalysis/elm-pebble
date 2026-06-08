defmodule Ide.Debugger.Protocol.Schema do
  @moduledoc """
  Companion AppMessage schema shape from `Ide.CompanionProtocolGenerator.schema_from_source/1`.

  Generator output uses atom keys. Runtime debugger code may also carry string-key maps;
  use `wire_schema/0` where extra keys are allowed.
  """

  alias Ide.CompanionProtocol.WireSchema
  alias Ide.Debugger.Types

  @type wire_type :: WireSchema.wire_type()
  @type constructor :: WireSchema.constructor()
  @type alias_field :: WireSchema.alias_field()
  @type record_field :: WireSchema.record_field()
  @type wire_slot :: WireSchema.wire_slot()
  @type field :: WireSchema.field()
  @type message :: WireSchema.message()

  @type runtime_message ::
          message()
          | %{optional(String.t() | atom()) => term()}

  @type t :: %{
          required(:enums) => WireSchema.enums(),
          required(:payload_unions) => WireSchema.payload_unions(),
          required(:type_aliases) => WireSchema.type_aliases(),
          required(:watch_to_phone) => [message()],
          required(:phone_to_watch) => [message()],
          required(:wire_slots) => WireSchema.wire_slots(),
          required(:key_ids) => WireSchema.key_ids()
        }

  @type wire_schema :: t() | Types.wire_map()
end
