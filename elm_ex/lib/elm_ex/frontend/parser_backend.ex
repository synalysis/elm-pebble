defmodule ElmEx.Frontend.ParserBackend do
  @moduledoc """
  Parser backend contract used by the frontend bridge.
  """

  alias ElmEx.Frontend.Bridge.Types, as: BridgeTypes

  @type path() :: String.t()
  @type parse_result() :: {:ok, ElmEx.Frontend.Module.t()} | {:error, BridgeTypes.bridge_error()}

  @callback parse_file(String.t()) :: parse_result()
end
