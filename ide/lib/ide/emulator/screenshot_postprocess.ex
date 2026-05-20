defmodule Ide.Emulator.ScreenshotPostprocess do
  @moduledoc false

  import Bitwise

  alias Ide.ScreenshotDimensions
  alias Ide.WatchModels

  @type pixel_format :: %{
          bpp: pos_integer(),
          depth: pos_integer(),
          big_endian: boolean(),
          true_color: boolean(),
          red_max: pos_integer(),
          green_max: pos_integer(),
          blue_max: pos_integer(),
          red_shift: pos_integer(),
          green_shift: pos_integer(),
          blue_shift: pos_integer()
        }

  @spec screen_size(String.t()) :: {pos_integer(), pos_integer()}
  def screen_size(platform) do
    case ScreenshotDimensions.store_dimensions(platform) do
      {width, height} ->
        {width, height}

      nil ->
        platform
        |> WatchModels.profile_for()
        |> Map.fetch!("screen")
        |> then(fn screen -> {screen["width"], screen["height"]} end)
    end
  end

  @doc """
  Initial VNC capture buffer size before rectangles are applied (may grow while reading).
  """
  @spec capture_framebuffer_size(pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {pos_integer(), pos_integer()}
  def capture_framebuffer_size(vnc_w, vnc_h, screen_w, screen_h) do
    {max(vnc_w, screen_w), max(vnc_h, screen_h)}
  end

  @doc """
  Row stride width in pixels when QEMU pads scanlines to 64-byte boundaries.
  """
  @spec row_stride_width_pixels(pos_integer()) :: pos_integer()
  def row_stride_width_pixels(width) when width > 0 do
    width
    |> Kernel.*(4)
    |> then(&((&1 + 63) |> Kernel.div(64) |> Kernel.*(64)))
    |> Kernel.div(4)
  end

  @opaque_black <<0, 0, 0, 255>>
  @opaque_white <<255, 255, 255, 255>>
  @transparent <<0, 0, 0, 0>>

  @spec blank_bgrx_pixel(map()) :: <<_::32>>
  def blank_bgrx_pixel(%{"is_color" => false}), do: @opaque_white
  def blank_bgrx_pixel(%{"shape" => "round"}), do: @transparent
  def blank_bgrx_pixel(_color), do: @opaque_black

  @spec finalize(binary(), pos_integer(), pos_integer(), String.t(), pixel_format()) ::
          {:ok, binary()} | {:error, term()}
  def finalize(pixels, width, height, platform, pixel_format) do
    profile = WatchModels.profile_for(platform)
    {exp_w, exp_h} = screen_size(platform)

    with {:ok, pixels} <- crop_framebuffer(pixels, width, height, exp_w, exp_h),
         {:ok, pixels} <- normalize_pixels_to_bgrx(pixels, pixel_format, exp_w, exp_h),
         {:ok, pixels, trim_w, trim_h} <- trim_content_margins(pixels, exp_w, exp_h, profile),
         {:ok, pixels} <- resize_bgrx(pixels, trim_w, trim_h, exp_w, exp_h),
         {:ok, pixels} <- force_opaque_bgrx(pixels, exp_w, exp_h, profile) do
      {:ok, pixels}
    end
  end

  @doc false
  @spec bgrx_to_rgb(binary(), pos_integer(), pos_integer()) :: {:ok, binary()} | {:error, term()}
  def bgrx_to_rgb(pixels, width, height) do
    expected = width * height * 4

    if byte_size(pixels) < expected do
      {:error, {:invalid_bgrx_buffer, byte_size(pixels), expected}}
    else
      rgb =
        pixels
        |> :binary.part(0, expected)
        |> then(fn bin ->
          for <<b, g, r, _a <- bin>>, into: <<>>, do: <<r, g, b>>
        end)

      {:ok, rgb}
    end
  end

  @spec crop_framebuffer(binary(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, term()}
  def crop_framebuffer(pixels, src_w, src_h, dst_w, dst_h)
      when src_w >= dst_w and src_h >= dst_h do
    if byte_size(pixels) < src_w * src_h * 4 do
      {:error, {:vnc_incomplete_framebuffer, byte_size(pixels), src_w * src_h * 4}}
    else
      cropped =
        for y <- 0..(dst_h - 1), into: <<>> do
          offset = y * src_w * 4
          :binary.part(pixels, offset, dst_w * 4)
        end

      {:ok, cropped}
    end
  end

  def crop_framebuffer(_pixels, src_w, src_h, dst_w, dst_h) do
    {:error, {:vnc_framebuffer_too_small, src_w, src_h, dst_w, dst_h}}
  end

  @spec normalize_pixels_to_bgrx(binary(), pixel_format(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, term()}
  def normalize_pixels_to_bgrx(pixels, format, width, height) do
    expected = width * height * 4

    if byte_size(pixels) < expected do
      {:error, {:vnc_incomplete_framebuffer, byte_size(pixels), expected}}
    else
      pixels = :binary.part(pixels, 0, expected)

      if format.true_color and format.bpp == 32 do
        {:ok, convert_truecolor32_to_bgrx(pixels, format, width, height)}
      else
        {:error, {:vnc_unsupported_pixel_format, format}}
      end
    end
  end

  @spec apply_shape_mask(binary(), pos_integer(), pos_integer(), map()) ::
          {:ok, binary()} | {:error, term()}
  def apply_shape_mask(pixels, width, height, %{"shape" => "round"} = profile) do
    {:ok, mask_round_bgrx(pixels, width, height, blank_bgrx_pixel(profile))}
  end

  def apply_shape_mask(pixels, _width, _height, _profile), do: {:ok, pixels}

  @spec parse_pixel_format(binary()) :: {:ok, pixel_format()} | {:error, term()}
  def parse_pixel_format(
        <<bpp, depth, big_endian, true_color, red_max::unsigned-big-16,
          green_max::unsigned-big-16, blue_max::unsigned-big-16, red_shift, green_shift,
          blue_shift, _::binary>>
      ) do
    {:ok,
     %{
       bpp: bpp,
       depth: depth,
       big_endian: big_endian == 1,
       true_color: true_color == 1,
       red_max: red_max,
       green_max: green_max,
       blue_max: blue_max,
       red_shift: red_shift,
       green_shift: green_shift,
       blue_shift: blue_shift
     }}
  end

  def parse_pixel_format(_), do: {:error, :invalid_vnc_pixel_format}

  defp convert_truecolor32_to_bgrx(pixels, %{big_endian: true} = format, _width, _height) do
    for <<pixel::unsigned-big-32 <- pixels>>, into: <<>> do
      pixel_to_bgrx(pixel, format)
    end
  end

  defp convert_truecolor32_to_bgrx(pixels, format, _width, _height) do
    for <<pixel::unsigned-little-32 <- pixels>>, into: <<>> do
      pixel_to_bgrx(pixel, format)
    end
  end

  defp pixel_to_bgrx(pixel, format) do
    r = component(pixel, format.red_shift, format.red_max)
    g = component(pixel, format.green_shift, format.green_max)
    b = component(pixel, format.blue_shift, format.blue_max)
    <<b, g, r, 255>>
  end

  defp component(value, shift, max) do
    raw = (value >>> shift) &&& 0xFF
    if max == 255, do: raw, else: div(raw * 255, max)
  end

  defp mask_round_bgrx(pixels, width, height, outside_pixel) do
    radius = min(width, height) / 2.0
    center_x = (width - 1) / 2.0
    center_y = (height - 1) / 2.0
    radius_sq = radius * radius

    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      offset = (y * width + x) * 4
      pixel = :binary.part(pixels, offset, 4)

      if circle_inside?(x, y, center_x, center_y, radius_sq) do
        pixel
      else
        outside_pixel
      end
    end
  end

  defp circle_inside?(x, y, center_x, center_y, radius_sq) do
    dx = x - center_x
    dy = y - center_y
    dx * dx + dy * dy <= radius_sq
  end

  @doc false
  @spec trim_content_margins(binary(), pos_integer(), pos_integer(), map()) ::
          {:ok, binary(), pos_integer(), pos_integer()} | {:error, term()}
  def trim_content_margins(pixels, width, height, profile) do
    blank = blank_bgrx_pixel(profile)

    case edge_trim_bounds(pixels, width, height, blank) do
      nil ->
        {:ok, pixels, width, height}

      {x0, y0, x1, y1} ->
        region_w = x1 - x0 + 1
        region_h = y1 - y0 + 1

        {crop_w, crop_h, crop_x, crop_y} =
          if Map.get(profile, "shape") == "round" do
            square_bounds(x0, y0, region_w, region_h, width, height)
          else
            {region_w, region_h, x0, y0}
          end

        {:ok, extract_region(pixels, width, crop_x, crop_y, crop_w, crop_h), crop_w, crop_h}
    end
  end

  defp edge_trim_bounds(pixels, width, height, blank) do
    with y0 when is_integer(y0) <- first_content_row(pixels, width, height, blank),
         y1 when is_integer(y1) <- last_content_row(pixels, width, height, blank),
         x0 when is_integer(x0) <- first_content_column(pixels, width, height, blank, y0, y1),
         x1 when is_integer(x1) <- last_content_column(pixels, width, height, blank, y0, y1) do
      {x0, y0, x1, y1}
    else
      _ -> nil
    end
  end

  defp first_content_row(pixels, width, height, blank) do
    Enum.find_value(0..(height - 1), fn y ->
      if row_has_content?(pixels, width, y, blank), do: y
    end)
  end

  defp last_content_row(pixels, width, height, blank) do
    Enum.find_value(Enum.reverse(0..(height - 1)), fn y ->
      if row_has_content?(pixels, width, y, blank), do: y
    end)
  end

  defp first_content_column(pixels, width, _height, blank, y0, y1) do
    Enum.find_value(0..(width - 1), fn x ->
      if column_has_content?(pixels, width, x, y0, y1, blank), do: x
    end)
  end

  defp last_content_column(pixels, width, _height, blank, y0, y1) do
    Enum.find_value(Enum.reverse(0..(width - 1)), fn x ->
      if column_has_content?(pixels, width, x, y0, y1, blank), do: x
    end)
  end

  defp row_has_content?(pixels, width, y, blank) do
    Enum.any?(0..(width - 1), fn x ->
      not margin_pixel?(pixel_at(pixels, width, x, y), blank)
    end)
  end

  defp column_has_content?(pixels, width, x, y0, y1, blank) do
    Enum.any?(y0..y1, fn y ->
      not margin_pixel?(pixel_at(pixels, width, x, y), blank)
    end)
  end

  defp pixel_at(pixels, width, x, y) do
    :binary.part(pixels, (y * width + x) * 4, 4)
  end

  defp margin_pixel?(pixel, blank) do
    pixel == blank or pixel in [@opaque_black, @opaque_white, @transparent]
  end

  defp square_bounds(x0, y0, w, h, fb_w, fb_h) do
    fb_side = min(fb_w, fb_h)
    region_side = max(w, h)

    side =
      if region_side < fb_side do
        fb_side
      else
        min(region_side, fb_side)
      end

    center_x = x0 + div(w, 2)
    center_y = y0 + div(h, 2)
    crop_x = (center_x - div(side, 2)) |> max(0) |> min(fb_w - side)
    crop_y = (center_y - div(side, 2)) |> max(0) |> min(fb_h - side)
    {side, side, crop_x, crop_y}
  end

  defp extract_region(pixels, src_w, x, y, w, h) do
    for row <- y..(y + h - 1), into: <<>> do
      :binary.part(pixels, row * src_w * 4 + x * 4, w * 4)
    end
  end

  @doc false
  @spec resize_bgrx(binary(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, term()}
  def resize_bgrx(pixels, src_w, src_h, dst_w, dst_h) do
    if src_w == dst_w and src_h == dst_h do
      {:ok, pixels}
    else
      resized =
        for y <- 0..(dst_h - 1), x <- 0..(dst_w - 1), into: <<>> do
          src_x = min(src_w - 1, div(x * src_w, dst_w))
          src_y = min(src_h - 1, div(y * src_h, dst_h))
          offset = (src_y * src_w + src_x) * 4
          :binary.part(pixels, offset, 4)
        end

      {:ok, resized}
    end
  end

  defp force_opaque_bgrx(pixels, _width, _height, %{"shape" => "round"}), do: {:ok, pixels}

  defp force_opaque_bgrx(pixels, width, height, _profile) do
    opaque =
      for <<b, g, r, _a <- pixels>>, into: <<>> do
        <<b, g, r, 255>>
      end

    expected = width * height * 4

    if byte_size(opaque) == expected do
      {:ok, opaque}
    else
      {:error, {:invalid_rgba_buffer, byte_size(opaque), expected}}
    end
  end
end
