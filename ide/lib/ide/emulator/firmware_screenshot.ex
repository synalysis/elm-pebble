defmodule Ide.Emulator.FirmwareScreenshot do
  @moduledoc false

  import Bitwise

  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.SdkScreenshotStyle
  alias Ide.Emulator.Types
  alias Ide.ScreenshotDimensions
  alias Ide.WatchModels

  @endpoint 8000
  @request <<0>>
  @default_timeout 20_000
  @min_capture_timeout 25_000
  @max_capture_timeout 90_000
  @capture_timeout_base 30_000
  @capture_timeout_per_kb 400

  @doc """
  Firmware screenshot timeout scaled by framebuffer size (large color watches
  such as Gabbro send ~67 KiB over endpoint 8000 and need more than 20s).
  """
  @spec capture_timeout_ms(String.t()) :: pos_integer()
  def capture_timeout_ms(platform) do
    pixels =
      case ScreenshotDimensions.store_dimensions(platform) do
        {width, height} ->
          width * height

        nil ->
          platform
          |> WatchModels.profile_for()
          |> Map.get("screen", %{})
          |> then(fn
            %{"width" => width, "height" => height} when is_integer(width) and is_integer(height) ->
              width * height

            _ ->
              nil
          end)
      end

    case pixels do
      n when is_integer(n) and n > 0 -> timeout_from_pixels(n)
      _ -> @default_timeout
    end
  end

  @spec capture(pid(), String.t(), keyword()) :: {:ok, binary()} | {:error, Types.session_error() | Types.screenshot_error()}
  def capture(session_pid, platform, opts \\ []) when is_pid(session_pid) and is_binary(platform) do
    timeout = Keyword.get(opts, :timeout, capture_timeout_ms(platform))

    with {:ok, router} <- GenServer.call(session_pid, :protocol_router_pid),
         :ok <- Router.acquire(router, timeout) do
      try do
        capture_locked(router, platform, timeout)
      after
        Router.release(router)
      end
    end
  end

  defp capture_locked(router, platform, timeout) do
    Process.sleep(capture_settle_ms(timeout))
    :ok = Router.send_packet(router, @endpoint, @request)
    deadline_ms = System.monotonic_time(:millisecond) + timeout

    with {:ok, header, data} <- read_screenshot(router, deadline_ms),
         {:ok, rgb} <- decode_image(header, data),
         {:ok, png} <- SdkScreenshotStyle.process(platform, rgb, header.width, header.height) do
      {:ok, png}
    end
  end

  defp capture_settle_ms(timeout) when timeout >= 60_000, do: 500
  defp capture_settle_ms(timeout) when timeout >= 40_000, do: 300
  defp capture_settle_ms(_timeout), do: 150

  defp timeout_from_pixels(pixels) do
    kb = div(pixels, 1024)
    ms = @capture_timeout_base + kb * @capture_timeout_per_kb
    min(@max_capture_timeout, max(@min_capture_timeout, ms))
  end

  defp read_screenshot(router, deadline_ms) do
    with {:ok, %{payload: payload}} <-
           Router.await_frame(
             router,
             &(&1.endpoint == @endpoint),
             remaining_ms(deadline_ms)
           ),
         {:ok, header, data} <- parse_header(payload) do
      collect_payload(router, header, data, deadline_ms)
    end
  end

  defp collect_payload(router, header, data, deadline_ms) do
    if byte_size(data) >= header.expected_bytes do
      {:ok, header, :binary.part(data, 0, header.expected_bytes)}
    else
      case Router.await_frame(
             router,
             &(&1.endpoint == @endpoint),
             remaining_ms(deadline_ms)
           ) do
        {:ok, %{payload: chunk}} ->
          collect_payload(router, header, data <> chunk, deadline_ms)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp remaining_ms(deadline_ms) do
    max(1, deadline_ms - System.monotonic_time(:millisecond))
  end

  # libpebble2 `Uint32` fields use network (big-endian) byte order.
  @doc false
  @spec parse_header_payload(binary()) ::
          {:ok, Types.screenshot_header(), binary()} | {:error, Types.screenshot_error()}
  def parse_header_payload(payload), do: parse_header(payload)

  defp parse_header(
         <<response_code, version::unsigned-big-32, width::unsigned-big-32,
           height::unsigned-big-32, rest::binary>>
       ) do
    if response_code != 0 do
      {:error, {:screenshot_failed, response_code}}
    else
      with {:ok, expected_bytes} <- expected_bytes(version, width, height) do
        {:ok,
         %{
           version: version,
           width: width,
           height: height,
           expected_bytes: expected_bytes
         }, rest}
      end
    end
  end

  defp parse_header(_), do: {:error, :invalid_screenshot_header}

  defp expected_bytes(1, width, height), do: {:ok, div(width * height, 8)}
  defp expected_bytes(2, width, height), do: {:ok, width * height}
  defp expected_bytes(version, _width, _height), do: {:error, {:unknown_screenshot_version, version}}

  defp decode_image(%{version: 1, width: width, height: height}, data) do
    {:ok, decode_1bpp(width, height, data)}
  end

  defp decode_image(%{version: 2, width: width, height: height}, data) do
    {:ok, decode_8bpp(width, height, data)}
  end

  defp decode_1bpp(width, height, data) do
    row_bytes = div(width, 8)

    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      byte_idx = y * row_bytes + div(x, 8)
      bit_idx = rem(x, 8)
      on = ((:binary.at(data, byte_idx) >>> bit_idx) &&& 1) == 1
      level = if on, do: 255, else: 0
      <<level, level, level>>
    end
  end

  @doc false
  def decode_8bpp(width, height, data) do
    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      pixel = :binary.at(data, y * width + x)
      r = ((pixel >>> 4) &&& 3) * 85
      g = ((pixel >>> 2) &&& 3) * 85
      b = (pixel &&& 3) * 85
      <<r, g, b>>
    end
  end
end
