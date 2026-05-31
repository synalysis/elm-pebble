defmodule Ide.Debugger.RuntimeExecutor do
  @moduledoc """
  Strict Core IR runtime execution for the debugger.

  All stepping and init go through the configured external executor (typically
  `ElmExecutorAdapter`). There is no parser-introspect or heuristic model mutation
  fallback.
  """

  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.RuntimeExecutor.Types.RuntimeMode
  alias Ide.Debugger.Types

  @type execution_input :: ExecutorTypes.execution_input()
  @type execution_result :: ExecutorTypes.execution_result()
  @type execute_request :: execution_input()

  @callback execute(execution_input()) :: {:ok, execution_result()} | {:error, Types.execution_error()}

  @spec execute(execution_input()) :: {:ok, execution_result()} | {:error, Types.execution_error()}
  def execute(%Request{} = input) do
    input
    |> Request.validate_execution_ready!()
    |> Request.to_map()
    |> execute()
  end

  def execute(input) when is_map(input) do
    case runtime_mode() do
      :legacy ->
        {:error, {:core_ir_execution_failed, :legacy_runtime_mode_disabled}}

      _ ->
        execute_external_strict(input)
    end
  end

  def execute(_), do: {:error, {:core_ir_execution_failed, :invalid_execution_input}}

  @doc false
  @spec execute_introspect_only(execution_input()) :: {:error, Types.execution_error()}
  def execute_introspect_only(_input) do
    {:error, {:core_ir_execution_failed, :parser_only_execution_disabled}}
  end

  @spec execute_external_strict(execution_input()) ::
          {:ok, execution_result()} | {:error, Types.execution_error()}
  defp execute_external_strict(input) when is_map(input) do
    module = external_executor_module()

    cond do
      not is_atom(module) ->
        {:error, {:core_ir_execution_failed, :no_external_executor_module}}

      not module_supports_execute?(module) ->
        {:error, {:core_ir_execution_failed, {:external_executor_not_loaded, module}}}

      true ->
        case module.execute(input) do
          {:ok, payload} when is_map(payload) ->
            case validate_execution_payload(payload) do
              :ok ->
                {:ok, annotate_execution_backend(normalize_execution_result(payload), "external")}

              {:error, reason} ->
                {:error, {:core_ir_execution_failed, reason}}
            end

          {:error, {:core_ir_execution_failed, _} = reason} ->
            {:error, reason}

          {:error, reason} ->
            {:error, {:core_ir_execution_failed, reason}}

          other ->
            {:error, {:core_ir_execution_failed, {:invalid_external_runtime_result, other}}}
        end
    end
  end

  @spec validate_execution_payload(map()) :: :ok | {:error, atom()}
  defp validate_execution_payload(%{model_patch: patch}) when is_map(patch) do
    if is_map(Map.get(patch, "runtime_model")) or is_map(Map.get(patch, :runtime_model)) do
      :ok
    else
      {:error, :missing_runtime_model}
    end
  end

  defp validate_execution_payload(%{"model_patch" => patch}) when is_map(patch) do
    if is_map(Map.get(patch, "runtime_model")) do
      :ok
    else
      {:error, :missing_runtime_model}
    end
  end

  defp validate_execution_payload(_payload), do: {:error, :missing_model_patch}

  @spec module_supports_execute?(module()) :: boolean()
  defp module_supports_execute?(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} -> function_exported?(module, :execute, 1)
      _ -> false
    end
  end

  @spec normalize_execution_result(ExecutorTypes.executor_wire_result()) :: execution_result()
  defp normalize_execution_result(result) when is_map(result) do
    ResultNormalizer.normalize(result)
  end

  @spec annotate_execution_backend(execution_result(), String.t()) :: execution_result()
  defp annotate_execution_backend(payload, backend) when is_map(payload) and is_binary(backend) do
    ResultNormalizer.annotate_backend(payload, backend, nil)
  end

  @spec external_executor_module() :: module() | nil
  defp external_executor_module do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:external_executor_module, Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter)
  end

  @spec runtime_mode() :: RuntimeMode.t()
  defp runtime_mode do
    mode =
      Application.get_env(:ide, __MODULE__, [])
      |> Keyword.get(:runtime_mode, :runtime_first)

    case mode do
      :legacy -> :legacy
      "legacy" -> :legacy
      :hybrid -> :hybrid
      "hybrid" -> :hybrid
      :runtime_first -> :runtime_first
      "runtime_first" -> :runtime_first
      "runtime-first" -> :runtime_first
      _ -> :runtime_first
    end
  end
end
