defmodule Elmc.RuntimeOomAbiTest do
  @moduledoc """
  Guards runtime generator C against OOM-hiding ABIs.

  Allocating helpers must return `RC` + out-param (or use a non-allocating native/
  immortal API). Value-return + `return NULL` / `(void)elmc_new_*` must not return.
  """

  use ExUnit.Case, async: true

  @generator_ex Path.expand("../lib/elmc/runtime/generator.ex", __DIR__)
  @runtime_ex_glob Path.expand("../lib/elmc/runtime/**/*.ex", __DIR__)

  @rc_list_allocators ~w(
    elmc_list_head
    elmc_list_tail
    elmc_list_length
    elmc_list_nth_maybe
    elmc_list_nth_int_default_boxed
  )

  # Known pre-existing `ElmcValue *` + `elmc_new_int` + `return NULL` debt.
  # Shrink by converting to RC; never add names.
  @legacy_null_as_oom_int_boxers ~w()

  @rc_converted_allocators ~w(
    elmc_list_replace_nth_int
    elmc_string_to_int
    elmc_string_to_float
    elmc_list_length
    elmc_new_char
    elmc_char_from_code
    elmc_debug_to_string
    elmc_debug_set_to_string
    elmc_basics_to_float
    elmc_basics_sin
    elmc_basics_cos
    elmc_basics_sqrt
    elmc_string_from_int
    elmc_string_left
    elmc_string_right
    elmc_array_set
    elmc_array_push
    elmc_result_to_maybe
    elmc_result_from_maybe
    elmc_basics_min
    elmc_basics_max
    elmc_basics_clamp
    elmc_debug_log
    elmc_append
    elmc_array_get
    elmc_cmd_backlight_from_maybe
    elmc_dict_singleton
    elmc_set_singleton
    elmc_set_to_list
    elmc_array_initialize
    elmc_array_repeat
    elmc_array_to_list
    elmc_array_to_indexed_list
    elmc_array_map
    elmc_array_append
    elmc_array_slice
    elmc_dict_to_list
    elmc_task_succeed
    elmc_task_fail
    elmc_task_map
    elmc_task_map2
    elmc_task_and_then
    elmc_task_command
    elmc_process_spawn
    elmc_process_sleep
    elmc_process_kill
    elmc_task_force
    elmc_cmd_batch
    elmc_cmd_map
    elmc_sub_batch
    elmc_sub_map
    elmc_port_outgoing
    elmc_port_incoming_sub
    elmc_build_constructor_payload
    elmc_record_update
    elmc_record_update_index
    elmc_record_update_index_cow
    elmc_record_update_index_cow_drop
    elmc_record_update_index_int_cow
    elmc_record_update_index_int_cow_drop
    elmc_record_update_index_bool_cow
    elmc_record_update_index_bool_cow_drop
    elmc_record_update_index_float_cow
    elmc_record_update_index_float_cow_drop
  )

  @rc_converted_json_allocators ~w(
    elmc_json_encode_string
    elmc_json_encode_int
    elmc_json_encode_bool
    elmc_json_encode_null
    elmc_json_encode_list
    elmc_json_encode_array
    elmc_json_encode_set
    elmc_json_encode_object
    elmc_json_encode_add_field
    elmc_json_encode_add_entry
    elmc_json_encode_dict
    elmc_json_encode_encode
    elmc_json_decode_value
    elmc_json_decode_string
    elmc_json_decode_string_decoder
    elmc_json_decode_int_decoder
    elmc_json_decode_bool_decoder
    elmc_json_decode_null
    elmc_json_decode_nullable
    elmc_json_decode_list
    elmc_json_decode_array
    elmc_json_decode_field
    elmc_json_decode_at
    elmc_json_decode_index
    elmc_json_decode_map
    elmc_json_decode_map2
    elmc_json_decode_map3
    elmc_json_decode_map4
    elmc_json_decode_map5
    elmc_json_decode_map6
    elmc_json_decode_map7
    elmc_json_decode_succeed
    elmc_json_decode_fail
    elmc_json_decode_and_then
    elmc_json_decode_one_of
    elmc_json_decode_maybe
    elmc_json_decode_lazy
    elmc_json_decode_value_decoder
    elmc_json_decode_error_to_string
    elmc_json_decode_key_value_pairs
    elmc_json_decode_dict
  )

  @json_sections_ex Path.expand("../lib/elmc/runtime/json_sections.ex", __DIR__)

  test "runtime Elixir sources forbid void-cast of elmc_new_*" do
    for path <- Path.wildcard(@runtime_ex_glob) do
      src = File.read!(path)

      refute src =~ ~r/\(void\)\s*elmc_new_/,
             "#{Path.relative_to_cwd(path)}: use immortal elmc_bool / RC out-params — never (void)elmc_new_*"
    end
  end

  test "list allocators use RC out-param ABI, not NULL-as-OOM value return" do
    src = File.read!(@generator_ex)

    for name <- @rc_list_allocators ++ @rc_converted_allocators do
      assert src =~ ~r/RC\s+#{name}\s*\(\s*ElmcValue\s*\*\*\s*out/,
             "#{name} must be RC elmc_*(ElmcValue **out, …)"

      refute src =~ ~r/ElmcValue\s*\*\s+#{name}\s*\(/,
             "#{name} must not be a value-returning ElmcValue * API"
    end

    json_src = File.read!(@json_sections_ex)

    for name <- @rc_converted_json_allocators do
      assert json_src =~ ~r/RC\s+#{name}\s*\(\s*ElmcValue\s*\*\*\s*out/,
             "#{name} must be RC elmc_*(ElmcValue **out, …) in json_sections.ex"

      refute json_src =~ ~r/ElmcValue\s*\*\s+#{name}\s*\(/,
             "#{name} must not be a value-returning ElmcValue * API"
    end

    refute json_src =~ ~r/_elmc_rc_out/,
           "json_sections.ex: decode/encode internals must not use NULL-as-OOM _elmc_rc_out boxers"

    assert src =~ ~r/elmc_int_t\s+elmc_list_length_native\s*\(/
    assert src =~ ~r/static\s+ElmcValue\s*\*\s*elmc_bool\s*\(\s*int\s+value\s*\)/

    assert src =~ ~r/static\s+RC\s+elmc_platform_manager_tag\s*\(\s*ElmcValue\s*\*\*\s*out/,
           "platform_manager_tag must propagate OOM via RC, not immortal zero"

    assert src =~ ~r/static\s+RC\s+elmc_closure_make_pap\s*\(\s*ElmcValue\s*\*\*\s*out/,
           "closure_make_pap must propagate OOM via RC, not immortal zero"
  end

  test "plan maps leave no allocating helpers in c_value_return" do
    assert Elmc.Backend.Plan.RuntimeBuiltins.Extra.c_value_return_ids() == []

    for id <- [
          :string_chop_end,
          :url_percent_encode,
          :http_command,
          :random_generate,
          :regex_from_string,
          :time_here,
          :browser_get_viewport
        ] do
      assert Elmc.Backend.Plan.RuntimeBuiltins.fallible?(id),
             "#{id} must be fallible RC, not c_value_return"
      refute Elmc.Backend.Plan.RuntimeBuiltins.c_value_return?(id)
    end
  end

  test "take wrappers must not hide OOM as immortal zero" do
    takes = File.read!(Path.expand("../lib/elmc/runtime/rc_macros.ex", __DIR__))

    refute takes =~ ~r/==\s*RC_SUCCESS\s*\?\s*out\s*:\s*elmc_int_zero\(\)/,
           "take shims must return NULL on RC failure, not elmc_int_zero()"

    refute takes =~ ~r/!=\s*RC_SUCCESS\)\s*return\s*elmc_int_zero\(\)/,
           "take shims must return NULL on RC failure, not elmc_int_zero()"
  end

  test "generated runtime C has no void-cast elmc_new_* and list_length is RC" do
    out = Path.join(System.tmp_dir!(), "elmc-oom-abi-#{System.unique_integer([:positive])}")
    File.rm_rf!(out)
    assert :ok = Elmc.Runtime.Generator.write_runtime(out)
    c = File.read!(Path.join(out, "elmc_runtime.c"))

    refute c =~ ~r/\(void\)\s*elmc_new_/
    assert c =~ ~r/RC\s+elmc_list_length\s*\(\s*ElmcValue\s*\*\*\s*out/
    assert c =~ ~r/elmc_int_t\s+elmc_list_length_native\s*\(/
    refute Regex.match?(
             ~r/ElmcValue\s*\*\s+elmc_list_length\s*\(\s*ElmcValue\s*\*\s*list\s*\)/,
             c
           )
  end

  test "no new ElmcValue* null-as-OOM int boxers beyond the legacy allowlist" do
    offenders = null_as_oom_int_boxers(File.read!(@generator_ex))
    unexpected = offenders -- @legacy_null_as_oom_int_boxers
    stale = @legacy_null_as_oom_int_boxers -- offenders

    assert unexpected == [],
           "new null-as-OOM value-return allocators (convert to RC): #{inspect(unexpected)}"

    assert stale == [],
           "allowlist stale (already fixed — drop from list): #{inspect(stale)}"
  end

  defp null_as_oom_int_boxers(src) do
    starts =
      Regex.scan(~r/ElmcValue\s*\*\s*(elmc_\w+)\s*\([^)]*\)\s*\{/, src, return: :index)
      |> Enum.map(fn [{abs, _}, {name_start, name_len}] ->
        name = binary_part(src, name_start, name_len)
        {abs, name}
      end)

    starts
    |> Enum.with_index()
    |> Enum.filter(fn {{abs, _name}, i} ->
      end_pos =
        case Enum.at(starts, i + 1) do
          {next, _} -> next
          nil -> byte_size(src)
        end

      body = binary_part(src, abs, end_pos - abs)

      String.contains?(body, "elmc_new_int(&_elmc_rc_out") and
        String.contains?(body, "return NULL")
    end)
    |> Enum.map(fn {{_abs, name}, _i} -> name end)
    |> Enum.uniq()
  end
end
