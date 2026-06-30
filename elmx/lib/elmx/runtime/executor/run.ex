defmodule Elmx.Runtime.Executor.Run do
  @moduledoc false

  alias Elmx.Runtime.Executor.Model
  alias Elmx.Runtime.MessageDecode
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec blank_message?(String.t() | Types.elm_msg() | nil) :: boolean()
  def blank_message?(nil), do: true
  def blank_message?(""), do: true
  def blank_message?(_), do: false

  @spec init_execution(module(), Types.launch_context(), Types.runtime_model()) ::
          {Types.runtime_model(), String.t(), Types.wire_cmd()}
  def init_execution(module, launch_context, previous_runtime_model) do
    if function_exported?(module, :init, 1) do
      {model, cmd} = apply(module, :init, [launch_context])
      {runtime_model, _} = Values.tuple_result_to_model_cmd({model, cmd})
      {Model.merge_runtime_model(previous_runtime_model, runtime_model), "init_model", cmd}
    else
      {previous_runtime_model, "init_model", Values.cmd_none()}
    end
  end

  @spec step_execution(
          module(),
          String.t() | Types.elm_msg(),
          Types.wire_value() | Types.elm_msg() | nil,
          Types.runtime_model()
        ) :: {Types.runtime_model(), String.t(), Types.wire_cmd()}
  def step_execution(module, message, message_value, runtime_model) do
    msg = MessageDecode.decode(message, message_value)

    if function_exported?(module, :update, 2) do
      {model, cmd} = apply(module, :update, [msg, Model.runtime_model_from_elm(runtime_model)])
      {next_runtime_model, _} = Values.tuple_result_to_model_cmd({model, cmd})

      {Model.merge_runtime_model(runtime_model, next_runtime_model), "step_message", cmd}
    else
      {runtime_model, "unmapped_message", Values.cmd_none()}
    end
  end
end
