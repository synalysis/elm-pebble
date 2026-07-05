# Memory-isolated elmc compile for template parity prepare.
[project_dir, out_dir, strip_dead_code_raw | _] = System.argv()
strip_dead_code? = strip_dead_code_raw in ["true", "1"]

Application.ensure_all_started(:elmc)

base_opts = [
  entry_module: "Main",
  out_dir: out_dir,
  prune_runtime: false,
  prune_native_wrappers: true,
  pebble_int32: true,
  strip_dead_code: strip_dead_code?,
  prod: false
]

compile = fn opts ->
  Ide.Test.TemplateElmxElmcParity.ElmcHostHarness.compile!(project_dir, out_dir, opts)
end

compile_with_direct_render_only = fn ->
  compile.(Keyword.merge(base_opts, direct_render_only: true))
end

compile_without_direct_render_only = fn ->
  File.rm_rf!(out_dir)
  compile.(Keyword.merge(base_opts, direct_render_only: false))
end

result =
  try do
    case compile_with_direct_render_only.() do
      :ok ->
        :ok

      {:error, _} ->
        compile_without_direct_render_only.()
    end
  rescue
    error in ArgumentError ->
      if Exception.message(error) =~ "direct_render_only" do
        compile_without_direct_render_only.()
      else
        reraise error, __STACKTRACE__
      end
  end

case result do
  :ok -> IO.puts("ok")
  {:error, reason} -> IO.puts("error:#{inspect(reason)}") && System.halt(1)
end
