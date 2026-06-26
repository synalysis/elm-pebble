defmodule Ide.Debugger.Types.CompanionConfiguration do
  @moduledoc """
  Companion phone preferences UI (`configuration` on companion surface model).
  """

  alias Ide.Debugger.Types

  @type field_control :: Types.wire_string_map()

  @type field :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:control) => field_control(),
          optional(String.t()) => Types.wire_input()
        }

  @type section :: %{
          optional(:title) => String.t(),
          optional(:fields) => [field()],
          optional(String.t()) => Types.wire_input()
        }

  @type values :: %{optional(String.t()) => Types.wire_scalar()}

  @type t :: %{
          optional(:title) => String.t(),
          optional(:sections) => [section()],
          optional(:values) => values(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
