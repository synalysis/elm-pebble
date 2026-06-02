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
      {:ok, payload |> maybe_mark_unmapped_message(input) |> ResultNormalizer.normalize()}
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

  @spec maybe_mark_unmapped_message(map(), map()) :: map()
  defp maybe_mark_unmapped_message(payload, input) when is_map(payload) and is_map(input) do
    message = Map.get(input, :message) || Map.get(input, "message")
    introspect = Map.get(input, :introspect) || Map.get(input, "introspect") || %{}

    branches =
      introspect
      |> Map.get("update_case_branches", Map.get(introspect, :update_case_branches, []))
      |> List.wrap()
      |> Kernel.++(
        introspect
        |> Map.get("msg_constructors", Map.get(introspect, :msg_constructors, []))
        |> List.wrap()
      )
      |> Enum.uniq()

    if mapped_update_message?(message, branches) do
      payload
    else
      patch = Map.get(payload, :model_patch, %{})
      runtime = Map.get(patch, "runtime_execution", %{})

      runtime =
        runtime
        |> Map.put("operation_source", "unmapped_message")
        |> Map.put("runtime_model_source", "unmapped_message")

      patch =
        patch
        |> Map.put("runtime_model_source", "unmapped_message")
        |> Map.put("runtime_execution", runtime)

      Map.put(payload, :model_patch, patch)
    end
  end

  defp maybe_mark_unmapped_message(payload, _input), do: payload

  defp mapped_update_message?(message, branches)
       when is_binary(message) and is_list(branches) and branches != [] do
    ctor =
      message
      |> String.trim()
      |> String.split(~r/[\s(]/, parts: 2)
      |> List.first()

    Enum.any?(branches, fn branch ->
      is_binary(branch) and String.downcase(branch) == String.downcase(ctor)
    end)
  end

  defp mapped_update_message?(_message, []), do: true
  defp mapped_update_message?(nil, _branches), do: true
  defp mapped_update_message?(_message, _branches), do: true
end
