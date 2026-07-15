repo_root = Path.expand("../../..", __DIR__)
elmc_root = Path.join(repo_root, "elmc")
app_root = Path.join(repo_root, "elm_pebble_dev")
out = Path.join(elmc_root, "tmp/elm_pebble_dev_wasm")

File.rm_rf!(out)

case Elmc.compile(app_root, %{
       out_dir: out,
       targets: [:wasm],
       web: true,
       entry_module: "Main",
       strip_dead_code: true,
       wasm_strict: false
     }) do
  {:ok, _} ->
    :ok

  {:error, reason} ->
    IO.inspect(reason, label: "compile failed")
    System.halt(1)
end

manifest =
  out
  |> Path.join("wasm/elmc_wasm.manifest.json")
  |> File.read!()
  |> Jason.decode!()

imports = manifest["imports"] || []
functions = manifest["functions"] || []
closures = manifest["closures"] || []
skipped = manifest["skipped"] || []

IO.puts("elm_pebble_dev wasm build: #{out}")
IO.puts("  entry_export: #{manifest["entry_export"]}")
IO.puts("  functions: #{length(functions)} closures: #{length(closures)} skipped: #{length(skipped)}")
IO.puts("  imports: #{length(imports)}")
IO.puts("  runtime bytes: #{File.read!(Path.join(out, "runtime/elmc_runtime.c")) |> byte_size()}")

IO.inspect(Enum.take(imports, 20), label: "imports (first 20)")

json_imports = Enum.filter(imports, &String.contains?(&1, "json"))
IO.puts("  json imports: #{length(json_imports)}")

web_imports = Enum.filter(imports, &String.starts_with?(&1, "web."))
IO.puts("  web imports: #{length(web_imports)}")
IO.inspect(web_imports, label: "web imports")

list_imports = Enum.filter(imports, &String.contains?(&1, "list"))
IO.puts("  list imports: #{length(list_imports)}")

wat_path = Path.join(out, "wasm/elmc_generated.wat")
wasm_path = Path.join(out, "wasm/app.wasm")

if System.find_executable("wat2wasm") do
  {output, code} = System.cmd("wat2wasm", [wat_path, "-o", wasm_path], stderr_to_stdout: true)

  if code == 0 do
    IO.puts("  linked wasm: #{wasm_path} (#{File.stat!(wasm_path).size} bytes)")
  else
    IO.puts("wat2wasm failed:\n#{output}")
    System.halt(1)
  end
else
  IO.puts("  wat2wasm not found; skipped app.wasm link")
end

IO.puts("")
IO.puts("Page-data probe (from elmc/):")
IO.puts("  node test/support/wasm_browser_page_data_probe_runner.mjs tmp/elm_pebble_dev_wasm")
