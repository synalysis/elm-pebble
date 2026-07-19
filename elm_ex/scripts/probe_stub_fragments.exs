alias ElmEx.Frontend.GeneratedExpressionParser

probe = fn label, path, start_marker, stop_marker ->
  source = File.read!(path)

  fragment =
    source
    |> String.split(start_marker, parts: 2)
    |> case do
      [_, rest] -> rest |> String.split(stop_marker, parts: 2) |> hd() |> String.trim()
      _ -> raise "start marker not found for #{label}: #{start_marker}"
    end

  IO.puts("\n=== #{label} ===")

  case GeneratedExpressionParser.parse(fragment) do
    {:ok, %{op: op}} ->
      IO.puts("OK op=#{op}")

    {:error, reason} ->
      IO.puts("FAIL #{inspect(reason, limit: 4)}")
      prep = GeneratedExpressionParser.prepare_for_debug(fragment)
      slug = label |> String.replace(".", "_") |> String.replace(" ", "_")
      File.write!("/tmp/stub_probe_#{slug}.prep", prep)

      prep
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.take(20)
      |> Enum.each(fn {l, n} -> IO.puts("#{n}: #{String.slice(l, 0, 120)}") end)
  end
end

platform =
  "/home/ape/projects/elm-pebble/elm_pebble_dev/node_modules/elm-pages/src/Pages/Internal/Platform.elm"

platform_frag =
  platform
  |> File.read!()
  |> String.split("\n")
  |> Enum.slice(267, 847)
  |> Enum.join("\n")
  |> String.trim()

IO.puts("\n=== Platform.update ===")

case GeneratedExpressionParser.parse(platform_frag) do
  {:ok, %{op: op}} ->
    IO.puts("OK op=#{op}")

  {:error, reason} ->
    IO.puts("FAIL #{inspect(reason, limit: 4)}")
    prep = GeneratedExpressionParser.prepare_for_debug(platform_frag)
    File.write!("/tmp/stub_probe_Platform_update.prep", prep)
end

layout_path =
  "/home/ape/.elm/0.19.1/packages/jcberentsen/elm-wiring-diagrams/5.4.7/src/Internal/Cartesian/Layout.elm"

probe.(
  "Cartesian.Layout.layout",
  layout_path,
  "layout config c =",
  "\n\n\ncomposeLayout"
)

pattern_path = "/home/ape/.elm/0.19.1/packages/justinmimbs/date/4.1.0/src/Pattern.elm"

probe.(
  "Pattern.finalize",
  pattern_path,
  "finalize =",
  "\n\n\n"
)
