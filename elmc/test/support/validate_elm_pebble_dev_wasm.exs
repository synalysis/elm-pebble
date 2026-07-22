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

# elm-3d-scene / WebGL is intentionally not WASM parity yet (see Route.Wasm docs).
# The live /wasm page still ships in the SPA; these stubs keep the rest of the
# site navigable until WebGL kernels are lowered.
webgl_stub_modules = MapSet.new([
  "BoundingBox3d",
  "Elm.Kernel.MJS",
  "Elm.Kernel.WebGL",
  "Scene3d",
  "Scene3d.Entity",
  "Scene3d.Mesh",
  "Scene3d.UnoptimizedShaders"
])

webgl_stub_pairs =
  MapSet.new([
    {"Browser.Events", "subscription"},
    {"Elm.Kernel.VirtualDom", "on"},
    # Plan names Float.Extra as module "Float" / name "Extra.interpolateFrom"
    {"Float", "Extra.interpolateFrom"}
  ])

allowed_stub? = fn entry ->
  mod = entry["module"] || ""
  name = entry["name"]

  MapSet.member?(webgl_stub_modules, mod) or
    String.starts_with?(mod, "Scene3d") or
    String.starts_with?(mod, "WebGL") or
    String.starts_with?(mod, "Elm.Kernel.MJS") or
    String.starts_with?(mod, "Elm.Kernel.WebGL") or
    MapSet.member?(webgl_stub_pairs, {mod, name})
end

unexpected_stubs = Enum.reject(stub_functions, allowed_stub?)

if unexpected_stubs != [] do
  IO.inspect(unexpected_stubs, label: "unexpected stub_functions")
  System.halt(1)
end

unexpected_skipped = Enum.reject(debug_skipped, allowed_stub?)

if unexpected_skipped != [] do
  IO.inspect(unexpected_skipped, label: "skipped (browser build)")
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

webgl_stubs = Enum.filter(stub_functions, allowed_stub?)

IO.puts("wasm validate OK: #{out}")
IO.puts("  stub_functions: #{length(stub_functions)} (webgl/scene allowed: #{length(webgl_stubs)})")
IO.puts("  skipped: #{length(debug_skipped)}")
IO.puts("  constructor_tags: #{map_size(constructor_tags)}")
