Mix.Task.run("app.start")

alias Ide.{ProjectTemplates, PebbleToolchain}

templates = ProjectTemplates.template_keys()
started = System.monotonic_time(:second)

results =
  Enum.map(templates, fn template ->
    workspace =
      Path.join(
        System.tmp_dir!(),
        "pbw-gate-#{template}-#{System.unique_integer([:positive])}"
      )

    slug = "pbw-gate-#{template}"
    t0 = System.monotonic_time(:second)

    outcome =
      try do
        with :ok <- ProjectTemplates.apply_template(template, workspace),
             {:ok, pkg} <-
               PebbleToolchain.package(slug,
                 workspace_root: workspace,
                 target_type: ProjectTemplates.target_type_for_template(template),
                 project_name: template,
                 target_platforms: ProjectTemplates.target_platforms_for_template(template)
               ),
             true <- File.regular?(pkg.artifact_path) do
          {:ok,
           %{
             artifact_path: pkg.artifact_path,
             bytes: File.stat!(pkg.artifact_path).size,
             platforms: ProjectTemplates.target_platforms_for_template(template)
           }}
        else
          {:error, {:pebble_build_failed, %{output: output}}} ->
            {:error, %{kind: :build_failed, tail: String.slice(output, -3000, 3000)}}

          {:error, reason} ->
            {:error, %{kind: :package, reason: reason}}

          false ->
            {:error, %{kind: :missing_pbw}}
        end
      rescue
        error ->
          {:error, %{kind: :exception, message: Exception.message(error)}}
      after
        File.rm_rf(workspace)
      end

    elapsed = System.monotonic_time(:second) - t0

    case outcome do
      {:ok, meta} ->
        IO.puts("OK   #{template} (#{elapsed}s, #{meta.bytes} B, #{length(meta.platforms)} platforms)")
        {template, :ok, meta}

      {:error, meta} ->
        IO.puts("FAIL #{template} (#{elapsed}s) #{inspect(meta, limit: :infinity)}")
        {template, :error, meta}
    end
  end)

failed = Enum.filter(results, fn {_t, status, _m} -> status == :error end)
total = System.monotonic_time(:second) - started

IO.puts("")
IO.puts("Finished in #{total}s: #{length(templates) - length(failed)}/#{length(templates)} passed")

if failed != [] do
  IO.puts("\nFailures:")
  Enum.each(failed, fn {template, _, meta} -> IO.puts("  - #{template}: #{inspect(meta)}") end)
  System.halt(1)
end
