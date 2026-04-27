defmodule ElmEx.Frontend.ParserBackend do
  @moduledoc """
  Parser backend contract used by the frontend bridge.
  """

  @type path() :: String.t()
  @type parse_result() :: {:ok, ElmEx.Frontend.Module.t()} | {:error, map()}

  @callback parse_file(String.t()) :: parse_result()
end
