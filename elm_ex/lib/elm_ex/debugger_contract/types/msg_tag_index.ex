defmodule ElmEx.DebuggerContract.Types.MsgTagIndex do
  @moduledoc """
  Msg constructor tag lookup built by `EffectNormalize.build_msg_tag_index/1`.

  Maps tag integers (as strings or ints) to constructor names.
  """

  @type t :: %{optional(String.t()) => String.t(), optional(integer()) => String.t()}
end
