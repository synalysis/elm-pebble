defmodule Ide.Debugger.SourceRevision do
  @moduledoc false

  @spec compute(String.t() | nil, String.t()) :: String.t()
  def compute(rel_path, source) when is_binary(source) do
    payload = "#{rel_path || "<none>"}:#{byte_size(source)}:#{source}"

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end
end
