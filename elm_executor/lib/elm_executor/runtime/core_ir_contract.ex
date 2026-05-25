defmodule ElmExecutor.Runtime.CoreIRContract do
  @moduledoc """
  Validates Core IR artifacts against the shared `ElmEx.CoreIR` shape contract.
  """

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @spec validate(EvalTypes.core_ir() | nil) :: :ok | {:error, {:invalid_core_ir, [map()]}}
  def validate(nil), do: :ok

  def validate(core_ir) when is_map(core_ir) do
    if normalized_core_ir?(core_ir) do
      case CoreIR.validate_shape(core_ir) do
        {:ok, _} ->
          :ok

        {:error, shape_errors} ->
          {:error, {:invalid_core_ir, shape_errors}}
      end
    else
      :ok
    end
  end

  def validate(_), do: :ok

  @spec normalized_core_ir?(map()) :: boolean()
  defp normalized_core_ir?(%CoreIR{}), do: true

  defp normalized_core_ir?(core_ir) when is_map(core_ir) do
    Map.get(core_ir, "version") == "elm_ex.core_ir.v1" or
      Map.get(core_ir, :version) == "elm_ex.core_ir.v1"
  end
end
