defmodule IdeWeb.WorkspaceLive.DebuggerPreview.SvgOps do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerPreview.{
    CompactScene,
    Hydration,
    RuntimeAccess,
    SvgStyle,
    ViewTreeOps
  }

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type runtime_input :: PreviewTypes.runtime_input()
  @type view_tree :: PreviewTypes.view_tree() | nil
  @type model_map :: PreviewTypes.model_map()
  @type svg_op :: PreviewTypes.svg_op()

  @path_kinds [:path_filled, :path_outline, :path_outline_open]
  @text_kinds [:text, :text_label, :text_int]
  @vector_kinds [:vector_at, :vector_sequence_at]
  @bitmap_kinds [:bitmap_in_rect, :rotated_bitmap]

  @spec svg_ops(view_tree(), runtime_input()) :: [svg_op()]
  def svg_ops(tree, runtime) when is_map(tree) do
    model = RuntimeAccess.runtime_model(runtime)
    vector_indices = RuntimeArtifacts.vector_resource_indices(model)
    bitmap_indices = RuntimeArtifacts.bitmap_resource_indices(model)
    animation_indices = RuntimeArtifacts.animation_resource_indices(model)

    runtime_ops =
      runtime
      |> runtime_compact_scene_output()
      |> Enum.map(&Hydration.resolve_vector_svg_op_id(&1, vector_indices))
      |> Enum.map(&resolve_bitmap_svg_op_id(&1, bitmap_indices, animation_indices))

    primary_int = RuntimeAccess.primary_int_model_value(model)

    tree_ops =
      tree
      |> ViewTreeOps.ops_from_tree(primary_int, model)
      |> SvgStyle.apply_state()

    tree_vector_ops = Enum.filter(tree_ops, &(&1.kind in @vector_kinds))
    tree_animation_ops = Enum.filter(tree_ops, &(&1.kind == :bitmap_sequence_at))
    tree_bitmap_ops = Enum.filter(tree_ops, &(&1.kind in @bitmap_kinds))
    tree_path_ops = Enum.filter(tree_ops, &(&1.kind in @path_kinds))
    tree_text_ops = Enum.filter(tree_ops, &(&1.kind in @text_kinds))

    runtime_has_vectors? = runtime_has_kind?(runtime_ops, @vector_kinds, :vector_id, 1)
    runtime_has_animations? = runtime_has_kind?(runtime_ops, [:bitmap_sequence_at], :animation_id, 1)
    runtime_has_bitmaps? = runtime_has_kind?(runtime_ops, @bitmap_kinds, :bitmap_id, 1)
    runtime_has_paths? = Enum.any?(runtime_ops, &(&1.kind in @path_kinds))
    runtime_has_text? = Enum.any?(runtime_ops, &(&1.kind in @text_kinds))

    ops =
      cond do
        runtime_ops == [] ->
          tree_ops

        true ->
          runtime_ops
          |> maybe_append_tree_ops(not runtime_has_vectors?, tree_vector_ops)
          |> maybe_append_tree_ops(not runtime_has_bitmaps?, tree_bitmap_ops)
          |> maybe_append_tree_ops(not runtime_has_animations?, tree_animation_ops)
          |> maybe_append_tree_ops(not runtime_has_paths?, tree_path_ops)
          |> maybe_append_tree_ops(not runtime_has_text?, tree_text_ops)
      end

    ops
    |> Enum.map(&Hydration.resolve_vector_svg_op_id(&1, vector_indices))
    |> Enum.map(&resolve_bitmap_svg_op_id(&1, bitmap_indices, animation_indices))
  end

  def svg_ops(_tree, runtime), do: runtime_compact_scene_output(runtime)

  @spec resolve_bitmap_svg_ops([svg_op()], Project.t() | runtime_input()) :: [svg_op()]
  def resolve_bitmap_svg_ops(rows, %Project{} = project) when is_list(rows) do
    bitmap_indices = RuntimeArtifacts.bitmap_resource_indices_for_project(project.slug)
    animation_indices = RuntimeArtifacts.animation_resource_indices_for_project(project.slug)
    Enum.map(rows, &resolve_bitmap_svg_op_id(&1, bitmap_indices, animation_indices))
  end

  def resolve_bitmap_svg_ops(rows, runtime) when is_list(rows) do
    model = RuntimeAccess.runtime_model(runtime)
    bitmap_indices = RuntimeArtifacts.bitmap_resource_indices(model)
    animation_indices = RuntimeArtifacts.animation_resource_indices(model)
    Enum.map(rows, &resolve_bitmap_svg_op_id(&1, bitmap_indices, animation_indices))
  end

  @spec resolve_bitmap_svg_op_id(
          svg_op(),
          PreviewTypes.resource_index_map(),
          PreviewTypes.resource_index_map()
        ) :: svg_op()
  def resolve_bitmap_svg_op_id(%{kind: :bitmap_in_rect} = op, bitmap_indices, _animation_indices) do
    case Map.get(op, :bitmap_id) do
      id when is_integer(id) and id > 0 ->
        op

      _ ->
        resource = Map.get(op, :resource) || Map.get(op, "resource")
        id = named_resource_index(resource, bitmap_indices)
        if id > 0, do: Map.put(op, :bitmap_id, id), else: op
    end
  end

  def resolve_bitmap_svg_op_id(%{kind: :rotated_bitmap} = op, bitmap_indices, _animation_indices) do
    case Map.get(op, :bitmap_id) do
      id when is_integer(id) and id > 0 ->
        op

      _ ->
        resource = Map.get(op, :resource) || Map.get(op, "resource")
        id = named_resource_index(resource, bitmap_indices)
        if id > 0, do: Map.put(op, :bitmap_id, id), else: op
    end
  end

  def resolve_bitmap_svg_op_id(
        %{kind: :bitmap_sequence_at} = op,
        _bitmap_indices,
        animation_indices
      ) do
    case Map.get(op, :animation_id) do
      id when is_integer(id) and id > 0 ->
        op

      _ ->
        resource = Map.get(op, :resource) || Map.get(op, "resource")
        id = named_resource_index(resource, animation_indices)
        if id > 0, do: Map.put(op, :animation_id, id), else: op
    end
  end

  def resolve_bitmap_svg_op_id(op, _bitmap_indices, _animation_indices), do: op

  @spec runtime_compact_scene_output(runtime_input()) :: [svg_op()]
  defp runtime_compact_scene_output(runtime) do
    runtime
    |> CompactScene.compact_scene()
    |> Map.get(:ops, [])
    |> Enum.map(&Map.get(&1, :op))
    |> Enum.filter(&is_map/1)
    |> SvgStyle.apply_state()
  end

  @spec maybe_append_tree_ops([svg_op()], boolean(), [svg_op()]) :: [svg_op()]
  defp maybe_append_tree_ops(ops, true, extra), do: ops ++ extra
  defp maybe_append_tree_ops(ops, false, _extra), do: ops

  @spec runtime_has_kind?([svg_op()], [atom()], atom(), pos_integer()) :: boolean()
  defp runtime_has_kind?(ops, kinds, id_key, min_id) do
    Enum.any?(ops, fn op ->
      op.kind in kinds and Map.get(op, id_key, 0) >= min_id
    end)
  end

  @spec named_resource_index(
          PreviewTypes.resource_ctor_ref(),
          PreviewTypes.resource_index_map()
        ) :: non_neg_integer()
  defp named_resource_index(resource, indices) when is_map(indices) do
    name = resource_name(resource)

    case Map.get(indices, name) || Map.get(indices, String.to_atom(name)) do
      id when is_integer(id) and id > 0 -> id
      _ -> 0
    end
  end

  defp named_resource_index(_resource, _indices), do: 0

  @spec resource_name(PreviewTypes.resource_ctor_ref()) :: String.t()
  defp resource_name(resource) when is_binary(resource), do: resource
  defp resource_name(resource) when is_atom(resource), do: Atom.to_string(resource)
  defp resource_name(%{"ctor" => ctor}), do: to_string(ctor)
  defp resource_name(%{ctor: ctor}), do: to_string(ctor)
  defp resource_name(_), do: ""
end
