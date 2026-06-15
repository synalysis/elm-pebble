defmodule Elmx.TypesContractTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.CodegenRefs

  @ref_funs CodegenRefs.__info__(:functions) -- [{:module_ref, 1}, {:registry_modules, 0}]

  test "CodegenRefs module paths are stable Elmx.Runtime strings" do
    for {name, 0} <- @ref_funs do
      path = apply(CodegenRefs, name, [])
      assert is_binary(path)
      assert String.starts_with?(path, "Elmx.Runtime.")
      assert CodegenRefs.module_ref(String.to_existing_atom("Elixir." <> path)) == path
    end
  end

  test "executor contract matches manifest contract field" do
    assert Elmx.Runtime.Executor.contract() == "elmx.runtime_executor.v1"
  end

  test "executor_request typespec accepts IDE-style wire keys" do
    request = %{
      "message" => "Tick",
      "message_value" => %{"ctor" => "FrameTick", "args" => [%{"dtMs" => 33}]},
      "current_model" => %{
        "runtime_model" => %{},
        "launch_context" => %{}
      },
      "source_root" => "watch"
    }

    assert is_map(request)
    assert Map.has_key?(request, "message")
  end

  test "ui_path accepts path node consumed by outline helpers" do
    triangle = Elmx.Runtime.Pebble.Ui.path([%{x: 0, y: 0}, %{x: 10, y: 0}], %{x: 0, y: 0}, 0)

    assert triangle.type == "path"
    outline = Elmx.Runtime.Pebble.Ui.path_outline(triangle)
    assert outline.type == "pathOutline"
  end

  test "view_shape_input accepts tagged IR and render-op lists" do
    tree =
      Elmx.Runtime.ViewShape.normalize([
        %{"type" => "clear", "color" => 255},
        %{"ctor" => "Line", "args" => [72, 84, 30, 60, 192]}
      ])

    assert tree["type"] == "windowStack"
  end

  test "wire_map values are wire_value-shaped" do
    map = %{"nested" => %{"ctor" => "Just", "args" => [1]}, "n" => 2}

    assert is_map(map["nested"])
    assert map["n"] == 2
  end

  test "dict_from_list normalizes wire tuple entries" do
    dict =
      Elmx.Runtime.Core.Collections.dict_from_list([
        %{"ctor" => "Tuple", "args" => [1, "a"]}
      ])

    assert dict == [{1, "a"}]
  end

  test "pebble colors accept ui_color wire and packed ints" do
    assert Elmx.Runtime.Pebble.Colors.to_int(0xFF000000) == 0xC0
    assert Elmx.Runtime.Pebble.Colors.to_int(%{"ctor" => "Indexed", "args" => [5]}) == 5
  end

  test "text options and subscription masks accept wire shapes" do
    assert Elmx.Runtime.Pebble.TextOptions.fields(%{"alignment" => "left"}) == {"left", "word_wrap"}

    assert Elmx.Runtime.Pebble.Subscriptions.item_mask(4) == 4
    assert Elmx.Runtime.Pebble.Subscriptions.item_mask(%{op: :int_literal, value: 2}) == 2
  end

  test "values wire helpers round-trip ctor and model maps" do
    assert Elmx.Runtime.Values.wire_value({:Ok, 1}) == %{"ctor" => "Ok", "args" => [1]}

    model = %{"ctor" => "Model", "args" => [%{"ctor" => "Record", "args" => [2]}]}
    assert Elmx.Runtime.Values.model_to_runtime_map(model) == model
    assert Elmx.Runtime.Values.model_to_runtime_map(7) == %{"value" => 7}
  end

  test "wire_value and cmd batch normalize nested command maps" do
    nested = Elmx.Runtime.Cmd.batch([Elmx.Runtime.Cmd.none(), %{"kind" => "none"}])

    assert nested["kind"] == "batch"
    assert Enum.all?(nested["commands"], &(&1["kind"] == "none"))

    assert Elmx.Runtime.Values.wire_value({:Just, 1}) == %{"ctor" => "Just", "args" => [1]}
  end

  test "maybe_result helpers accept native and wire unions" do
    assert Elmx.Runtime.Core.MaybeResult.maybe_with_default(0, :Nothing) == 0
    assert Elmx.Runtime.Core.MaybeResult.maybe_with_default(0, %{"ctor" => "Just", "args" => [7]}) == 7
    assert Elmx.Runtime.Core.MaybeResult.result_to_maybe({:Ok, 3}) == {:Just, 3}
  end

  test "http_body and loader error types accept runtime shapes" do
    body = %{"kind" => "json", "content_type" => "application/json", "body" => "{}"}
    assert body["kind"] == "json"

    detail = %{message: "syntax error", line: 1}
    assert {:compile_failed, "Main", ^detail} = {:compile_failed, "Main", detail}
  end

  test "view_shape normalizes ctor trees from different wire shapes" do
    wire_tree =
      Elmx.Runtime.ViewShape.normalize(%{
        "ctor" => "WindowStack",
        "args" => [[%{"ctor" => "WindowNode", "args" => [1, []]}]]
      })

    tagged =
      Elmx.Runtime.ViewShape.normalize({1000, [{1001, {1, []}}]})

    assert wire_tree["type"] == "windowStack"
    assert tagged["type"] == "windowStack"
  end

  test "launch_reason_to_int maps wire ctor names" do
    assert Elmx.Runtime.LaunchContext.launch_reason_to_int(%{"ctor" => "LaunchPhone", "args" => []}) ==
             2

    assert Elmx.Runtime.LaunchContext.launch_reason_to_int("LaunchUser") == 1
  end

  test "core apply helpers accept elm_hof callbacks" do
    double = fn x -> x + x end
    assert Elmx.Runtime.Core.apply1(double, 3) == 6
    assert Elmx.Runtime.Core.apply2(fn a, b -> a <> b end, "a", "b") == "ab"
  end

  test "qualified List.foldl codegen matches Core.foldl at runtime" do
    assert {:ok, code} = Elmx.Runtime.Stdlib.Qualified.call("List.foldl", "f, 0, xs")
    assert code =~ ".foldl("

    assert Elmx.Runtime.Core.foldl(fn x, acc -> [x | acc] end, [], [1, 2]) == [2, 1]
  end

  test "view_output flattens ViewShape-normalized trees from different draw inputs" do
    line_tree =
      Elmx.Runtime.ViewShape.normalize([
        Elmx.Runtime.Pebble.Ui.line(%{x: 0, y: 0}, %{x: 10, y: 10}, 0)
      ])

    rect_tree =
      Elmx.Runtime.ViewShape.normalize([
        Elmx.Runtime.Pebble.Ui.rect(%{x: 1, y: 2, w: 3, h: 4}, 0)
      ])

    assert [%{"kind" => "line"} | _] =
             Elmx.Runtime.ViewOutput.from_view_tree(line_tree, screen_w: 144, screen_h: 168)

    assert [%{"kind" => "rect"} | _] =
             Elmx.Runtime.ViewOutput.from_view_tree(rect_tree, screen_w: 144, screen_h: 168)
  end

  test "companion preferences decode accepts wire Just and raw JSON strings" do
    decoder = {:json_decoder, :string}

    assert {:Ok, %{"k" => 1}} =
             Elmx.Runtime.CompanionPreferences.decode_response(
               decoder,
               %{"ctor" => "Just", "args" => ["{\"k\":1}"]}
             )

    assert {:Ok, %{"plain" => true}} =
             Elmx.Runtime.CompanionPreferences.decode_response(decoder, "{\"plain\":true}")

    assert {:Err, :MissingResponse} =
             Elmx.Runtime.CompanionPreferences.decode_response(decoder, %{"ctor" => "Nothing"})
  end

  test "message_decode maps wire ctor and string messages to elm_msg" do
    assert Elmx.Runtime.MessageDecode.decode("Tick") == :Tick

    assert Elmx.Runtime.MessageDecode.decode("FrameTick", %{
             "ctor" => "FrameTick",
             "args" => [%{"dtMs" => 16}]
           }) == {:FrameTick, %{"dtMs" => 16}}
  end

  test "qualified_arg_code and Helpers.split_args agree on arity" do
    args = Elmx.Runtime.Stdlib.Qualified.Helpers.split_args("f, xs, 1")
    assert args == ["f", "xs", "1"]

    assert {:ok, code} = Elmx.Runtime.Stdlib.Qualified.call("List.map", "f, xs")
    assert code =~ ".map(f, xs)"
  end

  test "view_output_opts and cmd option types accept executor-style keywords" do
    tree = Elmx.Runtime.ViewShape.normalize([%{"type" => "clear", "color" => 0}])

    assert [_] =
             Elmx.Runtime.ViewOutput.from_view_tree(tree,
               screen_w: 144,
               screen_h: 168,
               vector_resource_indices: %{"logo" => 1}
             )

    assert %{"kind" => "cmd.companion.bridge"} =
             Elmx.Runtime.Cmd.companion_bridge("storage", "read", callback: "OnRead", key: "k")

    assert %{"kind" => "cmd.subscription.register"} =
             Elmx.Runtime.Cmd.subscription_register("Pebble.Tick",
               callback: "Tick",
               interval_ms: 1000
             )
  end

  test "followups flatten batch commands and extract protocol events" do
    protocol = %{"kind" => "protocol", "message" => "Tick", "message_value" => nil}
    batch = Elmx.Runtime.Cmd.batch([protocol, Elmx.Runtime.Cmd.none()])

    assert [%{"kind" => "protocol"}] = Elmx.Runtime.Followups.flatten_commands(batch)
    assert [%{type: "debugger.protocol_tx"} | _] = Elmx.Runtime.Followups.protocol_events(batch)
  end
end
