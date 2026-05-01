defmodule IdeWeb.WorkspaceLive.BuildFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias Ide.Compiler
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerBridge

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("run-check", _params, socket) do
    {:noreply, schedule_compiler_check(socket)}
  end

  def handle_event("run-build", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    strict? = socket.assigns.manifest_strict_mode

    {:noreply,
     socket
     |> assign(:build_status, :running)
     |> assign(:check_status, :running)
     |> assign(:compile_status, :running)
     |> assign(:manifest_status, :running)
     |> start_async(:run_build, fn ->
       run_build_pipeline(project, workspace_root, strict?)
     end)}
  end

  def handle_event("run-compile", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)

    {:noreply,
     socket
     |> assign(:compile_status, :running)
     |> start_async(:run_compile, fn ->
       Compiler.compile(project.slug, workspace_root: workspace_root)
     end)}
  end

  def handle_event("run-manifest", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    strict? = socket.assigns.manifest_strict_mode

    {:noreply,
     socket
     |> assign(:manifest_status, :running)
     |> start_async(:run_manifest, fn ->
       Compiler.manifest(project.slug, workspace_root: workspace_root, strict: strict?)
     end)}
  end

  def handle_event("set-manifest-strict", %{"value" => value}, socket) do
    strict? = value in ["true", true]
    {:noreply, assign(socket, :manifest_strict_mode, strict?)}
  end

  def handle_async(:run_check, {:ok, {:ok, result}}, socket) do
    socket =
      socket
      |> assign(:check_status, result.status)
      |> assign(:check_output, result.output)
      |> assign(:diagnostics, result.diagnostics)

    socket = DebuggerBridge.sync_check(socket, result)
    {:noreply, socket}
  end

  def handle_async(:run_build, {:ok, {:ok, result}}, socket) do
    primary = result.primary

    socket =
      socket
      |> assign(:build_status, result.status)
      |> assign(:build_output, result.output)
      |> assign(:check_status, primary.check.status)
      |> assign(:check_output, primary.check.output)
      |> assign(:compile_status, primary.compile.status)
      |> assign(:compile_output, primary.compile.output)
      |> assign(:manifest_status, primary.manifest.status)
      |> assign(:manifest_output, primary.manifest.output)

    socket =
      result.roots
      |> List.wrap()
      |> Enum.reduce(socket, fn root_result, acc ->
        acc
        |> DebuggerBridge.sync_check(Map.put(root_result.check, :source_root, root_result.label))
        |> DebuggerBridge.sync_compile(
          Map.put(root_result.compile, :source_root, root_result.label)
        )
        |> DebuggerBridge.sync_manifest(
          Map.put(root_result.manifest, :source_root, root_result.label)
        )
      end)

    {:noreply, socket}
  end

  def handle_async(:run_build, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:build_status, :error)
      |> assign(:build_output, "Build failed before execution: #{inspect(reason)}")
      |> assign(:check_status, :error)
      |> assign(:compile_status, :error)
      |> assign(:manifest_status, :error)

    socket = DebuggerBridge.sync_check_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_build, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:build_status, :error)
      |> assign(:build_output, "Build task exited: #{inspect(reason)}")
      |> assign(:check_status, :error)
      |> assign(:compile_status, :error)
      |> assign(:manifest_status, :error)

    socket = DebuggerBridge.sync_check_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_compile, {:ok, {:ok, result}}, socket) do
    socket =
      socket
      |> assign(:compile_status, result.status)
      |> assign(:compile_output, result.output)

    socket = DebuggerBridge.sync_compile(socket, result)
    {:noreply, socket}
  end

  def handle_async(:run_manifest, {:ok, {:ok, result}}, socket) do
    mode = if result[:strict?], do: "strict", else: "default"

    socket =
      socket
      |> assign(:manifest_status, result.status)
      |> assign(:manifest_output, "[manifest mode: #{mode}]\n#{result.output}")

    socket = DebuggerBridge.sync_manifest(socket, result)
    {:noreply, socket}
  end

  def handle_async(:run_compile, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:compile_status, :error)
      |> assign(:compile_output, inspect(reason))

    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_compile, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:compile_status, :error)
      |> assign(:compile_output, "Compiler compile task exited: #{inspect(reason)}")

    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_manifest, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:manifest_status, :error)
      |> assign(:manifest_output, inspect(reason))

    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_manifest, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:manifest_status, :error)
      |> assign(:manifest_output, "Compiler manifest task exited: #{inspect(reason)}")

    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_check, {:ok, {:error, reason}}, socket) do
    msg = inspect(reason)

    socket =
      socket
      |> assign(:check_status, :error)
      |> assign(:check_output, msg)
      |> assign(:diagnostics, [
        %{
          severity: "error",
          source: "ide",
          message: "Compiler check crashed: #{msg}",
          file: nil,
          line: nil,
          column: nil
        }
      ])

    socket = DebuggerBridge.sync_check_failed(socket, msg)
    {:noreply, socket}
  end

  def handle_async(:run_check, {:exit, reason}, socket) do
    msg = inspect(reason)

    socket =
      socket
      |> assign(:check_status, :error)
      |> assign(:check_output, msg)
      |> assign(:diagnostics, [
        %{
          severity: "error",
          source: "ide",
          message: "Compiler check task exited: #{msg}",
          file: nil,
          line: nil,
          column: nil
        }
      ])

    socket = DebuggerBridge.sync_check_failed(socket, msg)
    {:noreply, socket}
  end

  @spec schedule_compiler_check(term()) :: term()
  def schedule_compiler_check(socket) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        workspace_root = Projects.project_workspace_path(project)

        socket
        |> assign(:check_status, :running)
        |> start_async(:run_check, fn ->
          Compiler.check(project.slug, workspace_root: workspace_root)
        end)
    end
  end

  @spec warm_debugger_compile_context(term(), term()) :: term()
  def warm_debugger_compile_context(socket, project) do
    workspace_root = Projects.project_workspace_path(project)

    results =
      workspace_root
      |> build_roots(project.source_roots || [])
      |> Enum.map(fn {label, root_path} ->
        {label, Compiler.compile("#{project.slug}:#{label}", workspace_root: root_path)}
      end)

    primary =
      Enum.find(results, fn {label, _result} -> label == "watch" end) ||
        List.first(results)

    socket =
      Enum.reduce(results, socket, fn
        {label, {:ok, result}}, acc ->
          DebuggerBridge.sync_compile(acc, Map.put(result, :source_root, label))

        {_label, {:error, reason}}, acc ->
          DebuggerBridge.sync_compile_failed(acc, inspect(reason))
      end)

    case primary do
      {_label, {:ok, result}} ->
        socket
        |> assign(:compile_status, result.status)
        |> assign(:compile_output, result.output)

      {_label, {:error, reason}} ->
        socket
        |> assign(:compile_status, :error)
        |> assign(:compile_output, inspect(reason))

      nil ->
        socket
    end
  end

  @spec run_build_pipeline(term(), term(), term()) :: term()
  def run_build_pipeline(project, workspace_root, strict?) do
    roots = build_roots(workspace_root, project.source_roots || [])

    root_results =
      roots
      |> Enum.map(fn {label, root_path} ->
        {:ok, single} = run_build_pipeline_for_root(project.slug, label, root_path, strict?)
        single
      end)

    primary =
      Enum.find(root_results, fn result -> result.label == "watch" end) ||
        List.first(root_results)

    status =
      if Enum.all?(root_results, fn result -> result.status == :ok end),
        do: :ok,
        else: :error

    output =
      root_results
      |> Enum.map(fn result ->
        [
          "=== [#{result.label}] #{result.root_path} ===",
          render_build_pipeline_output(result.check, result.compile, result.manifest)
        ]
        |> Enum.join("\n")
      end)
      |> Enum.join("\n\n")
      |> String.trim()

    {:ok,
     %{
       status: status,
       output: output,
       primary: primary,
       roots: root_results
     }}
  end

  @spec run_build_pipeline_for_root(term(), term(), term(), term()) :: term()
  def run_build_pipeline_for_root(project_slug, label, root_path, strict?) do
    scoped_slug = "#{project_slug}:#{label}"

    with {:ok, check_result} <- Compiler.check(scoped_slug, workspace_root: root_path) do
      if check_result.status == :ok do
        with {:ok, compile_result} <-
               Compiler.compile(scoped_slug, workspace_root: root_path),
             {:ok, manifest_result} <-
               Compiler.manifest(scoped_slug, workspace_root: root_path, strict: strict?) do
          {:ok,
           %{
             label: label,
             root_path: root_path,
             status:
               if(compile_result.status == :ok and manifest_result.status == :ok,
                 do: :ok,
                 else: :error
               ),
             check: check_result,
             compile: compile_result,
             manifest: manifest_result
           }}
        end
      else
        compile_result = skipped_compile_result(root_path, "Compile skipped: check failed.")

        manifest_result =
          skipped_manifest_result(root_path, strict?, "Manifest skipped: check failed.")

        {:ok,
         %{
           label: label,
           root_path: root_path,
           status: :error,
           check: check_result,
           compile: compile_result,
           manifest: manifest_result
         }}
      end
    end
  end

  @spec run_emulator_install_flow(term(), term(), term(), term()) :: term()
  def run_emulator_install_flow(project, workspace_root, emulator_target, _package_path) do
    with {:ok, resolved_package_path} <-
           package_for_emulator_target(project, workspace_root, emulator_target),
         {:ok, install_result} <-
           PebbleToolchain.run_emulator(project.slug,
             emulator_target: emulator_target,
             package_path: resolved_package_path
           ) do
      {:ok, Map.put(install_result, :artifact_path, resolved_package_path)}
    end
  end

  @spec package_for_emulator_target(term(), term(), term()) :: term()
  def package_for_emulator_target(project, workspace_root, emulator_target) do
    with {:ok, packaged} <-
           PebbleToolchain.package(project.slug,
             workspace_root: workspace_root,
             target_type: project.target_type,
             project_name: project.name,
             target_platforms: [emulator_target]
           ) do
      {:ok, packaged.artifact_path}
    end
  end

  @spec build_roots(term(), term()) :: term()
  def build_roots(workspace_root, source_roots) do
    candidates =
      [{"workspace", workspace_root}] ++
        Enum.map(source_roots, fn root_name ->
          {root_name, Path.join(workspace_root, root_name)}
        end)

    roots =
      candidates
      |> Enum.uniq_by(fn {_label, path} -> path end)
      |> Enum.filter(fn {_label, path} -> File.exists?(Path.join(path, "elm.json")) end)

    if roots == [], do: [{"workspace", workspace_root}], else: roots
  end

  @spec render_build_pipeline_output(term(), term(), term()) :: term()
  def render_build_pipeline_output(check_result, compile_result, manifest_result) do
    [
      "[check]\n",
      check_result.output || "",
      "\n\n[compile]\n",
      compile_result.output || "",
      "\n\n[manifest]\n",
      manifest_result.output || ""
    ]
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  @spec skipped_compile_result(term(), term()) :: term()
  def skipped_compile_result(workspace_root, message) do
    %{
      status: :error,
      compiled_path: workspace_root,
      revision: "—",
      cached?: false,
      output: message,
      diagnostics: []
    }
  end

  @spec skipped_manifest_result(term(), term(), term()) :: term()
  def skipped_manifest_result(workspace_root, strict?, message) do
    %{
      status: :error,
      manifest_path: workspace_root,
      revision: "—",
      cached?: false,
      strict?: strict?,
      manifest: nil,
      output: message,
      diagnostics: []
    }
  end
end
