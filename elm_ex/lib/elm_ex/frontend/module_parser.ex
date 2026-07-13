defmodule ElmEx.Frontend.ModuleParser do
  @moduledoc """
  Compatibility facade for callers expecting the historical ModuleParser API.

  Parsing is now handled by the generated parser frontend.
  """

  alias ElmEx.Frontend.GeneratedParser

  @spec parse_file(String.t()) :: {:ok, ElmEx.Frontend.Module.t()} | {:error, GeneratedParser.parser_error()}
  def parse_file(path), do: GeneratedParser.parse_file(path)
end
