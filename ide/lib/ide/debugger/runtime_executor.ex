defmodule Ide.Debugger.RuntimeExecutor do
  @moduledoc """
  Strict `elmx` runtime execution for the debugger.

  All stepping and init go through the compiled Elixir `elmx` executor. There is no
  Core IR, parser-introspect, or heuristic model mutation fallback.
  """

  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Types

  @type execution_input :: ExecutorTypes.execution_input()
  @type execution_result :: ExecutorTypes.execution_result()
  @type execute_request :: execution_input()

  @callback execute(execution_input()) ::
              {:ok, execution_result()} | {:error, Types.execution_error()}

  @spec execute(execution_input()) ::
          {:ok, execution_result()} | {:error, Types.execution_error()}
  def execute(%Request{} = input) do
    input
    |> Request.validate_execution_ready!()
    |> Request.to_map()
    |> execute()
  end

  def execute(input) when is_map(input) do
    execute_compiled_elmx(input)
  end

  def execute(_), do: {:error, {:core_ir_execution_failed, :invalid_execution_input}}

  @doc """
  Re-evaluates Elm `view/1` for the current model without stepping `init/1` or `update/2`.
  """
  @spec view(execution_input() | Types.wire_map()) ::
          {:ok, Types.elmx_view_preview_payload()} | {:error, Types.execution_error()}
  def view(input) when is_map(input) do
    with :ok <- require_elmx_manifest(input),
         {:ok, module} <- resolve_view_module(input),
         {:ok, payload} <- Elmx.Runtime.Executor.view_generated(module, input) do
      {:ok,
       %{
         view_tree: map_or_nil_field(payload, :view_tree),
         view_output: map_or_nil_field(payload, :view_output) || []
       }}
    else
      {:error, {:core_ir_execution_failed, _} = err} -> {:error, err}
      {:error, {:elmx_execution_failed, _} = err} -> {:error, {:core_ir_execution_failed, err}}
    end
  end

  def view(_), do: {:error, {:core_ir_execution_failed, :invalid_execution_input}}

  @spec execute_compiled_elmx(execution_input()) ::
          {:ok, execution_result()} | {:error, Types.execution_error()}
  @doc false
  @spec execution_backend() :: :compiled_elixir
  def execution_backend do
    :compiled_elixir
  end

  @doc false
  @spec compiled_elixir_backend?() :: boolean()
  def compiled_elixir_backend?, do: true

  defp execute_compiled_elmx(input) when is_map(input) do
    module = Ide.Debugger.RuntimeExecutor.CompiledElixirAdapter

    cond do
      not module_supports_execute?(module) ->
        {:error, {:core_ir_execution_failed, {:external_executor_not_loaded, module}}}

      true ->
        case module.execute(input) do
          {:ok, payload} when is_map(payload) ->
            case validate_execution_payload(payload) do
              :ok ->
                {:ok,
                 annotate_execution_backend(
                   normalize_execution_result(payload),
                   execution_backend_label()
                 )}

              {:error, reason} ->
                {:error, {:core_ir_execution_failed, reason}}
            end

          {:error, {:core_ir_execution_failed, _} = reason} ->
            {:error, reason}
        end
    end
  end

  @spec validate_execution_payload(ExecutorTypes.executor_wire_result()) :: :ok | {:error, atom()}
  defp validate_execution_payload(payload) when is_map(payload) do
    patch = Map.get(payload, :model_patch) || Map.get(payload, "model_patch")

    if is_map(patch) and
         (is_map(Map.get(patch, "runtime_model")) or is_map(Map.get(patch, :runtime_model))) do
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

  @spec execution_backend_label() :: String.t()
  defp execution_backend_label, do: "compiled_elixir"

  @spec require_elmx_manifest(execution_input()) :: :ok | {:error, Types.execution_error()}
  defp require_elmx_manifest(input) do
    manifest = Map.get(input, :elmx_manifest) || Map.get(input, "elmx_manifest")

    if is_map(manifest) and Map.get(manifest, "contract") == "elmx.runtime_executor.v1" do
      :ok
    else
      {:error, missing_elmx_manifest_error(input)}
    end
  end

  @spec missing_elmx_manifest_error(execution_input()) :: Types.execution_error()
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

  @spec resolve_view_module(execution_input()) ::
          {:ok, module()} | {:error, Types.execution_error()}
  defp resolve_view_module(input) do
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

  defp map_or_nil_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
