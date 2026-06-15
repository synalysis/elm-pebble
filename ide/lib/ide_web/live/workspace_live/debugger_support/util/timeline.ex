defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util.Timeline do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type events :: Types.events()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type timeline_kind :: Types.timeline_kind()

  @spec upper_seq(events(), maybe_non_neg_integer()) :: non_neg_integer()
  def upper_seq(events, cursor_seq) do
    cond do
      is_integer(cursor_seq) -> cursor_seq
      events == [] -> 0
      true -> events |> Enum.map(& &1.seq) |> Enum.max()
    end
  end

  @spec kind_for_type(String.t()) :: timeline_kind()
  def kind_for_type(type) when is_binary(type) do
    cond do
      String.starts_with?(type, "debugger.protocol_") -> :protocol
      String.starts_with?(type, "debugger.update_") -> :update
      String.starts_with?(type, "debugger.view_") -> :render

      type in [
        "debugger.start",
        "debugger.reset",
        "debugger.reload",
        "debugger.contract",
        "debugger.elm_introspect",
        "debugger.elmc_check",
        "debugger.elmc_compile",
        "debugger.elmc_manifest"
      ] ->
        :lifecycle

      true ->
        :other
    end
  end

  def kind_for_type(_type), do: :other
end
