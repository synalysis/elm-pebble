cache_dir = Path.expand("../test/fixtures/simple_project/.elmc-cache/ir", __DIR__)
files = Path.wildcard(Path.join(cache_dir, "**/*")) |> Enum.filter(&File.regular?/1)
IO.puts("cache files=#{length(files)}")
Enum.each(files, fn path ->
  bin = File.read!(path)
  try do
    term = :erlang.binary_to_term(bin)
    decls = Map.get(term, :declarations) || []
    g = Enum.find(decls, &(Map.get(&1, :name) == "getByWeight"))
    if g do
      IO.puts("HIT #{path}")
      IO.puts("  args=#{inspect(g.args)}")
      IO.puts("  subject=#{inspect(get_in(g.expr, [:subject]))}")
    end
  rescue
    _ -> :ok
  end
end)
