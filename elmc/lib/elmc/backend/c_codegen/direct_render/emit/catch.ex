defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Catch do
  @moduledoc false

  @spec header_macros() :: String.t()
  def header_macros do
    ""
  end

  @spec function_body_prefix() :: String.t()
  def function_body_prefix do
    """
    RC Rc = RC_SUCCESS;
    static ElmcPebbleDrawCmd scene_cmd;

    CATCH_BEGIN
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n\n")
  end

  @spec function_body_suffix() :: String.t()
  def function_body_suffix do
    """

    CATCH_END;

    return Rc;
    """
  end

  @spec push_cmd_check() :: String.t()
  def push_cmd_check do
    """
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }
    """
    |> String.trim()
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

  @spec handle_child_rc(String.t()) :: String.t()
  def handle_child_rc(rc_var) do
    """
    if (#{rc_var} != RC_SUCCESS) {
      Rc = #{rc_var};
      break;
    }
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
