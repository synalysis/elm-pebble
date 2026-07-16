path = Path.expand("../../elm_pebble_dev/node_modules/elm-pages/src/Pages/Internal/Platform.elm", __DIR__)
source = File.read!(path)

fragment =
  source
  |> String.split("startNewGetLoad urlToGet ( model, effect ) =")
  |> Enum.at(1)
  |> then(fn rest ->
    rest
    |> String.split("\n\n\nclearLoadingFetchersAfterDataLoad")
    |> hd()
    |> String.trim()
  end)

IO.puts("body chars=#{String.length(fragment)}")

case ElmEx.Frontend.GeneratedExpressionParser.parse(fragment) do
  {:ok, expr} -> IO.puts("parse OK op=#{expr.op}")
  {:error, reason} -> IO.inspect(reason, label: "parse error")
end

prepared = ElmEx.Frontend.GeneratedExpressionParser.prepare_for_debug(fragment)
lines = String.split(prepared, "\n")

Enum.with_index(lines, 1)
|> Enum.each(fn {line, n} ->
  IO.puts("L#{n} len=#{String.length(line)} #{String.slice(line, 0, 80)}")
  if n == 1, do: IO.puts("L1 tail: ...#{String.slice(line, -120, 120)}")
end)

IO.inspect(ElmEx.Frontend.LetLayout.validate(prepared), label: "let_layout")
