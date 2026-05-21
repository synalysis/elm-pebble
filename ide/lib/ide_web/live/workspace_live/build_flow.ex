defmodule IdeWeb.WorkspaceLive.BuildFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias Ide.Compiler
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerBridge
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @type socket :: Phoenix.LiveView.Socket.t()
  @type root_pair :: {String.t(), String.t()}
  @type wire_input :: String.t() | integer() | boolean() | nil

  @type root_build_result :: %{
          label: String.t(),
          root_path: String.t(),
          status: :ok | :error,
          check: Compiler.check_result(),
          compile: Compiler.compile_result(),
          manifest: Compiler.manifest_result()
        }

  @type build_pipeline_result :: %{
          status: :ok | :error,
          output: String.t(),
          primary: root_build_result() | nil,
          package: map(),
          issues: [map()],
          roots: [root_build_result()]
        }

  @type emulator_install_result :: %{
          status: :ok | :error,
          command: String.t(),
          output: String.t(),
          exit_code: integer(),
          cwd: String.t(),
          artifact_path: String.t()
        }

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("run-check", _params, socket) do
    {:noreply, schedule_compiler_check(socket)}
  end

  def handle_event("run-build", params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    strict? = manifest_strict_from_params(params, socket.assigns.manifest_strict_mode)

    {:noreply,
     socket
     |> assign(:manifest_strict_mode, strict?)
     |> assign(:build_status, :running)
     |> assign(:build_issues, [])
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

  def handle_event("set-manifest-strict", params, socket) do
    strict? = manifest_strict_from_params(params, socket.assigns.manifest_strict_mode)
    {:noreply, assign(socket, :manifest_strict_mode, strict?)}
  end

  defp manifest_strict_from_params(%{"build" => %{"manifest_strict" => value}}, _default) do
    value in ["true", true]
  end

  defp manifest_strict_from_params(%{"value" => value}, _default) do
    value in ["true", true]
  end

  defp manifest_strict_from_params(_params, default), do: default == true

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
      |> assign(:build_issues, result.issues)
      |> assign(:publish_artifact_path, result.package.artifact_path)
      |> assign(:publish_app_root, package_app_root(result.package))
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
      |> assign(:build_issues, [
        %{
          title: "Build failed before execution",
          message: inspect(reason),
          detail: nil
        }
      ])
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
      |> assign(:build_issues, [
        %{
          title: "Build task exited",
          message: inspect(reason),
          detail: nil
        }
      ])
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

  defp package_app_root(%{raw: %{app_root: app_root}}) when is_binary(app_root), do: app_root
  defp package_app_root(_package), do: nil

  @spec schedule_compiler_check(socket()) :: socket()
  def schedule_compiler_check(socket) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        :ok = Projects.ensure_compiler_workspace(project)
        workspace_root = Projects.project_workspace_path(project)
        compiler_root = Projects.preferred_compiler_root(project) || workspace_root

        socket
        |> assign(:check_status, :running)
        |> start_async(:run_check, fn ->
          Compiler.check(project.slug,
            workspace_root: compiler_root,
            source_roots: project.source_roots
          )
        end)
    end
  end

  @spec warm_debugger_compile_context(socket(), Project.t()) :: socket()
  def warm_debugger_compile_context(socket, project) do
    :ok = Projects.ensure_compiler_workspace(project)
    workspace_root = Projects.project_workspace_path(project)

    results =
      workspace_root
      |> build_roots(project.source_roots || [])
      |> Enum.map(fn {label, root_path} ->
        {label,
         Compiler.compile("#{project.slug}:#{label}",
           workspace_root: root_path,
           source_roots: project.source_roots
         )}
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

  @spec run_build_pipeline(Project.t(), String.t(), boolean()) ::
          {:ok, build_pipeline_result()}
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

    roots_ok? = Enum.all?(root_results, fn result -> result.status == :ok end)
    package_result = run_package_validation(project, workspace_root, roots_ok?)
    issues = build_issues(root_results, package_result)

    status =
      if roots_ok? and package_result.status == :ok,
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
      |> Kernel.++([render_package_validation_output(package_result)])
      |> Enum.join("\n\n")
      |> String.trim()

    {:ok,
     %{
       status: status,
       output: output,
       primary: primary,
       package: package_result,
       issues: issues,
       roots: root_results
     }}
  end

  @spec build_issues([map()], map()) :: [map()]
  def build_issues(root_results, package_result) do
    root_issues =
      root_results
      |> Enum.filter(&(&1.status != :ok))
      |> Enum.map(fn result ->
        %{
          title: "Source-root build failed: #{result.label}",
          message: "Check, compile, or manifest validation failed before PBW packaging.",
          detail: result.root_path
        }
      end)

    package_issues =
      if package_result.status == :ok do
        []
      else
        package_output_issues(package_result.output || inspect(package_result.raw))
      end

    root_issues ++ package_issues
  end

  @spec package_output_issues(String.t()) :: [map()]
  def package_output_issues(output) when is_binary(output) do
    case memory_overflow_info(output) do
      nil ->
        [
          %{
            title: "PBW packaging failed",
            message: "Pebble SDK packaging failed. See the package log below for details.",
            detail: nil
          }
        ]

      info ->
        [
          %{
            title: "PBW too large for #{target_label(info.target)}",
            message:
              "The linker says the app does not fit in the Pebble APP memory region. " <>
                overflow_action(info.target),
            detail: overflow_detail(info)
          }
        ]
    end
  end

  def package_output_issues(_output), do: []

  defp memory_overflow_info(output) do
    normalized = String.downcase(output)

    if String.contains?(normalized, "region `app' overflowed") or
         String.contains?(normalized, "will not fit in region `app'") or
         String.contains?(normalized, "overflowed by") do
      %{
        target: overflow_target(output),
        bytes: overflow_bytes(output)
      }
    else
      nil
    end
  end

  defp overflow_target(output) do
    lines = String.split(output, "\n")

    with index when is_integer(index) <- overflow_line_index(lines) do
      overflow_context_target(lines, index) || last_linking_target_before(lines, index)
    else
      _ -> first_pebble_app_target(output)
    end
  end

  defp overflow_line_index(lines) do
    Enum.find_index(lines, fn line ->
      normalized = String.downcase(line)

      String.contains?(normalized, "region `app' overflowed") or
        String.contains?(normalized, "will not fit in region `app'") or
        String.contains?(normalized, "overflowed by")
    end)
  end

  defp overflow_context_target(lines, index) do
    before_or_at =
      lines
      |> Enum.take(index + 1)
      |> Enum.reverse()

    after_overflow =
      lines
      |> Enum.drop(index + 1)

    (before_or_at ++ after_overflow)
    |> Enum.find_value(&pebble_app_target_from_line/1)
  end

  defp last_linking_target_before(lines, index) do
    lines
    |> Enum.take(index + 1)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Regex.run(~r/Linking\s+([a-z0-9_-]+)/i, line) do
        [_, target] -> String.downcase(target)
        _ -> nil
      end
    end)
  end

  defp first_pebble_app_target(output), do: pebble_app_target_from_line(output)

  defp pebble_app_target_from_line(line) do
    case Regex.run(~r/build\/([a-z0-9_-]+)\/pebble-app\.elf/i, line) do
      [_, target] -> String.downcase(target)
      _ -> nil
    end
  end

  defp overflow_bytes(output) do
    case Regex.run(~r/overflowed by\s+(\d+)\s+bytes/i, output) do
      [_, bytes] -> bytes
      _ -> nil
    end
  end

  defp overflow_action("aplite") do
    "Aplite is enabled; remove it from target platforms if this app should not support original black-and-white Pebble, or reduce code/resources."
  end

  defp overflow_action(_target) do
    "Reduce generated code/resources or narrow target platforms to models that can fit the app."
  end

  defp target_label(nil), do: "target"
  defp target_label(target) when is_binary(target), do: String.capitalize(target)

  defp overflow_detail(%{target: target, bytes: bytes}) do
    [target && "target=#{target}", bytes && "overflow=#{bytes} bytes"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      detail -> detail
    end
  end

  @spec run_package_validation(Project.t(), String.t(), boolean()) :: map()
  def run_package_validation(_project, workspace_root, false) do
    %{
      status: :error,
      artifact_path: nil,
      output: "PBW packaging skipped: source-root build failed.",
      raw: nil,
      workspace_root: workspace_root
    }
  end

  def run_package_validation(project, workspace_root, true) do
    targets = PublishFlow.target_platforms(project)

    case PebbleToolchain.package(project.slug,
           workspace_root: workspace_root,
           target_type: project.target_type,
           project_name: project.name,
           target_platforms: targets
         ) do
      {:ok, package} ->
        %{
          status: package.status,
          artifact_path: package.artifact_path,
          output:
            [
              "Configured target platforms: #{Enum.join(targets, ", ")}",
              "Artifact: #{package.artifact_path}",
              "",
              ToolchainPresenter.render_publish_output(package)
            ]
            |> Enum.join("\n")
            |> String.trim(),
          raw: package,
          workspace_root: workspace_root
        }

      {:error, reason} ->
        %{
          status: :error,
          artifact_path: nil,
          output: render_package_failure(reason, targets),
          raw: reason,
          workspace_root: workspace_root
        }
    end
  end

  @spec render_package_validation_output(map()) :: String.t()
  def render_package_validation_output(package_result) do
    """
    === [pbw package] ===
    #{package_result.output}
    """
    |> String.trim()
  end

  @spec render_package_failure(PebbleToolchain.toolchain_error(), [String.t()]) :: String.t()
  def render_package_failure({:pebble_build_failed, %{output: output} = result}, targets)
      when is_binary(output) do
    [
      "PBW packaging failed.",
      "Configured target platforms: #{Enum.join(targets, ", ")}",
      package_failure_hint(output, targets),
      "",
      ToolchainPresenter.render_toolchain_output(result)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> String.trim()
  end

  def render_package_failure(reason, targets) do
    [
      "PBW packaging failed.",
      "Configured target platforms: #{Enum.join(targets, ", ")}",
      package_failure_hint(inspect(reason), targets),
      "",
      inspect(reason)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp package_failure_hint(output, targets) do
    normalized = String.downcase(output)

    cond do
      String.contains?(normalized, "region `app' overflowed") or
        String.contains?(normalized, "will not fit in region `app'") or
          String.contains?(normalized, "overflowed by") ->
        target_hint =
          if "aplite" in targets do
            " Aplite is enabled; consider removing it from target platforms if the app is not intended to support the original black-and-white Pebble, or reduce generated code/resources."
          else
            " Reduce generated code/resources or narrow target platforms to models that can fit the app."
          end

        "Diagnosis: Pebble SDK linker output indicates a memory-region overflow.#{target_hint}"

      true ->
        nil
    end
  end

  @spec run_build_pipeline_for_root(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, root_build_result()}
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

  @spec run_emulator_install_flow(Project.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, emulator_install_result()} | {:error, PebbleToolchain.toolchain_error()}
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

  @spec package_for_emulator_target(Project.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, PebbleToolchain.toolchain_error()}
  def package_for_emulator_target(project, workspace_root, emulator_target) do
    with {:ok, packaged} <- package_for_emulator_session(project, workspace_root, emulator_target) do
      {:ok, packaged.artifact_path}
    end
  end

  @spec package_for_emulator_session(Project.t(), String.t(), String.t()) ::
          {:ok, PebbleToolchain.package_result()} | {:error, PebbleToolchain.toolchain_error()}
  def package_for_emulator_session(project, workspace_root, emulator_target) do
    with :ok <- Projects.ensure_compiler_workspace(project),
         {:ok, packaged} <-
           PebbleToolchain.package(project.slug,
             workspace_root: workspace_root,
             target_type: project.target_type,
             project_name: project.name,
             target_platforms: [emulator_target],
             source_roots: project.source_roots
           ) do
      {:ok, packaged}
    end
  end

  @spec build_roots(String.t(), [String.t()]) :: [root_pair()]
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

    case roots do
      [] ->
        fallback_label = Enum.find(source_roots, &(&1 == "watch")) || List.first(source_roots) || "watch"

        [{fallback_label, Path.join(workspace_root, fallback_label)}]

      found ->
        found
    end
  end

  @spec render_build_pipeline_output(
          Compiler.check_result(),
          Compiler.compile_result(),
          Compiler.manifest_result()
        ) :: String.t()
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

  @spec skipped_compile_result(String.t(), String.t()) :: map()
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

  @spec skipped_manifest_result(String.t(), boolean(), String.t()) :: map()
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
