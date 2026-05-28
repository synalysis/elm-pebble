defmodule Ide.Debugger.CompanionPhoneCompile do
  @moduledoc """
  Lazy phone `elmc` compile for the debugger: only when the companion surface still
  needs Core IR (e.g. parser view is an unevaluated expression). Never blocks companion
  reload or the LiveView bootstrap banner.
  """

  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.RuntimeBackgroundNotify
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceAccess
  alias Ide.Debugger.Types.CompileIngestBridge
  alias Ide.Projects
  alias Ide.Projects.Project

  @spec skip_blocking_compile?(map()) :: boolean()
  def skip_blocking_compile?(state) when is_map(state) do
    Map.get(state, :debugger_skip_blocking_compile) == true
  end

  def skip_blocking_compile?(_), do: false

  @spec schedule_if_needed(String.t(), map()) :: :scheduled | :skipped
  def schedule_if_needed(scope_key, project) when is_binary(scope_key) do
    state = AgentStore.fetch(scope_key)

    if needs_compile?(state, project) do
      Task.start(fn -> compile_ingest_and_notify(scope_key, project) end)
      :scheduled
    else
      :skipped
    end
  end

  @spec needs_compile?(map(), map()) :: boolean()
  def needs_compile?(state, project) when is_map(state) and is_map(project) do
    cond do
      phone_root(project) == nil ->
        false

      SurfaceCompileArtifacts.surface_has_core_ir?(state, :companion) ->
        false

      not lazy_elmc?() ->
        true

      companion_parser_expression_view?(state) ->
        true

      true ->
        false
    end
  end

  def needs_compile?(_state, _project), do: false

  @spec compile_ingest_and_notify(String.t(), map()) :: :ok | {:error, String.t()}
  defp compile_ingest_and_notify(scope_key, project)
       when is_binary(scope_key) and is_map(project) do
    case phone_root(project) do
      nil ->
        :ok

      {label, root_path} ->
        case Compiler.compile(Projects.compiler_cache_key(project, label),
               workspace_root: root_path,
               source_roots: project.source_roots
             ) do
          {:ok, result} ->
            case ingest_result(scope_key, result) do
              :ok ->
                RuntimeBackgroundNotify.broadcast(scope_key)
                :ok

              {:error, _} = err ->
                err
            end

          {:error, reason} ->
            ingest_result(scope_key, %{
              status: :error,
              compiled_path: Projects.project_workspace_path(project),
              revision: "—",
              cached: false,
              error_count: 1,
              warning_count: 0,
              detail: inspect(reason),
              diagnostics: []
            })

            {:error, "Companion compile failed: #{inspect(reason)}"}
        end
    end
  end

  defp lazy_elmc? do
    Application.get_env(:ide, :debugger_lazy_elmc, true)
  end

  defp companion_parser_expression_view?(state) do
    case SurfaceAccess.introspect(state, :companion) do
      ei when is_map(ei) -> ElmIntrospect.parser_expression_view?(%{"elm_introspect" => ei})
      _ -> false
    end
  end

  defp phone_root(%Project{} = project) do
    workspace_root = Projects.project_workspace_path(project)

    workspace_root
    |> Compiler.workspace_check_roots(project.source_roots || [])
    |> Enum.find(fn {label, _path} -> label == "phone" end)
  end

  defp phone_root(_), do: nil

  defp ingest_result(scope_key, result) when is_binary(scope_key) and is_map(result) do
    diagnostics = Map.get(result, :diagnostics) || Map.get(result, "diagnostics") || []
    counts = Diagnostics.summary(diagnostics)

    attrs =
      result
      |> Map.put(:source_root, "phone")
      |> Map.put(:error_count, counts.error_count)
      |> Map.put(:warning_count, counts.warning_count)
      |> Map.put(:diagnostics, diagnostics)
      |> CompileIngestBridge.from_compiler_compile_result()

    case Ide.Debugger.ingest_elmc_compile(scope_key, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
