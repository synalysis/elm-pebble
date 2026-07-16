repo_root = Path.expand("../../..", __DIR__)
elmc_root = Path.join(repo_root, "elmc")
app_root = Path.join(repo_root, "elm_pebble_dev")

out =
  case System.get_env("ELMC_OUT_DIR") do
    nil -> Path.join(elmc_root, "tmp/elm_pebble_dev_wasm")
    dir -> dir
  end

export_all? = System.get_env("ELMC_WASM_EXPORT_ALL") == "1"
link_wasm? = System.get_env("ELMC_LINK_WASM") != "0"

if System.get_env("ELMC_RM_RF") != "0" do
  File.rm_rf!(out)
end

compile_opts =
  %{
    out_dir: out,
    targets: [:wasm],
    web: true,
    entry_module: "Main",
    strip_dead_code: true,
    wasm_strict: false
  }
  |> then(fn opts ->
    if export_all?, do: Map.put(opts, :wasm_export_all, true), else: opts
  end)

case Elmc.compile(app_root, compile_opts) do
  {:ok, _} ->
    :ok

  {:error, reason} ->
    IO.inspect(reason, label: "compile failed")
    System.halt(1)
end

if link_wasm? and System.find_executable("wat2wasm") do
  alias Elmc.Backend.Wasm.ProjectWriter

  wat_path = ProjectWriter.wat_path(out)
  wasm_path = Path.join(out, "wasm/app.wasm")
  {output, code} = System.cmd("wat2wasm", [wat_path, "-o", wasm_path], stderr_to_stdout: true)

  if code != 0 do
    IO.puts("wat2wasm failed:\n#{output}")
    System.halt(1)
  end
end

out
