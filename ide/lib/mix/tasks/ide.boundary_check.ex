defmodule Mix.Tasks.Ide.BoundaryCheck do
  @moduledoc false
  use Mix.Task

  @shortdoc "Checks debugger boundary invariants (no raw elm_introspect outside RuntimeArtifacts)"

  @allowed_elm_introspect_files [
    "lib/ide/debugger/runtime_artifacts.ex",
    "lib/ide/debugger/surface.ex",
    "lib/ide/debugger/elm_introspect.ex",
    "lib/mix/tasks/ide.boundary_check.ex"
  ]

  @allowed_stale_model_patterns [
    "lib/ide/debugger.ex",
    "lib/mix/tasks/ide.boundary_check.ex"
  ]

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()

    check_elm_introspect_access!(root)
    check_stale_watch_model_reads!(root)
    Mix.shell().info("Debugger boundary checks passed.")
  end

  defp check_elm_introspect_access!(root) do
    lib_root = Path.join(root, "lib")

    lib_root
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.reject(&allowed_elm_introspect_file?/1)
    |> Enum.each(fn path ->
      content = File.read!(path)

      if String.contains?(content, ~s("elm_introspect")) and
           Regex.match?(~r/Map\.get\([^)]*,\s*"elm_introspect"/, content) do
        Mix.raise("""
        Raw Map.get(..., "elm_introspect") found in #{Path.relative_to(path, root)}.
        Use Ide.Debugger.RuntimeArtifacts.introspect/1 or Surface.introspect/1 instead.
        """)
      end
    end)
  end

  defp check_stale_watch_model_reads!(root) do
    lib_root = Path.join(root, "lib")

    lib_root
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.reject(&allowed_stale_model_file?/1)
    |> Enum.each(fn path ->
      content = File.read!(path)

      if Regex.match?(~r/get_in\(state,\s*\[:watch,\s*:model\]\)/, content) do
        Mix.raise("""
        Stale get_in(state, [:watch, :model]) found in #{Path.relative_to(path, root)}.
        Use Surface.from_state/2 and Surface.app_model/1 instead.
        """)
      end
    end)
  end

  defp allowed_elm_introspect_file?(path) do
    Enum.any?(@allowed_elm_introspect_files, &String.ends_with?(path, &1))
  end

  defp allowed_stale_model_file?(path) do
    Enum.any?(@allowed_stale_model_patterns, &String.ends_with?(path, &1))
  end
end
