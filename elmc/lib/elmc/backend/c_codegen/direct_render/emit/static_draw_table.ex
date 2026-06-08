defmodule Elmc.Backend.CCodegen.DirectRender.Emit.StaticDrawTable do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.Commands
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @spec static_draw_table_loop(
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def static_draw_table_loop(items, env, counter) when is_list(items) and length(items) >= 2 do
    case Enum.map(items, &static_draw_row(&1, env)) do
      rows when length(rows) == length(items) ->
        if Enum.all?(rows, &match?({:ok, _}, &1)) do
          parsed = Enum.map(rows, fn {:ok, row} -> row end)
          kinds = Enum.map(parsed, & &1.kind_macro)

          case Enum.uniq(kinds) do
            [_single_kind] -> emit_table(parsed, counter)
            _ -> :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  def static_draw_table_loop(_items, _env, _counter), do: :error

  @spec static_draw_row(Types.ir_expr(), Types.compile_env()) :: Types.static_draw_row_result()
  defp static_draw_row(item, env) do
    case item do
      %{op: :qualified_call, target: target, args: args} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.clear" ->
            with [color] <- args,
                 {:ok, _code, color_ref, _c} <- row_int(color, env, 0) do
              {:ok,
               %{
                 kind: :clear,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:clear)),
                 params: [color_ref]
               }}
            end

          "Pebble.Ui.textInt" ->
            with [font, pos, value] <- args,
                 {:ok, _fc, font_ref, _c1} <- row_int(font, env, 0),
                 {:ok, x_code, x_ref, c2} <- row_int(Host.record_field_expr(pos, "x"), env, 0),
                 {:ok, y_code, y_ref, c3} <- row_int(Host.record_field_expr(pos, "y"), env, c2),
                 {:ok, _vc, val_ref, _c4} <- row_int(value, env, c3) do
              {:ok,
               %{
                 kind: :text_int,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:text_int_with_font)),
                 setup: x_code <> y_code,
                 params: [font_ref, x_ref, y_ref, val_ref]
               }}
            end

          "Pebble.Ui.pixel" ->
            with [pos, color] <- args,
                 {:ok, setup, [x_ref, y_ref], _c} <-
                   static_record_int_fields(pos, ["x", "y"], env, 0),
                 {:ok, _cc, color_ref, _c2} <- row_int(color, env, 0) do
              {:ok,
               %{
                 kind: :pixel,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:pixel)),
                 setup: setup,
                 params: [x_ref, y_ref, color_ref]
               }}
            end

          "Pebble.Ui.rect" ->
            with [bounds, color] <- args,
                 {:ok, setup, bounds_refs, _c} <-
                   static_record_int_fields(bounds, ["x", "y", "w", "h"], env, 0),
                 {:ok, _cc, color_ref, _c2} <- row_int(color, env, 0) do
              {:ok,
               %{
                 kind: :rect,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:rect)),
                 setup: setup,
                 params: bounds_refs ++ [color_ref]
               }}
            end

          "Pebble.Ui.fillRect" ->
            with [bounds, color] <- args,
                 {:ok, setup, bounds_refs, _c} <-
                   static_record_int_fields(bounds, ["x", "y", "w", "h"], env, 0),
                 {:ok, _cc, color_ref, _c2} <- row_int(color, env, 0) do
              {:ok,
               %{
                 kind: :fill_rect,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:fill_rect)),
                 setup: setup,
                 params: bounds_refs ++ [color_ref]
               }}
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  @spec row_int(Types.ir_expr() | nil, Types.compile_env(), Types.compile_counter()) ::
          Types.static_row_int_result()
  defp row_int(nil, _env, counter), do: {:ok, "", "0", counter}

  defp row_int(expr, env, counter) do
    {code, ref, counter} = Host.direct_int_value(expr, env, counter)

    if static_int_ref?(ref) do
      {:ok, code, ref, counter}
    else
      :error
    end
  end

  defp static_int_ref?(ref) when is_binary(ref), do: Regex.match?(~r/^-?\d+$/, ref)

  @spec static_record_int_fields(
          Types.ir_expr(),
          [String.t()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.static_record_fields_result()
  defp static_record_int_fields(record, field_names, env, counter) do
    Enum.reduce_while(field_names, {:ok, "", [], counter}, fn field, {:ok, setup, refs, c} ->
      case row_int(Host.record_field_expr(record, field), env, c) do
        {:ok, code, ref, c2} -> {:cont, {:ok, setup <> code, refs ++ [ref], c2}}
        :error -> {:halt, :error}
      end
    end)
  end

  @spec emit_table([Types.static_draw_row()], Types.compile_counter()) :: Types.direct_emit_result()
  defp emit_table(rows, counter) do
    next = counter + 1
    table_name = "direct_static_draw_table_#{next}"

    setup_code =
      rows
      |> Enum.map_join("", fn row -> Map.get(row, :setup, "") end)

    entries =
      rows
      |> Enum.map_join(",\n", fn row ->
        [p0, p1, p2, p3, p4] =
          (row.params ++ ["0", "0", "0", "0", "0"]) |> Enum.take(5)

        "{ #{row.kind_macro}, #{p0}, #{p1}, #{p2}, #{p3}, #{p4} }"
      end)

    copy_lines =
      rows
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {_row, index} ->
        """
        #{Commands.scene_emit_guard_open()}
          elmc_draw_cmd_init(&scene_cmd, (int32_t)#{table_name}[#{index}].kind);
          scene_cmd.p0 = #{table_name}[#{index}].p0;
          scene_cmd.p1 = #{table_name}[#{index}].p1;
          scene_cmd.p2 = #{table_name}[#{index}].p2;
          scene_cmd.p3 = #{table_name}[#{index}].p3;
          scene_cmd.p4 = #{table_name}[#{index}].p4;
          #{Elmc.Backend.CCodegen.DirectRender.Emit.Catch.push_cmd_check()}
        #{Commands.scene_emit_guard_close()}
        """
      end)

    code = """
    #{setup_code}
    static const struct { int64_t kind; elmc_int_t p0, p1, p2, p3, p4; } #{table_name}[] = {
    #{entries}
    };
    #{copy_lines}
    """

    {:ok, code, counter}
  end

  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)
end
