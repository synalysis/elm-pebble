defmodule Ide.Debugger.Types.ReplayRow do
  @moduledoc """
  One replay step in `Debugger.replay_recent/2` (`replay_rows` attribute).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:seq) => non_neg_integer(),
          optional(:target) => Types.surface_target(),
          optional(:message) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
