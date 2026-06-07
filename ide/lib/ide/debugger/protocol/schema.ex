defmodule Ide.Debugger.Protocol.Schema do
  @moduledoc """
  Companion AppMessage schema shape from `Ide.CompanionProtocolGenerator.schema_from_source/1`.

  Generator output uses atom keys. Runtime debugger code may also carry string-key maps;
  use `wire_schema/0` where extra keys are allowed.
  """

  @type wire_type ::
          :int
          | :bool
          | :string
          | {:enum, String.t()}
          | {:union, String.t()}
          | {:list, wire_type()}
          | {:record, String.t(), [map()]}
          | {:dict, wire_type()}

  @type constructor :: %{
          required(:name) => String.t(),
          required(:args) => [String.t()]
        }

  @type field :: %{
          required(:name) => String.t(),
          required(:key) => String.t(),
          required(:type) => String.t(),
          required(:wire_type) => wire_type()
        }

  @type message :: %{
          required(:name) => String.t(),
          required(:tag) => pos_integer(),
          required(:fields) => [field()]
        }

  @type t :: %{
          required(:enums) => %{optional(String.t()) => [String.t()]},
          required(:payload_unions) => %{optional(String.t()) => [constructor()]},
          required(:type_aliases) => %{optional(String.t()) => [map()]},
          required(:watch_to_phone) => [message()],
          required(:phone_to_watch) => [message()],
          required(:wire_slots) => [map()],
          required(:key_ids) => %{optional(String.t()) => pos_integer()}
        }

  alias Ide.Debugger.Types

  @type wire_schema :: t() | Types.wire_map()
end
