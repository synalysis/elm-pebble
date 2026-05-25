defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types.CommandMap
  @spec eval(String.t(), EvalTypes.runtime_values()) :: EvalTypes.builtin_eval_result()
  def eval("none", []), do: {:ok, %{"kind" => "cmd.none", "commands" => []}}

  def eval("batch", [commands]) when is_list(commands),
    do: {:ok, %{"kind" => "cmd.batch", "commands" => commands}}

  def eval("timerAfter", [ms]) when is_integer(ms),
    do: {:ok, {:builtin_partial, "timerAfter", [ms]}}

  def eval("timerAfter", [ms, message_ctor]) when is_integer(ms),
    do: timer_after_command(ms, message_ctor)

  def eval("map", [_fun, command]), do: {:ok, command}
  def eval(_function_name, _values), do: :no_builtin

  @spec timer_after_command(integer(), EvalTypes.runtime_value()) ::
          {:ok, CommandMap.t()} | :no_builtin
  defp timer_after_command(ms, message_ctor) when is_integer(ms) do
    {message, message_value} = normalize_timer_message(message_ctor)

    {:ok,
     %{
       "kind" => "cmd.timer.after",
       "package" => "pebble/cmd",
       "delay_ms" => ms,
       "message" => message,
       "message_value" => message_value
     }}
  end

  @spec normalize_timer_message(EvalTypes.runtime_value()) :: {String.t(), EvalTypes.runtime_value()}
  defp normalize_timer_message(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: {ctor, %{"ctor" => ctor, "args" => args || []}}

  defp normalize_timer_message(%{ctor: ctor, args: args}) when is_binary(ctor),
    do: {ctor, %{ctor: ctor, args: args || []}}

  defp normalize_timer_message({:function_ref, name}) when is_binary(name),
    do: {name, %{"ctor" => name, "args" => []}}

  defp normalize_timer_message({tag, payload}) when is_integer(tag),
    do: {"tag:#{tag}", {tag, payload}}

  defp normalize_timer_message(ctor) when is_binary(ctor),
    do: {ctor, %{"ctor" => ctor, "args" => []}}

  defp normalize_timer_message(tag) when is_integer(tag),
    do: {"tag:#{tag}", tag}

  defp normalize_timer_message(_message_ctor), do: {"TimerFired", %{"ctor" => "TimerFired", "args" => []}}
end
