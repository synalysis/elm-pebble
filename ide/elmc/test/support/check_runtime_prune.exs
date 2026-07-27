elmc_root = Path.expand("../..", __DIR__)
out = Path.join(elmc_root, "tmp/wasm_runtime_prune_check")
fixture = Path.join(elmc_root, "test/fixtures/rc_track_list_project")

File.rm_rf!(out)

{:ok, _} =
  Elmc.compile(fixture,
    out_dir: out,
    entry_module: "Main",
    strip_dead_code: false,
    plan_ir_mode: :primary,
    targets: [:wasm],
    wasm_strict: false
  )

manifest =
  out
  |> Path.join("wasm/elmc_wasm.manifest.json")
  |> File.read!()
  |> Jason.decode!()

imports = manifest["imports"] || []
IO.puts("imports count: #{length(imports)}")
IO.inspect(Enum.filter(imports, &String.contains?(&1, "json")), label: "json imports")

c = File.read!(Path.join(out, "runtime/elmc_runtime.c"))
IO.puts("runtime bytes: #{byte_size(c)}")
IO.puts("elmc_json_decode occurrences: #{length(Regex.scan(~r/elmc_json_decode/, c))}")

c_files = Path.wildcard(Path.join(out, "**/*.c"))
IO.puts("c files in out: #{length(c_files)}")
IO.inspect(c_files, label: "c files")
