defmodule Ide.Formatter.Semantics.Normalize do
  @moduledoc false
  alias Ide.Formatter.Printer.Pipeline
  alias Ide.Formatter.Types

  @spec apply(String.t(), Types.metadata(), keyword()) :: String.t()
  def apply(source, metadata, opts \\ []) when is_binary(source) and is_map(metadata) do
    Pipeline.apply(source, metadata, opts)
  end
end
