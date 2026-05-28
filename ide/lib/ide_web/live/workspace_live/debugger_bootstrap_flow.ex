defmodule IdeWeb.WorkspaceLive.DebuggerBootstrapFlow do
  @moduledoc false

  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.CompanionPhoneCompile
  alias Ide.Debugger.DeferredCompanionInit
  alias Ide.Debugger.Types.CompileIngestBridge
  alias Ide.Projects
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.BuildFlow

  @type bootstrap_tab :: %{optional(:rel_path) => String.t(), optional(:content) => String.t(), optional(:source_root) => String.t()} | nil
  @type progress :: (String.t() -> :ok)
  @type compile_results :: [{String.t(), {:ok, map()} | {:error, term()}}]
  @type primary_compile :: {String.t(), {:ok, map()} | {:error, term()}} | nil

  @type result :: %{
          message: String.t(),
          compile_results: compile_results(),
          primary: primary_compile(),
          companion_async?: boolean(),
          scope_key: String.t()
        }

  @type companion_bootstrap_result :: %{
          optional(:phone_compile) => {:ok, map()} | {:error, term()} | :skipped,
          optional(:reload) => {:ok, term()} | {:error, term()} | :skipped
        }

  @spec run(Project.t(), keyword()) :: {:ok, result()} | {:error, String.t()}
  def run(%Project{} = project, opts \\ []) do
    progress = Keyword.get(opts, :progress, fn _ -> :ok end)
    bootstrap_tab = Keyword.get(opts, :bootstrap_tab)
    watch_profile_id = Keyword.fetch!(opts, :watch_profile_id)

    with :ok <- start_session(project, watch_profile_id, progress),
         {:ok, compile_results, primary} <- warm_compile(project, progress),
         {:ok, message} <- bootstrap_watch_preview(project, bootstrap_tab, progress),
         :ok <- maybe_sync_companion(project, progress) do
      {:ok,
       %{
         message: message,
         compile_results: compile_results,
         primary: primary,
         companion_async?: companion_bootstrap_async?(),
         scope_key: Projects.scope_key(project)
       }}
    end
  end

  @spec run_companion_bootstrap(Project.t(), keyword()) ::
          {:ok, companion_bootstrap_result()} | {:error, String.t()}
  def run_companion_bootstrap(%Project{} = project, opts \\ []) do
    progress = Keyword.get(opts, :progress, fn _ -> :ok end)
    scope_key = Projects.scope_key(project)

    if companion_bootstrap_async?() do
      run_companion_bootstrap_async(project, scope_key, progress)
    else
      run_companion_bootstrap_sync(project, scope_key, progress)
    end
  end

  defp run_companion_bootstrap_sync(project, scope_key, progress) do
    with :ok <- compile_and_ingest_phone(project, scope_key, progress),
         reload <- companion_reload(project, progress) do
      {:ok, %{reload: reload}}
    end
  end

  defp run_companion_bootstrap_async(project, scope_key, progress) do
    progress.("Loading companion model...")

    reload =
      with_companion_fast_bootstrap(scope_key, fn ->
        companion_reload(project, progress)
      end)

    _ = CompanionPhoneCompile.schedule_if_needed(scope_key, project)

    case reload do
      {:ok, _} ->
        DeferredCompanionInit.schedule(scope_key)
        {:ok, %{reload: reload}}

      {:error, _} = err ->
        err

      :skipped ->
        {:ok, %{reload: :skipped}}
    end
  end

  defp with_companion_fast_bootstrap(scope_key, fun) when is_binary(scope_key) and is_function(fun, 0) do
    {:ok, _} = AgentSession.mutate(scope_key, &BootstrapInit.with_companion_bootstrap_flags/1)

    try do
      fun.()
    after
      {:ok, _} = AgentSession.mutate(scope_key, &BootstrapInit.clear_companion_bootstrap_flags/1)
    end
  end

  @spec companion_reload(Project.t()) :: {:ok, term()} | {:error, term()} | :skipped
  def companion_reload(%Project{} = project) do
    companion_reload(project, fn _ -> :ok end)
  end

  defp companion_reload(%Project{} = project, progress) do
    progress.("Loading companion model...")
    scope_key = Projects.scope_key(project)

    case Projects.read_source_file(project, "phone", "src/CompanionApp.elm") do
      {:ok, content} ->
        result =
          Ide.Debugger.reload(scope_key, %{
            rel_path: "src/CompanionApp.elm",
            source: content,
            reason: "debugger_companion_bootstrap",
            source_root: "phone"
          })

        case result do
          {:ok, _} ->
            if companion_reload_await_idle?() do
              progress.("Applying companion init follow-ups...")
              _ = Ide.Debugger.RuntimeBackgroundDrains.await_idle(scope_key)
            end

            result

          _ ->
            result
        end

      {:error, _} ->
        :skipped
    end
  end

  @spec companion_bootstrap_async?() :: boolean()
  def companion_bootstrap_async? do
    Application.get_env(:ide, :debugger_async_companion_bootstrap, true)
  end

  # When companion bootstrap runs in a background Task, do not block on the full
  # HTTP + protocol cascade; LiveView refreshes on debugger:runtime PubSub events.
  @spec companion_reload_await_idle?() :: boolean()
  def companion_reload_await_idle? do
    not companion_bootstrap_async?() or
      Application.get_env(:ide, :debugger_companion_reload_await_idle, false)
  end

  defp start_session(project, watch_profile_id, progress) do
    progress.("Starting debugger session...")

    case Ide.Debugger.start_session(Projects.scope_key(project), %{watch_profile_id: watch_profile_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Could not start debugger: #{inspect(reason)}"}
    end
  end

  defp warm_compile(project, progress) do
    progress.("Preparing compiler workspace...")
    progress.("Compiling Elm sources...")

    skip_roots =
      if companion_bootstrap_async?(), do: ["phone"], else: []

    BuildFlow.warm_debugger_compile_context_work(project, skip_roots: skip_roots)
  end

  defp compile_and_ingest_phone(project, scope_key, progress) do
    progress.("Compiling companion app...")

    case compile_phone_root(project) do
      :skipped ->
        :ok

      {:ok, result} ->
        progress.("Ingesting companion compile artifacts...")
        ingest_phone_compile(scope_key, result)
        :ok

      {:error, reason} ->
        ingest_phone_compile(scope_key, %{
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

  defp compile_phone_root(%Project{} = project) do
    workspace_root = Projects.project_workspace_path(project)
    roots = BuildFlow.build_roots(workspace_root, project.source_roots || [])

    case Enum.find(roots, fn {label, _path} -> label == "phone" end) do
      {label, root_path} ->
        Compiler.compile(Projects.compiler_cache_key(project, label),
          workspace_root: root_path,
          source_roots: project.source_roots
        )

      nil ->
        :skipped
    end
  end

  defp ingest_phone_compile(scope_key, result) when is_binary(scope_key) and is_map(result) do
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
      {:error, reason} -> {:error, reason}
    end
  end

  defp bootstrap_watch_preview(project, bootstrap_tab, progress) do
    progress.("Loading watch preview...")

    case debugger_bootstrap_elm_source(project, bootstrap_tab) do
      {:ok, rel_path, content, source_root} ->
        case Ide.Debugger.reload(Projects.scope_key(project), %{
               rel_path: rel_path,
               source: content,
               reason: "debugger_bootstrap",
               source_root: source_root
             }) do
          {:ok, _} ->
            {:ok,
             "Debugger started. Loaded #{display_path(rel_path)}; watch preview uses parser snapshots when the view outline parses."}

          {:error, reason} ->
            {:error, "Debugger started but watch preview failed: #{inspect(reason)}"}
        end

      :error ->
        {:ok,
         "Debugger started. Open an Elm tab or add Main.elm under the watch source tree, then save a file to load the sample preview."}
    end
  end

  defp maybe_sync_companion(project, progress) do
    if companion_bootstrap_async?() do
      :ok
    else
      case run_companion_bootstrap(project, progress: progress) do
        {:ok, _} -> :ok
        {:error, message} -> {:error, message}
      end
    end
  end

  defp debugger_bootstrap_elm_source(project, bootstrap_tab) do
    case bootstrap_tab do
      %{rel_path: rel_path, content: content, source_root: "watch"} = tab
      when is_binary(rel_path) and is_binary(content) ->
        if elm_bootstrap_tab?(tab) do
          {:ok, rel_path, content, "watch"}
        else
          try_read_watch_main_elm(project)
        end

      _ ->
        try_read_watch_main_elm(project)
    end
  end

  defp elm_bootstrap_tab?(%{rel_path: path, content: content})
       when is_binary(path) and is_binary(content) do
    String.ends_with?(path, ".elm")
  end

  defp elm_bootstrap_tab?(_), do: false

  defp try_read_watch_main_elm(project) do
    candidates = [{"watch", "src/Main.elm"}, {"watch", "Main.elm"}]

    Enum.reduce_while(candidates, :error, fn {root, path}, _ ->
      case Projects.read_source_file(project, root, path) do
        {:ok, content} -> {:halt, {:ok, path, content, root}}
        {:error, _} -> {:cont, :error}
      end
    end)
  end

  defp display_path("src/" <> rest), do: rest
  defp display_path(path) when is_binary(path), do: path
end
