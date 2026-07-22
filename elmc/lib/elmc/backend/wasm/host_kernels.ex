defmodule Elmc.Backend.Wasm.HostKernels do
  @moduledoc false

  # Replace deep recursive Elm kernels with thin host-backed bodies.
  # TriangularMesh.gridFaceIndices is O(u*v) recursion; each WASM frame
  # calls into JS (as_int/new_int), which blows the JS call stack for
  # typical Scene3d sphere grids.

  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @spec maybe_override(map()) :: map()
  def maybe_override(%{module: "TriangularMesh", name: "gridFaceIndices"} = fun) do
    %{
      fun
      | body: grid_face_indices_body(),
        imports:
          MapSet.put(
            fun.imports || MapSet.new(),
            "runtime.triangular_mesh_grid_face_indices"
          ),
        import_arities:
          Map.put(
            fun.import_arities || %{},
            "runtime.triangular_mesh_grid_face_indices",
            6
          )
    }
  end

  def maybe_override(fun), do: fun

  defp grid_face_indices_body do
    """
    (local $out i32)
    local.get $param0
    local.get $param1
    local.get $param2
    local.get $param3
    local.get $param4
    local.get $param5
    call #{WasmTypes.import_ident("runtime.triangular_mesh_grid_face_indices")}
    local.set $out
    i32.const 0
    local.get $out
    """
  end
end
