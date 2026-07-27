defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Catch do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.ValueSlots

  @spec header_macros() :: String.t()
  def header_macros do
    ""
  end

  @spec function_body_prefix() :: String.t()
  def function_body_prefix do
    RecordCompile.reset_borrowed_field_refs()
    owned = ValueSlots.owned_declaration()
    ValueSlots.set_emit_owned_epilogue(owned != "")

    owned_line =
      case owned do
        "" -> ""
        decl -> decl <> "\n\n"
      end

    """
    RC Rc = RC_SUCCESS;
    #{owned_line}static ElmcPebbleDrawCmd scene_cmd;

    CATCH_BEGIN
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n\n")
  end

  @spec function_body_suffix() :: String.t()
  def function_body_suffix do
    cleanup = ValueSlots.epilogue_cleanup()

    cleanup_block =
      case cleanup do
        "" -> ""
        code -> "\n#{code}\n"
      end

    """

    CATCH_END;#{cleanup_block}
    return Rc;
    """
  end

  @spec push_cmd_check() :: String.t()
  def push_cmd_check do
    assign_command_append("elmc_scene_writer_push_cmd(writer, &scene_cmd)")
  end

  @spec soft_stop_if(String.t()) :: String.t()
  def soft_stop_if(rc_var) do
    """
    if (#{rc_var} != RC_SUCCESS) {
      Rc = RC_ERR_RENDER_ABORT;
      break;
    }
    """
    |> String.trim()
  end

  @spec check_rc(String.t()) :: String.t()
  def check_rc(on_failure_code \\ "") do
    on_failure = String.trim_trailing(on_failure_code)

    if on_failure == "" do
      "CHECK_RC(Rc);"
    else
      """
      if (Rc != RC_SUCCESS) {
      #{CSource.indent(on_failure, 2)}
      }
      CHECK_RC(Rc);
      """
      |> String.trim()
    end
  end

  @spec assign_command_append(String.t(), String.t()) :: String.t()
  def assign_command_append(call_expr, on_failure_code \\ "") when is_binary(call_expr) do
    """
    Rc = #{call_expr};
    #{check_rc(on_failure_code)}
    """
    |> String.trim()
  end

  @spec catch_break() :: String.t()
  def catch_break do
    """
    Rc = RC_ERR_RENDER_ABORT;
    break;
    """
    |> String.trim()
  end
end
