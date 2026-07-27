defmodule Elmc.PlanPatternBindCrossModulePayloadTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.PatternBind

  test "constructor payload specs resolve from union home module, not call-site module" do
    # Scene3d.lightPair patterns `Types.Light first` while payload_specs are keyed
    # under {"Scene3d.Types", "Light"}. Looking up only {"Scene3d", "Light"} left
    # `first` untyped → field indices fell back to Point2d x@0 → broken lights12.
    light_spec =
      "{ type_ : Float, castsShadows : Bool, parameter : Float, x : Float, y : Float, z : Float, r : Float, g : Float, b : Float }"

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Scene3d.Types", "Light"} => light_spec
    })

    on_exit(fn -> Process.delete(:elmc_union_constructor_payload_specs) end)

    ctx = Context.new(module: "Scene3d", function_name: "lightPair", params: ["arg0"])
    b = Builder.new("Scene3d", "lightPair", rc_required: false)
    {subject_reg, b1} = Builder.fresh_reg(b)

    # Shorthand `Types.Light first` → payload in `:bind`
    pattern_bind = %{
      kind: :constructor,
      name: "Types.Light",
      resolved_name: "Scene3d.Types.Light",
      bind: "first",
      arg_pattern: nil
    }

    assert {:ok, ctx1, _} = PatternBind.bind(pattern_bind, ctx, b1, subject_reg)
    assert Context.local_type(ctx1, "first") == light_spec
    assert_light_fields(ctx1, "first")

    # Same ctor with payload as arg_pattern var
    pattern_arg = %{
      kind: :constructor,
      name: "Types.Light",
      resolved_name: "Scene3d.Types.Light",
      arg_pattern: %{kind: :var, name: "first"}
    }

    assert {:ok, ctx2, _} = PatternBind.bind(pattern_arg, ctx, b1, subject_reg)
    assert Context.local_type(ctx2, "first") == light_spec
    assert_light_fields(ctx2, "first")
  end

  test "Result.Ok type-var payload spec does not poison Ok pageData field indices" do
    # Result is `Ok value | Err error`; payload_specs store the type variables.
    # mainView's `Ok pageData -> pageData.pageData` must use Model_pageData @1,
    # not Platform.Model @4 (OOB → Int(0) → "Page not found").
    alias Elmc.Backend.Plan.Lower.Record

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Result", "Ok"} => "value",
      {"Result", "Err"} => "error"
    })

    Process.put(:elmc_record_alias_shapes, %{
      {"Pages.Internal.Platform", "Model"} => [
        "key",
        "url",
        "currentPath",
        "ariaNavigationAnnouncement",
        "pageData",
        "notFound",
        "userFlags",
        "transition",
        "nextTransitionKey",
        "inFlightFetchers",
        "pageFormState",
        "pendingRedirect",
        "pendingData",
        "pendingFrozenViewsUrl"
      ],
      {"RouteBuilder", "App"} => [
        "data",
        "sharedData",
        "routeParams"
      ]
    })

    Process.put(:elmc_inline_record_literal_shapes, %{
      {"Pages.Internal.Platform", "Model_pageData"} => [
        "userModel",
        "pageData",
        "sharedData",
        "actionData"
      ]
    })

    on_exit(fn ->
      Process.delete(:elmc_union_constructor_payload_specs)
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_inline_record_literal_shapes)
    end)

    ctx = Context.new(module: "Pages.Internal.Platform", function_name: "mainView", params: ["model"])
    b = Builder.new("Pages.Internal.Platform", "mainView", rc_required: false)
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{
      kind: :constructor,
      name: "Ok",
      resolved_name: "Result.Ok",
      bind: "pageData",
      arg_pattern: nil
    }

    assert {:ok, ctx1, _} = PatternBind.bind(pattern, ctx, b1, subject_reg)
    # Type-var payload must not become a local type.
    assert Context.local_type(ctx1, "pageData") in [nil, ""]

    base = %{op: :var, name: "pageData"}

    assert Record.resolve_field_index_int("userModel", ctx1, base) == {:ok, 0}
    assert Record.resolve_field_index_int("pageData", ctx1, base) == {:ok, 1}
    assert Record.resolve_field_index_int("sharedData", ctx1, base) == {:ok, 2}
    assert Record.resolve_field_index_int("actionData", ctx1, base) == {:ok, 3}
  end

  defp assert_light_fields(ctx, name) do
    fields = get_in(ctx.inferred_param_fields, [name])
    assert "x" in fields
    assert "castsShadows" in fields
    # Alphabetical like Elm runtime storage.
    assert Enum.find_index(fields, &(&1 == "x")) == 6
    assert Enum.find_index(fields, &(&1 == "type_")) == 5
  end
end
