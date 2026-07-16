defmodule Elmc.Test.ElmPebbleDevWasmServe do
  @moduledoc false

  @spec prepare_playwright_serve_root!(String.t(), String.t(), String.t(), [String.t()]) :: :ok
  def prepare_playwright_serve_root!(serve_root, wasm_build, dist_root, extra_route_dirs \\ []) do
    File.rm_rf!(serve_root)
    File.mkdir_p!(serve_root)

    link!(Path.join(dist_root, "index.html"), Path.join(serve_root, "index.html"))

    for route_dir <- extra_route_dirs do
      src = Path.join(dist_root, route_dir)
      dest = Path.join(serve_root, route_dir)

      if File.dir?(src) do
        File.mkdir_p!(Path.dirname(dest))
        link!(Path.join(src, "index.html"), Path.join(dest, "index.html"))
      end
    end

    link!(Path.join(wasm_build, "host"), Path.join(serve_root, "wasm-web/host"))
    link!(Path.join(wasm_build, "wasm"), Path.join(serve_root, "wasm-web/wasm"))
    link!(Path.join(wasm_build, "runtime"), Path.join(serve_root, "wasm-web/runtime"))

    :ok
  end

  defp link!(source, dest) do
    dest_parent = Path.dirname(dest)
    File.mkdir_p!(dest_parent)
    File.ln_s!(Path.expand(source), dest)
  end
end
