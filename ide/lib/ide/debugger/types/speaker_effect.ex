defmodule Ide.Debugger.Types.SpeakerEffect do
  @moduledoc """
  Latest queued speaker effect snapshot on debugger runtime state.

  Runtime maps use **string keys** at the wire boundary; typespec keys are atoms
  for Dialyzer (see `wire_map/0`).
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.SpeakerCommand

  @type t :: %{
          optional(:seq) => pos_integer(),
          optional(:command) => SpeakerCommand.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
