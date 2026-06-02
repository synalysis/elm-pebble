defmodule ElmEx.DebuggerContract.ViewTree.Structure do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.DebuggerContract.ViewTree
  alias ElmEx.DebuggerContract.ViewTree.Support
  alias ElmEx.DebuggerContract.Types

  @spec function_type_key(String.t(), String.t(), non_neg_integer()) :: String.t()
  def function_type_key(module_name, function_name, arity)
      when is_binary(module_name) and is_binary(function_name) and is_integer(arity) do
    module_name <> "|" <> function_name <> "|" <> Integer.to_string(arity)
  end

  @spec return_type_from_signature(String.t()) :: String.t()
  def return_type_from_signature(type) when is_binary(type) do
    type
    |> String.split("->")
    |> List.last()
    |> to_string()
    |> String.trim()
  end

  @spec render_op_function_return_type?(String.t()) :: boolean()
  def render_op_function_return_type?(signature) when is_binary(signature) do
    normalized =
      signature
      |> String.replace(~r/\s+/, "")
      |> String.downcase()

    String.match?(normalized, ~r/list.*renderop/) or String.match?(normalized, ~r/->renderop$/)
  end

  def render_op_function_return_type?(_signature), do: false

  @spec view_tree_call_returns_ui_node_from_target?(
          String.t() | nil,
          non_neg_integer(),
          Types.elm_introspect()
        ) ::
          boolean()
  def view_tree_call_returns_ui_node_from_target?(target, arity, ei)
      when is_binary(target) and is_integer(arity) and is_map(ei) do
    with types when is_map(types) <- Map.get(ei, "function_types"),
         {module_name, function_name} <- resolve_view_tree_call_target(target, ei),
         key <- function_type_key(module_name, function_name, arity),
         type when is_binary(type) <-
           Map.get(types, key) || find_function_type_signature(types, module_name, function_name) do
      ViewTree.ui_node_type_signature?(return_type_from_signature(type)) or
        render_ops_to_ui_node_signature?(type)
    else
      _ -> false
    end
  end

  def view_tree_call_returns_ui_node_from_target?(_target, _arity, _ei), do: false

  @spec view_tree_call_return_kind(String.t(), non_neg_integer(), Types.elm_introspect()) ::
          String.t() | nil
  def view_tree_call_return_kind(target, arity, api_metadata)
      when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    cond do
      view_tree_call_returns_ui_node_from_target?(target, arity, api_metadata) ->
        "ui_node"

      scene_root_call_return_kind?(target, arity, api_metadata) ->
        "ui_node"

      render_op_call_from_target?(target, arity, api_metadata) ->
        "render_op"

      true ->
        infer_local_function_return_kind(target, arity, api_metadata)
    end
  end

  def view_tree_call_return_kind(_target, _arity, _api_metadata), do: nil

  @spec infer_local_function_return_kind(String.t(), non_neg_integer(), Types.elm_introspect()) ::
          String.t() | nil
  defp infer_local_function_return_kind(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    with %Module{} = mod <- Map.get(api_metadata, :module_ref),
         {module_name, function_name} <- resolve_view_tree_call_target(target, api_metadata),
         true <- module_name == mod.name,
         %{args: args, expr: expr} <-
           ElmEx.DebuggerContract.find_function_definition(mod, function_name),
         true <- length(List.wrap(args)) == arity do
      infer_expr_return_kind(expr, api_metadata)
    else
      _ -> nil
    end
  end

  defp infer_local_function_return_kind(_target, _arity, _api_metadata), do: nil

  @spec infer_expr_return_kind(Types.ast_expr(), Types.binding_map()) :: String.t() | nil
  defp infer_expr_return_kind(expr, api_metadata) when is_map(expr) and is_map(api_metadata) do
    case expr do
      %{op: :qualified_call, target: target, args: args} when is_list(args) ->
        view_tree_call_return_kind(target, length(args), api_metadata)

      %{op: :call, name: name, args: args} when is_list(args) ->
        view_tree_call_return_kind(name, length(args), api_metadata)

      %{op: :expr, expr: inner} ->
        infer_expr_return_kind(inner, api_metadata)

      %{op: :let_in, in_expr: inner} ->
        infer_expr_return_kind(inner, api_metadata)

      _ ->
        nil
    end
  end

  defp infer_expr_return_kind(_expr, _api_metadata), do: nil

  @spec render_op_call_from_target?(String.t(), non_neg_integer(), Types.elm_introspect()) ::
          boolean()
  defp render_op_call_from_target?(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    with types when is_map(types) <- Map.get(api_metadata, "function_types"),
         {module_name, function_name} <- resolve_view_tree_call_target(target, api_metadata),
         key <- function_type_key(module_name, function_name, arity),
         type when is_binary(type) <-
           Map.get(types, key) || find_function_type_signature(types, module_name, function_name) do
      render_op_function_return_type?(type)
    else
      _ -> false
    end
  end

  defp render_op_call_from_target?(_target, _arity, _api_metadata), do: false

  @spec scene_root_call_return_kind?(String.t(), non_neg_integer(), Types.elm_introspect()) ::
          boolean()
  defp scene_root_call_return_kind?(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    with types when is_map(types) <-
           Map.get(api_metadata, "function_types") || Map.get(api_metadata, :function_types),
         {module_name, function_name} <- resolve_view_tree_call_target(target, api_metadata),
         key <- function_type_key(module_name, function_name, arity),
         type when is_binary(type) <-
           Map.get(types, key) || find_function_type_signature(types, module_name, function_name),
         return_type when is_binary(return_type) <- return_type_from_signature(type) do
      ViewTree.ui_node_type_signature?(return_type) or
        ViewTree.runtime_drawable_view_root_type?(Support.view_type_name(return_type))
    else
      _ -> false
    end
  end

  defp scene_root_call_return_kind?(_target, _arity, _api_metadata), do: false

  @spec resolve_view_tree_call_target(String.t(), Types.elm_introspect()) ::
          {String.t(), String.t()} | nil
  def resolve_view_tree_call_target(target, metadata)
      when is_binary(target) and is_map(metadata) do
    resolution =
      case metadata do
        %{aliases: _} -> metadata
        %{"aliases" => _} -> metadata
        _ -> introspect_call_resolution(metadata)
      end

    case resolve_source_call(target, resolution) do
      {module_name, function_name} when is_binary(module_name) and is_binary(function_name) ->
        {module_name, function_name}

      _ ->
        module_name = Map.get(metadata, "module") || Map.get(metadata, :module)

        if is_binary(module_name) and not String.contains?(target, ".") do
          {module_name, target}
        end
    end
  end

  def resolve_view_tree_call_target(_target, _metadata), do: nil

  @spec maybe_put_view_tree_return_kind(
          Types.view_tree_node(),
          String.t(),
          non_neg_integer(),
          Types.elm_introspect()
        ) :: Types.view_tree_node()
  def maybe_put_view_tree_return_kind(node, target, arity, api_metadata)
      when is_map(node) and is_binary(target) and is_map(api_metadata) do
    case view_tree_call_return_kind(target, arity, api_metadata) do
      kind when is_binary(kind) -> Map.put(node, "return_kind", kind)
      _ -> node
    end
  end

  def maybe_put_view_tree_return_kind(node, _target, _arity, _api_metadata), do: node

  @spec view_tree_call_target_name(String.t(), Types.elm_introspect()) :: String.t()
  def view_tree_call_target_name(name, api_metadata)
      when is_binary(name) and is_map(api_metadata) do
    if String.contains?(name, ".") do
      name
    else
      module_name = Map.get(api_metadata, "module") || Map.get(api_metadata, :module) || ""

      if module_name != "", do: module_name <> "." <> name, else: name
    end
  end

  @spec view_tree_call_target(Types.view_tree_node()) :: String.t() | nil
  def view_tree_call_target(node) when is_map(node) do
    Map.get(node, "qualified_target") ||
      case {Map.get(node, "label"), Map.get(node, "type")} do
        {name, name} when is_binary(name) -> name
        {label, _} when is_binary(label) -> label
        {_, type} when is_binary(type) -> type
        _ -> nil
      end
  end

  @spec render_ops_to_ui_node_signature?(String.t()) :: boolean()
  defp render_ops_to_ui_node_signature?(type) when is_binary(type) do
    type
    |> String.replace(~r/\s+/, "")
    |> String.downcase()
    |> then(fn normalized ->
      String.match?(normalized, ~r/listrenderop->.*uinode$/) or
        String.match?(normalized, ~r/\(.*listrenderop.*\)->.*uinode$/)
    end)
  end

  @spec introspect_call_resolution(Types.elm_introspect()) :: Types.import_resolution()
  defp introspect_call_resolution(ei) when is_map(ei) do
    aliases =
      (Map.get(ei, "import_entries") || [])
      |> Enum.reduce(%{}, fn entry, acc ->
        module_name = Map.get(entry, "module")
        alias_name = Map.get(entry, "as")

        acc
        |> Support.put_module_alias(module_name, module_name)
        |> Support.put_module_alias(alias_name, module_name)
        |> Support.put_module_alias(Support.module_short_name(module_name), module_name)
      end)

    unqualified =
      (Map.get(ei, "import_entries") || [])
      |> Enum.reduce(%{}, fn entry, acc ->
        case Map.get(entry, "exposing") do
          names when is_list(names) ->
            Enum.reduce(names, acc, fn name, inner_acc ->
              if is_binary(name),
                do: Map.put(inner_acc, name, Map.get(entry, "module")),
                else: inner_acc
            end)

          _ ->
            acc
        end
      end)

    %{aliases: aliases, unqualified: unqualified}
  end

  @spec call_tree_arity(Types.view_tree_node()) :: non_neg_integer()
  def call_tree_arity(root) when is_map(root) do
    root
    |> Map.get("children", [])
    |> case do
      children when is_list(children) -> length(children)
      _ -> 0
    end
  end

  @spec find_function_type_signature(Types.function_types_index(), String.t(), String.t()) ::
          String.t() | nil
  defp find_function_type_signature(types, module_name, function_name)
       when is_map(types) and is_binary(module_name) and is_binary(function_name) do
    prefix = module_name <> "|" <> function_name <> "|"

    types
    |> Enum.find_value(fn {key, type} ->
      if is_binary(key) and String.starts_with?(key, prefix), do: type
    end)
  end

  def source_call_arg_names(target, arity, api_metadata)
      when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    case resolve_source_call(target, api_metadata) do
      {module_name, function_name} when is_binary(module_name) and is_binary(function_name) ->
        Map.get(Map.get(api_metadata, :functions, %{}), {module_name, function_name, arity}, [])

      _ ->
        []
    end
  end

  def source_call_arg_names(_target, _arity, _api_metadata), do: []

  @spec resolve_source_call(String.t(), Types.view_build_metadata()) ::
          {String.t(), String.t()} | nil
  def resolve_source_call(target, api_metadata)
      when is_binary(target) and is_map(api_metadata) do
    parts = String.split(target, ".")

    cond do
      length(parts) == 1 ->
        module_name = Map.get(Map.get(api_metadata, :unqualified, %{}), target)
        if is_binary(module_name), do: {module_name, target}, else: nil

      true ->
        resolve_qualified_source_call(parts, api_metadata)
    end
  end

  def resolve_source_call(_target, _api_metadata), do: nil

  @spec resolve_qualified_source_call([String.t()], Types.view_build_metadata()) ::
          {String.t(), String.t()} | nil
  def resolve_qualified_source_call(parts, api_metadata)
      when is_list(parts) and is_map(api_metadata) do
    aliases = Map.get(api_metadata, :aliases, %{})

    1..(length(parts) - 1)
    |> Enum.reverse()
    |> Enum.find_value(fn module_part_count ->
      {module_parts, function_parts} = Enum.split(parts, module_part_count)
      qualifier = Enum.join(module_parts, ".")
      function_name = Enum.join(function_parts, ".")
      module_name = Map.get(aliases, qualifier, qualifier)

      if is_binary(function_name) and function_name != "" do
        {module_name, function_name}
      end
    end)
  end
end
