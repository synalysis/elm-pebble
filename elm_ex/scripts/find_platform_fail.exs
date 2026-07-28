alias ElmEx.Frontend.GeneratedExpressionParser

frag =
  Path.expand(
    "../../elm_pebble_dev/node_modules/elm-pages/src/Pages/Internal/Platform.elm",
    __DIR__
  )
  |> File.read!()
  |> String.split("update config appMsg model =", parts: 2)
  |> Enum.at(1)
  |> String.split("\n\n\nfetchRouteData", parts: 2)
  |> hd()
  |> String.trim()

lines = String.split(frag, "\n")

first_fail =
  Enum.find(101..200, fn n ->
    chunk = lines |> Enum.take(n) |> Enum.join("\n")
    match?({:error, _}, GeneratedExpressionParser.parse(chunk))
  end)

IO.puts("first fail line count: #{first_fail}")

if first_fail do
  chunk = lines |> Enum.take(first_fail) |> Enum.join("\n")
  IO.inspect(GeneratedExpressionParser.parse(chunk), limit: 3)

  lines
  |> Enum.slice(first_fail - 5, 8)
  |> Enum.with_index(first_fail - 4)
  |> Enum.each(fn {l, n} -> IO.puts("#{n}: #{l}") end)
end

# full body
IO.puts("\nfull parse:")

case GeneratedExpressionParser.parse(frag) do
  {:ok, %{op: op}} -> IO.puts("OK op=#{op}")
  {:error, err} -> IO.inspect(err, limit: 3)
end
