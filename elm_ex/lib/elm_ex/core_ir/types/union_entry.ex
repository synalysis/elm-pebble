defmodule ElmEx.CoreIR.Types.UnionEntry do
  @moduledoc """
  Union metadata on normalized Core IR modules (wire maps with string keys).

  Same semantic shape as `ElmEx.IR.Types.UnionEntry`; re-exported for Core IR consumers.
  """

  alias ElmEx.CoreIR.Types

  @type t :: ElmEx.IR.Types.UnionEntry.t()

  @type wire_map_alias :: %{
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | wire_map_alias()
end
