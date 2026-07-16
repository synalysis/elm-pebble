out =
  case System.get_env("ELMC_OUT_DIR") do
    nil ->
      IO.puts("ELMC_OUT_DIR required for validate_elm_pebble_dev_wasm.exs")
      System.halt(2)

    dir ->
      dir
  end

alias Elmc.Backend.Wasm.ProjectWriter

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

allowed_server_stubs = MapSet.new([])

unexpected_stubs =
  Enum.reject(stub_functions, fn entry ->
    MapSet.member?(allowed_server_stubs, {entry["module"], entry["name"]})
  end)

if unexpected_stubs != [] do
  IO.inspect(unexpected_stubs, label: "unexpected stub_functions")
  System.halt(1)
end

if debug_skipped != [] do
  IO.inspect(debug_skipped, label: "skipped (browser build)")
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

IO.puts("wasm validate OK: #{out}")
IO.puts("  stub_functions: #{length(stub_functions)} skipped: #{length(debug_skipped)}")
IO.puts("  constructor_tags: #{map_size(constructor_tags)}")
