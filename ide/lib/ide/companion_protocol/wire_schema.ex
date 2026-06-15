defmodule Ide.CompanionProtocol.WireSchema do
  @moduledoc false

  @type constructor :: %{
          required(:name) => String.t(),
          required(:args) => [String.t()]
        }

  @type alias_field :: %{
          required(:name) => String.t(),
          required(:type) => String.t()
        }

  @type record_field :: %{
          required(:name) => String.t(),
          required(:type) => String.t(),
          required(:wire_type) => wire_type()
        }

  @type storage_type :: :int | :bool | :string

  @type wire_offset :: :raw | :offset

  @type path_kind ::
          :field
          | :record_field
          | :list_count
          | :list_index
          | :dict_count
          | :dict_key
          | :dict_value
          | :union_tag
          | :union_variant
          | :union_arg

  @type path_segment :: %{
          required(:kind) => path_kind(),
          optional(:name) => String.t(),
          optional(:index) => non_neg_integer(),
          optional(:type) => String.t(),
          optional(:tag) => pos_integer()
        }

  @type wire_type ::
          :int
          | :bool
          | :string
          | {:enum, String.t()}
          | {:union, String.t()}
          | {:union, String.t(), [constructor()]}
          | {:list, wire_type()}
          | {:record, String.t(), [record_field()]}
          | {:dict, wire_type()}

  @type wire_slots :: [wire_slot()]

  @type wire_slot :: %{
          required(:key) => String.t(),
          required(:c_name) => String.t(),
          required(:wire_type) => wire_type(),
          required(:storage_type) => storage_type(),
          required(:path) => [path_segment()],
          required(:wire_offset) => wire_offset(),
          optional(:message) => String.t()
        }

  @type enums :: %{optional(String.t()) => [String.t()]}

  @type payload_unions :: %{optional(String.t()) => [constructor()]}

  @type type_aliases :: %{optional(String.t()) => [alias_field()]}

  @type type_resolution_context :: %{
          required(:enums) => enums(),
          required(:payload_unions) => payload_unions(),
          required(:type_aliases) => type_aliases(),
          optional(atom()) => term(),
          optional(String.t()) => term()
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

  @type flatten_context :: type_resolution_context()

  @type message_build_context :: %{
          required(:enums) => enums(),
          required(:payload_unions) => payload_unions(),
          required(:type_aliases) => type_aliases(),
          required(:watch_to_phone) => [message()],
          required(:phone_to_watch) => [message()],
          required(:wire_slots) => wire_slots(),
          optional(:key_ids) => key_ids(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_schema_too_large_detail :: %{
          required(:message) => String.t(),
          required(:max_keys) => pos_integer(),
          required(:key_count) => non_neg_integer()
        }

  @type key_ids :: %{optional(String.t()) => pos_integer()}

  @type runtime_tags :: %{optional(String.t()) => %{optional(String.t()) => non_neg_integer()}}
end
