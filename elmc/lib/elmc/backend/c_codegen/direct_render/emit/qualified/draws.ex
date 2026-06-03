defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Qualified.Draws do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.Commands
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @type emit_result :: Types.direct_emit_result() | :no_match

  @spec emit(String.t(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          emit_result()
  def emit("Pebble.Ui.clear", [color], env, counter),
    do: Commands.append(draw_kind(:clear), [color], env, counter)

  def emit("Pebble.Ui.pixel", [pos, color], env, counter),
    do:
      Commands.append(
        draw_kind(:pixel),
        [
          SpecialValues.field_access_expr(pos, "x"),
          SpecialValues.field_access_expr(pos, "y"),
          color
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.line", [start_pos, end_pos, color], env, counter),
    do:
      Commands.append(
        draw_kind(:line),
        [
          SpecialValues.field_access_expr(start_pos, "x"),
          SpecialValues.field_access_expr(start_pos, "y"),
          SpecialValues.field_access_expr(end_pos, "x"),
          SpecialValues.field_access_expr(end_pos, "y"),
          color
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.rect", [bounds, color], env, counter),
    do: Commands.bounds_command(draw_kind(:rect), bounds, [color], env, counter)

  def emit("Pebble.Ui.fillRect", [bounds, color], env, counter),
    do: Commands.bounds_command(draw_kind(:fill_rect), bounds, [color], env, counter)

  def emit("Pebble.Ui.circle", [center, radius, color], env, counter),
    do:
      Commands.append(
        draw_kind(:circle),
        [
          SpecialValues.field_access_expr(center, "x"),
          SpecialValues.field_access_expr(center, "y"),
          radius,
          color
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.fillCircle", [center, radius, color], env, counter),
    do:
      Commands.append(
        draw_kind(:fill_circle),
        [
          SpecialValues.field_access_expr(center, "x"),
          SpecialValues.field_access_expr(center, "y"),
          radius,
          color
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.textInt", [font, pos, value], env, counter),
    do:
      Commands.append(
        draw_kind(:text_int_with_font),
        [
          font,
          SpecialValues.field_access_expr(pos, "x"),
          SpecialValues.field_access_expr(pos, "y"),
          value
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.textLabel", [font, pos, label], env, counter),
    do:
      Commands.append_text(
        draw_kind(:text_label_with_font),
        [
          font,
          SpecialValues.field_access_expr(pos, "x"),
          SpecialValues.field_access_expr(pos, "y"),
          %{op: :int_literal, value: 0},
          %{op: :int_literal, value: 0}
        ],
        label,
        env,
        counter
      )

  def emit("Pebble.Ui.text", [font, options, bounds, value], env, counter),
    do:
      Commands.append_text(
        draw_kind(:text),
        [
          font,
          SpecialValues.field_access_expr(bounds, "x"),
          SpecialValues.field_access_expr(bounds, "y"),
          SpecialValues.field_access_expr(bounds, "w"),
          SpecialValues.field_access_expr(bounds, "h"),
          Host.direct_text_options_arg(options, env, counter)
        ],
        value,
        env,
        counter
      )

  def emit("Pebble.Ui.roundRect", [bounds, radius, color], env, counter),
    do: Commands.bounds_command(draw_kind(:round_rect), bounds, [radius, color], env, counter)

  def emit("Pebble.Ui.arc", [bounds, start_angle, end_angle], env, counter),
    do: Commands.bounds_command(draw_kind(:arc), bounds, [start_angle, end_angle], env, counter)

  def emit("Pebble.Ui.fillRadial", [bounds, start_angle, end_angle], env, counter),
    do:
      Commands.bounds_command(
        draw_kind(:fill_radial),
        bounds,
        [start_angle, end_angle],
        env,
        counter
      )

  def emit("Pebble.Ui.drawBitmapInRect", [bitmap, bounds], env, counter),
    do:
      Commands.append(
        draw_kind(:bitmap_in_rect),
        [
          bitmap,
          SpecialValues.field_access_expr(bounds, "x"),
          SpecialValues.field_access_expr(bounds, "y"),
          SpecialValues.field_access_expr(bounds, "w"),
          SpecialValues.field_access_expr(bounds, "h")
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.drawVectorAt", [vector, origin], env, counter),
    do:
      Commands.append(
        draw_kind(:vector_at),
        [
          vector,
          SpecialValues.field_access_expr(origin, "x"),
          SpecialValues.field_access_expr(origin, "y")
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.drawVectorSequenceAt", [vector, origin], env, counter),
    do:
      Commands.append(
        draw_kind(:vector_sequence_at),
        [
          vector,
          SpecialValues.field_access_expr(origin, "x"),
          SpecialValues.field_access_expr(origin, "y")
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.drawBitmapSequenceAt", [animation, origin], env, counter),
    do:
      Commands.append(
        draw_kind(:bitmap_sequence_at),
        [
          animation,
          SpecialValues.field_access_expr(origin, "x"),
          SpecialValues.field_access_expr(origin, "y")
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.drawRotatedBitmap", [bitmap, bounds, rotation, center], env, counter),
    do:
      Commands.append(
        draw_kind(:rotated_bitmap),
        [
          bitmap,
          SpecialValues.field_access_expr(bounds, "w"),
          SpecialValues.field_access_expr(bounds, "h"),
          rotation,
          SpecialValues.field_access_expr(center, "x"),
          SpecialValues.field_access_expr(center, "y")
        ],
        env,
        counter
      )

  def emit("Pebble.Ui.pathFilled", [path], env, counter),
    do: Commands.path_command(draw_kind(:path_filled), path, env, counter)

  def emit("Pebble.Ui.pathOutline", [path], env, counter),
    do: Commands.path_command(draw_kind(:path_outline), path, env, counter)

  def emit("Pebble.Ui.pathOutlineOpen", [path], env, counter),
    do: Commands.path_command(draw_kind(:path_outline_open), path, env, counter)

  def emit(_target, _args, _env, _counter), do: :no_match

  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)
end
