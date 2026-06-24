defmodule IdeWeb.WorkspaceLive.DebuggerPage.Timeline do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type timeline_row :: SupportTypes.debugger_row()
  @type selected_row :: SupportTypes.debugger_row() | nil

  @spec row_class(timeline_row(), selected_row()) :: [String.t() | boolean()]
  def row_class(row, selected_row) do
    selected? =
      is_map(row) and is_map(selected_row) and
        Map.get(row, :seq) == Map.get(selected_row, :seq)

    target = if is_map(row), do: Map.get(row, :target), else: nil

    target_class =
      case target do
        "watch" -> "bg-sky-50 hover:bg-sky-100"
        "companion" -> "bg-emerald-50 hover:bg-emerald-100"
        _ -> "bg-white hover:bg-blue-50"
      end

    [
      "block w-full border-b border-zinc-100 px-2 py-1.5 text-left text-[11px]",
      target_class,
      selected? && "bg-blue-100 text-blue-950 ring-1 ring-inset ring-blue-300"
    ]
  end
end
