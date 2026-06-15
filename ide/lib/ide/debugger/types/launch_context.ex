defmodule Ide.Debugger.Types.LaunchContext do
  @moduledoc """
  Watch launch metadata from `Debugger.launch_context_for/2` stored on session state and models.
  """

  alias Ide.Debugger.Types

  @type screen :: %{
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer(),
          optional(:shape) => String.t(),
          optional(:color_mode) => String.t(),
          optional(:isRound) => boolean(),
          optional(:is_round) => boolean(),
          optional(String.t()) => Types.wire_input()
        }

  @type t :: %{
          optional(:launch_reason) => String.t(),
          optional(:watch_profile_id) => String.t(),
          optional(:watch_model) => String.t() | nil,
          optional(:shape) => String.t() | nil,
          optional(:has_microphone) => boolean(),
          optional(:has_compass) => boolean(),
          optional(:supports_health) => boolean(),
          optional(:screen) => screen(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()
end
