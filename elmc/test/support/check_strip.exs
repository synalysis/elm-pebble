elmc_root = Path.expand("../..", __DIR__)
out = Path.join(elmc_root, "tmp/wasm_runtime_prune_strip")
fixture = Path.join(elmc_root, "test/fixtures/rc_track_list_project")

File.rm_rf!(out)

for strip <- [false, true] do
  dir = out <> "_#{strip}"
  File.rm_rf!(dir)

  {:ok, _} =
    Elmc.compile(fixture,
      out_dir: dir,
      entry_module: "Main",
      strip_dead_code: strip,
      plan_ir_mode: :primary,
      targets: [:wasm],
      wasm_strict: false
    )

  manifest = dir |> Path.join("wasm/elmc_wasm.manifest.json") |> File.read!() |> Jason.decode!()
  imports = manifest["imports"] || []
  c = File.read!(Path.join(dir, "runtime/elmc_runtime.c"))
  json_imports = Enum.count(imports, &String.contains?(&1, "json"))
  json_c = length(Regex.scan(~r/elmc_json_decode/, c))

  IO.puts(
    "strip=#{strip} imports=#{length(imports)} json_imports=#{json_imports} json_c=#{json_c} functions=#{length(manifest["functions"] || [])}"
  )
end
