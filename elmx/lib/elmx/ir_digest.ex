defmodule Elmx.IRDigest do
  @moduledoc false

  @spec sha256(ElmEx.IR.t()) :: String.t()
  def sha256(%ElmEx.IR{} = ir) do
    ir
    |> Map.from_struct()
    |> Map.delete(:diagnostics)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
