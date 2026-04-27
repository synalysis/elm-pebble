defmodule Ide.Formatter.Printer.Common.Separators do
  @moduledoc false
  alias Ide.Formatter.Semantics.SpacingRules

  @spec normalize_commas(String.t(), [map()] | nil) :: String.t()
  def normalize_commas(source, tokens) when is_binary(source) do
    SpacingRules.normalize_comma_spacing(source, tokens)
  end
end
