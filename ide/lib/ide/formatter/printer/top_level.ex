defmodule Ide.Formatter.Printer.TopLevel do
  @moduledoc false
  alias Ide.Formatter.Semantics.DeclarationSpacing

  @spec normalize(String.t()) :: String.t()
  def normalize(source) when is_binary(source), do: DeclarationSpacing.normalize(source)
end
