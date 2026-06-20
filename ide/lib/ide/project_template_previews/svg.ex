defmodule Ide.ProjectTemplatePreviews.Svg do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPage.SvgRender
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type svg_op :: SupportTypes.svg_op()

  @skip_kinds ~w(
    push_context
    pop_context
    stroke_width
    antialiased
    stroke_color
    fill_color
    text_color
    compositing_mode
    unresolved
  )a

  @spec document([svg_op()], pos_integer(), pos_integer(), keyword()) :: String.t()
  def document(ops, width, height, opts \\ []) when is_list(ops) do
    round? = Keyword.get(opts, :round, false)
    clip_id = "template-preview-clip"
    clip = if round?, do: clip_markup(clip_id, width, height), else: ""
    clip_attr = if round?, do: " clip-path=\"url(##{clip_id})\"", else: ""

    body =
      ops
      |> Enum.reject(&(Map.get(&1, :kind) in @skip_kinds))
      |> Enum.map(&render_op/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}">
      <defs>#{clip}</defs>
      <g#{clip_attr}>
        <rect x="0" y="0" width="#{width}" height="#{height}" fill="white"/>
        #{body}
      </g>
    </svg>
    """
    |> String.trim()
  end

  @spec clip_markup(String.t(), pos_integer(), pos_integer()) :: String.t()
  defp clip_markup(clip_id, width, height) do
    radius = min(width, height) / 2

    """
    <clipPath id="#{clip_id}"><circle cx="#{width / 2}" cy="#{height / 2}" r="#{radius}"/></clipPath>
    """
  end

  @spec render_op(svg_op()) :: String.t()
  defp render_op(%{kind: :clear, color: color}) do
    "<rect x=\"0\" y=\"0\" width=\"100%\" height=\"100%\" fill=\"#{SvgRender.color(color, "white")}\"/>"
  end

  defp render_op(%{kind: :bitmap_in_rect, href: href} = op) when is_binary(href) do
    "<image x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" href=\"#{escape_attr(href)}\" preserveAspectRatio=\"none\"/>"
  end

  defp render_op(%{kind: :rotated_bitmap, href: href} = op) when is_binary(href) do
    cx = op.center_x
    cy = op.center_y
    x = op.center_x - div(op.src_w, 2)
    y = op.center_y - div(op.src_h, 2)
    angle = op |> Map.get(:angle, 0) |> pebble_angle_deg()

    "<image x=\"#{x}\" y=\"#{y}\" width=\"#{op.src_w}\" height=\"#{op.src_h}\" href=\"#{escape_attr(href)}\" transform=\"rotate(#{angle} #{cx} #{cy})\" preserveAspectRatio=\"none\"/>"
  end

  defp render_op(%{kind: :bitmap_sequence_at, href: href} = op) when is_binary(href) do
    width = Map.get(op, :width, op[:w] || 1)
    height = Map.get(op, :height, op[:h] || 1)

    "<image x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{width}\" height=\"#{height}\" href=\"#{escape_attr(href)}\" preserveAspectRatio=\"none\"/>"
  end

  defp render_op(%{kind: :vector_sequence_anim, frame_elements: [first | _]} = op) do
    "<svg x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.width}\" height=\"#{op.height}\" viewBox=\"0 0 #{op.width} #{op.height}\" overflow=\"visible\">#{first}</svg>"
  end

  defp render_op(%{kind: :round_rect} = op) do
    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" rx=\"#{op.radius}\" ry=\"#{op.radius}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :rect} = op) do
    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :fill_rect} = op) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :line} = op) do
    "<line x1=\"#{op.x1}\" y1=\"#{op.y1}\" x2=\"#{op.x2}\" y2=\"#{op.y2}\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :arc} = op) do
    "<path d=\"#{SvgRender.arc_path(op)}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :fill_radial} = op) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<path d=\"#{SvgRender.arc_sector_path(op)}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :path_filled} = op) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<path d=\"#{SvgRender.path_d(op, true)}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :path_outline} = op) do
    "<path d=\"#{SvgRender.path_d(op, true)}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :path_outline_open} = op) do
    "<path d=\"#{SvgRender.path_d(op, false)}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :circle} = op) do
    "<circle cx=\"#{op.cx}\" cy=\"#{op.cy}\" r=\"#{op.r}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :fill_circle} = op) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<circle cx=\"#{op.cx}\" cy=\"#{op.cy}\" r=\"#{op.r}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :pixel} = op) do
    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"1\" height=\"1\" fill=\"#{SvgRender.color(op.stroke_color, "#111111")}\"/>"
  end

  defp render_op(%{kind: :text_int, text: text} = op) do
    "<text x=\"#{op.x}\" y=\"#{op.y}\" font-size=\"14\" font-family=\"monospace\" fill=\"#{SvgRender.color(op.text_color, "#111111")}\">#{escape_text(text)}</text>"
  end

  defp render_op(%{kind: :text_label, text: text} = op) do
    anchor = SvgRender.text_anchor(op) || "start"
    baseline = SvgRender.text_baseline(op) || "auto"

    "<text x=\"#{SvgRender.text_x(op)}\" y=\"#{SvgRender.text_y(op)}\" font-size=\"#{SvgRender.text_font_size(op)}\" font-family=\"sans-serif\" text-anchor=\"#{anchor}\" dominant-baseline=\"#{baseline}\" fill=\"#{SvgRender.color(op.text_color, "#111111")}\">#{escape_text(text)}</text>"
  end

  defp render_op(_op), do: ""

  @spec pebble_angle_deg(integer() | term()) :: float()
  defp pebble_angle_deg(angle) when is_integer(angle), do: angle * 360.0 / 65_536.0
  defp pebble_angle_deg(_), do: 0.0

  @spec escape_text(term()) :: String.t()
  defp escape_text(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  @spec escape_attr(String.t()) :: String.t()
  defp escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
  end
end
