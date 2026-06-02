defmodule Ide.Emulator.ScreenshotCaptureRepair do
  @moduledoc false

  alias Ide.Emulator.Types
  alias Ide.ScreenshotDimensions

  @white <<255, 255, 255>>
  @transparent <<0, 0, 0, 0>>

  @doc """
  Repairs common emulator/firmware capture artifacts before SDK colour correction.

  - Normalizes to App Store dimensions (roundness tables are height-specific)
  - Shifts content up-left when a black bezel appears only on the top and left edges
  """
  @spec repair_rgb(binary(), pos_integer(), pos_integer(), String.t(), keyword()) ::
          {binary(), pos_integer(), pos_integer()}
  def repair_rgb(rgb, width, height, platform, opts \\ []) when is_binary(platform) do
    {rgb, width, height} =
      if Keyword.get(opts, :normalize, true) do
        normalize_dimensions(rgb, width, height, platform)
      else
        {rgb, width, height}
      end

    if top_left_bezel?(rgb, width, height) do
      {shift_top_left(rgb, width, height, @white), width, height}
    else
      {rgb, width, height}
    end
  end

  @doc """
  Post-SDK touch-ups for emulator captures (after `correct_colours` and `roundify`).
  """
  @spec repair_rgba(binary(), pos_integer(), pos_integer(), String.t() | Types.watch_profile()) ::
          binary()
  def repair_rgba(rgba, width, height, platform) when is_binary(platform) do
    profile = Ide.WatchModels.profile_for(platform)

    rgba
    |> maybe_clear_round_black_ring(width, height, profile)
    |> clear_top_left_edge_black(width, height, profile)
    |> maybe_clear_black_adjacent_transparent(width, height, profile)
    |> maybe_flood_rect_letterbox(width, height, profile)
  end

  @spec normalize_dimensions(binary(), pos_integer(), pos_integer(), String.t()) ::
          {binary(), pos_integer(), pos_integer()}
  def normalize_dimensions(rgb, width, height, platform) do
    case ScreenshotDimensions.store_dimensions(platform) do
      {target_w, target_h} when target_w != width or target_h != height ->
        {resize_rgb_nearest(rgb, width, height, target_w, target_h), target_w, target_h}

      _ ->
        {rgb, width, height}
    end
  end

  defp top_left_bezel?(rgb, width, height) do
    row0 = black_fraction(rgb, width, width, fn x -> {x, 0} end)
    col0 = black_fraction(rgb, width, height, fn y -> {0, y} end)
    row_last = black_fraction(rgb, width, width, fn x -> {x, height - 1} end)
    col_last = black_fraction(rgb, width, height, fn y -> {width - 1, y} end)

    uniform_bezel =
      row0 >= 0.85 and col0 >= 0.85 and row_last < 0.5 and col_last < 0.5

    # Round/QEMU captures: a full black left column with a partial top row (shift down-right).
    shifted_capture =
      col0 >= 0.75 and row0 >= 0.2 and row_last < 0.45 and col_last < 0.45

    uniform_bezel or shifted_capture
  end

  defp black_fraction(rgb, stride, count, coord) do
    black =
      Enum.count(0..(count - 1), fn i ->
        {x, y} = coord.(i)
        pixel_rgb(rgb, stride, x, y) == {0, 0, 0}
      end)

    black / count
  end

  defp shift_top_left(rgb, width, height, fill) do
    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      cond do
        x > 0 and y > 0 ->
          {r, g, b} = pixel_rgb(rgb, width, x - 1, y - 1)
          <<r, g, b>>

        true ->
          fill
      end
    end
  end

  defp resize_rgb_nearest(rgb, src_w, src_h, dst_w, dst_h) do
    for y <- 0..(dst_h - 1), x <- 0..(dst_w - 1), into: <<>> do
      src_x = min(src_w - 1, div(x * src_w, dst_w))
      src_y = min(src_h - 1, div(y * src_h, dst_h))
      {r, g, b} = pixel_rgb(rgb, src_w, src_x, src_y)
      <<r, g, b>>
    end
  end

  defp clear_top_left_edge_black(rgba, width, height, %{"shape" => "round"} = profile) do
    fill = margin_fill_rgba(profile)
    strip = min(3, div(min(width, height), 2))

    Enum.reduce(0..(strip - 1), rgba, fn offset, acc ->
      acc
      |> clear_row_black(width, offset, fill)
      |> clear_column_black(width, height, offset, fill)
    end)
  end

  defp clear_top_left_edge_black(rgba, width, height, profile) do
    fill = margin_fill_rgba(profile)

    rgba
    |> clear_row_black(width, 0, fill)
    |> clear_column_black(width, height, 0, fill)
  end

  defp clear_row_black(rgba, width, y, fill) do
    Enum.reduce(0..(width - 1), rgba, fn x, acc ->
      if pixel_black?(acc, width, x, y), do: put_rgba(acc, width, x, y, fill), else: acc
    end)
  end

  defp clear_column_black(rgba, width, height, x, fill) do
    Enum.reduce(0..(height - 1), rgba, fn y, acc ->
      if pixel_black?(acc, width, x, y), do: put_rgba(acc, width, x, y, fill), else: acc
    end)
  end

  defp margin_fill_rgba(%{"shape" => "round"}), do: @transparent
  defp margin_fill_rgba(_), do: <<255, 255, 255, 255>>

  defp maybe_clear_round_black_ring(rgba, width, height, %{"shape" => "round"}) do
    radius = min(width, height) / 2.0
    center_x = (width - 1) / 2.0
    center_y = (height - 1) / 2.0
    radius_sq = radius * radius

    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      offset = (y * width + x) * 4
      pixel = :binary.part(rgba, offset, 4)

      case pixel do
        <<0, 0, 0, 255>> ->
          if circle_inside?(x, y, center_x, center_y, radius_sq), do: pixel, else: @transparent

        _ ->
          pixel
      end
    end
  end

  defp maybe_clear_round_black_ring(rgba, _width, _height, _profile), do: rgba

  # Roundify leaves opaque black pixels along the inner arc; clear those that touch
  # transparent corners so listing screenshots do not show a thin top/left ring.
  defp maybe_clear_black_adjacent_transparent(rgba, width, height, %{"shape" => "round"}) do
    indices =
      for y <- 0..(height - 1),
          x <- 0..(width - 1),
          pixel_black?(rgba, width, x, y),
          transparent_neighbor?(rgba, width, height, x, y),
          do: {x, y}

    paint_indices(rgba, width, MapSet.new(indices), @transparent)
  end

  defp maybe_clear_black_adjacent_transparent(rgba, _width, _height, _profile), do: rgba

  defp transparent_neighbor?(rgba, width, height, x, y) do
    Enum.any?(neighbors(x, y, width, height), fn {nx, ny} ->
      case pixel_rgba(rgba, width, nx, ny) do
        <<_, _, _, 0>> -> true
        _ -> false
      end
    end)
  end

  defp neighbors(x, y, width, height) do
    for {nx, ny} <- [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}],
        nx >= 0 and nx < width and ny >= 0 and ny < height,
        do: {nx, ny}
  end

  defp maybe_flood_rect_letterbox(rgba, width, height, %{
         "shape" => "rect",
         "color_mode" => "BlackWhite"
       }) do
    background = border_connected_black(width, height, rgba)
    paint_indices(rgba, width, background, <<255, 255, 255, 255>>)
  end

  defp maybe_flood_rect_letterbox(rgba, _width, _height, _profile), do: rgba

  defp border_connected_black(width, height, rgba) do
    seeds =
      for(x <- 0..(width - 1), y <- [0, height - 1], do: {x, y}) ++
        for(y <- 1..(height - 2)//1, x <- [0, width - 1], do: {x, y})

    seeds =
      Enum.filter(seeds, fn {x, y} -> pixel_black?(rgba, width, x, y) end)

    flood_black(width, height, rgba, seeds)
  end

  defp flood_black(_width, _height, _rgba, []), do: MapSet.new()

  defp flood_black(width, height, rgba, seeds) do
    {queue, visited} =
      Enum.reduce(seeds, {:queue.new(), MapSet.new()}, fn coord, {q, vis} ->
        {:queue.in(coord, q), MapSet.put(vis, coord)}
      end)

    flood_loop(queue, width, height, rgba, visited)
  end

  defp flood_loop(queue, width, height, rgba, visited) do
    case :queue.out(queue) do
      {:empty, _} ->
        visited

      {{:value, {x, y}}, queue} ->
        neighbors = [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}]

        {queue, visited} =
          Enum.reduce(neighbors, {queue, visited}, fn {nx, ny}, {q, vis} ->
            if nx >= 0 and nx < width and ny >= 0 and ny < height and
                 not MapSet.member?(vis, {nx, ny}) and pixel_black?(rgba, width, nx, ny) do
              {:queue.in({nx, ny}, q), MapSet.put(vis, {nx, ny})}
            else
              {q, vis}
            end
          end)

        flood_loop(queue, width, height, rgba, visited)
    end
  end

  defp paint_indices(rgba, width, %MapSet{} = indices, pixel) do
    Enum.reduce(indices, rgba, fn {x, y}, acc ->
      put_rgba(acc, width, x, y, pixel)
    end)
  end

  defp circle_inside?(x, y, center_x, center_y, radius_sq) do
    dx = x - center_x
    dy = y - center_y
    dx * dx + dy * dy <= radius_sq
  end

  defp pixel_rgb(rgb, width, x, y) do
    <<r, g, b>> = :binary.part(rgb, (y * width + x) * 3, 3)
    {r, g, b}
  end

  defp pixel_black?(rgba, width, x, y) do
    <<0, 0, 0, 255>> == pixel_rgba(rgba, width, x, y)
  end

  defp pixel_rgba(rgba, width, x, y) do
    :binary.part(rgba, (y * width + x) * 4, 4)
  end

  defp put_rgba(rgba, width, x, y, pixel) do
    offset = (y * width + x) * 4
    <<before::binary-size(offset), _::binary-size(4), after_rest::binary>> = rgba
    before <> pixel <> after_rest
  end
end
