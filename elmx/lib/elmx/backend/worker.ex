defmodule Elmx.Backend.Worker do
  @moduledoc false

  alias Elmx.Backend.MainProgram
  alias Elmx.Runtime.CodegenRefs

  @executor_callbacks ~w(init update view subscriptions)

  @spec render(String.t(), String.t(), ElmEx.IR.t(), map()) :: String.t()
  def render(_generated_module, entry_module, ir, _opts) do
    callbacks =
      ir
      |> MainProgram.worker_field_names(entry_module)
      |> Enum.filter(&(&1 in @executor_callbacks))

    callbacks =
      if callbacks == [] do
        Enum.filter(@executor_callbacks, &function_defined?(ir, entry_module, &1))
      else
        callbacks
      end

    callback_defs =
      callbacks
      |> Enum.map(&callback_definition(&1, entry_module, ir))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    """
    def debugger_execute(request) when is_map(request) do
      Elmx.Runtime.Executor.execute_generated(__MODULE__, request)
    end

    #{callback_defs}
    """
  end

  defp callback_definition("init", entry_module, ir) do
    fn_name = callback_fn(entry_module, "init")

    if function_defined?(ir, entry_module, "init") do
      init_call =
        case function_arity(ir, entry_module, "init") do
          0 -> "#{fn_name}()"
          _ -> "#{fn_name}(launch_context)"
        end

      """
      def init(launch_context) do
        #{init_call}
      end
      """
    else
      """
      def init(_launch_context), do: {%{}, #{CodegenRefs.values()}.cmd_none()}
      """
    end
  end

  defp callback_definition("update", entry_module, ir) do
    fn_name = callback_fn(entry_module, "update")

    if function_defined?(ir, entry_module, "update") do
      """
      def update(msg, model) do
        #{fn_name}(msg, model)
      end
      """
    else
      """
      def update(_msg, model), do: {model, #{CodegenRefs.values()}.cmd_none()}
      """
    end
  end

  defp callback_definition("view", entry_module, ir) do
    fn_name = callback_fn(entry_module, "view")

    if function_defined?(ir, entry_module, "view") do
      """
      def view(model) do
        #{fn_name}(model)
      end
      """
    else
      """
      def view(_model), do: %{type: "empty", children: []}
      """
    end
  end

  defp callback_definition("subscriptions", entry_module, ir) do
    fn_name = callback_fn(entry_module, "subscriptions")

    if function_defined?(ir, entry_module, "subscriptions") do
      """
      def subscriptions(model) do
        #{fn_name}(model)
      end
      """
    end
  end

  defp callback_definition(_, _, _), do: ""

  defp callback_fn(entry_module, name) do
    "elmx_fn_#{safe(entry_module)}_#{name}"
  end

  defp function_defined?(ir, module, name) do
    Enum.any?(ir.modules, fn mod ->
      mod.name == module and
        Enum.any?(mod.declarations, &(&1.kind == :function and &1.name == name and is_map(&1.expr)))
    end)
  end

  defp function_arity(ir, module, name) do
    Enum.find_value(ir.modules, fn mod ->
      if mod.name == module do
        Enum.find_value(mod.declarations, fn
          %{kind: :function, name: ^name, args: args} when is_list(args) -> length(args)
          _ -> nil
        end)
      end
    end) || 1
  end

  defp safe(name), do: name |> String.replace(".", "_")
end
