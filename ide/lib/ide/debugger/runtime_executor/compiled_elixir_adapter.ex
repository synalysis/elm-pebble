defmodule Ide.Debugger.RuntimeExecutor.CompiledElixirAdapter do
  @moduledoc """
  Adapter for `elmx` compiled Elixir runtime execution.

  Requires `elmx_manifest` and a registered module for `elmx_revision` on the request.
  Does not read generated `.ex` files from disk on the hot path.
  """

  @behaviour Ide.Debugger.RuntimeExecutor

  alias Elmx.Runtime.Executor
  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.Types

  @type execution_input :: Ide.Debugger.RuntimeExecutor.execution_input()
  @type execution_result :: Ide.Debugger.RuntimeExecutor.execution_result()

  @impl true
  @spec execute(execution_input()) ::
          {:ok, execution_result()} | {:error, Types.execution_error()}
  def execute(input) when is_map(input) do
    with :ok <- require_elmx_manifest(input),
         {:ok, module} <- resolve_compiled_module(input),
         {:ok, payload} <-
           Executor.execute_generated(
             module,
             Map.put(input, :debugger_contract, "elmx.runtime_executor.v1")
           ),
         :ok <- validate_runtime_model(payload) do
      {:ok, ResultNormalizer.normalize(payload)}
    else
      {:error, {:core_ir_execution_failed, _} = err} -> {:error, err}
      {:error, {:elmx_execution_failed, _} = err} -> {:error, {:core_ir_execution_failed, err}}
      {:error, reason} -> {:error, {:core_ir_execution_failed, reason}}
    end
  end

  def execute(_), do: {:error, {:core_ir_execution_failed, :invalid_execution_input}}

  @spec require_elmx_manifest(map()) :: :ok | {:error, Types.execution_error()}
  defp require_elmx_manifest(input) do
    manifest = Map.get(input, :elmx_manifest) || Map.get(input, "elmx_manifest")

    if is_map(manifest) and Map.get(manifest, "contract") == "elmx.runtime_executor.v1" do
      :ok
    else
      {:error, missing_elmx_manifest_error(input)}
    end
  end

  @spec missing_elmx_manifest_error(map()) :: Types.execution_error()
  defp missing_elmx_manifest_error(input) do
    detail =
      Map.get(input, :elmx_compile_error_message) ||
        Map.get(input, "elmx_compile_error_message")

    if is_binary(detail) and detail != "" do
      {:core_ir_execution_failed, {:missing_elmx_manifest, detail}}
    else
      {:core_ir_execution_failed, :missing_elmx_manifest}
    end
  end

  @spec resolve_compiled_module(map()) :: {:ok, module()} | {:error, Types.execution_error()}
  defp resolve_compiled_module(input) do
    revision = Map.get(input, :elmx_revision) || Map.get(input, "elmx_revision")

    cond do
      is_binary(revision) and revision != "" ->
        case Elmx.module_for_revision(revision) do
          mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
          _ -> {:error, {:core_ir_execution_failed, {:elmx_module_not_registered, revision}}}
        end

      true ->
        {:error, {:core_ir_execution_failed, :missing_elmx_revision}}
    end
  end

  @spec validate_runtime_model(map()) :: :ok | {:error, Types.execution_error()}
  defp validate_runtime_model(payload) when is_map(payload) do
    patch = Map.get(payload, :model_patch) || Map.get(payload, "model_patch") || %{}

    if is_map(Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model)) do
      :ok
    else
      {:error, {:core_ir_execution_failed, :missing_runtime_model}}
    end
  end
end
