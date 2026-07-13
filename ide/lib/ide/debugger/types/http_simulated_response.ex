defmodule Ide.Debugger.Types.HttpSimulatedResponse do
  @moduledoc """
  Simulated HTTP response body returned by `HttpSimulator` for weather decoders.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          required(:status) => pos_integer(),
          required(:body) => String.t(),
          optional(:headers) => [{String.t(), String.t()}] | Types.wire_string_map()
        }

  @typedoc "Wire JSON shape (`status`, `body`, optional `headers` / `error`)."
  @type wire_map :: t() | Types.wire_string_map()
end
