defmodule IdeWeb.WorkspaceLive.DebuggerPage.Preview do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeSurfaces
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerPage.Assigns
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type assigns :: Assigns.t()
  @type runtime_input :: SupportTypes.runtime_input()
  @type view_tree :: SupportTypes.view_tree() | nil
  @type svg_op :: SupportTypes.svg_op()

  @spec preview_tree(runtime_input() | nil) :: view_tree()
  def preview_tree(%{} = runtime) do
    view_tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    if is_map(view_tree) and map_size(view_tree) > 0 do
      view_tree
    else
      case RuntimeArtifacts.introspect(runtime) do
        ei when is_map(ei) ->
          parser_tree = Map.get(ei, "view_tree") || Map.get(ei, :view_tree)
          if is_map(parser_tree), do: parser_tree, else: nil

        _ ->
          nil
      end
    end
  end

  def preview_tree(_runtime), do: nil

  @spec svg_preview_tree(view_tree(), view_tree()) :: view_tree()
  def svg_preview_tree(%{} = rendered_tree, _fallback) when map_size(rendered_tree) > 0,
    do: rendered_tree

  def svg_preview_tree(_rendered_tree, fallback), do: fallback

  @spec watch_color_mode(runtime_input()) :: String.t() | nil
  def watch_color_mode(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}

    launch_context =
      Map.get(model, "launch_context") || Map.get(model, :launch_context) ||
        get_in(model, ["runtime_model", "launch_context"]) ||
        get_in(model, [:runtime_model, :launch_context])

    case launch_context do
      %{} = ctx -> RuntimeSurfaces.launch_context_color_mode(ctx)
      _ -> nil
    end
  end

  def watch_color_mode(_runtime), do: nil

  @spec dimensions(runtime_input() | nil, view_tree()) :: {pos_integer(), pos_integer()}
  def dimensions(runtime, tree), do: DebuggerPreview.screen_dimensions(runtime, tree)

  @spec clip_id(assigns(), pos_integer(), pos_integer(), boolean()) :: String.t()
  def clip_id(assigns, screen_w, screen_h, screen_round?) do
    key = {
      Map.get(assigns, :title),
      Map.get(assigns, :hover_scope),
      screen_w,
      screen_h,
      screen_round?
    }

    "debugger-preview-clip-#{:erlang.phash2(key)}"
  end

  @spec svg_class(boolean(), boolean()) :: [String.t()]
  def svg_class(true, true) do
    [
      "mx-auto min-w-0 flex-1 aspect-square max-w-52 rounded-full border border-zinc-700 bg-white shadow-inner object-contain"
    ]
  end

  def svg_class(true, false) do
    [
      "mx-auto h-52 w-52 rounded-full border border-zinc-700 bg-white shadow-inner object-contain"
    ]
  end

  def svg_class(false, true) do
    [
      "mx-auto min-w-0 flex-1 max-w-[11.25rem] rounded border border-zinc-700 bg-white shadow-inner object-contain"
    ]
  end

  def svg_class(false, false) do
    [
      "mx-auto h-52 w-[11.25rem] rounded border border-zinc-700 bg-white shadow-inner object-contain"
    ]
  end

  @spec svg_id(assigns()) :: String.t()
  def svg_id(assigns) do
    key = {Map.get(assigns, :title), Map.get(assigns, :hover_scope)}
    "debugger-preview-svg-#{:erlang.phash2(key)}"
  end

  @spec pebble_angle_deg(integer() | term()) :: float()
  def pebble_angle_deg(angle) when is_integer(angle), do: angle * 360.0 / 65_536.0
  def pebble_angle_deg(_), do: 0.0

  @spec unresolved_svg_summary([map()]) :: String.t()
  def unresolved_svg_summary(rows), do: DebuggerPreview.unresolved_summary(rows)

  @spec svg_op_tooltip(svg_op()) :: String.t() | nil
  def svg_op_tooltip(op) when is_map(op) do
    source = Map.get(op, :source) || Map.get(op, "source")

    with %{} <- source,
         call when is_binary(call) and call != "" <-
           Map.get(source, "call") || Map.get(source, :call),
         path when is_binary(path) and path != "" <-
           Map.get(source, "path") || Map.get(source, :path),
         line when is_integer(line) <- Map.get(source, "line") || Map.get(source, :line) do
      "#{call} at #{path}:#{line}"
    else
      _ -> nil
    end
  end

  def svg_op_tooltip(_op), do: nil
end
