defmodule Elmc.Backend.CCodegen.ProdMode do
  @moduledoc false

  @spec enabled?() :: boolean()
  def enabled? do
    Process.get(:elmc_codegen_opts, %{})
    |> Map.get(:prod, false)
    |> Kernel.==(true)
  end

  @doc "True when codegen targets Pebble watch builds (sin_lookup path, no host trig fallback)."
  @spec pebble_watch?() :: boolean()
  def pebble_watch? do
    opts = Process.get(:elmc_codegen_opts, %{})
    opts[:pebble_int32] == true or opts[:prune_runtime] == true
  end
end
