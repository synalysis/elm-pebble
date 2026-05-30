# Regenerate ViewTree split. Run from ide/: mix run scripts/split_view_tree.exs

root = Path.dirname(Path.dirname(Path.expand(__ENV__.file)))
src_path = Path.join(root, "lib/ide/debugger/elm_introspect/view_tree.ex")
lines = src_path |> File.read!() |> String.split("\n", trim: false)

# Drop trailing empty line from split if file ends with newline
lines =
  case lines do
    ["" | rest] when rest == [] -> []
    ls -> Enum.drop(ls, -1)
  end

structure_common = """
  alias ElmEx.Frontend.Module
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.ElmIntrospect.ViewTree
  alias Ide.Debugger.ElmIntrospect.ViewTree.Support
  alias Ide.Debugger.ElmIntrospect.Types

"""

operators_common = """
  alias Ide.Debugger.ElmIntrospect.ViewTree
  alias Ide.Debugger.ElmIntrospect.ViewTree.Structure
  alias Ide.Debugger.ElmIntrospect.ViewTree.Support
  alias Ide.Debugger.ElmIntrospect.Types

"""

parent_common = """
  alias ElmEx.Frontend.Module
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.ElmIntrospect.ViewTree.Operators
  alias Ide.Debugger.ElmIntrospect.ViewTree.Structure
  alias Ide.Debugger.ElmIntrospect.Types
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types, as: DebuggerTypes

"""

slice = fn ranges ->
  Enum.flat_map(ranges, fn {a, b} -> Enum.slice(lines, a - 1, b - a + 1) end)
  |> Enum.map(&(&1 <> "\n"))
  |> IO.iodata_to_binary()
end

structure_ranges = [
  {11, 24},
  {174, 184},
  {202, 444},
  {1096, 1144}
]

operator_ranges = [{507, 827}]

parent_ranges = [
  {17, 175},
  {443, 506},
  {828, 1018}
]

structure_body = slice.(structure_ranges)
operator_body = slice.(operator_ranges)
parent_body = slice.(parent_ranges)

structure_public = [
  "function_type_key",
  "return_type_from_signature",
  "render_op_function_return_type?",
  "view_tree_call_returns_ui_node_from_target?",
  "view_tree_call_return_kind",
  "maybe_put_view_tree_return_kind",
  "view_tree_call_target_name",
  "view_tree_call_target",
  "source_call_arg_names",
  "resolve_source_call",
  "resolve_qualified_source_call",
  "resolve_view_tree_call_target",
  "call_tree_arity"
]

structure_body =
  Enum.reduce(structure_public, structure_body, fn name, acc ->
    String.replace(acc, "defp #{name}(", "def #{name}(")
  end)

structure_body =
  structure_body
  |> String.replace("ui_node_type_signature?(", "ViewTree.ui_node_type_signature?(")
  |> String.replace("ViewTree.ViewTree.ui_node_type_signature?(", "ViewTree.ui_node_type_signature?(")
  |> String.replace(
    "runtime_drawable_view_root_type?(view_type_name(return_type))",
    "ViewTree.runtime_drawable_view_root_type?(Support.view_type_name(return_type))"
  )
  |> String.replace("put_module_alias(", "Support.put_module_alias(")
  |> String.replace("module_short_name(", "Support.module_short_name(")

operator_body =
  operator_body
  |> String.replace("defp expr_to_view_tree", "def expr_to_view_tree")
  |> String.replace("def build_view_tree", "def build_view_tree")
  |> String.replace("view_tree_unknown()", "ViewTree.view_tree_unknown()")
  |> String.replace("maybe_put_view_tree_return_kind(", "Structure.maybe_put_view_tree_return_kind(")
  |> String.replace("source_call_arg_names(", "Structure.source_call_arg_names(")
  |> String.replace("view_tree_call_target_name(", "Structure.view_tree_call_target_name(")

parent_body =
  parent_body
  |> String.replace(
    "view_tree_call_returns_ui_node_from_target?(view_tree_call_target(node), call_tree_arity(node), ei)",
    "Structure.view_tree_call_returns_ui_node_from_target?(Structure.view_tree_call_target(node), call_tree_arity(node), ei)"
  )
  |> String.replace(
    "if render_op_function_return_type?(signature) do",
    "if Structure.render_op_function_return_type?(signature) do"
  )
  |> String.replace(
    "Map.put(acc, key, expr_to_view_tree(expr, 0, 40, api_metadata))",
    "Map.put(acc, key, Operators.build_view_tree(expr, api_metadata))"
  )
  |> String.replace("|> ViewTree.build_view_tree(api_metadata)", "|> Operators.build_view_tree(api_metadata)")

operators_existing = File.read!(Path.join(root, "lib/ide/debugger/elm_introspect/view_tree/operators.ex"))

operators_prefix =
  operators_existing
  |> String.split("  @spec normalize_view_expr")
  |> hd()
  |> String.trim_trailing()

operators_mod = """
#{operators_prefix}

  alias Ide.Debugger.ElmIntrospect.ViewTree.Structure

#{operator_body}end
"""

structure_mod = """
defmodule Ide.Debugger.ElmIntrospect.ViewTree.Structure do
  @moduledoc false

#{structure_common}#{structure_body}end
"""

parent_header = """
defmodule Ide.Debugger.ElmIntrospect.ViewTree do
  @moduledoc false

#{parent_common}"""

view_tree_call_returns = """
  @spec view_tree_call_returns_ui_node?(Types.view_tree_node(), Types.elm_introspect()) :: boolean()
  defp view_tree_call_returns_ui_node?(node, ei) when is_map(node) and is_map(ei) do
    case Map.get(node, "return_kind") do
      "ui_node" -> true
      "render_op" -> false
      _ ->
        Structure.view_tree_call_returns_ui_node_from_target?(
          Structure.view_tree_call_target(node),
          Structure.call_tree_arity(node),
          ei
        )
    end
  end

  defp view_tree_call_returns_ui_node?(_, _), do: false

"""

parent_mod = parent_header <> view_tree_call_returns <> parent_body <> """
  defdelegate from_view_expr(expr, api_metadata), to: Operators
  defdelegate unknown(), to: Operators
  defdelegate build_view_tree(expr, api_metadata), to: Operators
end
"""

# Fix duplicate view_tree_unknown @spec if present in parent slice
parent_mod = String.replace(parent_mod, "@spec view_tree_unknown() :: Types.view_tree()\n  @spec view_tree_unknown()", "@spec view_tree_unknown()")

structure_path = Path.join(root, "lib/ide/debugger/elm_introspect/view_tree/structure.ex")
File.write!(structure_path, structure_mod)

if System.get_env("STRUCTURE_ONLY") == "1" do
  IO.puts("ViewTree structure.ex written (STRUCTURE_ONLY).")
else
  File.write!(Path.join(root, "lib/ide/debugger/elm_introspect/view_tree/operators.ex"), operators_mod)
  File.write!(src_path, parent_mod)
  IO.puts("ViewTree split written.")
end
