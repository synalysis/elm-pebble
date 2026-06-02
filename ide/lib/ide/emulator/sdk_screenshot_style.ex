defmodule Ide.Emulator.SdkScreenshotStyle do
  @moduledoc """
  Pebble SDK screenshot post-processing from `pebble_tool.commands.screenshot`:

  1. `_correct_colours/1` on every platform (including monochrome)
  2. `_roundify/1` on chalk and gabbro only (transparent corners via alpha)
  """

  alias Ide.Emulator.ScreenshotCaptureRepair
  alias Ide.Emulator.Types

  # Pebble SDK `pebble_tool.commands.screenshot._correct_colours/1` palette mapping.
  @colour_map %{
    {0, 0, 0} => {0, 0, 0},
    {0, 0, 85} => {0, 30, 65},
    {0, 0, 170} => {0, 67, 135},
    {0, 0, 255} => {0, 104, 202},
    {0, 85, 0} => {43, 74, 44},
    {0, 85, 85} => {39, 81, 79},
    {0, 85, 170} => {22, 99, 141},
    {0, 85, 255} => {0, 125, 206},
    {0, 170, 0} => {94, 152, 96},
    {0, 170, 85} => {92, 155, 114},
    {0, 170, 170} => {87, 165, 162},
    {0, 170, 255} => {76, 180, 219},
    {0, 255, 0} => {142, 227, 145},
    {0, 255, 85} => {142, 230, 158},
    {0, 255, 170} => {138, 235, 192},
    {0, 255, 255} => {132, 245, 241},
    {85, 0, 0} => {74, 22, 27},
    {85, 0, 85} => {72, 39, 72},
    {85, 0, 170} => {64, 72, 138},
    {85, 0, 255} => {47, 107, 204},
    {85, 85, 0} => {86, 78, 54},
    {85, 85, 85} => {84, 84, 84},
    {85, 85, 170} => {79, 103, 144},
    {85, 85, 255} => {65, 128, 208},
    {85, 170, 0} => {117, 154, 100},
    {85, 170, 85} => {117, 157, 118},
    {85, 170, 170} => {113, 166, 164},
    {85, 170, 255} => {105, 181, 221},
    {85, 255, 0} => {158, 229, 148},
    {85, 255, 85} => {157, 231, 160},
    {85, 255, 170} => {155, 236, 194},
    {85, 255, 255} => {149, 246, 242},
    {170, 0, 0} => {153, 53, 63},
    {170, 0, 85} => {152, 62, 90},
    {170, 0, 170} => {149, 86, 148},
    {170, 0, 255} => {143, 116, 210},
    {170, 85, 0} => {157, 91, 77},
    {170, 85, 85} => {157, 96, 100},
    {170, 85, 170} => {154, 112, 153},
    {170, 85, 255} => {149, 135, 213},
    {170, 170, 0} => {175, 160, 114},
    {170, 170, 85} => {174, 163, 130},
    {170, 170, 170} => {171, 171, 171},
    {170, 170, 255} => {167, 186, 226},
    {170, 255, 0} => {201, 232, 157},
    {170, 255, 85} => {201, 234, 167},
    {170, 255, 170} => {199, 240, 200},
    {170, 255, 255} => {195, 249, 247},
    {255, 0, 0} => {227, 84, 98},
    {255, 0, 85} => {226, 88, 116},
    {255, 0, 170} => {225, 106, 163},
    {255, 0, 255} => {222, 131, 220},
    {255, 85, 0} => {230, 110, 107},
    {255, 85, 85} => {230, 114, 124},
    {255, 85, 170} => {227, 127, 167},
    {255, 85, 255} => {225, 148, 223},
    {255, 170, 0} => {241, 170, 134},
    {255, 170, 85} => {241, 173, 147},
    {255, 170, 170} => {239, 181, 184},
    {255, 170, 255} => {236, 195, 235},
    {255, 255, 0} => {255, 238, 171},
    {255, 255, 85} => {255, 241, 181},
    {255, 255, 170} => {255, 246, 211},
    {255, 255, 255} => {255, 255, 255}
  }

  @transparent <<0, 0, 0, 0>>

  # Corner skip counts from display_spalding.c via Pebble SDK `_roundify/1`.
  @roundness_chalk [
    76,
    71,
    66,
    63,
    60,
    57,
    55,
    52,
    50,
    48,
    46,
    45,
    43,
    41,
    40,
    38,
    37,
    36,
    34,
    33,
    32,
    31,
    29,
    28,
    27,
    26,
    25,
    24,
    23,
    22,
    22,
    21,
    20,
    19,
    18,
    18,
    17,
    16,
    15,
    15,
    14,
    13,
    13,
    12,
    12,
    11,
    10,
    10,
    9,
    9,
    8,
    8,
    7,
    7,
    7,
    6,
    6,
    5,
    5,
    5,
    4,
    4,
    4,
    3,
    3,
    3,
    2,
    2,
    2,
    2,
    2,
    1,
    1,
    1,
    1,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  ]

  @roundness_gabbro [
    119,
    110,
    105,
    100,
    96,
    93,
    89,
    86,
    84,
    81,
    79,
    77,
    74,
    72,
    70,
    68,
    67,
    65,
    63,
    62,
    60,
    58,
    57,
    55,
    54,
    53,
    51,
    50,
    49,
    48,
    46,
    45,
    44,
    43,
    42,
    41,
    40,
    39,
    38,
    37,
    36,
    35,
    34,
    33,
    32,
    31,
    30,
    30,
    29,
    28,
    27,
    26,
    26,
    25,
    24,
    23,
    23,
    22,
    21,
    21,
    20,
    20,
    19,
    18,
    18,
    17,
    17,
    16,
    15,
    15,
    14,
    14,
    13,
    13,
    12,
    12,
    12,
    11,
    11,
    10,
    10,
    9,
    9,
    9,
    8,
    8,
    7,
    7,
    7,
    6,
    6,
    6,
    6,
    5,
    5,
    5,
    4,
    4,
    4,
    4,
    3,
    3,
    3,
    3,
    3,
    2,
    2,
    2,
    2,
    2,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  ]

  @roundness_by_platform %{
    "chalk" => @roundness_chalk,
    "gabbro" => @roundness_gabbro
  }

  @spec process(String.t(), binary(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, Types.screenshot_error()}
  def process(platform, rgb, width, height)
      when is_binary(rgb) and is_integer(width) and width > 0 and is_integer(height) and
             height > 0 do
    expected = width * height * 3

    if byte_size(rgb) < expected do
      {:error, {:invalid_rgb_buffer, byte_size(rgb), expected}}
    else
      with {:ok, rgba} <- build_rgba(platform, rgb, width, height, []) do
        Ide.Png.encode_rgba(rgba, width, height)
      end
    end
  end

  @doc false
  @spec build_rgba(String.t(), binary(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, Types.screenshot_error()}
  def build_rgba(platform, rgb, width, height, opts \\ []) do
    {rgb, width, height} = ScreenshotCaptureRepair.repair_rgb(rgb, width, height, platform, opts)

    rgba =
      rgb
      |> correct_colours()
      |> rgb_to_rgba()
      |> roundify(platform, width, height)
      |> ScreenshotCaptureRepair.repair_rgba(width, height, platform)

    {:ok, rgba}
  end

  @spec correct_colours(binary()) :: binary()
  def correct_colours(rgb) do
    for <<r, g, b <- rgb>>, into: <<>> do
      {nr, ng, nb} = Map.get(@colour_map, {r, g, b}, {r, g, b})
      <<nr, ng, nb>>
    end
  end

  defp rgb_to_rgba(rgb) do
    for <<r, g, b <- rgb>>, into: <<>> do
      <<r, g, b, 255>>
    end
  end

  defp roundify(rgba, platform, width, height) do
    case Map.get(@roundness_by_platform, platform) do
      nil ->
        rgba

      quarter ->
        skips = quarter ++ Enum.reverse(quarter)
        row_bytes = width * 4

        for y <- 0..(height - 1), into: <<>> do
          skip = Enum.at(skips, y, 0)
          row_offset = y * row_bytes
          row = :binary.part(rgba, row_offset, row_bytes)

          for x <- 0..(width - 1), into: <<>> do
            if x >= skip and x < width - skip do
              :binary.part(row, x * 4, 4)
            else
              @transparent
            end
          end
        end
    end
  end
end
