# Usage: mix run scripts/probe_list_repeat_compile.exs [strip|nostrip]
# WARNING: nostrip compiles all of elm/core (~787 functions) and can OOM (multi-GB).
alias ElmEx.IR.Lowerer
alias ElmEx.Frontend.Bridge

strip? = System.argv() != ["nostrip"]

minimal_json = Jason.encode!(%{
  "type" => "application",
  "source-directories" => ["src"],
  "elm-version" => "0.19.1",
  "dependencies" => %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}}
})

source = """
module Main exposing (board, len)

board : List Int
board =
    List.repeat 140 0

len : Int
len =
    List.length board
"""

project_dir = Path.expand("test/tmp/plan_fold_probe", __DIR__)
out_dir = Path.expand("test/tmp/plan_fold_out", __DIR__)
File.rm_rf!(project_dir)
File.rm_rf!(out_dir)
File.mkdir_p!(Path.join(project_dir, "src"))
File.write!(Path.join(project_dir, "src/Main.elm"), source)
File.write!(Path.join(project_dir, "elm.json"), minimal_json <> "\n")

opts =
  Map.merge(
    %{out_dir: out_dir, entry_module: "Main", plan_ir_mode: :primary, plan_ir_strict: true},
  %{strip_dead_code: strip?}
  )
IO.puts("compile strip_dead_code=#{strip?}")

{us, result} = :timer.tc(fn -> Elmc.compile(project_dir, opts) end)
IO.puts("compile #{div(us, 1000)}ms #{inspect(elem(result, 0))}")

case result do
  {:ok, _} ->
    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    IO.puts("c bytes=#{byte_size(c)}")
    IO.puts("140<=0? #{String.contains?(c, "140 <= 0")}")
    IO.puts("plan_list_int? #{String.contains?(c, "plan_list_int_values_")}")
    IO.puts("[140]? #{String.contains?(c, "[140]")}")

  {:error, err} ->
    IO.inspect(err, limit: :infinity)
end
