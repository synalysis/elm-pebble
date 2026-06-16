defmodule IdeWeb.WorkspaceLive.DebuggerBootstrapFlow do
  @moduledoc false

  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.CompanionBootstrapLock
  alias Ide.Debugger.CompanionPhoneCompile
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.Types.CompileIngestBridge
  alias Ide.Projects
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.BuildFlow

  @type bootstrap_tab ::
          %{
            optional(:rel_path) => String.t(),
            optional(:content) => String.t(),
            optional(:source_root) => String.t()
          }
          | nil
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

    scope_key = Projects.scope_key(project)

    with :ok <- start_session(project, watch_profile_id, progress),
         {:ok, compile_results, primary} <- warm_compile(project, progress),
         :ok <- ingest_warm_compile_results(scope_key, compile_results, progress),
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

  @companion_protocol_runtime_keys ~w(
    status
    protocol_message_count
    protocol_inbound_count
    protocol_outbound_count
    protocol_last_inbound_message
    protocol_last_inbound_from
    screenW
    screenH
    displayShape
    colorMode
  )

  @spec run_companion_bootstrap(Project.t(), keyword()) ::
          {:ok, companion_bootstrap_result()} | {:error, String.t()}
  def run_companion_bootstrap(%Project{} = project, opts \\ []) do
    progress = Keyword.get(opts, :progress, fn _ -> :ok end)
    scope_key = Projects.scope_key(project)
    force_sync? = Keyword.get(opts, :force_sync, false)

    unless CompanionBootstrapLock.try_acquire(scope_key) do
      {:ok, %{reload: :skipped}}
    else
      try do
        with :ok <- compile_and_ingest_phone(project, scope_key, progress),
             :ok <- bootstrap_watch_for_companion(project, progress) do
          run_companion_bootstrap_body(project, scope_key, progress, force_sync: force_sync?)
        end
      after
        CompanionBootstrapLock.release(scope_key)
      end
    end
  end

  @spec bootstrap_watch_for_companion(Project.t(), progress()) :: :ok | {:error, String.t()}
  def bootstrap_watch_for_companion(%Project{} = project, progress \\ fn _ -> :ok end) do
    scope_key = Projects.scope_key(project)

    state =
      try do
        AgentStore.fetch(scope_key, timeout: 5_000)
      catch
        :exit, _ -> %{}
      end

    if watch_surface_bootstrapped?(state) do
      :ok
    else
      progress.("Loading watch for companion bootstrap...")
      bootstrap_watch_reload(project, scope_key)
    end
  end

  @spec bootstrap_watch_reload(Project.t(), String.t()) :: :ok | {:error, String.t()}
  defp bootstrap_watch_reload(%Project{} = project, scope_key) when is_binary(scope_key) do
    case try_read_watch_main_elm(project) do
      {:ok, rel_path, content, source_root} ->
        reload =
          with_skip_blocking_compile(scope_key, fn ->
            Ide.Debugger.reload(scope_key, %{
              rel_path: rel_path,
              source: content,
              reason: "debugger_companion_bootstrap",
              source_root: source_root,
              skip_precompile: true
            })
          end)

        case reload do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, "Watch bootstrap failed: #{inspect(reason)}"}
        end

      :error ->
        :ok
    end
  end

  defp with_skip_blocking_compile(scope_key, fun)
       when is_binary(scope_key) and is_function(fun, 0) do
    {:ok, _} = AgentSession.mutate(scope_key, &BootstrapInit.with_skip_blocking_compile_flags/1)

    try do
      fun.()
    after
      {:ok, _} = AgentSession.mutate(scope_key, &BootstrapInit.clear_skip_blocking_compile_flags/1)
    end
  end

  defp run_companion_bootstrap_body(project, scope_key, progress, opts) do
    force_sync? = Keyword.get(opts, :force_sync, false)

    reload =
      with_skip_blocking_compile(scope_key, fn ->
        companion_reload(project, progress)
      end)

    _ = CompanionPhoneCompile.schedule_if_needed(scope_key, project)

    case reload do
      {:ok, _} ->
        if force_sync? do
          progress.("Waiting for companion follow-ups...")
          _ = RuntimeBackgroundDrains.await_idle(scope_key, 120_000)
        end

        {:ok, %{reload: reload}}

      {:error, _} = err ->
        err

      :skipped ->
        {:ok, %{reload: :skipped}}
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
            source_root: "phone",
            skip_precompile: true
          })

        result

      {:error, _} ->
        :skipped
    end
  end

  @spec companion_bootstrap_async?() :: boolean()
  def companion_bootstrap_async? do
    Application.get_env(:ide, :debugger_async_companion_bootstrap, true)
  end

  @spec companion_bootstrapped?(map() | nil) :: boolean()
  def companion_bootstrapped?(state) when is_map(state) do
    companion_runtime_model_bootstrapped?(state)
  end

  def companion_bootstrapped?(_state), do: false

  @spec companion_bootstrap_incomplete?(map() | nil) :: boolean()
  def companion_bootstrap_incomplete?(state) when is_map(state) do
    companion_surface_init_started?(state) and not companion_bootstrapped?(state)
  end

  def companion_bootstrap_incomplete?(_state), do: false

  @spec companion_surface_init_started?(map() | nil) :: boolean()
  def companion_surface_init_started?(state) when is_map(state) do
    companion_init_on_timeline?(state)
  end

  def companion_surface_init_started?(_state), do: false

  @spec watch_surface_bootstrapped?(map() | nil) :: boolean()
  def watch_surface_bootstrapped?(state) when is_map(state) do
    watch_init_on_timeline?(state) or watch_runtime_model_bootstrapped?(state)
  end

  def watch_surface_bootstrapped?(_state), do: false

  @spec companion_init_on_timeline?(map()) :: boolean()
  defp companion_init_on_timeline?(state) when is_map(state) do
    state
    |> Map.get(:debugger_timeline, [])
    |> Enum.any?(fn row ->
      target = Map.get(row, :target) || Map.get(row, "target")
      type = Map.get(row, :type) || Map.get(row, "type")

      target in ["phone", "companion"] and
        type in ["init", "debugger.init_in", "debugger.runtime_exec"]
    end)
  end

  @spec watch_init_on_timeline?(map()) :: boolean()
  defp watch_init_on_timeline?(state) when is_map(state) do
    state
    |> Map.get(:debugger_timeline, [])
    |> Enum.any?(fn row ->
      target = Map.get(row, :target) || Map.get(row, "target")
      type = Map.get(row, :type) || Map.get(row, "type")

      target == "watch" and
        type in ["init", "debugger.init_in", "debugger.runtime_exec"]
    end)
  end

  @spec watch_runtime_model_bootstrapped?(map()) :: boolean()
  defp watch_runtime_model_bootstrapped?(state) when is_map(state) do
    runtime_model =
      get_in(state, [:watch, :model, "runtime_model"]) ||
        get_in(state, [:watch, :model, :runtime_model]) ||
        %{}

    is_map(runtime_model) and map_size(runtime_model) > 0 and
      not Map.has_key?(runtime_model, "runtime_execution_error") and
      not Map.has_key?(runtime_model, :runtime_execution_error)
  end

  @spec companion_runtime_model_bootstrapped?(map()) :: boolean()
  defp companion_runtime_model_bootstrapped?(state) when is_map(state) do
    runtime_model =
      get_in(state, [:companion, :model, "runtime_model"]) ||
        get_in(state, [:companion, :model, :runtime_model]) ||
        %{}

    is_map(runtime_model) and map_size(runtime_model) > 0 and
      not companion_protocol_only_model?(runtime_model)
  end

  @spec companion_protocol_only_model?(map()) :: boolean()
  defp companion_protocol_only_model?(model) when is_map(model) do
    keys =
      model
      |> Map.keys()
      |> Enum.map(&to_string/1)

    keys != [] and Enum.all?(keys, &(&1 in @companion_protocol_runtime_keys))
  end

  # Background companion bootstrap refreshes via debugger:runtime PubSub when HTTP drains finish.
  @spec companion_reload_await_idle?() :: boolean()
  def companion_reload_await_idle? do
    not companion_bootstrap_async?() or
      Application.get_env(:ide, :debugger_companion_reload_await_idle, false)
  end

  @spec start_session(Project.t(), String.t(), progress()) :: :ok | {:error, String.t()}
  defp start_session(project, watch_profile_id, progress) do
    progress.("Starting debugger session...")

    case Ide.Debugger.start_session(Projects.scope_key(project), %{
           watch_profile_id: watch_profile_id
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Could not start debugger: #{inspect(reason)}"}
    end
  end

  @spec warm_compile(Project.t(), progress()) ::
          {:ok, BuildFlow.warm_compile_results(), BuildFlow.warm_compile_primary()}
  defp warm_compile(project, progress) do
    progress.("Preparing compiler workspace...")
    progress.("Compiling Elm sources...")

    skip_roots =
      if companion_bootstrap_async?(), do: ["phone"], else: []

    BuildFlow.warm_debugger_compile_context_work(project, skip_roots: skip_roots)
  end

  @spec compile_and_ingest_phone(Project.t(), String.t(), progress()) ::
          :ok | {:error, String.t()}
  defp compile_and_ingest_phone(project, scope_key, progress) do
    state =
      try do
        AgentStore.fetch(scope_key, timeout: 5_000)
      catch
        :exit, _ -> %{}
      end

    if companion_bootstrapped?(state) do
      progress.("Companion artifacts ready")
      :ok
    else
      progress.("Compiling companion app...")

      case compile_phone_root(project) do
        :skipped ->
          {:error, "Companion phone source root is missing"}

        {:ok, result} ->
          progress.("Ingesting companion compile artifacts...")
          ingest_phone_compile(scope_key, result)

          if Map.get(result, :status) == :error do
            {:error, "Companion compile failed: #{Map.get(result, :output, "elmc error")}"}
          else
            :ok
          end
      end
    end
  end

  @spec compile_phone_root(Project.t()) :: :skipped | {:ok, map()}
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

  @spec ingest_warm_compile_results(String.t(), compile_results(), progress()) :: :ok
  defp ingest_warm_compile_results(scope_key, compile_results, progress)
       when is_binary(scope_key) and is_list(compile_results) do
    progress.("Attaching runtime artifacts...")

    Enum.each(compile_results, fn
      {label, {:ok, result}} ->
        ingest_compile_result(scope_key, result, label)

      _ ->
        :ok
    end)

    :ok
  end

  @spec ingest_compile_result(String.t(), map(), String.t()) :: :ok
  defp ingest_compile_result(scope_key, result, source_root)
       when is_binary(scope_key) and is_map(result) and is_binary(source_root) do
    diagnostics = Map.get(result, :diagnostics) || Map.get(result, "diagnostics") || []
    counts = Diagnostics.summary(diagnostics)

    attrs =
      result
      |> Map.put(:source_root, source_root)
      |> Map.put(:error_count, counts.error_count)
      |> Map.put(:warning_count, counts.warning_count)
      |> Map.put(:diagnostics, diagnostics)
      |> CompileIngestBridge.from_compiler_compile_result()

    {:ok, _} = Ide.Debugger.ingest_elmc_compile(scope_key, attrs)
    :ok
  end

  @spec ingest_phone_compile(String.t(), map()) :: :ok
  defp ingest_phone_compile(scope_key, result) when is_binary(scope_key) and is_map(result) do
    ingest_compile_result(scope_key, result, "phone")
  end

  @spec bootstrap_watch_preview(Project.t(), bootstrap_tab(), progress()) ::
          {:ok, String.t()} | {:error, String.t()}
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
