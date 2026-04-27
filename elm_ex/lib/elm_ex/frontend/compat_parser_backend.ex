defmodule ElmEx.Frontend.CompatParserBackend do
  @moduledoc """
  Compatibility adapter for callers expecting the historical parser backend.
  """

  @behaviour ElmEx.Frontend.ParserBackend

  alias ElmEx.Frontend.ModuleParser

  @impl true
  @spec parse_file(term()) :: term()
  def parse_file(path), do: ModuleParser.parse_file(path)
end
