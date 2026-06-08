defmodule Ide.Debugger.StepExecution.Message do
  @moduledoc false

  alias Ide.Debugger.StepExecution.Core

  defdelegate resolve_message(model, requested_message), to: Core
  defdelegate canonicalize_known_message(message, known_messages), to: Core
  defdelegate message_constructor_known?(message, known_messages), to: Core
  defdelegate canonicalize_message_constructor(constructor, known_messages), to: Core
  defdelegate unmapped_runtime_result(step, msg_source, known_messages), to: Core
end
