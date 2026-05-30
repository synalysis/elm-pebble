root = Path.dirname(Path.expand(__ENV__.file))
repo_root = Path.dirname(root)
git_path = "elm_executor/lib/elm_executor/runtime/semantic_executor.ex"
{text, 0} = System.cmd("git", ["show", "HEAD:#{git_path}"], cd: repo_root)
lines = String.split(text, "\n", parts: :infinity)
lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
to_body = fn slice -> Enum.map(slice, &(&1 <> "\n")) |> IO.iodata_to_binary() end

take_slices = fn slices ->
  Enum.flat_map(slices, fn {start, finish} ->
    Enum.slice(lines, start - 1, finish - start + 1)
  end)
end

execution_body = take_slices.([{124, 1084}, {4476, 4831}]) |> to_body.()
IO.puts("raw: #{byte_size(execution_body)}")

execution_public = ["map_value", "generic_map_value", "entry_module_name"]

execution_body =
  Enum.reduce(execution_public, execution_body, fn name, acc ->
    String.replace(acc, "defp #{name}(", "def #{name}(")
  end)

execution_body =
  [
    {"derive_view_tree", "View"},
    {"derive_view_output", "View"},
    {"evaluate_runtime_view_tree", "View"},
    {"annotate_view_output_sources", "View"}
  ]
  |> Enum.concat(
    Enum.map(
      [
        "source_core_ir_fallback",
        "evaluator_context",
        "vector_resource_indices_context",
        "bitmap_resource_indices_context",
        "launch_context_from_model",
        "normalize_runtime_model_by_declared_type",
        "enrich_runtime_model_for_view",
        "normalize_launch_context"
      ],
      &{&1, "View"}
    )
  )
  |> Enum.reduce(execution_body, fn {fn_name, mod}, acc ->
    String.replace(acc, "#{fn_name}(", "#{mod}.#{fn_name}(")
  end)

IO.puts("after: #{byte_size(execution_body)}")
IO.puts(String.slice(execution_body, 0, 120))
