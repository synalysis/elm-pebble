defmodule Ide.Debugger.CompanionPhoneCompileTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompanionPhoneCompile

  test "needs_compile? is false when lazy elmc and companion has no parser-expression view" do
    previous = Application.get_env(:ide, :debugger_lazy_elmc)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ide, :debugger_lazy_elmc)
      else
        Application.put_env(:ide, :debugger_lazy_elmc, previous)
      end
    end)

    Application.put_env(:ide, :debugger_lazy_elmc, true)

    state = %{
      companion: %{
        model: %{},
        shell: %{
          "elm_introspect" => %{
            "view_tree" => %{"type" => "window", "children" => []}
          }
        }
      }
    }

    refute CompanionPhoneCompile.needs_compile?(state, %{})
  end
end
