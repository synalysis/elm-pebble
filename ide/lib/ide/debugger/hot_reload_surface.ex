defmodule Ide.Debugger.HotReloadSurface do
  @moduledoc false

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SampleViewTrees
  alias Ide.Debugger.Types

  @spec put_view_trees(Types.runtime_state(), String.t(), String.t(), String.t()) ::
          Types.runtime_state()
  def put_view_trees(state, path, revision, "phone") when is_map(state) do
    state
    |> put_in([:watch, :view_tree], SampleViewTrees.watch(path, revision))
    |> put_in([:companion, :view_tree], SampleViewTrees.companion(path, revision))
    |> put_in([:phone, :view_tree], SampleViewTrees.phone(path, revision))
  end

  def put_view_trees(state, path, revision, "protocol") when is_map(state) do
    state
    |> put_in([:watch, :view_tree], SampleViewTrees.watch(path, revision))
    |> put_in([:companion, :view_tree], SampleViewTrees.companion("protocol:#{path}", revision))
    |> put_in([:phone, :view_tree], Map.get(RuntimeSurfaces.default_phone(), :view_tree))
  end

  def put_view_trees(state, path, revision, "watch") when is_map(state) do
    state
    |> put_in([:watch, :view_tree], SampleViewTrees.watch(path, revision))
    |> put_in([:companion, :view_tree], SampleViewTrees.companion(path, revision))
    |> put_in([:phone, :view_tree], Map.get(RuntimeSurfaces.default_phone(), :view_tree))
  end

  def put_view_trees(state, _path, _revision, _source_root), do: state

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @spec maybe_append_phone_view_render(Types.runtime_state(), String.t(), append_event_fn()) ::
          Types.runtime_state()
  def maybe_append_phone_view_render(state, "phone", append_event)
      when is_map(state) and is_function(append_event, 3) do
    append_event.(
      state,
      "debugger.view_render",
      Types.ViewRenderEventPayload.from_render("phone", "phone-root")
    )
  end

  def maybe_append_phone_view_render(state, _source_root, _append_event), do: state
end
