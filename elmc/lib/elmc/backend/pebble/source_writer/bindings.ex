defmodule Elmc.Backend.Pebble.SourceWriter.Bindings do
  @moduledoc false

  alias Elmc.Backend.Pebble.{DispatchEmit, MsgCodegen, SceneWriter, Types, Util}

  @type t :: Types.source_bindings()

  @spec from_analysis(Types.shim_analysis(), Types.entry_module()) :: Types.source_bindings()
  def from_analysis(%{} = analysis, entry_module) do
    %{
      msg_constructors: msg_constructors,
      msg_constructor_arities: msg_constructor_arities,
      has_view: has_view,
      random_generate_tag: random_generate_tag,
      feature_flags: feature_flags
    } = analysis

    %{
      msg: MsgCodegen.fragments(msg_constructors, msg_constructor_arities),
      direct_view_macro: Util.direct_command_macro(entry_module, "view"),
      entry_view_scene_append: Util.entry_fn_name(entry_module, "view_scene_append"),
      entry_view_fn: Util.entry_fn_name(entry_module, "view"),
      random_generate_tag: random_generate_tag,
      has_view: has_view,
      compass_dispatch_source: DispatchEmit.compass_source(feature_flags),
      scene_writer_source: SceneWriter.source_implementation()
    }
  end
end
