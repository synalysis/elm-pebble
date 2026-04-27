defmodule Ide.Formatter.Semantics.Rules do
  @moduledoc false

  @indent_width 4

  @spec indent_width() :: pos_integer()
  def indent_width, do: @indent_width
end
