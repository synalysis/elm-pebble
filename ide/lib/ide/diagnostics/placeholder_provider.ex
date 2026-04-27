defmodule Ide.Diagnostics.PlaceholderProvider do
  @moduledoc """
  Parser-aware diagnostics seam used until real lexer/parser integration lands.
  """

  @type diagnostic :: %{severity: String.t(), source: String.t(), message: String.t()}

  @doc """
  Returns placeholder diagnostics for the IDE diagnostics panel.
  """
  @spec placeholder_diagnostics() :: [diagnostic()]
  def placeholder_diagnostics do
    [
      %{
        severity: "info",
        source: "parser-seam",
        message: "Parser-backed Elm diagnostics will be connected in a later phase."
      }
    ]
  end
end
