defmodule Elmc.DispatchTagPayloadOwnershipTest do
  @moduledoc """
  Ownership matrix for generated `elmc_pebble_dispatch_tag_*` emitters.

  Convention: public APIs that accept caller-owned `ElmcValue *` **borrow**.
  `_take` is only for locals the callee allocated. Callers always release after
  a borrowed dispatch (template, TEA, companion, int_values wrapper).

  Regression: `tuple2_take` of caller payload + caller `elmc_release` double-freed
  on emery after companion ProvideMoon / datetime drain.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.IntDispatch
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagPayload
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars.TagBool
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars.TagString
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars.TagValue
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.IntValuesDispatch
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields
  alias Elmc.Backend.Pebble.HeaderWriter.ApiDecls.InitDispatch

  @caller_owned_params ~w(payload flags)

  test "dispatch_tag_payload retains payload instead of taking ownership" do
    body = TagPayload.body()
    assert body =~ "elmc_tuple2(&msg, tag_value, payload)"
    refute body =~ "elmc_tuple2_take(&msg, tag_value, payload)"
    # Must not release the caller's payload on success or error paths.
    refute body =~ ~r/elmc_release\(\s*payload\s*\)/
    assert body =~ "elmc_release(tag_value)"
    assert body =~ "Borrows `payload`"
  end

  test "dispatch_tag_int_values releases inner_msg after borrowed dispatch" do
    body = IntValuesDispatch.body()
    assert body =~ "elmc_pebble_dispatch_tag_payload(app, outer_tag, inner_msg)"
    assert body =~ "elmc_release(inner_msg)"
    # Local construction may take owned locals.
    assert body =~ "elmc_tuple2_take(&inner_msg, inner_tag_value, inner_payload)"
  end

  test "scalar tag dispatchers only take callee-allocated locals" do
    for {mod, name} <- [
          {TagValue, "dispatch_tag_value"},
          {TagBool, "dispatch_tag_bool"},
          {TagString, "dispatch_tag_string"}
        ] do
      body = mod.body()
      assert body =~ "elmc_pebble_#{name}(", "#{name}: missing function"
      assert body =~ "elmc_tuple2_take(&msg, tag_value, payload_value)",
             "#{name}: should take locally built tag/payload"
      refute_take_of_caller_params(body, name)
      # Scalars do not accept ElmcValue* payloads from callers.
      refute body =~ ~r/ElmcValue\s*\*\s*payload\s*\)/,
             "#{name}: must not take caller-owned ElmcValue* payload"
    end
  end

  test "dispatch_int allocates and releases its own msg" do
    body = IntDispatch.body()
    assert body =~ "elmc_new_int(&msg, tag)"
    assert body =~ "elmc_release(msg)"
    refute_take_of_caller_params(body, "dispatch_int")
  end

  test "record_int_fields takes only locally built record/tag values" do
    body = RecordIntFields.body()
    assert body =~ "elmc_tuple2_take(&msg, tag_value, payload_value)"
    refute_take_of_caller_params(body, "dispatch_tag_record_int_fields")
    refute body =~ ~r/ElmcValue\s*\*\s*payload\b/,
           "record_int_fields must not accept caller ElmcValue* payload"
  end

  test "combined tag_dispatch bodies never take caller-owned ElmcValue* params" do
    combined = [Primitives.body(), Records.body()] |> IO.iodata_to_binary()

    for param <- @caller_owned_params do
      refute combined =~ ~r/elmc_tuple2_take\([^)]*\b#{param}\b/,
             "forbidden tuple2_take of caller-owned #{param}"

      # Any ownership-transfer helper applied to a caller-owned param.
      refute combined =~ ~r/elmc_\w+_take\([^;)]*\b#{param}\b/,
             "forbidden elmc_*_take of caller-owned #{param}"
    end

    # Only dispatch_tag_payload may accept ElmcValue *payload; it must borrow.
    payload_fns =
      Regex.scan(~r/int\s+elmc_pebble_dispatch_\w+\([^;{]*ElmcValue\s*\*\s*payload/, combined)

    assert length(payload_fns) == 1
    assert hd(hd(payload_fns)) =~ "dispatch_tag_payload"
  end

  test "public header documents borrow for dispatch_tag_payload" do
    body = InitDispatch.body()
    assert body =~ "elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload)"
    assert String.contains?(String.downcase(body), "borrows")
    assert String.contains?(String.downcase(body), "caller retains")
  end

  defp refute_take_of_caller_params(body, label) do
    for param <- @caller_owned_params do
      refute body =~ ~r/elmc_tuple2_take\([^)]*\b#{param}\b/,
             "#{label}: must not tuple2_take caller-owned #{param}"
    end
  end
end
