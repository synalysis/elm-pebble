defmodule Ide.Formatter.Printer.Record do
  @moduledoc false
  alias Ide.Formatter.Semantics.RecordRules

  @spec normalize(String.t()) :: String.t()
  def normalize(source) when is_binary(source) do
    RecordRules.normalize_multiline_record_alignment(source)
  end
end
