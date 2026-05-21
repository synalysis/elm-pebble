defmodule ElmEx.Frontend.CompatParserBackend do
  @moduledoc """
  Compatibility adapter for callers expecting the historical parser backend.
  """

  @behaviour ElmEx.Frontend.ParserBackend

  alias ElmEx.Frontend.ModuleParser

  @impl true
  @spec parse_file(String.t()) :: ElmEx.Frontend.ParserBackend.parse_result()
  def parse_file(path), do: ModuleParser.parse_file(path)
end
