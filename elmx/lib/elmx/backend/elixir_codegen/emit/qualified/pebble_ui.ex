defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.PebbleUi do
  @moduledoc false

  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  @spec compile(String.t(), ir_arg_list(), env(), emit_counter()) :: qualified_result()
  def compile(target, args, env, counter) do
    case {target, args} do
      {"Pebble.Ui.windowStack", [windows]} ->
        pebble_ui_call(:window_stack, [windows], env, counter)

      {"Pebble.Ui.window", [id, layers]} ->
        pebble_ui_call(:window, [id, layers], env, counter)

      {"Pebble.Ui.canvasLayer", [z, ops]} ->
        pebble_ui_call(:canvas_layer, [z, ops], env, counter)

      {"Pebble.Ui.group", [arg]} ->
        pebble_ui_call(:group, [arg], env, counter)

      {"Pebble.Ui.context", [settings, ops]} ->
        pebble_ui_call(:context, [settings, ops], env, counter)

      _ ->
        :error
    end
  end

  def pebble_ui_call(fun, args, env, counter) when is_atom(fun) and is_list(args) do
    {parts, env, c} = Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_parts(args, env, counter)
    {:ok, code} = QualifiedCodegen.module_call(Elmx.Runtime.Pebble.Ui, Atom.to_string(fun), parts)
    {:ok, code, env, c}
  end

end
