repo_root = Path.expand("../../..", __DIR__)
elmc_root = Path.join(repo_root, "elmc")

{out, _} = Code.eval_file(Path.join(__DIR__, "compile_elm_pebble_dev_wasm.exs"))

System.put_env("ELMC_OUT_DIR", out)

{_, _} = Code.eval_file(Path.join(__DIR__, "validate_elm_pebble_dev_wasm.exs"))

alias Elmc.Backend.Wasm.ProjectWriter

manifest =
  out
  |> ProjectWriter.manifest_path()
  |> File.read!()
  |> Jason.decode!()

imports = manifest["imports"] || []
closures = manifest["closures"] || []
stub_functions = ProjectWriter.stub_functions(out)

debug_skipped =
  case File.read(ProjectWriter.debug_manifest_path(out)) do
    {:ok, body} -> body |> Jason.decode!() |> Map.get("skipped", [])
    _ -> []
  end

IO.puts("elm_pebble_dev wasm build: #{out}")
IO.puts("  entry_export: #{manifest["entry_export"]}")
IO.puts("  closures: #{length(closures)} skipped: #{length(debug_skipped)}")
IO.puts("  stub_functions: #{length(stub_functions)}")
IO.puts("  imports: #{length(imports)}")
IO.puts("  constructor_tags: #{map_size(manifest["constructor_tags"] || %{})}")
IO.puts("  runtime bytes: #{File.read!(Path.join(out, "runtime/elmc_runtime.c")) |> byte_size()}")

wasm_path = Path.join(out, "wasm/app.wasm")

if File.regular?(wasm_path) do
  IO.puts("  linked wasm: #{wasm_path} (#{File.stat!(wasm_path).size} bytes)")
else
  IO.puts("  linked wasm: (missing — wat2wasm not run or not found)")
end

IO.puts("")
IO.puts("Page-data probe (from elmc/):")
IO.puts("  node test/support/wasm_browser_page_data_probe_runner.mjs tmp/elm_pebble_dev_wasm")
