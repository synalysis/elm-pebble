defmodule Elmx.Runtime.ViewOutput.Resources do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Geometry

  @type opts :: Types.view_output_opts()

  @spec apply_resource_indices([Types.view_output_row()], opts()) :: [Types.view_output_row()]
  def apply_resource_indices(rows, opts \\ []) when is_list(rows) do
    vector_indices = vector_resource_indices(opts)
    bitmap_indices = bitmap_resource_indices(opts)
    animation_indices = animation_resource_indices(opts)

    Enum.map(rows, fn row ->
      row
      |> apply_vector_resource_index(vector_indices)
      |> apply_bitmap_resource_index(bitmap_indices)
      |> apply_animation_resource_index(animation_indices)
    end)
  end

  def vector_id(node, resource, indices) do
    case Geometry.int_field(node, "vector_id", nil) do
      id when is_integer(id) and id > 0 ->
        id

      _ ->
        resource_vector_id(resource, indices)
    end
  end

  def vector_resource_indices(opts) when is_list(opts) do
    case Keyword.get(opts, :vector_resource_indices) do
      %{} = indices -> indices
      _ -> %{}
    end
  end

  def animation_resource_indices(opts) when is_list(opts) do
    case Keyword.get(opts, :animation_resource_indices) do
      %{} = indices -> indices
      _ -> %{}
    end
  end

  def apply_vector_resource_index(row, indices) when is_map(row) and is_map(indices) do
    kind = Map.get(row, "kind") || Map.get(row, :kind)

    if kind in ["vector_at", "vector_sequence_at", :vector_at, :vector_sequence_at] do
      case Geometry.int_field(row, "vector_id", 0) do
        id when is_integer(id) and id > 0 ->
          row

        _ ->
          resource = Map.get(row, "resource") || Map.get(row, :resource)
          id = resource_vector_id(resource, indices)
          if id > 0, do: Map.put(row, "vector_id", id), else: row
      end
    else
      row
    end
  end

  def apply_vector_resource_index(row, _indices), do: row

  def apply_animation_resource_index(row, indices) when is_map(row) and is_map(indices) do
    kind = Map.get(row, "kind") || Map.get(row, :kind)

    if kind in ["bitmap_sequence_at", :bitmap_sequence_at] do
      case Geometry.int_field(row, "animation_id", 0) do
        id when is_integer(id) and id > 0 ->
          row

        _ ->
          resource = Map.get(row, "resource") || Map.get(row, :resource)
          id = resource_animation_id(resource, indices)

          if id > 0, do: Map.put(row, "animation_id", id), else: row
      end
    else
      row
    end
  end

  def apply_animation_resource_index(row, _indices), do: row

  def apply_bitmap_resource_index(row, indices) when is_map(row) and is_map(indices) do
    kind = Map.get(row, "kind") || Map.get(row, :kind)

    if kind in ["bitmap_in_rect", "rotated_bitmap", :bitmap_in_rect, :rotated_bitmap] do
      case Geometry.int_field(row, "bitmap_id", 0) do
        id when is_integer(id) and id > 0 ->
          row

        _ ->
          resource = Map.get(row, "resource") || Map.get(row, :resource)
          id = resource_bitmap_id(resource, indices)
          if id > 0, do: Map.put(row, "bitmap_id", id), else: row
      end
    else
      row
    end
  end

  def apply_bitmap_resource_index(row, _indices), do: row

  def bitmap_resource_indices(opts) when is_list(opts) do
    case Keyword.get(opts, :bitmap_resource_indices) do
      %{} = indices -> indices
      _ -> %{}
    end
  end

  def resource_name(resource) when is_binary(resource), do: resource
  def resource_name(resource) when is_atom(resource), do: Atom.to_string(resource)
  def resource_name(%{"ctor" => ctor}), do: to_string(ctor)
  def resource_name(%{ctor: ctor}), do: to_string(ctor)
  def resource_name(_), do: ""

  def resource_bitmap_id(resource, indices), do: resource_index_id(resource, indices)

  def resource_animation_id(resource, indices), do: resource_index_id(resource, indices)

  def resource_index_id(resource, indices), do: resource_vector_id(resource, indices)

  def sanitize_rect({x, y, w, h}, _node, opts) do
    screen_w = screen_dimension(opts, :screen_w)
    screen_h = screen_dimension(opts, :screen_h)

    w = max(w, 0)
    h = max(h, 0)

    {w, h} =
      if is_integer(screen_w) and screen_w > 0 and is_integer(screen_h) and screen_h > 0 do
        {
          min(w, max(0, screen_w - max(x, 0))),
          min(h, max(0, screen_h - max(y, 0)))
        }
      else
        {min(w, 512), min(h, 512)}
      end

    {x, y, w, h}
  end

  def screen_dimension(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      n when is_integer(n) and n > 0 ->
        n

      _ ->
        case Keyword.get(opts, :runtime_model) do
          %{} = model ->
            model
            |> Map.get(Atom.to_string(key))
            |> case do
              nil -> Map.get(model, screen_key_fallback(key))
              other -> other
            end
            |> case do
              n when is_integer(n) -> n
              n when is_float(n) -> trunc(n)
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  def screen_key_fallback(:screen_w), do: "screenW"
  def screen_key_fallback(:screen_h), do: "screenH"

  def resource_vector_id(resource, indices) when is_map(indices) do
    case resource do
      id when is_integer(id) and id > 0 ->
        id

      resource ->
        name = resource_name(resource)

        case Map.get(indices, name) || Map.get(indices, String.to_atom(name)) do
          id when is_integer(id) and id > 0 ->
            id

          _ ->
            case Integer.parse(name) do
              {id, ""} when id > 0 -> id
              _ -> 0
            end
        end
    end
  end

end
