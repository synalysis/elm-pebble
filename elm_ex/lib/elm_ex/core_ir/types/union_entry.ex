defmodule ElmEx.CoreIR.Types.UnionEntry do
  @moduledoc """
  Union metadata on normalized Core IR modules (wire maps with string keys).

  Same semantic shape as `ElmEx.IR.Types.UnionEntry`; re-exported for Core IR consumers.
  """

  @type t :: ElmEx.IR.Types.UnionEntry.t()

  @type wire_map :: t() | map()
end
