Mix.Task.run("app.start")

alias Ide.ProjectTemplates
alias Ide.TemplatePbwGate

templates = ProjectTemplates.template_keys()
started = System.monotonic_time(:second)

results = TemplatePbwGate.run_all()

Enum.each(results, fn
  {template, :ok, meta} ->
    IO.puts(
      "OK   #{template} (#{meta.elapsed_s}s, #{meta.bytes} B, #{length(meta.platforms)} platforms)"
    )

  {template, :error, meta} ->
    IO.puts("FAIL #{template} (#{meta.elapsed_s}s) #{inspect(meta, limit: :infinity)}")
end)

failed = Enum.filter(results, fn {_t, status, _m} -> status == :error end)
total = System.monotonic_time(:second) - started

IO.puts("")
IO.puts("Finished in #{total}s: #{length(templates) - length(failed)}/#{length(templates)} passed")

if failed != [] do
  IO.puts("\nFailures:")

  Enum.each(failed, fn {template, _, meta} ->
    IO.puts("  - #{template}:")
    IO.puts(TemplatePbwGate.format_failure(meta))
  end)

  System.halt(1)
end
