defmodule Elmc.Backend.CCodegen.ProdMode do
  @moduledoc false

  @spec enabled?() :: boolean()
  def enabled? do
    Process.get(:elmc_codegen_opts, %{})
    |> Map.get(:prod, false)
    |> Kernel.==(true)
  end
end
