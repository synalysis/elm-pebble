defmodule ElmEx.IR.Types.Pattern do
  @moduledoc """
  Case-branch and constructor argument patterns in lowered IR.
  """

  @type kind :: :wildcard | :var | :constructor | :tuple | :list | :cons | :alias | atom()

  @type t :: %{
          required(:kind) => kind(),
          optional(atom()) => term()
        }

  @type wire_pattern :: t()
end
