defmodule Elmx.WorkerInitArityTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.Worker

  test "worker init wrapper calls zero-arity Elm init with no args" do
    ir = %ElmEx.IR{
      modules: [
        %{
          name: "CompanionApp",
          declarations: [
            %{
              kind: :function,
              name: "init",
              args: [],
              expr: %{op: :tuple2, left: %{op: :int_literal, value: 0}, right: %{op: :cmd_none}}
            }
          ],
          unions: %{},
          diagnostics: []
        }
      ],
      diagnostics: []
    }

    source = Worker.render("Generated", "CompanionApp", ir, %{})

    assert source =~ "elmx_fn_CompanionApp_init()"
    refute source =~ "elmx_fn_CompanionApp_init(launch_context)"
  end

  test "worker init wrapper passes launch_context for Platform init" do
    ir = %ElmEx.IR{
      modules: [
        %{
          name: "Main",
          declarations: [
            %{
              kind: :function,
              name: "init",
              args: [%{name: "context"}],
              expr: %{op: :int_literal, value: 0}
            }
          ],
          unions: %{},
          diagnostics: []
        }
      ],
      diagnostics: []
    }

    source = Worker.render("Generated", "Main", ir, %{})

    assert source =~ "elmx_fn_Main_init(launch_context)"
  end
end
