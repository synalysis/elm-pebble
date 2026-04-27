defmodule ElmEx.Frontend.GeneratedParserBackend do
  @moduledoc """
  Adapter for the generated parser frontend.
  """

  @behaviour ElmEx.Frontend.ParserBackend

  alias ElmEx.Frontend.GeneratedParser

  @impl true
  @spec parse_file(term()) :: term()
  def parse_file(path) do
    GeneratedParser.parse_file(path)
  end
end
