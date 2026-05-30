# Regenerate SemanticExecutor split from monolithic semantic_executor.ex in git.
# Run from elm_executor/: elixir scripts/split_semantic_executor.exs

root = Path.dirname(Path.dirname(Path.expand(__ENV__.file)))
repo_root = Path.dirname(root)
src = Path.join(root, "lib/elm_executor/runtime/semantic_executor.ex")
git_path = "elm_executor/lib/elm_executor/runtime/semantic_executor.ex"

text =
  case System.cmd("git", ["show", "HEAD:#{git_path}"], cd: repo_root, stderr_to_stdout: true) do
    {body, 0} -> body
    {err, _} -> raise "read monolith from git failed: #{err}"
  end

lines = String.split(text, "\n", parts: :infinity)
lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines

common =
  lines
  |> Enum.slice(9, 9)
  |> Enum.map(&(&1 <> "\n"))
  |> IO.iodata_to_binary()

wrap = fn name, body, extra ->
  """
  defmodule ElmExecutor.Runtime.SemanticExecutor.#{name} do
    @moduledoc false
    @dialyzer :no_match

  #{extra}#{common}#{body}end
  """
end

to_body = fn slice -> Enum.map(slice, &(&1 <> "\n")) |> IO.iodata_to_binary() end

# 1-based line numbers from original file
execution_slices = [{124, 1084}, {4476, 4831}]
view_slices = [{1085, 3659}, {4284, 4474}]
eval_slices = [{3661, 4283}]

take_slices = fn slices ->
  Enum.flat_map(slices, fn {start, finish} ->
    Enum.slice(lines, start - 1, finish - start + 1)
  end)
end

execution_body = take_slices.(execution_slices) |> to_body.()
view_body = take_slices.(view_slices) |> to_body.()
eval_body = take_slices.(eval_slices) |> to_body.()

execution_public = ["map_value", "generic_map_value", "entry_module_name"]

execution_view_helpers = [
  "source_core_ir_fallback",
  "evaluator_context",
  "vector_resource_indices_context",
  "bitmap_resource_indices_context",
  "launch_context_from_model",
  "normalize_runtime_model_by_declared_type",
  "enrich_runtime_model_for_view",
  "normalize_launch_context"
]

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
  |> Enum.concat(Enum.map(execution_view_helpers, &{&1, "View"}))
  |> Enum.reduce(execution_body, fn {fn_name, mod}, acc ->
    String.replace(acc, "#{fn_name}(", "#{mod}.#{fn_name}(")
  end)

view_api = to_body.(Enum.slice(lines, 35, 88))
eval_api = to_body.(Enum.slice(lines, 19, 16))

view_tree_eval_public = [
  "node_children",
  "field_value_int",
  "eval_view_color",
  "eval_view_int",
  "eval_view_text",
  "eval_tree_expr_value",
  "record_point_coords_from_node",
  "eval_tree_expr_int",
  "view_var_name",
  "view_binding_value",
  "apply_let_view_binding",
  "selected_if_branch",
  "normalize_text_value",
  "model_value_by_key",
  "point_coords_from_value",
  "extract_ints",
  "evaluate_view_tree_value"
]

view_public_for_execution =
  execution_view_helpers ++
    [
      "derive_view_tree",
      "derive_view_output",
      "annotate_view_output_sources",
      "evaluate_runtime_view_tree"
    ]

eval_body =
  Enum.reduce(view_tree_eval_public ++ execution_public, eval_body, fn name, acc ->
    String.replace(acc, "defp #{name}(", "def #{name}(")
  end)

eval_body =
  Enum.reduce(execution_public, eval_body, fn name, acc ->
    String.replace(acc, "#{name}(", "Execution.#{name}(")
  end)

view_body =
  Enum.reduce(view_public_for_execution, view_body, fn name, acc ->
    String.replace(acc, "defp #{name}(", "def #{name}(")
  end)

dir = Path.join(root, "lib/elm_executor/runtime/semantic_executor")
File.mkdir_p!(dir)

view_body =
  Enum.reduce(view_tree_eval_public, view_body, fn name, acc ->
    String.replace(acc, "#{name}(", "ViewTreeEval.#{name}(")
  end)

view_body =
  Enum.reduce(execution_public, view_body, fn name, acc ->
    String.replace(acc, "#{name}(", "Execution.#{name}(")
  end)

view_body =
  Enum.reduce(view_tree_eval_public, view_body, fn name, acc ->
    String.replace(acc, "@spec #{name}", "@spec _unused_#{name}")
  end)

view_body = String.replace(view_body, "@spec ViewTreeEval.", "@spec ")
view_body = String.replace(view_body, "@spec Execution.", "@spec ")
view_body = String.replace(view_body, ~r/  @spec _unused_[a-z0-9_]+\(.*\n/, "")

execution_body =
  execution_body
  |> String.replace("@spec View.", "@spec ")
  |> String.replace(~r/  @spec _unused_[a-z0-9_]+\(.*\n/, "")

eval_body =
  eval_body
  |> String.replace("@spec Execution.", "@spec ")
  |> String.replace(~r/  @spec _unused_[a-z0-9_]+\(.*\n/, "")

unless byte_size(execution_body) > 10_000 do
  raise "execution_body too small (#{byte_size(execution_body)} bytes); check git monolith path"
end

File.write!(
  Path.join(dir, "execution.ex"),
  wrap.("Execution", execution_body, "  alias ElmExecutor.Runtime.SemanticExecutor.View\n\n")
)

File.write!(
  Path.join(dir, "view.ex"),
  wrap.(
    "View",
    view_api <> view_body,
    "  alias ElmExecutor.Runtime.SemanticExecutor.Execution\n  alias ElmExecutor.Runtime.SemanticExecutor.ViewTreeEval\n\n"
  )
)
File.write!(
  Path.join(dir, "view_tree_eval.ex"),
  wrap.("ViewTreeEval", eval_api <> eval_body, "  alias ElmExecutor.Runtime.SemanticExecutor.Execution\n\n")
)

facade_header = Enum.slice(lines, 0, 8) |> Enum.map(&(&1 <> "\n")) |> IO.iodata_to_binary()

facade =
  facade_header <>
    """
      alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
      alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes
      alias ElmExecutor.Runtime.SemanticExecutor.Execution
      alias ElmExecutor.Runtime.SemanticExecutor.View
      alias ElmExecutor.Runtime.SemanticExecutor.ViewTreeEval

      @spec evaluate_view_tree_value(map(), map(), map()) :: EvalTypes.runtime_value() | nil
      defdelegate evaluate_view_tree_value(node, runtime_model, eval_context \\\\ %{}), to: ViewTreeEval

      @spec derive_view_output_preview(map(), map(), map()) :: [map()]
      defdelegate derive_view_output_preview(view_tree, runtime_model, eval_context \\\\ %{}), to: View

      @spec derive_view_output_for_runtime_model(map(), map()) :: %{
              view_output: [map()],
              view_tree: map()
            }
      defdelegate derive_view_output_for_runtime_model(runtime_model, eval_context), to: View

      @spec drawable_view_tree?(map()) :: boolean()
      defdelegate drawable_view_tree?(tree), to: View

      @spec drawable_view_tree_types() :: [String.t()]
      defdelegate drawable_view_tree_types(), to: View

      @spec execute(SemTypes.execution_request() | map()) ::
              {:ok, SemTypes.execution_result()} | {:error, SemTypes.exec_error()}
      defdelegate execute(request), to: Execution
    end
    """

File.write!(src, facade)
IO.puts("split complete")
