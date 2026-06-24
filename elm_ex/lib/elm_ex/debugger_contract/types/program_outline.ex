defmodule ElmEx.DebuggerContract.Types.ProgramOutline do
  @moduledoc """
  `Main` program shape summary from `EffectAnalysis.main_program_outline/1`.
  """

  @typedoc """
  Runtime keys: `"target"`, `"kind"`, `"fields"`.
  """
  @type t :: %{
          optional(atom()) => String.t() | [String.t()],
          optional(String.t()) => String.t() | [String.t()]
        }
end
