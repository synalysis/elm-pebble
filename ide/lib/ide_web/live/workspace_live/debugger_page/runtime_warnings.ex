defmodule IdeWeb.WorkspaceLive.DebuggerPage.RuntimeWarnings do
  @moduledoc false

  @type runtime :: map() | nil

  @spec text(runtime()) :: String.t() | nil
  def text(runtime) do
    model = raw_runtime_model(runtime)

    warnings =
      [
        elmx_compile_warning(model),
        runtime_execution_warning(model),
        unresolved_runtime_model_warning(model)
      ]
      |> Enum.reject(&is_nil/1)

    case warnings do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  @spec raw_runtime_model(runtime()) :: map()
  defp raw_runtime_model(%{} = runtime) do
    case Map.get(runtime, :model) || Map.get(runtime, "model") do
      %{} = model -> model
      _ -> %{}
    end
  end

  defp raw_runtime_model(_), do: %{}

  @spec elmx_compile_warning(map()) :: String.t() | nil
  defp elmx_compile_warning(model) when is_map(model) do
    case Map.get(model, "elmx_compile_error_message") ||
           Map.get(model, :elmx_compile_error_message) do
      message when is_binary(message) and message != "" ->
        "elmx compile failed: #{message}\n\nRecompile the watch (and phone, if used) from the Build tab, then reload the debugger."

      _ ->
        nil
    end
  end

  @spec runtime_execution_warning(map()) :: String.t() | nil
  defp runtime_execution_warning(model) when is_map(model) do
    case Map.get(model, "runtime_execution_error") || Map.get(model, :runtime_execution_error) do
      message when is_binary(message) and message != "" ->
        "Runtime execution error: #{message}"

      _ ->
        nil
    end
  end

  @spec unresolved_runtime_model_warning(map()) :: String.t() | nil
  defp unresolved_runtime_model_warning(model) when is_map(model) do
    case Ide.Debugger.RuntimeModelQuality.unresolved_field_names(model) do
      [] ->
        nil

      fields ->
        """
        Some watch `runtime_model` fields still contain parser/introspect artifacts (`$var`, `call`, `$opaque`) instead of evaluated Elm values: #{Enum.join(fields, ", ")}.

        Typical causes: elmx artifacts were missing on reload, or `Main.init` did not evaluate via the executor. Recompile, reload the debugger, and check `runtime_execution_error` / `operation_source` on the watch model. Preview needs a fully evaluated model (see `previewUnavailable` when view eval fails).
        """
        |> String.trim()
    end
  end
end
