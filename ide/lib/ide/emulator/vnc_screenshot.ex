defmodule Ide.Emulator.VncScreenshot do
  @moduledoc false

  alias Ide.Emulator.PebblePalette
  alias Ide.Emulator.SdkScreenshotStyle
  alias Ide.Emulator.ScreenshotPostprocess
  alias Ide.Emulator.Types
  alias Ide.WatchModels

  @client_version "RFB 003.008\n"
  @connect_timeout 5_000
  @default_timeout 15_000
  @max_raw_rectangle_bytes 50_000_000

  @spec capture(pos_integer(), keyword()) ::
          {:ok, binary()} | {:error, Types.screenshot_error() | :timeout}
  def capture(port, opts \\ []) when is_integer(port) and port > 0 do
    platform = Keyword.fetch!(opts, :platform)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with {:ok, socket} <-
           :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], @connect_timeout),
         {:ok, png} <- capture_from_socket(socket, platform, timeout) do
      {:ok, png}
    end
  end

  defp capture_from_socket(socket, platform, timeout) do
    try do
      profile = WatchModels.profile_for(platform)
      {exp_w, exp_h} = ScreenshotPostprocess.screen_size(platform)

      with {:ok, server_version} <- recv_line(socket, timeout),
           true <- String.starts_with?(server_version, "RFB "),
           :ok <- :gen_tcp.send(socket, @client_version),
           {:ok, security} <- negotiate_security(socket, timeout),
           :ok <- security,
           :ok <- :gen_tcp.send(socket, <<1>>),
           {:ok, vnc_w, vnc_h, pixel_format} <- read_server_init(socket, timeout),
           {fb_w, fb_h} =
             ScreenshotPostprocess.capture_framebuffer_size(vnc_w, vnc_h, exp_w, exp_h),
           request_w = max(fb_w, ScreenshotPostprocess.row_stride_width_pixels(exp_w)),
           request_h = fb_h,
           :ok <- request_framebuffer(socket, request_w, request_h, timeout),
           {:ok, raw_pixels, fb_w, fb_h} <-
             read_framebuffer_update(socket, fb_w, fb_h, profile, timeout),
           {:ok, pixels} <-
             crop_trim_and_normalize_vnc(
               raw_pixels,
               fb_w,
               fb_h,
               exp_w,
               exp_h,
               pixel_format,
               profile
             ),
           {:ok, rgb} <- ScreenshotPostprocess.bgrx_to_rgb(pixels, exp_w, exp_h),
           rgb = PebblePalette.quantize_rgb(rgb),
           {:ok, png} <- SdkScreenshotStyle.process(platform, rgb, exp_w, exp_h) do
        {:ok, png}
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp negotiate_security(socket, timeout) do
    with {:ok, <<count::unsigned-8>>} <- recv_exact(socket, 1, timeout),
         true <- count > 0,
         {:ok, types} <- recv_exact(socket, count, timeout) do
      cond do
        1 in :binary.bin_to_list(types) ->
          :gen_tcp.send(socket, <<1>>)
          recv_security_result(socket, timeout)

        true ->
          {:error, :vnc_no_none_security}
      end
    end
  end

  defp recv_security_result(socket, timeout) do
    case recv_exact(socket, 4, timeout) do
      {:ok, <<0, 0, 0, 0>>} -> {:ok, :ok}
      {:ok, <<_::32>>} -> {:error, :vnc_security_failed}
      other -> other
    end
  end

  defp read_server_init(socket, timeout) do
    with {:ok,
          <<width::unsigned-big-16, height::unsigned-big-16, pf::binary-size(16),
            name_len::unsigned-big-32>>} <-
           recv_exact(socket, 24, timeout),
         {:ok, pixel_format} <- ScreenshotPostprocess.parse_pixel_format(pf),
         {:ok, _name} <- recv_exact(socket, name_len, timeout) do
      {:ok, width, height, pixel_format}
    end
  end

  defp request_framebuffer(socket, width, height, _timeout) do
    message =
      <<
        3,
        0,
        0::16,
        0::16,
        width::unsigned-big-16,
        height::unsigned-big-16
      >>

    case :gen_tcp.send(socket, message) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_framebuffer_update(socket, width, height, profile, timeout) do
    with {:ok, <<0, _padding, count::unsigned-big-16>>} <- recv_exact(socket, 4, timeout),
         {:ok, pixels, fb_w, fb_h} <-
           composite_rectangles(socket, count, width, height, profile, timeout) do
      {:ok, pixels, fb_w, fb_h}
    end
  end

  defp composite_rectangles(_socket, 0, _fb_w, _fb_h, _profile, _timeout) do
    {:error, :vnc_empty_framebuffer_update}
  end

  defp composite_rectangles(socket, count, fb_w, fb_h, profile, timeout) when count > 0 do
    composite_rectangles_loop(
      socket,
      count,
      fb_w,
      fb_h,
      timeout,
      blank_buffer(fb_w, fb_h, profile),
      profile
    )
  end

  defp composite_rectangles_loop(_socket, 0, fb_w, fb_h, _timeout, buffer, _profile),
    do: {:ok, buffer, fb_w, fb_h}

  defp composite_rectangles_loop(socket, count, fb_w, fb_h, timeout, buffer, profile) do
    with {:ok, buffer, fb_w, fb_h} <-
           read_rectangle(socket, fb_w, fb_h, timeout, buffer, profile) do
      composite_rectangles_loop(socket, count - 1, fb_w, fb_h, timeout, buffer, profile)
    end
  end

  defp blank_buffer(width, height, profile) do
    blank = ScreenshotPostprocess.blank_bgrx_pixel(profile)
    blank_row = :binary.copy(blank, width)
    :binary.copy(blank_row, height)
  end

  defp read_rectangle(socket, fb_width, fb_height, timeout, buffer, profile) do
    with {:ok, header} <- recv_exact(socket, 12, timeout) do
      <<x::unsigned-big-16, y::unsigned-big-16, rect_w::unsigned-big-16, rect_h::unsigned-big-16,
        encoding::signed-big-32>> = header

      apply_rectangle(
        socket,
        fb_width,
        fb_height,
        x,
        y,
        rect_w,
        rect_h,
        encoding,
        timeout,
        buffer,
        profile
      )
    end
  end

  defp apply_rectangle(
         socket,
         fb_width,
         fb_height,
         x,
         y,
         rect_w,
         rect_h,
         0,
         timeout,
         buffer,
         profile
       ) do
    wire_bytes = rect_w * rect_h * 4

    cond do
      wire_bytes > @max_raw_rectangle_bytes ->
        {:error, {:vnc_rectangle_too_large, wire_bytes}}

      rect_w == 0 or rect_h == 0 ->
        {:ok, buffer, fb_width, fb_height}

      true ->
        needed_w = max(fb_width, x + rect_w)
        needed_h = max(fb_height, y + rect_h)

        {buffer, fb_width, fb_height} =
          grow_framebuffer(buffer, fb_width, fb_height, needed_w, needed_h, profile)

        with {:ok, wire_pixels} <- recv_exact(socket, wire_bytes, timeout) do
          case clip_rectangle(x, y, rect_w, rect_h, fb_width, fb_height) do
            :discard ->
              {:ok, buffer, fb_width, fb_height}

            {:clip, dst_x, dst_y, clip_w, clip_h, src_x, src_y} ->
              pixels =
                extract_rectangle_pixels(
                  wire_pixels,
                  rect_w,
                  rect_h,
                  src_x,
                  src_y,
                  clip_w,
                  clip_h
                )

              with {:ok, buffer} <-
                     blit_raw(buffer, fb_width, fb_height, dst_x, dst_y, clip_w, clip_h, pixels) do
                {:ok, buffer, fb_width, fb_height}
              end
          end
        end
    end
  end

  defp apply_rectangle(
         _socket,
         fb_w,
         fb_h,
         _x,
         _y,
         _rect_w,
         _rect_h,
         -223,
         _timeout,
         buffer,
         _profile
       ) do
    {:ok, buffer, fb_w, fb_h}
  end

  defp apply_rectangle(
         socket,
         fb_w,
         fb_h,
         _x,
         _y,
         rect_w,
         rect_h,
         -239,
         timeout,
         buffer,
         _profile
       ) do
    pixels = rect_w * rect_h * 4
    mask_bytes = div(rect_w * rect_h + 7, 8)

    with {:ok, _} <- recv_exact(socket, pixels + mask_bytes, timeout) do
      {:ok, buffer, fb_w, fb_h}
    end
  end

  defp apply_rectangle(
         _socket,
         fb_w,
         fb_h,
         _x,
         _y,
         _rect_w,
         _rect_h,
         encoding,
         _timeout,
         buffer,
         _profile
       )
       when encoding < 0 do
    {:ok, buffer, fb_w, fb_h}
  end

  defp apply_rectangle(
         _socket,
         _fb_w,
         _fb_h,
         _x,
         _y,
         _w,
         _h,
         encoding,
         _timeout,
         _buffer,
         _profile
       ) do
    {:error, {:vnc_unsupported_encoding, encoding}}
  end

  defp grow_framebuffer(buffer, fb_w, fb_h, needed_w, needed_h, profile) do
    if needed_w <= fb_w and needed_h <= fb_h do
      {buffer, fb_w, fb_h}
    else
      new_w = max(fb_w, needed_w)
      new_h = max(fb_h, needed_h)
      {copy_region(blank_buffer(new_w, new_h, profile), buffer, fb_w, fb_h), new_w, new_h}
    end
  end

  defp copy_region(dest, src, src_w, src_h) do
    dest_w = div(byte_size(dest), src_h)
    dest_row_bytes = dest_w * 4
    src_row_bytes = src_w * 4

    Enum.reduce(0..(src_h - 1), dest, fn y, acc ->
      row = :binary.part(src, y * src_row_bytes, src_row_bytes)
      dst_offset = y * dest_row_bytes

      <<
        before::binary-size(dst_offset),
        _old::binary-size(src_row_bytes),
        after_rest::binary
      >> = acc

      before <> row <> after_rest
    end)
  end

  defp clip_rectangle(x, y, rect_w, rect_h, fb_width, fb_height) do
    dst_x = max(x, 0)
    dst_y = max(y, 0)
    dst_x2 = min(x + rect_w, fb_width)
    dst_y2 = min(y + rect_h, fb_height)

    if dst_x >= dst_x2 or dst_y >= dst_y2 do
      :discard
    else
      clip_w = dst_x2 - dst_x
      clip_h = dst_y2 - dst_y
      {:clip, dst_x, dst_y, clip_w, clip_h, dst_x - x, dst_y - y}
    end
  end

  defp extract_rectangle_pixels(wire_pixels, rect_w, _rect_h, src_x, src_y, clip_w, clip_h) do
    row_bytes = rect_w * 4
    clip_row_bytes = clip_w * 4

    for row <- src_y..(src_y + clip_h - 1), into: <<>> do
      :binary.part(wire_pixels, row * row_bytes + src_x * 4, clip_row_bytes)
    end
  end

  defp blit_raw(_buffer, fb_width, fb_height, 0, 0, rect_w, rect_h, pixels)
       when rect_w == fb_width and rect_h == fb_height do
    expected = fb_width * fb_height * 4

    if byte_size(pixels) == expected do
      {:ok, pixels}
    else
      {:error, {:vnc_incomplete_framebuffer, byte_size(pixels), expected}}
    end
  end

  defp blit_raw(buffer, fb_width, _fb_height, x, y, rect_w, rect_h, pixels) do
    row_bytes = rect_w * 4
    fb_stride = fb_width * 4

    buffer =
      Enum.reduce(0..(rect_h - 1), buffer, fn row, acc ->
        src_offset = row * row_bytes
        dst_offset = (y + row) * fb_stride + x * 4
        chunk = :binary.part(pixels, src_offset, row_bytes)

        <<
          before::binary-size(dst_offset),
          _old::binary-size(row_bytes),
          after_rest::binary
        >> = acc

        before <> chunk <> after_rest
      end)

    {:ok, buffer}
  end

  defp recv_line(socket, timeout) do
    recv_line(socket, timeout, <<>>)
  end

  defp recv_line(socket, timeout, acc) do
    case recv_exact(socket, 1, timeout) do
      {:ok, <<?\n>>} -> {:ok, acc}
      {:ok, <<byte>>} -> recv_line(socket, timeout, acc <> <<byte>>)
      other -> other
    end
  end

  defp recv_exact(socket, length, timeout) do
    :gen_tcp.recv(socket, length, timeout)
  end

  # SDK uses firmware screenshots, not VNC. Trim QEMU margins, then SDK styling on RGB.
  defp crop_trim_and_normalize_vnc(raw_pixels, fb_w, fb_h, exp_w, exp_h, pixel_format, profile) do
    with {:ok, pixels} <-
           ScreenshotPostprocess.crop_framebuffer(raw_pixels, fb_w, fb_h, exp_w, exp_h),
         {:ok, pixels} <-
           ScreenshotPostprocess.normalize_pixels_to_bgrx(pixels, pixel_format, exp_w, exp_h),
         {:ok, pixels, trim_w, trim_h} <-
           ScreenshotPostprocess.trim_content_margins(pixels, exp_w, exp_h, profile),
         {:ok, pixels} <- ScreenshotPostprocess.resize_bgrx(pixels, trim_w, trim_h, exp_w, exp_h) do
      {:ok, pixels}
    end
  end
end
