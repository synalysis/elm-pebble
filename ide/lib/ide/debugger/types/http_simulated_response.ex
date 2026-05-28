defmodule Ide.Debugger.Types.HttpSimulatedResponse do
  @moduledoc """
  Simulated HTTP response body returned by `HttpSimulator` for weather decoders.
  """

  @type t :: %{
          required(:status) => pos_integer(),
          required(:body) => String.t()
        }

  @type wire_map :: t() | map()
end
