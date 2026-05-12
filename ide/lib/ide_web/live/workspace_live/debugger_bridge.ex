defmodule IdeWeb.WorkspaceLive.DebuggerBridge do
  @moduledoc false

  alias Ide.Compiler.Diagnostics
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @spec sync_check(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def sync_check(socket, result) do
    case socket.assigns[:project] do
      %{slug: slug} when not is_nil(slug) ->
        if debugger_session_active?(socket) do
          diagnostics = result_diagnostics(result)
          counts = Diagnostics.summary(diagnostics)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_check(slug, %{
              status: result.status,
              checked_path: result.checked_path,
              error_count: counts.error_count,
              warning_count: counts.warning_count,
              diagnostics: diagnostics
            })

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec sync_check_failed(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def sync_check_failed(socket, message) do
    case socket.assigns[:project] do
      %{slug: slug} when not is_nil(slug) ->
        if debugger_session_active?(socket) do
          workspace = Projects.project_workspace_path(socket.assigns.project)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_check(slug, %{
              status: :error,
              checked_path: workspace,
              error_count: 1,
              warning_count: 0,
              diagnostics: async_task_failure_diagnostics("check: #{message}")
            })

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec sync_compile(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def sync_compile(socket, result) do
    case socket.assigns[:project] do
      %{slug: slug} when not is_nil(slug) ->
        if debugger_session_active?(socket) do
          diagnostics = result_diagnostics(result)
          counts = Diagnostics.summary(diagnostics)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_compile(slug, %{
              status: result.status,
              compiled_path: result.compiled_path,
              source_root: compile_result_source_root(socket, result),
              revision: result.revision,
              cached: result.cached? == true,
              error_count: counts.error_count,
              warning_count: counts.warning_count,
              diagnostics: diagnostics,
              elm_executor_core_ir_b64:
                Map.get(result, :elm_executor_core_ir_b64) ||
                  Map.get(result, "elm_executor_core_ir_b64"),
              elm_executor_metadata:
                Map.get(result, :elm_executor_metadata) ||
                  Map.get(result, "elm_executor_metadata")
            })

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec sync_compile_failed(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def sync_compile_failed(socket, message) do
    case socket.assigns[:project] do
      %{slug: slug} when not is_nil(slug) ->
        if debugger_session_active?(socket) do
          workspace = Projects.project_workspace_path(socket.assigns.project)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_compile(slug, %{
              status: :error,
              compiled_path: workspace,
              revision: "—",
              cached: false,
              error_count: 1,
              warning_count: 0,
              detail: String.slice(message, 0, 240),
              diagnostics: async_task_failure_diagnostics("compile: #{message}")
            })

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec sync_manifest(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def sync_manifest(socket, result) do
    case socket.assigns[:project] do
      %{slug: slug} when not is_nil(slug) ->
        if debugger_session_active?(socket) do
          diagnostics = result_diagnostics(result)
          counts = Diagnostics.summary(diagnostics)
          schema_version = manifest_schema_version_from_result(result)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_manifest(slug, %{
              status: result.status,
              manifest_path: result.manifest_path,
              revision: result.revision,
              strict: result[:strict?] == true,
              cached: result[:cached?] == true,
              error_count: counts.error_count,
              warning_count: counts.warning_count,
              schema_version: schema_version,
              diagnostics: diagnostics
            })

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec sync_manifest_failed(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def sync_manifest_failed(socket, message) do
    case socket.assigns[:project] do
      %{slug: slug} when not is_nil(slug) ->
        if debugger_session_active?(socket) do
          workspace = Projects.project_workspace_path(socket.assigns.project)
          strict? = socket.assigns[:manifest_strict_mode] == true

          {:ok, _} =
            Ide.Debugger.ingest_elmc_manifest(slug, %{
              status: :error,
              manifest_path: workspace,
              revision: "—",
              strict: strict?,
              cached: false,
              error_count: 1,
              warning_count: 0,
              schema_version: nil,
              detail: String.slice(message, 0, 240),
              diagnostics: async_task_failure_diagnostics("manifest: #{message}")
            })

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec manifest_schema_version_from_result(term()) :: term()
  defp manifest_schema_version_from_result(result) do
    case Map.get(result, :manifest) do
      %{"schema_version" => v} -> v
      %{schema_version: v} -> v
      _ -> nil
    end
  end

  @spec async_task_failure_diagnostics(term()) :: term()
  defp async_task_failure_diagnostics(message) when is_binary(message) do
    [
      %{
        severity: "error",
        source: "ide",
        message: String.slice(message, 0, 500),
        file: nil,
        line: nil,
        column: nil
      }
    ]
  end

  @spec result_diagnostics(term()) :: term()
  defp result_diagnostics(result) when is_map(result) do
    result
    |> Map.get(:diagnostics, Map.get(result, "diagnostics"))
    |> Diagnostics.normalize_list()
  end

  @spec compile_result_source_root(Phoenix.LiveView.Socket.t(), map()) :: String.t() | nil
  defp compile_result_source_root(socket, result) when is_map(result) do
    explicit = Map.get(result, :source_root) || Map.get(result, "source_root")

    if is_binary(explicit) and explicit != "" do
      explicit
    else
      infer_source_root_from_compiled_path(socket, Map.get(result, :compiled_path))
    end
  end

  @spec infer_source_root_from_compiled_path(Phoenix.LiveView.Socket.t(), term()) ::
          String.t() | nil
  defp infer_source_root_from_compiled_path(socket, compiled_path)
       when is_binary(compiled_path) do
    with %{source_roots: source_roots} = project <- socket.assigns[:project],
         workspace when is_binary(workspace) <- Projects.project_workspace_path(project) do
      compiled = Path.expand(compiled_path)

      source_roots
      |> List.wrap()
      |> Enum.find(fn source_root ->
        root_path = Path.expand(to_string(source_root), workspace)
        relative = Path.relative_to(compiled, root_path)
        relative != compiled and not String.starts_with?(relative, "..")
      end)
    else
      _ -> nil
    end
  end

  defp infer_source_root_from_compiled_path(_socket, _compiled_path), do: nil

  @spec debugger_session_active?(term()) :: term()
  defp debugger_session_active?(socket) do
    match?(%{running: true}, socket.assigns[:debugger_state])
  end
end
