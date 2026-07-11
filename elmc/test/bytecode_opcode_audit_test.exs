defmodule Elmc.BytecodeOpcodeAuditTest do
  @moduledoc """
  Ensures bytecode emitted for strict templates only uses opcodes the VM implements.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.{Loader, Lower, Opcodes}
  alias Elmc.TestSupport.{PlanStrictTemplates, TemplateCompile}

  @moduletag :plan_surface

  @quick_templates ~w(game_2048 game_elmtris watchface_yes watchface_poke_battle game_basic)
  @slow_templates Enum.reject(PlanStrictTemplates.names(), &(&1 in @quick_templates))

  for template <- @quick_templates do
    @tag template: template

    test "bytecode opcodes for #{template} are all implemented", %{template: template} do
      assert :ok = check_opcode_coverage(template)
    end
  end

  for template <- @slow_templates do
    @tag :slow
    @tag template: template

    test "bytecode opcodes for #{template} are all implemented", %{template: template} do
      assert :ok = check_opcode_coverage(template)
    end
  end

  defp check_opcode_coverage(template) do
      out_dir = Path.expand("tmp/bytecode_opcode_audit/#{template}", __DIR__)
      File.rm_rf!(out_dir)

      assert {:ok, _} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 out_dir: out_dir
               )

      {:ok, manifest} =
        Loader.load_manifest(Path.join(out_dir, "bytecode/elmc_bytecode.manifest.json"))

      {unknown, unregistered} = scan_manifest_opcodes(out_dir, manifest)

      cond do
        MapSet.size(unknown) > 0 ->
          {:error,
           "unknown opcode bytes #{inspect(MapSet.to_list(unknown) |> Enum.sort())}"}

        MapSet.size(unregistered) > 0 ->
          {:error,
           "unimplemented opcodes #{inspect(MapSet.to_list(unregistered) |> Enum.sort())}"}

        true ->
          :ok
      end
  end

  defp scan_manifest_opcodes(out_dir, manifest) do
    (manifest["functions"] || [])
    |> Enum.reduce({MapSet.new(), MapSet.new()}, fn entry, {unk_acc, unreg_acc} ->
      path = Path.join(out_dir, ["bytecode", entry["file"]])

      if File.exists?(path) do
        sec = Lower.decode_section(File.read!(path))
        codes = scan_opcodes(sec.code)

        unk =
          codes
          |> Enum.filter(fn code -> is_nil(Opcodes.name(code)) end)
          |> MapSet.new()

        unreg =
          codes
          |> Enum.map(&Opcodes.name/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(fn name -> not vm_implements?(name) end)
          |> MapSet.new()

        {MapSet.union(unk_acc, unk), MapSet.union(unreg_acc, unreg)}
      else
        {unk_acc, unreg_acc}
      end
    end)
  end

  defp vm_implements?(name) do
    name in [
      :const_int,
      :const_immortal_string,
      :load_param,
      :load_local,
      :call_runtime,
      :call_fn,
      :release,
      :publish,
      :catch_begin,
      :catch_end,
      :record_get,
      :pebble_cmd,
      :ret,
      :br,
      :br_if,
      :switch_tag,
      :phi,
      :compare,
      :test_maybe_nothing,
      :switch_ctor_tag,
      :record_update,
      :list_nil,
      :int_arith,
      :render_cmd,
      :pebble_sub,
      :make_closure,
      :tuple_proj,
      :boxed_binop,
      :const_static_list,
      :const_c_expr,
      :record_get_int,
      :test_string_literal,
      :test_list_empty,
      :test_ctor_tag,
      :test_bool,
      :bool_and,
      :call_closure,
      :list_cursor_map,
      :forward_ref_set,
      :forward_ref_load,
      :forward_ref_capture,
      :forward_ref_load_captured
    ]
  end

  defp scan_opcodes(code), do: scan_opcodes(code, 0, MapSet.new())

  defp scan_opcodes(code, ip, acc) when ip >= byte_size(code), do: acc

  defp scan_opcodes(code, ip, acc) do
    <<op::8, _dest::16, rest::binary>> = binary_part(code, ip, byte_size(code) - ip)
    acc = MapSet.put(acc, op)
    scan_opcodes(code, ip + 3 + skip_args(op, rest), acc)
  end

  defp skip_args(op, rest) do
    case Opcodes.name(op) do
      :call_runtime ->
        <<_id::16, _lit::8, sz::16, rest2::binary>> = rest
        4 + sz + skip_runtime_literal(rest2)

      :call_fn ->
        <<_idx::16, sz::16, _::binary>> = rest
        4 + sz

      :const_immortal_string ->
        <<sz::16, _::binary>> = rest
        2 + sz

      :compare -> 5
      :br_if -> 4
      :br -> 2
      :switch_tag -> <<_d::16, sz::16, _::binary>> = rest; 4 + sz
      :phi -> <<sz::16, _::binary>> = rest; 2 + sz
      :test_string_literal -> <<_s::16, sz::16, _::binary>> = rest; 4 + sz
      :test_bool -> 3
      :test_ctor_tag -> 4
      :test_list_empty -> 2
      :test_maybe_nothing -> 2
      :bool_and -> 4
      :call_closure -> <<_c::16, argc::16, _::binary>> = rest; 4 + argc * 2
      :list_cursor_map -> list_cursor_map_arg_size(rest)
      :forward_ref_set -> <<sz::16, _::binary>> = rest; 2 + sz + 2
      :forward_ref_load -> <<sz::16, _::binary>> = rest; 2 + sz
      :forward_ref_capture -> <<sz::16, _::binary>> = rest; 2 + sz
      :forward_ref_load_captured -> <<sz::16, _::binary>> = rest; 2 + sz
      :switch_ctor_tag -> <<_s::16, _d::16, sz::16, _::binary>> = rest; 6 + sz
      :record_update -> 6
      :record_get -> 4
      :tuple_proj -> 3
      :make_closure -> <<_i::16, _a::16, sz::16, _::binary>> = rest; 6 + sz
      :int_arith -> 5
      :boxed_binop -> 5
      :const_static_list -> static_list_size(rest)
      :const_c_expr -> <<sz::16, _::binary>> = rest; 2 + sz
      :const_int -> 4
      :pebble_cmd -> platform_param_size(rest)
      :render_cmd -> platform_param_size(rest)
      :pebble_sub -> platform_param_size(rest)
      :load_param -> 2
      :load_local -> 2
      :publish -> 2
      :release -> 2
      :catch_begin -> 0
      :catch_end -> 0
      :ret -> 0
      :list_nil -> 0
      _ -> 0
    end
  end

  defp skip_runtime_literal(<<0, _::binary>>), do: 0
  defp skip_runtime_literal(<<1, _::32, _::binary>>), do: 4
  defp skip_runtime_literal(<<2, _::32, _::binary>>), do: 4
  defp skip_runtime_literal(_), do: 0

  defp static_list_size(<<kind::8, count::16, _::binary>>) do
    payload =
      case kind do
        0 -> count * 4
        1 -> count * 8
        2 -> count * 8
        k when k in [3, 4] -> count * 2
        _ -> 0
      end

    3 + payload
  end

  defp platform_param_size(<<_::16, _::16, sz::16, _::binary>>), do: 4 + sz

  defp list_cursor_map_arg_size(<<flags::8, _idx::16, rest::binary>>) do
    3 + cursor_bound_size(flags, 0, rest) + cursor_bound_size(flags, 1, skip_cursor_bound(flags, 0, rest))
  end

  defp cursor_bound_size(flags, bit, _rest) do
    if Bitwise.band(flags, Bitwise.bsl(1, bit)) != 0, do: 4, else: 2
  end

  defp skip_cursor_bound(flags, bit, rest) do
    size = cursor_bound_size(flags, bit, rest)
    binary_part(rest, size, max(0, byte_size(rest) - size))
  end
end
