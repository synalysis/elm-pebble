defmodule Elmx.Backend.MainProgram do
  @moduledoc """
  Reads `Platform.application` / `Platform.watchface` worker fields from lowered IR.
  """

  alias ElmEx.DebuggerContract.EffectAnalysis

  @default_roots ~w(init update view subscriptions main)

  @doc """
  Worker record field names from `main` (e.g. `init`, `update`, `view`, `subscriptions`).
  """
  @spec worker_field_names(ElmEx.IR.t(), String.t()) :: [String.t()]
  def worker_field_names(%ElmEx.IR{} = ir, entry_module) when is_binary(entry_module) do
    case outline(ir, entry_module) do
      %{"fields" => fields} when is_list(fields) -> Enum.filter(fields, &is_binary/1)
      _ -> []
    end
  end

  @doc """
  Roots for dead-code stripping: worker fields declared in `main` plus `main`.
  """
  @spec dead_code_roots(ElmEx.IR.t(), String.t()) :: [String.t()]
  def dead_code_roots(%ElmEx.IR{} = ir, entry_module) when is_binary(entry_module) do
    case worker_field_names(ir, entry_module) do
      [] -> @default_roots
      fields -> fields ++ ["main"]
    end
  end

  @doc false
  @spec outline(ElmEx.IR.t(), String.t()) :: map() | nil
  def outline(%ElmEx.IR{} = ir, entry_module) when is_binary(entry_module) do
    ir
    |> main_expr(entry_module)
    |> EffectAnalysis.main_program_outline()
  end

  @spec main_expr(ElmEx.IR.t(), String.t()) :: map() | nil
  defp main_expr(%ElmEx.IR{modules: modules}, entry_module) do
    modules
    |> Enum.find_value(fn mod ->
      if mod.name != entry_module do
        nil
      else
        Enum.find_value(mod.declarations, fn
          %{kind: :function, name: "main", expr: expr} when is_map(expr) -> expr
          _ -> nil
        end)
      end
    end)
  end
end
