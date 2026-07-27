defmodule Ide.Formatter.Printer.Common.Separators do
  @moduledoc false
  alias Ide.Formatter.Semantics.SpacingRules
  alias Ide.Formatter.Types, as: FormatterTypes

  @spec normalize_commas(String.t(), [FormatterTypes.format_token()] | nil) :: String.t()
  def normalize_commas(source, tokens) when is_binary(source) do
    SpacingRules.normalize_comma_spacing(source, tokens)
  end
end
