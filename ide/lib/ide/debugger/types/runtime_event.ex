defmodule Ide.Debugger.Types.RuntimeEvent do
  @moduledoc """
  Internal debugger history event (`RuntimeState.events`).
  """

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types.RuntimeEventPayload

  @type payload :: RuntimeEventPayload.t()

  @type t :: %{
          required(:seq) => non_neg_integer(),
          required(:type) => String.t(),
          required(:payload) => payload(),
          required(:watch) => Surface.surface_map(),
          required(:companion) => Surface.surface_map(),
          required(:phone) => Surface.surface_map()
        }

  @type surfaces :: %{
          required(:watch) => Surface.surface_map(),
          required(:companion) => Surface.surface_map(),
          required(:phone) => Surface.surface_map()
        }

  @spec build(non_neg_integer(), String.t(), payload(), surfaces()) :: t()
  def build(seq, type, payload, %{watch: watch, companion: companion, phone: phone})
      when is_integer(seq) and seq >= 0 and is_binary(type) and is_map(payload) do
    %{
      seq: seq,
      type: type,
      payload: payload,
      watch: watch,
      companion: companion,
      phone: phone
    }
  end
end
