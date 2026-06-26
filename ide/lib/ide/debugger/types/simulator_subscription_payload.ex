defmodule Ide.Debugger.Types.SimulatorSubscriptionPayload do
  @moduledoc """
  Simulator stub payloads attached to subscription step messages in the debugger.

  Runtime maps use **string keys** at the wire boundary; atom keys document fields
  for Dialyzer.
  """

  alias Ide.Debugger.Types

  @type compass_heading :: %{
          optional(:degrees) => number(),
          optional(:isValid) => boolean(),
          optional(String.t()) => Types.wire_input()
        }

  @type screen :: %{
          optional(:width) => non_neg_integer(),
          optional(:height) => non_neg_integer(),
          optional(:shape) => String.t(),
          optional(:colorMode) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @type rect :: %{
          optional(:x) => non_neg_integer(),
          optional(:y) => non_neg_integer(),
          optional(:w) => non_neg_integer(),
          optional(:h) => non_neg_integer(),
          optional(String.t()) => Types.wire_input()
        }
end
