defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Catch do
  @moduledoc false

  @spec header_macros() :: String.t()
  def header_macros do
    """
    #ifndef ELMC_CATCH_MACROS
    #define ELMC_CATCH_MACROS
    #define CATCH_BEGIN     do {
    #define CATCH_END       } while (1!=1);
    #define CATCH_BREAK     { direct_rc = -2; break; }
    #endif
    """
  end

  @spec function_body_prefix() :: String.t()
  def function_body_prefix do
    """
    int direct_rc = 0;
    static ElmcPebbleDrawCmd scene_cmd;
    CATCH_BEGIN
    """
  end

  @spec function_body_suffix() :: String.t()
  def function_body_suffix do
    """
    CATCH_END
    return direct_rc;
    """
  end

  @spec push_cmd_check() :: String.t()
  def push_cmd_check do
    """
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }
    """
    |> String.trim()
  end

  @spec soft_stop_if(String.t()) :: String.t()
  def soft_stop_if(rc_var) do
    """
    if (#{rc_var} == -2) {
      CATCH_BREAK;
    }
    """
    |> String.trim()
  end

  @spec handle_child_rc(String.t()) :: String.t()
  def handle_child_rc(rc_var) do
    """
    if (#{rc_var} < 0) return #{rc_var};
    if (#{rc_var} == -2) {
      CATCH_BREAK;
    }
    """
    |> String.trim()
  end
end
