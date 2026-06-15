defmodule IdeWeb.WorkspaceLive.DebuggerBridge do
  @moduledoc false

  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.Types.CompileIngestBridge
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @type socket :: Phoenix.LiveView.Socket.t()
  @type compiler_result ::
          Ide.Compiler.check_result()
          | Ide.Compiler.compile_result()
          | Ide.Compiler.manifest_result()
          | map()

  @spec sync_check(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def sync_check(socket, result) do
    case socket.assigns[:project] do
      %{slug: slug} = project when not is_nil(slug) ->
        session_key = Projects.scope_key(project)

        if debugger_session_active?(socket) do
          diagnostics = result_diagnostics(result)
          counts = Diagnostics.summary(diagnostics)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_check(
              session_key,
              result
              |> Map.put(:error_count, counts.error_count)
              |> Map.put(:warning_count, counts.warning_count)
              |> Map.put(:diagnostics, diagnostics)
              |> CompileIngestBridge.from_compiler_check_result()
            )

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
      project when is_map(project) ->
        if debugger_session_active?(socket) do
          workspace = Projects.project_workspace_path(project)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_check(project_session_key(project), %{
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
      project when is_map(project) ->
        if debugger_session_active?(socket) do
          diagnostics = result_diagnostics(result)
          counts = Diagnostics.summary(diagnostics)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_compile(
              project_session_key(project),
              result
              |> Map.put(:source_root, compile_result_source_root(socket, result))
              |> Map.put(:error_count, counts.error_count)
              |> Map.put(:warning_count, counts.warning_count)
              |> Map.put(:diagnostics, diagnostics)
              |> CompileIngestBridge.from_compiler_compile_result()
            )

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec sync_emulator_rc_fail(Phoenix.LiveView.Socket.t(), term(), term()) ::
          Phoenix.LiveView.Socket.t()
  def sync_emulator_rc_fail(socket, code, line) do
    case socket.assigns[:project] do
      project when is_map(project) ->
        if debugger_session_active?(socket) do
          {:ok, _} =
            Ide.Debugger.ingest_emulator_rc_fail(project_session_key(project), %{
              code: code,
              line: line
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
      project when is_map(project) ->
        if debugger_session_active?(socket) do
          workspace = Projects.project_workspace_path(project)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_compile(project_session_key(project), %{
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
      project when is_map(project) ->
        if debugger_session_active?(socket) do
          diagnostics = result_diagnostics(result)
          counts = Diagnostics.summary(diagnostics)
          schema_version = manifest_schema_version_from_result(result)

          {:ok, _} =
            Ide.Debugger.ingest_elmc_manifest(
              project_session_key(project),
              result
              |> Map.put(:strict?, result[:strict?] == true)
              |> Map.put(:cached?, result[:cached?] == true)
              |> Map.put(:error_count, counts.error_count)
              |> Map.put(:warning_count, counts.warning_count)
              |> Map.put(:schema_version, schema_version)
              |> Map.put(:diagnostics, diagnostics)
              |> CompileIngestBridge.from_compiler_manifest_result()
            )

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
      project when is_map(project) ->
        if debugger_session_active?(socket) do
          workspace = Projects.project_workspace_path(project)
          strict? = socket.assigns[:manifest_strict_mode] == true

          {:ok, _} =
            Ide.Debugger.ingest_elmc_manifest(
              project_session_key(project),
              %{
                status: :error,
                manifest_path: workspace,
                revision: "—",
                strict?: strict?,
                cached?: false,
                error_count: 1,
                warning_count: 0,
                schema_version: nil,
                detail: String.slice(message, 0, 240),
                diagnostics: async_task_failure_diagnostics("manifest: #{message}")
              }
              |> CompileIngestBridge.from_compiler_manifest_result()
            )

          DebuggerSupport.refresh(socket)
        else
          socket
        end

      _ ->
        socket
    end
  end

  @spec manifest_schema_version_from_result(map()) :: integer() | String.t() | nil
  defp manifest_schema_version_from_result(result) do
    case Map.get(result, :manifest) do
      %{"schema_version" => v} -> v
      %{schema_version: v} -> v
      _ -> nil
    end
  end

  @spec async_task_failure_diagnostics(String.t()) :: [Ide.Compiler.diagnostic()]
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

  @spec result_diagnostics(compiler_result()) :: [Ide.Compiler.diagnostic()]
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

  @spec infer_source_root_from_compiled_path(socket(), String.t() | nil) :: String.t() | nil
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

  @spec debugger_session_active?(socket()) :: boolean()
  defp debugger_session_active?(socket) do
    match?(%{running: true}, socket.assigns[:debugger_state])
  end

  @spec project_session_key(map()) :: String.t()
  defp project_session_key(project), do: Projects.scope_key(project)
end
