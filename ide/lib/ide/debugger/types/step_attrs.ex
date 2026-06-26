defmodule Ide.Debugger.Types.StepAttrs do
  @moduledoc """
  Attributes for `Debugger.step/2`, `tick/2`, and related step ingress APIs.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => Types.surface_target() | String.t() | atom() | nil,
          optional(:message) => String.t() | nil,
          optional(:count) => pos_integer() | non_neg_integer() | String.t() | nil,
          optional(:interval_ms) => pos_integer() | String.t() | nil,
          optional(:enabled) => boolean() | String.t() | nil,
          optional(:trigger) => String.t() | nil,
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
