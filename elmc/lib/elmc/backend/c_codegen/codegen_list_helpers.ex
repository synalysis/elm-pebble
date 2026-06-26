defmodule Elmc.Backend.CCodegen.CodegenListHelpers do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ListLoopCodegen

  @type repeat_codegen :: {:inline, String.t(), String.t()}

  @zero_list_head "ELMC_STATIC_INT(0)"

  @spec repeat_codegen(String.t(), String.t(), pos_integer(), map()) :: repeat_codegen()
  def repeat_codegen(count_ref, value_ref, loop_id, env \\ %{}) do
    {code, out} = ListLoopCodegen.emit_repeat_inline_loop(count_ref, value_ref, loop_id, env)
    {:inline, code, out}
  end

  @spec emit_immortal_zero_list(String.t(), String.t(), pos_integer()) :: String.t()
  def emit_immortal_zero_list(sym, out, count) when is_integer(count) and count > 0 do
    last = count - 1

    """
    #{emit_zero_list_static_array(sym, count)}
      #{out} = &#{sym}_cells[#{last}].value;
    """
    |> String.trim_trailing()
  end

  @spec emit_zero_repeat_prelude(String.t(), pos_integer()) :: String.t()
  def emit_zero_repeat_prelude(sym, count) when is_integer(count) and count > 0 do
    last = count - 1

    """
    #{emit_zero_list_static_array(sym, count)}

    static ElmcValue *#{sym}_get(void) {
      return &#{sym}_cells[#{last}].value;
    }
    """
    |> String.trim_trailing()
  end

  @spec emit_zero_list_static_array(String.t(), pos_integer()) :: String.t()
  def emit_zero_list_static_array(sym, count) when is_integer(count) and count > 0 do
    inits = emit_zero_list_static_inits(sym, count)

    """
    static struct {
      ElmcValue value;
      ElmcCons cons;
    } #{sym}_cells[#{count}] = {
    #{inits}
    };
    """
    |> String.trim_trailing()
  end

  @spec emit_zero_list_static_inits(String.t(), pos_integer()) :: String.t()
  defp emit_zero_list_static_inits(sym, count) when count > 0 do
    0..(count - 1)
    |> Enum.map_join(",\n", fn i ->
      tail =
        if i == 0 do
          "ELMC_STATIC_LIST_NIL"
        else
          "&#{sym}_cells[#{i - 1}].value"
        end

      [
        "      [#{i}] = {",
        "        .value = {",
        "          .rc = ELMC_RC_IMMORTAL,",
        "          .tag = ELMC_TAG_LIST,",
        "          .payload = &#{sym}_cells[#{i}].cons,",
        "          .scalar = ELMC_LIST_CELL_SCALAR",
        "        },",
        "        .cons = {",
        "          .head = #{@zero_list_head},",
        "          .tail = #{tail}",
        "        }",
        "      }"
      ]
      |> Enum.join("\n")
    end)
  end
end
