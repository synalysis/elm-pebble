defmodule Elmx.ExecutorFromElmTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Executor

  test "runtime_model_from_elm decodes nested record bools and lists" do
    wire = %{
      "platforms" => [
        %{"slot" => -1, "baseY" => 132, "moving" => %{"ctor" => "False", "args" => []}}
      ]
    }

    assert %{
             "platforms" => [%{"slot" => -1, "baseY" => 132, "moving" => false}]
           } = Executor.runtime_model_from_elm(wire)
  end
end
