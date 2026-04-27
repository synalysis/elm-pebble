defmodule Ide.Formatter.Semantics.Normalize do
  @moduledoc false
  alias Ide.Formatter.Printer.Pipeline

  @spec apply(String.t(), map(), keyword()) :: String.t()
  def apply(source, metadata, opts \\ []) when is_binary(source) and is_map(metadata) do
    Pipeline.apply(source, metadata, opts)
  end
end
