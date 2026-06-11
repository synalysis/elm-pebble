defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Screen do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.{RuntimeAccess, Wire}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @default_screen_w 144
  @default_screen_h 168

  @type runtime_input :: PreviewTypes.runtime_input()
  @type view_tree :: PreviewTypes.view_tree() | nil

  @spec screen_dimensions(runtime_input(), view_tree()) :: {pos_integer(), pos_integer()}
  def screen_dimensions(runtime, tree \\ nil) do
    raw_model = RuntimeAccess.raw_runtime_model(runtime)
    model = RuntimeAccess.runtime_model(runtime)

    launch =
      Wire.first_map([
        Wire.map_get_any(model, "launch_context"),
        Wire.map_get_any(raw_model, "launch_context")
      ])

    launch_screen = Wire.first_map([Wire.map_get_any(launch, "screen")])
    tree_box = if is_map(tree), do: Wire.first_map([Wire.map_get_any(tree, "box")]), else: %{}

    width =
      Wire.first_present([
        Wire.map_get_any(launch_screen, "width"),
        Wire.map_get_any(tree_box, "w")
      ])

    height =
      Wire.first_present([
        Wire.map_get_any(launch_screen, "height"),
        Wire.map_get_any(tree_box, "h")
      ])

    {Wire.dimension_int(width, @default_screen_w), Wire.dimension_int(height, @default_screen_h)}
  end

  @spec screen_round?(runtime_input(), view_tree()) :: boolean()
  def screen_round?(runtime, tree \\ nil) do
    raw_model = RuntimeAccess.raw_runtime_model(runtime)
    model = RuntimeAccess.runtime_model(runtime)

    launch =
      Wire.first_map([
        Wire.map_get_any(model, "launch_context"),
        Wire.map_get_any(raw_model, "launch_context")
      ])

    launch_screen = Wire.first_map([Wire.map_get_any(launch, "screen")])

    round? =
      Wire.first_present([
        case Wire.map_get_any(launch_screen, "shape") do
          "Round" -> true
          "Rectangular" -> false
          "round" -> true
          "rect" -> false
          _ -> nil
        end,
        Wire.map_get_any(launch_screen, "isRound")
      ])

    shape =
      if is_map(tree) do
        Wire.map_get_any(tree, "shape")
      end

    Wire.boolean_value?(round?) || shape == "round"
  end
end
