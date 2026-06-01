defmodule Elmx.SimpleProjectCompileSourceTest do
  use ExUnit.Case

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "compile_in_memory emits window_stack in Main view" do
    revision = "source-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, result} =
             Elmx.compile_in_memory(@project_dir, %{
               entry_module: "Main",
               revision: revision,
               strip_dead_code: true,
               mode: :ide_runtime
             })

    main_source =
      result.modules
      |> Enum.find_value(fn
        %{name: name, source: source} when is_binary(name) and is_binary(source) ->
          if String.contains?(name, ".Main_") or name == "Main", do: source

        _ ->
          nil
      end)

    assert is_binary(main_source), "expected generated Main module in #{inspect(Enum.map(result.modules, & &1.name))}"
    assert main_source =~ "def elmx_fn_Main_view"
    assert main_source =~ "elmx_ui_window_stack"
    refute main_source =~ "PebbleUi.windowStack"
  end
end
