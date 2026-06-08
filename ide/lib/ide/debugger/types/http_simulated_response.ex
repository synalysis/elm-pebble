defmodule Ide.Debugger.Types.HttpSimulatedResponse do
  @moduledoc """
  Simulated HTTP response body returned by `HttpSimulator` for weather decoders.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          required(:status) => pos_integer(),
          required(:body) => String.t()
        }

  @type wire_map :: t() | Types.wire_map()
end
