out =
  case System.get_env("ELMC_OUT_DIR") do
    nil ->
      IO.puts("ELMC_OUT_DIR required for validate_elm_pebble_dev_wasm.exs")
      System.halt(2)

    dir ->
      dir
  end

alias Elmc.Backend.Wasm.ProjectWriter

# `mix run` of this script does not load test/support beams; require the helper.
Code.require_file(Path.join(__DIR__, "elm_pebble_dev_wasm_compile.ex"))
alias Elmc.Test.ElmPebbleDevWasmCompile

unless File.regular?(ProjectWriter.manifest_path(out)) do
  IO.puts("missing wasm manifest: #{ProjectWriter.manifest_path(out)}")
  System.halt(1)
end

manifest =
  out
  |> ProjectWriter.manifest_path()
  |> File.read!()
  |> Jason.decode!()

stub_functions = ProjectWriter.stub_functions(out)

debug_skipped =
  case File.read(ProjectWriter.debug_manifest_path(out)) do
    {:ok, body} -> body |> Jason.decode!() |> Map.get("skipped", [])
    _ -> []
  end

unexpected_stubs = Enum.reject(stub_functions, &ElmPebbleDevWasmCompile.allowed_host_bridge_stub?/1)

if unexpected_stubs != [] do
  IO.inspect(unexpected_stubs, label: "unexpected stub_functions")
  System.halt(1)
end

unexpected_skipped = Enum.reject(debug_skipped, &ElmPebbleDevWasmCompile.allowed_host_bridge_stub?/1)

if unexpected_skipped != [] do
  IO.inspect(unexpected_skipped, label: "skipped (browser build)")
  System.halt(1)
end

if Enum.any?(debug_skipped, fn entry -> entry["reason"] == "fusion_only" end) do
  IO.inspect(debug_skipped, label: "fusion_only skips (forbidden on web-reachable fns)")
  System.halt(1)
end

constructor_tags = manifest["constructor_tags"] || %{}

if constructor_tags == %{} do
  IO.puts("constructor_tags missing from wasm manifest")
  System.halt(1)
end

if manifest["entry_export"] != "elmc_fn_Main_main" do
  IO.puts("unexpected entry_export: #{inspect(manifest["entry_export"])}")
  System.halt(1)
end

webgl_stubs = Enum.filter(stub_functions, &ElmPebbleDevWasmCompile.allowed_host_bridge_stub?/1)

IO.puts("wasm validate OK: #{out}")
IO.puts("  stub_functions: #{length(stub_functions)} (leftover host bridges: #{length(webgl_stubs)})")
IO.puts("  skipped: #{length(debug_skipped)}")
IO.puts("  constructor_tags: #{map_size(constructor_tags)}")
