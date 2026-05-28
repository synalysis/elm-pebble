defmodule Ide.Debugger.Types.CompanionConfiguration do
  @moduledoc """
  Companion phone preferences UI (`configuration` on companion surface model).
  """

  alias Ide.Debugger.Types

  @type field_control :: Types.wire_map()

  @type field :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:control) => field_control(),
          optional(String.t()) => Types.wire_input()
        }

  @type section :: %{
          optional(:title) => String.t(),
          optional(:fields) => [field() | Types.wire_map()],
          optional(String.t()) => Types.wire_input()
        }

  @type values :: %{optional(String.t()) => Types.wire_scalar()}

  @type t :: %{
          optional(:title) => String.t(),
          optional(:sections) => [section() | Types.wire_map()],
          optional(:values) => values(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
