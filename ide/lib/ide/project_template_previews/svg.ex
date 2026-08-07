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
    text_clips? = Keyword.get(opts, :text_clips, false)
    svg_id = Keyword.get(opts, :svg_id, "template-preview")
    clip_id = "#{svg_id}-clip"
    clip = if round?, do: clip_markup(clip_id, width, height), else: ""
    clip_attr = if round?, do: " clip-path=\"url(##{clip_id})\"", else: ""

    drawable_ops =
      ops
      |> Enum.reject(&(Map.get(&1, :kind) in @skip_kinds))
      |> Enum.with_index()

    text_clip_defs =
      if text_clips? do
        drawable_ops
        |> Enum.flat_map(fn
          {op, index} ->
            if SvgRender.text_clippable?(op) do
              [
                ~s(<clipPath id="#{SvgRender.text_clip_id(svg_id, index)}"><rect x="#{op.x}" y="#{op.y}" width="#{op.w}" height="#{SvgRender.text_clip_height(op)}"/></clipPath>)
              ]
            else
              []
            end
        end)
        |> Enum.join("\n")
      else
        ""
      end

    body =
      drawable_ops
      |> Enum.map(fn {op, index} -> render_op(op, svg_id, index, text_clips?) end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}">
      <defs>#{clip}#{text_clip_defs}</defs>
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

  @spec render_op(svg_op(), String.t(), non_neg_integer(), boolean()) :: String.t()
  defp render_op(%{kind: :clear, color: color}, _svg_id, _index, _text_clips?) do
    "<rect x=\"0\" y=\"0\" width=\"100%\" height=\"100%\" fill=\"#{SvgRender.color(color, "white")}\"/>"
  end

  defp render_op(%{kind: :bitmap_in_rect, href: href} = op, _svg_id, _index, _text_clips?)
       when is_binary(href) do
    "<image x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" href=\"#{escape_attr(href)}\" preserveAspectRatio=\"none\"/>"
  end

  defp render_op(%{kind: :rotated_bitmap, href: href} = op, _svg_id, _index, _text_clips?)
       when is_binary(href) do
    cx = op.center_x
    cy = op.center_y
    x = op.center_x - div(op.src_w, 2)
    y = op.center_y - div(op.src_h, 2)
    angle = op |> Map.get(:angle, 0) |> pebble_angle_deg()

    "<image x=\"#{x}\" y=\"#{y}\" width=\"#{op.src_w}\" height=\"#{op.src_h}\" href=\"#{escape_attr(href)}\" transform=\"rotate(#{angle} #{cx} #{cy})\" preserveAspectRatio=\"none\"/>"
  end

  defp render_op(%{kind: :bitmap_sequence_at, href: href} = op, _svg_id, _index, _text_clips?)
       when is_binary(href) do
    width = Map.get(op, :width, op[:w] || 1)
    height = Map.get(op, :height, op[:h] || 1)

    "<image x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{width}\" height=\"#{height}\" href=\"#{escape_attr(href)}\" preserveAspectRatio=\"none\"/>"
  end

  defp render_op(%{kind: :vector_sequence_anim, frame_elements: [first | _]} = op, _svg_id, _index, _text_clips?) do
    "<svg x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.width}\" height=\"#{op.height}\" viewBox=\"0 0 #{op.width} #{op.height}\" overflow=\"visible\">#{first}</svg>"
  end

  defp render_op(%{kind: :round_rect} = op, _svg_id, _index, _text_clips?) do
    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" rx=\"#{op.radius}\" ry=\"#{op.radius}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :rect} = op, _svg_id, _index, _text_clips?) do
    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :fill_rect} = op, _svg_id, _index, _text_clips?) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"#{op.w}\" height=\"#{op.h}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :line} = op, _svg_id, _index, _text_clips?) do
    "<line x1=\"#{op.x1}\" y1=\"#{op.y1}\" x2=\"#{op.x2}\" y2=\"#{op.y2}\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :arc} = op, _svg_id, _index, _text_clips?) do
    "<path d=\"#{SvgRender.arc_path(op)}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :fill_radial} = op, _svg_id, _index, _text_clips?) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<path d=\"#{SvgRender.arc_sector_path(op)}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :path_filled} = op, _svg_id, _index, _text_clips?) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<path d=\"#{SvgRender.path_d(op, true)}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :path_outline} = op, _svg_id, _index, _text_clips?) do
    "<path d=\"#{SvgRender.path_d(op, true)}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :path_outline_open} = op, _svg_id, _index, _text_clips?) do
    "<path d=\"#{SvgRender.path_d(op, false)}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :circle} = op, _svg_id, _index, _text_clips?) do
    "<circle cx=\"#{op.cx}\" cy=\"#{op.cy}\" r=\"#{op.r}\" fill=\"none\" stroke=\"#{SvgRender.color(op.stroke_color, "#111111")}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :fill_circle} = op, _svg_id, _index, _text_clips?) do
    fill = SvgRender.color(op.fill_color, "#111111")

    "<circle cx=\"#{op.cx}\" cy=\"#{op.cy}\" r=\"#{op.r}\" fill=\"#{fill}\" stroke=\"#{SvgRender.color(op.stroke_color, fill)}\" stroke-width=\"#{op.stroke_width || 1}\"/>"
  end

  defp render_op(%{kind: :pixel} = op, _svg_id, _index, _text_clips?) do
    "<rect x=\"#{op.x}\" y=\"#{op.y}\" width=\"1\" height=\"1\" fill=\"#{SvgRender.color(op.stroke_color, "#111111")}\"/>"
  end

  defp render_op(%{kind: :text_int, text: text} = op, _svg_id, _index, _text_clips?) do
    "<text x=\"#{op.x}\" y=\"#{op.y}\" font-size=\"14\" font-family=\"monospace\" fill=\"#{SvgRender.color(op.text_color, "#111111")}\">#{escape_text(text)}</text>"
  end

  defp render_op(%{kind: :text_label, text: text} = op, svg_id, index, text_clips?) do
    anchor = SvgRender.text_anchor(op) || "start"
    baseline = SvgRender.text_baseline(op) || "auto"

    clip_attr =
      if text_clips? and SvgRender.text_clippable?(op) do
        " clip-path=\"url(##{SvgRender.text_clip_id(svg_id, index)})\""
      else
        ""
      end

    "<text x=\"#{SvgRender.text_x(op)}\" y=\"#{SvgRender.text_y(op)}\" font-size=\"#{SvgRender.text_font_size(op)}\" font-family=\"sans-serif\" text-anchor=\"#{anchor}\" dominant-baseline=\"#{baseline}\"#{clip_attr} fill=\"#{SvgRender.color(op.text_color, "#111111")}\">#{escape_text(text)}</text>"
  end

  defp render_op(_op, _svg_id, _index, _text_clips?), do: ""

  @spec pebble_angle_deg(integer() | float() | nil) :: float()
  defp pebble_angle_deg(angle) when is_integer(angle), do: angle * 360.0 / 65_536.0
  defp pebble_angle_deg(_), do: 0.0

  @spec escape_text(String.t() | number() | atom() | boolean()) :: String.t()
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
