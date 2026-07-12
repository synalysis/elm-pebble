defmodule Elmx.Backend.ReachableModules do
  @moduledoc false

  alias ElmEx.IR
  alias ElmEx.IR.DeadCode
  alias Elmx.Backend.CompileTimeCall
  alias Elmx.Backend.MainProgram

  alias Elmx.Backend.CompileTimeCall

  @spec modules_for_emit(IR.t(), String.t(), keyword()) :: [map()]
  def modules_for_emit(%IR{} = ir, entry_module, opts \\ []) when is_binary(entry_module) do
    roots = MainProgram.dead_code_roots(ir, entry_module)
    reachable = DeadCode.reachable_keys(ir, entry_module, roots: roots)

    ir.modules
    |> Enum.filter(fn mod ->
      emit_module?(mod, opts) and
        Enum.any?(mod.declarations, fn
          %{kind: :function, name: name} ->
            CompileTimeCall.emit_function?(mod.name, name, reachable, opts)

          _ ->
            false
        end)
    end)
    |> Enum.map(fn mod ->
      declarations =
        Enum.filter(mod.declarations, fn
          %{kind: :function, name: name} ->
            CompileTimeCall.emit_function?(mod.name, name, reachable, opts)

          _ ->
            true
        end)

      %{mod | declarations: declarations}
    end)
  end

  @spec emit_module_names(IR.t(), String.t(), keyword()) :: [String.t()]
  def emit_module_names(%IR{} = ir, entry_module, opts \\ []) when is_binary(entry_module) do
    ir
    |> modules_for_emit(entry_module, opts)
    |> Enum.map(& &1.name)
  end

  defp emit_module?(mod, opts) do
    if Keyword.has_key?(opts, :user_module_names) do
      user_names = Keyword.get(opts, :user_module_names, [])
      mod.name in user_names or CompileTimeCall.bundled_emit_module?(mod.name)
    else
      true
    end
  end
end
