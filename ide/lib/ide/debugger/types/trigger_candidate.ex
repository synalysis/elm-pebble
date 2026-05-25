defmodule Ide.Debugger.Types.TriggerCandidate do
  @moduledoc """
  Auto-fire / inject-trigger candidate row from `Debugger.trigger_candidates/2`.
  """

  @type source :: String.t()

  @type t :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:trigger) => String.t(),
          optional(:trigger_display) => String.t(),
          optional(:target) => String.t(),
          optional(:message) => String.t(),
          optional(:source) => source(),
          optional(:model_active) => boolean(),
          optional(:interval_ms) => pos_integer(),
          optional(:declared_interval_ms) => pos_integer(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()
end
