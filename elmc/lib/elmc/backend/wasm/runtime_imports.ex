defmodule Elmc.Backend.Wasm.RuntimeImports do
  @moduledoc """
  Logical builtin id → WASM import name mapping for future web runtime.

  C backend uses `Plan.RuntimeBuiltins.c_symbol/1`; WASM will use these imports.
  """

  alias Elmc.Backend.Plan.RuntimeBuiltins

  @spec import_name(atom()) :: String.t()
  def import_name(id) when is_atom(id) do
    "runtime." <> Atom.to_string(id)
  end

  @spec all_imports() :: [{atom(), String.t()}]
  def all_imports do
    Enum.map(RuntimeBuiltins.ids(), fn id -> {id, import_name(id)} end)
  end
end
