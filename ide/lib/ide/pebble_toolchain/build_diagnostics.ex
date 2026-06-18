defmodule Ide.PebbleToolchain.BuildDiagnostics do
  @moduledoc """
  User-facing diagnostics for Pebble SDK packaging failures.
  """

  @spec package_issue(String.t()) :: %{title: String.t(), message: String.t(), detail: String.t() | nil}
  def package_issue(output) when is_binary(output) do
    cond do
      bitmap_resource_error?(output) ->
        bitmap_resource_issue(output)

      is_map(memory_overflow_info(output)) ->
        linker_overflow_issue(memory_overflow_info(output))

      true ->
        %{
          title: "PBW packaging failed",
          message: "Pebble SDK packaging failed. See the package log below for details.",
          detail: nil
        }
    end
  end

  def package_issue(_output),
    do: %{
      title: "PBW packaging failed",
      message: "Pebble SDK packaging failed. See the package log below for details.",
      detail: nil
    }

  @spec package_hint(String.t(), [String.t()]) :: String.t() | nil
  def package_hint(output, targets) when is_binary(output) and is_list(targets) do
    cond do
      is_binary(bitmap_resource_hint(output)) ->
        bitmap_resource_hint(output)

      is_binary(memory_overflow_hint(output, targets)) ->
        memory_overflow_hint(output, targets)

      true ->
        nil
    end
  end

  def package_hint(_output, _targets), do: nil

  @spec launch_message(String.t()) :: String.t() | nil
  def launch_message(output) when is_binary(output) do
    cond do
      bitmap_resource_hint(output) ->
        "Pebble packaging failed while converting a bitmap resource. " <> bitmap_resource_hint(output)

      memory_overflow_hint(output, []) ->
        "Pebble packaging failed because the app is too large for the watch memory region. " <>
          memory_overflow_hint(output, [])

      true ->
        nil
    end
  end

  def launch_message(_output), do: nil

  @spec bitmap_resource_error?(String.t()) :: boolean()
  def bitmap_resource_error?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "resource_generator_bitmap") or
      String.contains?(normalized, "png2pblpng") or
      String.contains?(normalized, "get_palette_for_png")
  end

  def bitmap_resource_error?(_output), do: false

  defp linker_overflow_issue(info) do
    %{
      title: "PBW too large for #{target_label(info.target)}",
      message:
        "The linker says the app does not fit in the Pebble APP memory region. " <>
          overflow_action(info.target),
      detail: overflow_detail(info)
    }
  end

  defp bitmap_resource_issue(output) do
    filename = bitmap_resource_filename(output)

    message =
      case filename do
        name when is_binary(name) and name != "" ->
          "Pebble could not package bitmap `#{name}`. The file may be corrupted or not a valid PNG " <>
            "(for example a JPEG saved with a .png extension). Remove or replace it on the Resources page, " <>
            "or re-import the image."

        _ ->
          "Pebble could not package one of the bitmap resources. A file may be corrupted or not a valid PNG. " <>
            "Check bitmaps on the Resources page and re-import any suspicious images."
      end

    %{
      title: "Bitmap resource packaging failed",
      message: message,
      detail: if(filename, do: "resource=#{filename}", else: nil)
    }
  end

  defp bitmap_resource_hint(output) do
    if bitmap_resource_error?(output) do
      case bitmap_resource_filename(output) do
        name when is_binary(name) and name != "" ->
          "Diagnosis: Pebble SDK could not read bitmap `#{name}` as PNG. " <>
            "Open Resources, delete or replace that bitmap, and import a real PNG or a JPEG/WebP/BMP that the IDE can convert."

        _ ->
          "Diagnosis: Pebble SDK could not convert a bitmap resource to the watch format. " <>
            "Open Resources and re-import or remove bitmap images, then rebuild."
      end
    end
  end

  defp bitmap_resource_filename(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/resources\/bitmaps\/([^\s]+)/i, line) do
        [_, filename] -> filename
        _ -> nil
      end
    end)
  end

  defp memory_overflow_hint(output, targets) do
    normalized = String.downcase(output)

    if String.contains?(normalized, "region `app' overflowed") or
         String.contains?(normalized, "will not fit in region `app'") or
         String.contains?(normalized, "overflowed by") do
      target_hint =
        if "aplite" in targets do
          " Aplite is enabled; consider removing it from target platforms if the app is not intended to support the original black-and-white Pebble, or reduce generated code/resources."
        else
          " Reduce generated code/resources or narrow target platforms to models that can fit the app."
        end

      "Diagnosis: Pebble SDK linker output indicates a memory-region overflow.#{target_hint}"
    end
  end

  defp memory_overflow_info(output) do
    normalized = String.downcase(output)

    if String.contains?(normalized, "region `app' overflowed") or
         String.contains?(normalized, "will not fit in region `app'") or
         String.contains?(normalized, "overflowed by") do
      %{
        target: overflow_target(output),
        bytes: overflow_bytes(output)
      }
    else
      nil
    end
  end

  defp overflow_target(output) do
    lines = String.split(output, "\n")

    with index when is_integer(index) <- overflow_line_index(lines) do
      overflow_context_target(lines, index) || last_linking_target_before(lines, index)
    else
      _ -> first_pebble_app_target(output)
    end
  end

  defp overflow_line_index(lines) do
    Enum.find_index(lines, fn line ->
      normalized = String.downcase(line)

      String.contains?(normalized, "region `app' overflowed") or
        String.contains?(normalized, "will not fit in region `app'") or
        String.contains?(normalized, "overflowed by")
    end)
  end

  defp overflow_context_target(lines, index) do
    before_or_at =
      lines
      |> Enum.take(index + 1)
      |> Enum.reverse()

    after_overflow =
      lines
      |> Enum.drop(index + 1)

    (before_or_at ++ after_overflow)
    |> Enum.find_value(&pebble_app_target_from_line/1)
  end

  defp last_linking_target_before(lines, index) do
    lines
    |> Enum.take(index + 1)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Regex.run(~r/Linking\s+([a-z0-9_-]+)/i, line) do
        [_, target] -> String.downcase(target)
        _ -> nil
      end
    end)
  end

  defp first_pebble_app_target(output), do: pebble_app_target_from_line(output)

  defp pebble_app_target_from_line(line) do
    case Regex.run(~r/build\/([a-z0-9_-]+)\/pebble-app\.elf/i, line) do
      [_, target] -> String.downcase(target)
      _ -> nil
    end
  end

  defp overflow_bytes(output) do
    case Regex.run(~r/overflowed by\s+(\d+)\s+bytes/i, output) do
      [_, bytes] -> String.to_integer(bytes)
      _ -> nil
    end
  end

  defp overflow_detail(%{target: target, bytes: bytes}) when is_integer(bytes) do
    "target=#{target} overflow=#{bytes} bytes"
  end

  defp overflow_detail(%{target: target}), do: "target=#{target}"

  defp target_label(nil), do: "watch"
  defp target_label(target) when is_binary(target), do: String.capitalize(target)

  defp overflow_action("aplite") do
    "Aplite is enabled. Remove it from target platforms if you do not need original black-and-white Pebble support, or reduce app size."
  end

  defp overflow_action(_target) do
    "Reduce generated code or resources, or narrow target platforms to models that can fit the app."
  end
end
