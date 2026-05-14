defmodule Elmc.Backend.CCodegen do
  @moduledoc """
  Writes C source files from lowered IR.
  """

  alias ElmEx.IR

  @pebble_color_constants %{
    "clearColor" => 0x00,
    "black" => 0xC0,
    "oxfordBlue" => 0xC1,
    "dukeBlue" => 0xC2,
    "blue" => 0xC3,
    "darkGreen" => 0xC4,
    "midnightGreen" => 0xC5,
    "cobaltBlue" => 0xC6,
    "blueMoon" => 0xC7,
    "islamicGreen" => 0xC8,
    "jaegerGreen" => 0xC9,
    "tiffanyBlue" => 0xCA,
    "vividCerulean" => 0xCB,
    "green" => 0xCC,
    "malachite" => 0xCD,
    "mediumSpringGreen" => 0xCE,
    "cyan" => 0xCF,
    "bulgarianRose" => 0xD0,
    "imperialPurple" => 0xD1,
    "indigo" => 0xD2,
    "electricUltramarine" => 0xD3,
    "armyGreen" => 0xD4,
    "darkGray" => 0xD5,
    "liberty" => 0xD6,
    "veryLightBlue" => 0xD7,
    "kellyGreen" => 0xD8,
    "mayGreen" => 0xD9,
    "cadetBlue" => 0xDA,
    "pictonBlue" => 0xDB,
    "brightGreen" => 0xDC,
    "screaminGreen" => 0xDD,
    "mediumAquamarine" => 0xDE,
    "electricBlue" => 0xDF,
    "darkCandyAppleRed" => 0xE0,
    "jazzberryJam" => 0xE1,
    "purple" => 0xE2,
    "vividViolet" => 0xE3,
    "windsorTan" => 0xE4,
    "roseVale" => 0xE5,
    "purpureus" => 0xE6,
    "lavenderIndigo" => 0xE7,
    "limerick" => 0xE8,
    "brass" => 0xE9,
    "lightGray" => 0xEA,
    "babyBlueEyes" => 0xEB,
    "springBud" => 0xEC,
    "inchworm" => 0xED,
    "mintGreen" => 0xEE,
    "celeste" => 0xEF,
    "red" => 0xF0,
    "folly" => 0xF1,
    "fashionMagenta" => 0xF2,
    "magenta" => 0xF3,
    "orange" => 0xF4,
    "sunsetOrange" => 0xF5,
    "brilliantRose" => 0xF6,
    "shockingPink" => 0xF7,
    "chromeYellow" => 0xF8,
    "rajah" => 0xF9,
    "melon" => 0xFA,
    "richBrilliantLavender" => 0xFB,
    "yellow" => 0xFC,
    "icterine" => 0xFD,
    "pastelYellow" => 0xFE,
    "white" => 0xFF
  }

  @spec write_project(IR.t(), String.t(), map()) :: :ok | {:error, term()}
  def write_project(%IR{} = ir, out_dir, opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), header(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), source(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), host_harness()),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), makefile()) do
      :ok
    end
  end

  @spec write_project_multi(IR.t(), String.t(), map()) :: :ok | {:error, term()}
  def write_project_multi(%IR{} = ir, out_dir, opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- write_per_module_headers(ir, c_dir),
         :ok <- write_per_module_sources(ir, c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), header(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), source(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), host_harness()),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), makefile()),
         :ok <- File.write(Path.join(out_dir, "link_manifest.json"), link_manifest(ir)) do
      :ok
    end
  end

  @spec header(ElmEx.IR.t(), map()) :: String.t()
  defp header(ir, opts) do
    direct_cmd_decls = direct_command_decls(ir, opts)
    wrapper_targets = generic_wrapper_targets(ir, opts)

    function_decls =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(
          &(&1.kind == :function && MapSet.member?(wrapper_targets, {mod.name, &1.name}))
        )
        |> Enum.map(fn decl ->
          c_name = module_fn_name(mod.name, decl.name)
          "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"
        end)
      end)
      |> Enum.join("\n")

    """
    #ifndef ELMC_GENERATED_H
    #define ELMC_GENERATED_H

    #include "../runtime/elmc_runtime.h"
    #include "../ports/elmc_ports.h"

    #{function_decls}
    #{direct_cmd_decls}

    #endif
    """
  end

  @spec source(ElmEx.IR.t(), map()) :: String.t()
  defp source(ir, opts) do
    # Initialize lambda collection for hoisting to file scope
    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_lambda_counter, 0)
    Process.put(:elmc_lambda_defs, %{})

    function_arities =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, length(decl.args || [])} end)
      end)
      |> Map.new()

    constructor_tags = constructor_tag_map(ir)
    Process.put(:elmc_constructor_tags, constructor_tags)
    Process.put(:elmc_enum_types, enum_type_set(ir))
    Process.put(:elmc_record_alias_shapes, record_alias_shape_map(ir))
    decl_map = function_decl_map(ir)
    generic_targets = generic_function_targets(ir, opts)

    wrapper_targets =
      generic_wrapper_targets(ir, opts, decl_map, direct_command_targets(ir, opts, decl_map))

    generic_native_prototypes = generic_native_function_prototypes(ir, generic_targets)

    function_defs =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(
          &(&1.kind == :function && MapSet.member?(generic_targets, {mod.name, &1.name}))
        )
        |> Enum.map(fn decl ->
          c_name = module_fn_name(mod.name, decl.name)
          emit_wrapper? = MapSet.member?(wrapper_targets, {mod.name, decl.name})

          emit_function_def(decl, mod.name, c_name, function_arities, decl_map, emit_wrapper?)
        end)
      end)
      |> Enum.join("\n")

    direct_command_defs = direct_command_defs(ir, opts)

    lambda_defs =
      Process.get(:elmc_lambdas, [])
      |> Enum.reverse()
      |> Enum.join("\n")

    Process.delete(:elmc_lambdas)
    Process.delete(:elmc_lambda_counter)
    Process.delete(:elmc_lambda_defs)
    Process.delete(:elmc_constructor_tags)
    Process.delete(:elmc_enum_types)

    trig_fallback_prelude =
      generated_trig_fallback_prelude([lambda_defs, function_defs, direct_command_defs])

    """
    #include "elmc_generated.h"
    #include <stdio.h>

    #if defined(__GNUC__)
    #pragma GCC diagnostic ignored "-Wunused-function"
    #endif

    #{pebble_debug_probe_prelude()}

    #{trig_fallback_prelude}

    #{direct_command_prelude(direct_command_defs != "")}

    #{generic_native_prototypes}

    #{lambda_defs}

    #{function_defs}

    #{direct_command_defs}
    """
  end

  defp pebble_debug_probe_prelude do
    """
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
    #include <pebble.h>
    static inline void elmc_agent_generated_probe(uint32_t tag) {
      static uint32_t seen_tags[16];
      static int seen_count = 0;
      for (int i = 0; i < seen_count; i++) {
        if (seen_tags[i] == tag) return;
      }
      if (seen_count >= 16) return;
      DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
      if (session) {
        seen_tags[seen_count++] = tag;
        data_logging_finish(session);
      }
    }
    #else
    static inline void elmc_agent_generated_probe(uint32_t tag) {
      (void)tag;
    }
    #endif
    """
  end

  defp generated_trig_fallback_prelude(chunks) do
    source = Enum.join(chunks, "\n")
    needs_sin? = String.contains?(source, "generated_trig_sin_double")
    needs_cos? = String.contains?(source, "generated_trig_cos_double")

    if needs_sin? or needs_cos? do
      cos_helper =
        if needs_cos? do
          """

          static double generated_trig_cos_double(double x) {
            const double half_pi = 1.57079632679489661923;
            return generated_trig_sin_double(x + half_pi);
          }
          """
        else
          ""
        end

      """
      #if !(defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO))
      static double generated_trig_normalize_radians(double x) {
        const double pi = 3.14159265358979323846;
        const double two_pi = 6.28318530717958647692;
        while (x > pi) x -= two_pi;
        while (x < -pi) x += two_pi;
        return x;
      }

      static double generated_trig_sin_double(double x) {
        const double pi = 3.14159265358979323846;
        const double half_pi = 1.57079632679489661923;
        x = generated_trig_normalize_radians(x);
        if (x > half_pi) x = pi - x;
        if (x < -half_pi) x = -pi - x;
        double x2 = x * x;
        return x * (1.0
            - x2 / 6.0
            + (x2 * x2) / 120.0
            - (x2 * x2 * x2) / 5040.0
            + (x2 * x2 * x2 * x2) / 362880.0);
      }
      #{cos_helper}
      #endif
      """
    else
      ""
    end
  end

  @spec constructor_tag_map(IR.t()) :: map()
  defp constructor_tag_map(%IR{} = ir) do
    qualified =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Map.values()
        |> Enum.flat_map(fn union ->
          union.tags
          |> Enum.map(fn {name, tag} -> {"#{mod.name}.#{name}", tag} end)
        end)
      end)

    unqualified =
      qualified
      |> Enum.group_by(fn {qualified_name, _tag} ->
        qualified_name |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {name, [{_qualified_name, tag}]} -> [{name, tag}]
        {_name, _duplicates} -> []
      end)

    Map.new(qualified ++ unqualified)
  end

  defp enum_type_set(%IR{} = ir) do
    qualified =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Enum.filter(fn {_type_name, union} -> enum_union?(union) end)
        |> Enum.map(fn {type_name, _union} -> "#{mod.name}.#{type_name}" end)
      end)

    unqualified =
      qualified
      |> Enum.group_by(fn qualified_name ->
        qualified_name |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {type_name, [_qualified_name]} -> [type_name]
        {_type_name, _duplicates} -> []
      end)

    MapSet.new(qualified ++ unqualified)
  end

  defp enum_union?(%{payload_kinds: payload_kinds}) when is_map(payload_kinds) do
    payload_kinds != %{} and Enum.all?(Map.values(payload_kinds), &(&1 == :none))
  end

  defp enum_union?(_union), do: false

  @spec cmake() :: String.t()
  defp cmake do
    """
    cmake_minimum_required(VERSION 3.20)
    project(elmc_generated C)

    add_library(elmc_runtime runtime/elmc_runtime.c)
    add_library(elmc_ports ports/elmc_ports.c)
    add_library(elmc_generated c/elmc_generated.c)
    add_library(elmc_worker c/elmc_worker.c)
    add_library(elmc_pebble c/elmc_pebble.c)
    target_include_directories(elmc_runtime PUBLIC runtime)
    target_include_directories(elmc_ports PUBLIC ports runtime)
    target_include_directories(elmc_generated PUBLIC c ports runtime)
    target_include_directories(elmc_worker PUBLIC c ports runtime)
    target_include_directories(elmc_pebble PUBLIC c ports runtime)
    target_link_libraries(elmc_generated PRIVATE elmc_runtime elmc_ports)
    target_link_libraries(elmc_worker PRIVATE elmc_generated elmc_ports elmc_runtime)
    target_link_libraries(elmc_pebble PRIVATE elmc_worker elmc_generated elmc_ports elmc_runtime)

    add_executable(elmc_host c/host_harness.c)
    target_include_directories(elmc_host PRIVATE c ports runtime)
    target_link_libraries(elmc_host PRIVATE elmc_pebble elmc_worker elmc_generated elmc_ports elmc_runtime)
    """
  end

  @spec makefile() :: String.t()
  defp makefile do
    """
    CC ?= cc
    CFLAGS ?= -std=c11 -Wall -Wextra -Iruntime -Iports -Ic
    SOURCES := runtime/elmc_runtime.c ports/elmc_ports.c c/elmc_generated.c c/elmc_worker.c c/elmc_pebble.c c/host_harness.c

    all: elmc_host

    elmc_host: $(SOURCES)
    \t$(CC) $(CFLAGS) $(SOURCES) -o elmc_host

    clean:
    \trm -f elmc_host
    """
  end

  @spec host_harness() :: String.t()
  defp host_harness do
    """
    #include "elmc_generated.h"
    #include <stdio.h>

    static void on_outgoing(ElmcValue *value, void *context) {
      (void)context;
      printf("port callback value=%lld\\n", (long long)elmc_as_int(value));
    }

    int main(void) {
      register_incoming_port("demo", on_outgoing, NULL);
      ElmcValue *payload = elmc_new_int(7);
      send_outgoing_port("demo", payload);
      elmc_release(payload);
      return 0;
    }
    """
  end

  @spec emit_body(ElmEx.IR.Declaration.t(), String.t(), map(), map()) :: String.t()
  defp emit_body(decl, module_name, function_arities \\ %{}, decl_map \\ %{})

  defp emit_body(%{expr: nil}, _module_name, _function_arities, _decl_map) do
    "(void)args; (void)argc; return elmc_int_zero();"
  end

  defp emit_body(decl, module_name, function_arities, decl_map) do
    arg_names = decl.args || []
    arg_bindings = c_arg_bindings(arg_names)
    {entry_probe, exit_probe} = generated_debug_probes(module_name, decl.name)

    arg_binding_code =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, index} ->
        "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)
      |> Enum.join("\n  ")

    # Always cast bound args to void; this keeps generated C warning-clean even
    # when special lowering paths bypass an argument that appeared in source AST.
    unused_casts =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    env =
      arg_bindings
      |> Enum.reduce(%{__module__: module_name}, fn arg, acc ->
        {source_arg, c_arg, _index} = arg
        Map.put(acc, source_arg, c_arg)
      end)
      |> Map.put(:__function_name__, decl.name)
      |> put_typed_arg_bindings(arg_bindings, decl.type)
      |> Map.put(:__function_arities__, function_arities)
      |> Map.put(:__program_decls__, decl_map)
      |> Map.put(
        :__function_analysis__,
        analyze_function_expr(decl.expr || %{op: :int_literal, value: 0}, module_name, decl_map)
      )

    {code, result_var, _counter} =
      compile_expr(decl.expr || %{op: :int_literal, value: 0}, env, 0)

    result_probe = generated_result_probe(module_name, decl.name, result_var)

    """
    (void)args;
      (void)argc;
    #{arg_binding_code}
      #{unused_casts}
      #{entry_probe}
      #{code}
      #{exit_probe}
      #{result_probe}
      return #{result_var};
    """
  end

  defp generated_debug_probes("Main", name) do
    case name do
      "view" -> {agent_probe_region("elmc_agent_generated_probe(0xED998100);"), ""}
      "faceOps" -> {agent_probe_region("elmc_agent_generated_probe(0xED998200);"), ""}
      _ -> {"", ""}
    end
  end

  defp generated_debug_probes("Pebble.Ui", "toUiNode") do
    {agent_probe_region("elmc_agent_generated_probe(0xED998300);"), ""}
  end

  defp generated_debug_probes(_module_name, _name), do: {"", ""}

  defp generated_result_probe("Main", "view", result_var) do
    agent_shape_probe(result_var, 0xED998110, 0xED998111, 0xED998112, 0xED998113)
  end

  defp generated_result_probe("Main", "faceOps", result_var) do
    agent_list_probe(result_var, 0xED998210, 0xED998211, 0xED998212, 0xED998213)
  end

  defp generated_result_probe("Pebble.Ui", "toUiNode", result_var) do
    agent_shape_probe(result_var, 0xED998310, 0xED998311, 0xED998312, 0xED998313)
  end

  defp generated_result_probe(_module_name, _name, _result_var), do: ""

  defp agent_shape_probe(result_var, other_tag, tuple_tag, list_tag, null_tag) do
    agent_probe_region("""
    if (!#{result_var}) {
      elmc_agent_generated_probe(#{hex_tag(null_tag)});
    } else if (#{result_var}->tag == ELMC_TAG_TUPLE2) {
      elmc_agent_generated_probe(#{hex_tag(tuple_tag)});
    } else if (#{result_var}->tag == ELMC_TAG_LIST) {
      elmc_agent_generated_probe(#{hex_tag(list_tag)});
    } else {
      elmc_agent_generated_probe(#{hex_tag(other_tag)});
    }
    """)
  end

  defp agent_list_probe(result_var, empty_tag, nonempty_tag, other_tag, null_tag) do
    agent_probe_region("""
    if (!#{result_var}) {
      elmc_agent_generated_probe(#{hex_tag(null_tag)});
    } else if (#{result_var}->tag == ELMC_TAG_LIST && #{result_var}->payload == NULL) {
      elmc_agent_generated_probe(#{hex_tag(empty_tag)});
    } else if (#{result_var}->tag == ELMC_TAG_LIST) {
      elmc_agent_generated_probe(#{hex_tag(nonempty_tag)});
    } else {
      elmc_agent_generated_probe(#{hex_tag(other_tag)});
    }
    """)
  end

  defp face_ops_list_literal_probe(env, result_var, counter) do
    if Map.get(env, :__module__) == "Main" and Map.get(env, :__function_name__) == "faceOps" do
      base = 0xED998500 + Integer.mod(counter, 16) * 0x10
      agent_list_probe(result_var, base, base + 1, base + 2, base + 3)
    else
      ""
    end
  end

  defp face_ops_append_probe(env, "elmc_append", result_var, counter) do
    if Map.get(env, :__module__) == "Main" and Map.get(env, :__function_name__) == "faceOps" do
      base = 0xED998400 + Integer.mod(counter, 16) * 0x10
      agent_list_probe(result_var, base, base + 1, base + 2, base + 3)
    else
      ""
    end
  end

  defp face_ops_append_probe(_env, _function, _result_var, _counter), do: ""

  defp hex_tag(tag) do
    "0x" <> (tag |> Integer.to_string(16) |> String.upcase())
  end

  defp face_ops_let_probe(env, name, position) do
    if Map.get(env, :__module__) == "Main" and Map.get(env, :__function_name__) == "faceOps" do
      case {name, position} do
        _ -> ""
      end
    else
      ""
    end
  end

  defp battery_alert_case_probe(_env, _branch_index, _position), do: ""

  defp battery_alert_field_probe(_env, _arg, _field, _position), do: ""

  defp draw_corners_call_probe(_env, _module_name, _name, _position), do: ""

  defp agent_probe_region(""), do: ""

  defp agent_probe_region(probe) do
    """
    // #region agent log
    #{probe}
    // #endregion
    """
  end

  defp c_arg_bindings(arg_names) do
    arg_names
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      c_arg =
        cond do
          c_reserved_binding_name?(arg) -> "#{arg}_arg"
          Enum.count(arg_names, &(&1 == arg)) > 1 -> "#{arg}_#{index}"
          true -> arg
        end

      {arg, c_arg, index}
    end)
  end

  defp c_reserved_binding_name?(name) do
    name in ["args", "argc", "out_cmds", "max_cmds", "skip", "count", "emitted"]
  end

  defp emit_function_def(
         decl,
         module_name,
         c_name,
         function_arities,
         decl_map,
         emit_wrapper?
       ) do
    if native_function_args?(decl) do
      emit_native_function_def(
        decl,
        module_name,
        c_name,
        function_arities,
        decl_map,
        emit_wrapper?
      )
    else
      """
      ElmcValue *#{c_name}(ElmcValue ** const args, const int argc) {
        /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
        #{emit_body(decl, module_name, function_arities, decl_map)}
      }
      """
    end
  end

  defp emit_native_function_def(
         decl,
         module_name,
         c_name,
         function_arities,
         decl_map,
         emit_wrapper?
       ) do
    arg_names = decl.args || []
    c_arg_bindings = c_arg_bindings(arg_names)
    arg_kinds = native_function_arg_kinds(decl)
    {entry_probe, exit_probe} = generated_debug_probes(module_name, decl.name)

    wrapper_bindings =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.map_join("\n  ", fn {{_arg, c_arg, index}, kind} ->
        case kind do
          :native_int ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"

          :boxed ->
            "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    native_env =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.reduce(%{__module__: module_name}, fn {{source_arg, c_arg, _index}, kind}, acc ->
        case kind do
          :native_int -> put_native_int_binding(acc, source_arg, c_arg)
          :boxed -> Map.put(acc, source_arg, c_arg)
        end
      end)
      |> put_typed_arg_bindings(c_arg_bindings, decl.type)
      |> Map.put(:__function_name__, decl.name)
      |> Map.put(:__function_arities__, function_arities)
      |> Map.put(:__program_decls__, decl_map)
      |> Map.put(
        :__function_analysis__,
        analyze_function_expr(decl.expr || %{op: :int_literal, value: 0}, module_name, decl_map)
      )

    unused_casts =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    {body_code, body_var, _counter} =
      compile_expr(decl.expr || %{op: :int_literal, value: 0}, native_env, 0)

    wrapper_def =
      if emit_wrapper? do
        """
        ElmcValue *#{c_name}(ElmcValue ** const args, const int argc) {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          (void)args;
          (void)argc;
          #{wrapper_bindings}
          return #{c_name}_native(#{native_args});
        }
        """
      else
        ""
      end

    """
    #{wrapper_def}
    static ElmcValue *#{c_name}_native(#{native_function_params(decl)}) {
      #{unused_casts}
      #{entry_probe}
      #{body_code}
      #{exit_probe}
      return #{body_var};
    }
    """
  end

  defp generic_native_function_prototypes(ir, generic_targets) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(
        &(&1.kind == :function and MapSet.member?(generic_targets, {mod.name, &1.name}) and
            native_function_args?(&1))
      )
      |> Enum.map(fn decl ->
        c_name = module_fn_name(mod.name, decl.name)
        "static ElmcValue *#{c_name}_native(#{native_function_params(decl)});"
      end)
    end)
    |> Enum.join("\n")
  end

  defp native_function_args?(decl) do
    decl
    |> native_function_arg_kinds()
    |> Enum.any?(&(&1 == :native_int))
  end

  defp native_function_params(decl) do
    c_arg_bindings(decl.args || [])
    |> Enum.zip(native_function_arg_kinds(decl))
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> "const elmc_int_t #{c_arg}"
        :boxed -> "ElmcValue * const #{c_arg}"
      end
    end)
  end

  defp native_function_arg_kinds(%{args: args, type: type, expr: expr})
       when is_list(args) and is_binary(type) do
    arg_types = function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      case Enum.at(arg_types, index) |> normalize_type_name() do
        "Int" ->
          if native_function_int_arg_safe?(arg, expr) do
            :native_int
          else
            :boxed
          end

        _other ->
          :boxed
      end
    end)
  end

  defp native_function_arg_kinds(%{args: args, type: type})
       when is_list(args) and is_binary(type) do
    arg_types = function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {_arg, index} ->
      case Enum.at(arg_types, index) |> normalize_type_name() do
        "Int" ->
          :native_int

        _other ->
          :boxed
      end
    end)
  end

  defp native_function_arg_kinds(%{args: args}) when is_list(args),
    do: Enum.map(args, fn _ -> :boxed end)

  defp native_function_arg_kinds(_decl), do: []

  defp native_function_int_arg_safe?(arg, expr) do
    usage = native_int_usage(arg, expr || %{op: :int_literal, value: 0})
    (usage.total == 0 or usage.boxed == 0) and not binding_used_in_lambda?(arg, expr)
  end

  defp binding_used_in_lambda?(name, %{op: :lambda, args: args, body: body}) when is_list(args) do
    not Enum.any?(args, &same_binding?(name, &1)) and binding_referenced?(name, body)
  end

  defp binding_used_in_lambda?(name, expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(&binding_used_in_lambda?(name, &1))
  end

  defp binding_used_in_lambda?(name, exprs) when is_list(exprs),
    do: Enum.any?(exprs, &binding_used_in_lambda?(name, &1))

  defp binding_used_in_lambda?(_name, _expr), do: false

  defp binding_referenced?(name, %{op: :var, name: var_name}), do: same_binding?(name, var_name)

  defp binding_referenced?(name, value) when is_binary(value), do: same_binding?(name, value)

  defp binding_referenced?(name, expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(&binding_referenced?(name, &1))
  end

  defp binding_referenced?(name, exprs) when is_list(exprs),
    do: Enum.any?(exprs, &binding_referenced?(name, &1))

  defp binding_referenced?(_name, _expr), do: false

  defp binding_reference_count(name, %{op: :var, name: var_name}),
    do: if(same_binding?(name, var_name), do: 1, else: 0)

  defp binding_reference_count(name, %{
         op: :let_in,
         name: let_name,
         value_expr: value,
         in_expr: body
       }) do
    value_count = binding_reference_count(name, value)

    body_count =
      if same_binding?(name, let_name), do: 0, else: binding_reference_count(name, body)

    value_count + body_count
  end

  defp binding_reference_count(name, %{op: :lambda, args: args} = expr)
       when is_list(args) do
    if Enum.any?(args, &same_binding?(name, &1)) do
      binding_reference_count(name, expr |> Map.delete(:body) |> Map.values())
    else
      binding_reference_count(name, Map.values(expr))
    end
  end

  defp binding_reference_count(name, expr) when is_map(expr) do
    binding_reference_count(name, Map.values(expr))
  end

  defp binding_reference_count(name, exprs) when is_list(exprs),
    do: Enum.reduce(exprs, 0, fn expr, acc -> acc + binding_reference_count(name, expr) end)

  defp binding_reference_count(_name, _expr), do: 0

  defp pebble_angle_optimized_reference_count(name, expr) do
    cond do
      pebble_trig_round_expr?(expr, name) ->
        1

      is_map(expr) ->
        pebble_angle_optimized_reference_count(name, Map.values(expr))

      is_list(expr) ->
        Enum.reduce(expr, 0, fn value, acc ->
          acc + pebble_angle_optimized_reference_count(name, value)
        end)

      true ->
        0
    end
  end

  defp pebble_trig_round_expr?(
         %{op: :qualified_call, target: target, args: [value]},
         angle_name
       )
       when target in ["Basics.round", "round"],
       do: pebble_trig_scaled_expr?(value, angle_name)

  defp pebble_trig_round_expr?(
         %{op: :runtime_call, function: "elmc_basics_round", args: [value]},
         angle_name
       ),
       do: pebble_trig_scaled_expr?(value, angle_name)

  defp pebble_trig_round_expr?(_expr, _angle_name), do: false

  defp pebble_trig_scaled_expr?(
         %{op: :call, name: "__mul__", args: [left, right]},
         angle_name
       ) do
    (pebble_trig_call_expr?(left, angle_name) and to_float_expr?(right)) or
      (pebble_trig_call_expr?(right, angle_name) and to_float_expr?(left))
  end

  defp pebble_trig_scaled_expr?(_expr, _angle_name), do: false

  defp pebble_trig_call_expr?(
         %{op: :qualified_call, target: target, args: [%{op: :var, name: name}]},
         angle_name
       )
       when target in ["Basics.sin", "Basics.cos", "sin", "cos"],
       do: same_binding?(name, angle_name)

  defp pebble_trig_call_expr?(
         %{op: :runtime_call, function: function, args: [%{op: :var, name: name}]},
         angle_name
       )
       when function in ["elmc_basics_sin", "elmc_basics_cos"],
       do: same_binding?(name, angle_name)

  defp pebble_trig_call_expr?(_expr, _angle_name), do: false

  defp to_float_expr?(%{op: :qualified_call, target: target, args: [_value]})
       when target in ["Basics.toFloat", "toFloat"],
       do: true

  defp to_float_expr?(%{op: :runtime_call, function: "elmc_basics_to_float", args: [_value]}),
    do: true

  defp to_float_expr?(_expr), do: false

  defp pebble_angle_expr?(%{
         op: :call,
         name: "__fdiv__",
         args: [numerator, %{op: :int_literal, value: 65_536}]
       }),
       do: pebble_angle_numerator_expr?(numerator)

  defp pebble_angle_expr?(_expr), do: false

  defp pebble_angle_numerator_expr?(%{op: :call, name: "__mul__", args: [left, right]}) do
    (pi_expr?(left) and double_to_float_expr?(right)) or
      (pi_expr?(right) and double_to_float_expr?(left))
  end

  defp pebble_angle_numerator_expr?(_expr), do: false

  defp double_to_float_expr?(%{
         op: :call,
         name: "__mul__",
         args: [left, %{op: :int_literal, value: 2}]
       }),
       do: to_float_expr?(left)

  defp double_to_float_expr?(%{
         op: :call,
         name: "__mul__",
         args: [%{op: :int_literal, value: 2}, right]
       }),
       do: to_float_expr?(right)

  defp double_to_float_expr?(_expr), do: false

  defp pi_expr?(%{op: :qualified_call, target: target, args: []})
       when target in ["Basics.pi", "pi"],
       do: true

  defp pi_expr?(%{op: :float_literal, value: value}) when value == 3.141592653589793, do: true
  defp pi_expr?(_expr), do: false

  defp put_typed_arg_bindings(env, arg_bindings, type) when is_binary(type) do
    arg_types = function_arg_types(type)

    arg_bindings
    |> Enum.zip(arg_types)
    |> Enum.reduce(env, fn {{arg, _c_arg, _index}, arg_type}, acc ->
      acc =
        case normalize_type_name(arg_type) do
          "Int" -> put_boxed_int_binding(acc, arg, true)
          _other -> if enum_type?(arg_type), do: put_boxed_int_binding(acc, arg, true), else: acc
        end

      put_record_shape(acc, arg, record_shape_for_type(arg_type, acc))
    end)
  end

  defp put_typed_arg_bindings(env, _arg_bindings, _type), do: env

  defp enum_type?(type) when is_binary(type) do
    Process.get(:elmc_enum_types, MapSet.new())
    |> MapSet.member?(normalize_type_name(type))
  end

  defp enum_type?(_type), do: false

  defp function_arg_types(type) when is_binary(type) do
    type
    |> split_top_level_arrows()
    |> Enum.drop(-1)
  end

  defp function_arg_types(_type), do: []

  defp function_return_type(type) when is_binary(type) do
    type
    |> split_top_level_arrows()
    |> List.last()
    |> normalize_type_name()
  end

  defp function_return_type(_type), do: ""

  defp split_top_level_arrows(type) do
    type
    |> String.graphemes()
    |> split_top_level_arrows([], "", 0)
    |> Enum.map(&String.trim/1)
  end

  defp split_top_level_arrows(["-" | [">" | rest]], parts, current, 0) do
    split_top_level_arrows(rest, [current | parts], "", 0)
  end

  defp split_top_level_arrows([char | rest], parts, current, depth) do
    next_depth =
      case char do
        "(" -> depth + 1
        "{" -> depth + 1
        "[" -> depth + 1
        ")" -> max(depth - 1, 0)
        "}" -> max(depth - 1, 0)
        "]" -> max(depth - 1, 0)
        _other -> depth
      end

    split_top_level_arrows(rest, parts, current <> char, next_depth)
  end

  defp split_top_level_arrows([], parts, current, _depth), do: Enum.reverse([current | parts])

  defp normalize_type_name(type) when is_binary(type) do
    type
    |> String.trim()
    |> strip_wrapping_parens()
  end

  defp normalize_type_name(_type), do: ""

  defp strip_wrapping_parens("(" <> rest = type) do
    if String.ends_with?(type, ")") do
      rest
      |> String.slice(0, String.length(rest) - 1)
      |> normalize_type_name()
    else
      type
    end
  end

  defp strip_wrapping_parens(type), do: type

  defp substitute_expr(%{op: :var, name: name}, substitutions) do
    Map.get(substitutions, name, %{op: :var, name: name})
  end

  defp substitute_expr(%{op: :add_const, var: name, value: value}, substitutions) do
    case Map.fetch(substitutions, name) do
      {:ok, expr} ->
        %{
          op: :call,
          name: "__add__",
          args: [substitute_expr(expr, substitutions), %{op: :int_literal, value: value}]
        }

      :error ->
        %{op: :add_const, var: name, value: value}
    end
  end

  defp substitute_expr(%{op: :sub_const, var: name, value: value}, substitutions) do
    case Map.fetch(substitutions, name) do
      {:ok, expr} ->
        %{
          op: :call,
          name: "__sub__",
          args: [substitute_expr(expr, substitutions), %{op: :int_literal, value: value}]
        }

      :error ->
        %{op: :sub_const, var: name, value: value}
    end
  end

  defp substitute_expr(%{op: :add_vars, left: left, right: right}, substitutions) do
    left_expr = Map.get(substitutions, left, %{op: :var, name: left})
    right_expr = Map.get(substitutions, right, %{op: :var, name: right})

    %{
      op: :call,
      name: "__add__",
      args: [
        substitute_expr(left_expr, substitutions),
        substitute_expr(right_expr, substitutions)
      ]
    }
  end

  defp substitute_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = expr,
         substitutions
       ) do
    %{
      expr
      | value_expr: substitute_expr(value_expr, substitutions),
        in_expr: substitute_expr(in_expr, Map.delete(substitutions, name))
    }
  end

  defp substitute_expr(%{op: :lambda, args: args, body: body} = expr, substitutions)
       when is_list(args) do
    scoped = Enum.reduce(args, substitutions, &Map.delete(&2, &1))
    %{expr | body: substitute_expr(body, scoped)}
  end

  defp substitute_expr(expr, substitutions) when is_map(expr) do
    expr
    |> Enum.map(fn {key, value} -> {key, substitute_expr(value, substitutions)} end)
    |> Map.new()
  end

  defp substitute_expr(values, substitutions) when is_list(values) do
    Enum.map(values, &substitute_expr(&1, substitutions))
  end

  defp substitute_expr(value, _substitutions), do: value

  defp inline_record_field_expr(arg_expr, field, env) do
    with target_key when not is_nil(target_key) <- record_helper_target(arg_expr, env),
         decl_map <- Map.get(env, :__program_decls__, %{}),
         %{args: arg_names, expr: expr} when is_list(arg_names) <- Map.get(decl_map, target_key),
         args <- Map.get(arg_expr, :args, []),
         true <- length(arg_names) == length(args),
         substituted <- substitute_expr(expr, Map.new(Enum.zip(arg_names, args))),
         field_expr when not is_nil(field_expr) <- record_field_expr(substituted, field) do
      field_expr
    else
      _ -> nil
    end
  end

  defp record_helper_target(%{op: :call, name: name}, env) when is_binary(name) do
    {Map.get(env, :__module__, "Main"), name}
  end

  defp record_helper_target(%{op: :qualified_call, target: target}, _env)
       when is_binary(target) do
    target
    |> normalize_special_target()
    |> split_qualified_function_target()
  end

  defp record_helper_target(_expr, _env), do: nil

  defp analyze_function_expr(expr, module_name, decl_map) do
    let_names = collect_let_names(expr)
    duplicate_names = duplicate_names(let_names)

    expr
    |> collect_let_analyses(duplicate_names, %{})
    |> Map.values()
    |> Map.new(fn {name, value_expr, in_expr} ->
      usage = native_int_usage(name, in_expr, module_name, decl_map)

      classification =
        cond do
          MapSet.member?(duplicate_names, name) ->
            :boxed

          int_expr?(value_expr) and usage.total > 0 and usage.boxed == 0 and
              usage.native_container > 0 ->
            :native_int

          int_expr?(value_expr) ->
            :boxed_int

          true ->
            :boxed
        end

      {name, classification}
    end)
  end

  defp collect_let_names(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    [name | collect_let_names(value_expr) ++ collect_let_names(in_expr)]
  end

  defp collect_let_names(expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_let_names/1)
  end

  defp collect_let_names(exprs) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_let_names/1)

  defp collect_let_names(_expr), do: []

  defp duplicate_names(names) do
    names
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> MapSet.new()
  end

  defp collect_let_analyses(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
         duplicate_names,
         acc
       ) do
    acc
    |> Map.put(name, {name, value_expr, in_expr})
    |> then(&collect_let_analyses(value_expr, duplicate_names, &1))
    |> then(&collect_let_analyses(in_expr, duplicate_names, &1))
  end

  defp collect_let_analyses(expr, duplicate_names, acc) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.reduce(acc, &collect_let_analyses(&1, duplicate_names, &2))
  end

  defp collect_let_analyses(exprs, duplicate_names, acc) when is_list(exprs) do
    Enum.reduce(exprs, acc, &collect_let_analyses(&1, duplicate_names, &2))
  end

  defp collect_let_analyses(_expr, _duplicate_names, acc), do: acc

  defp native_int_usage(name, expr, module_name \\ nil, decl_map \\ %{}) do
    base_contexts = collect_var_contexts(name, expr, :boxed)
    native_arg_contexts = collect_native_function_arg_contexts(name, expr, module_name, decl_map)

    usage =
      base_contexts
      |> Enum.reduce(%{total: 0, boxed: 0, native_container: 0}, fn context, acc ->
        %{
          total: acc.total + 1,
          boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
        }
      end)

    native_arg_contexts
    |> Enum.reduce(usage, fn context, acc ->
      boxed =
        if context == :native_container do
          max(acc.boxed - 1, 0)
        else
          acc.boxed
        end

      %{
        acc
        | boxed: boxed,
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
      }
    end)
  end

  defp collect_native_function_arg_contexts(name, expr, module_name, decl_map)
       when is_map(expr) do
    own_contexts =
      case native_function_call_arg_kinds(expr, module_name, decl_map) do
        {args, arg_kinds} ->
          args
          |> Enum.zip(arg_kinds)
          |> Enum.flat_map(fn
            {arg, :native_int} -> collect_var_contexts(name, arg, :native_container)
            {_arg, _kind} -> []
          end)

        nil ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(&collect_native_function_arg_contexts(name, &1, module_name, decl_map))

    own_contexts ++ child_contexts
  end

  defp collect_native_function_arg_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs),
       do:
         Enum.flat_map(
           exprs,
           &collect_native_function_arg_contexts(name, &1, module_name, decl_map)
         )

  defp collect_native_function_arg_contexts(_name, _expr, _module_name, _decl_map), do: []

  defp native_function_call_arg_kinds(%{op: :call, name: name, args: args}, module_name, decl_map)
       when is_binary(name) and is_binary(module_name) do
    native_function_arg_kinds_for({module_name, name}, args, decl_map)
  end

  defp native_function_call_arg_kinds(
         %{op: :qualified_call, target: target, args: args},
         _module_name,
         decl_map
       )
       when is_binary(target) do
    target
    |> normalize_special_target()
    |> split_qualified_function_target()
    |> native_function_arg_kinds_for(args, decl_map)
  end

  defp native_function_call_arg_kinds(_expr, _module_name, _decl_map), do: nil

  defp native_function_arg_kinds_for(nil, _args, _decl_map), do: nil

  defp native_function_arg_kinds_for(target, args, decl_map) do
    case Map.get(decl_map, target) do
      nil ->
        nil

      decl ->
        arg_kinds = native_function_arg_kinds(decl)

        if Enum.any?(arg_kinds, &(&1 == :native_int)) do
          {args, arg_kinds}
        else
          nil
        end
    end
  end

  defp native_int_let?(name, value_expr, in_expr, env) when is_binary(name) or is_atom(name) do
    usage =
      native_int_usage(
        name,
        in_expr,
        Map.get(env, :__module__),
        Map.get(env, :__program_decls__, %{})
      )

    native_int_expr?(value_expr, env) and usage.total > 0 and usage.boxed == 0 and
      usage.native_container > 0
  end

  defp native_int_let?(_name, _value_expr, _in_expr, _env), do: false

  defp native_float_usage(name, expr) do
    name
    |> collect_float_contexts(expr, :boxed)
    |> Enum.reduce(%{total: 0, boxed: 0, native: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
        native: acc.native + if(context == :native, do: 1, else: 0)
      }
    end)
  end

  defp native_float_let?(name, value_expr, in_expr, env) when is_binary(name) or is_atom(name) do
    usage = native_float_usage(name, in_expr)

    native_float_expr?(value_expr, env) and usage.total > 0 and usage.boxed == 0 and
      usage.native > 0 and not binding_used_in_lambda?(name, in_expr)
  end

  defp native_float_let?(_name, _value_expr, _in_expr, _env), do: false

  defp pebble_angle_let?(name, value_expr, in_expr) when is_binary(name) or is_atom(name) do
    pebble_angle_expr?(value_expr) and binding_reference_count(name, in_expr) > 0 and
      binding_reference_count(name, in_expr) ==
        pebble_angle_optimized_reference_count(name, in_expr)
  end

  defp pebble_angle_let?(_name, _value_expr, _in_expr), do: false

  defp native_bool_usage(name, expr) do
    name
    |> collect_bool_contexts(expr, :boxed)
    |> Enum.reduce(%{total: 0, boxed: 0, tests: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
        tests: acc.tests + if(context == :bool_test, do: 1, else: 0)
      }
    end)
  end

  defp native_bool_let?(name, value_expr, in_expr) when is_binary(name) or is_atom(name) do
    usage = native_bool_usage(name, in_expr)
    bool_expr?(value_expr) and usage.total > 0 and usage.boxed == 0 and usage.tests > 0
  end

  defp native_bool_let?(_name, _value_expr, _in_expr), do: false

  defp collect_bool_contexts(name, %{op: :var, name: var_name}, context) do
    if same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_bool_contexts(
         name,
         %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr},
         _context
       ) do
    collect_bool_contexts(name, cond, :bool_test) ++
      collect_bool_contexts(name, then_expr, :boxed) ++
      collect_bool_contexts(name, else_expr, :boxed)
  end

  defp collect_bool_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context
       ) do
    value_contexts = collect_bool_contexts(name, value_expr, context)

    if same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_bool_contexts(name, in_expr, context)
    end
  end

  defp collect_bool_contexts(name, expr, context) when is_map(expr),
    do: collect_bool_contexts_from_map(name, expr, context)

  defp collect_bool_contexts(name, exprs, context) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_bool_contexts(name, &1, context))

  defp collect_bool_contexts(_name, _expr, _context), do: []

  defp collect_bool_contexts_from_map(name, expr, context) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_bool_contexts(name, &1, context))
  end

  defp collect_var_contexts(name, %{op: :var, name: var_name}, context) do
    if same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_var_contexts(name, %{op: :add_const, var: var_name}, _context) do
    if same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_var_contexts(name, %{op: :sub_const, var: var_name}, _context) do
    if same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_var_contexts(name, %{op: :add_vars, left: left, right: right}, _context) do
    [left, right]
    |> Enum.filter(&same_binding?(name, &1))
    |> Enum.map(fn _ -> :native end)
  end

  defp collect_var_contexts(name, %{op: :call, name: call_name, args: args}, _context)
       when call_name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(name, %{op: :runtime_call, function: function, args: args}, _context)
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(name, %{op: :runtime_call, function: function, args: args}, _context)
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context
       )
       when function in ["elmc_basics_mod_by", "elmc_basics_remainder_by"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         _context
       ) do
    collect_var_contexts(name, value, :native)
  end

  defp collect_var_contexts(
         name,
         %{op: :qualified_call, target: target, args: args} = expr,
         context
       ) do
    case special_value_from_target(target, args) do
      nil ->
        if qualified_builtin_operator_name(target) in [
             "__add__",
             "__sub__",
             "__mul__",
             "__idiv__",
             "modBy",
             "remainderBy"
           ] do
          Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
        else
          collect_var_contexts_from_map(name, expr, context)
        end

      rewritten ->
        collect_var_contexts(name, rewritten, context)
    end
  end

  defp collect_var_contexts(name, %{op: :tuple2, left: left, right: right}, _context) do
    left_context =
      if native_int_candidate_for_analysis?(name, left), do: :native_container, else: :boxed

    right_context =
      if native_int_candidate_for_analysis?(name, right), do: :native_container, else: :boxed

    collect_var_contexts(name, left, left_context) ++
      collect_var_contexts(name, right, right_context)
  end

  defp collect_var_contexts(name, %{op: :record_literal, fields: fields}, _context)
       when is_list(fields) do
    Enum.flat_map(fields, fn field ->
      context =
        if native_int_candidate_for_analysis?(name, field.expr),
          do: :native_container,
          else: :boxed

      collect_var_contexts(name, field.expr, context)
    end)
  end

  defp collect_var_contexts(name, %{op: :compare, left: left, right: right}, _context) do
    context =
      if native_int_candidate_for_analysis?(name, left) and
           native_int_candidate_for_analysis?(name, right),
         do: :native,
         else: :boxed

    collect_var_contexts(name, left, context) ++ collect_var_contexts(name, right, context)
  end

  defp collect_var_contexts(
         name,
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         _context
       ) do
    branch_context =
      if native_int_candidate_for_analysis?(name, then_expr) and
           native_int_candidate_for_analysis?(name, else_expr),
         do: :native,
         else: :boxed

    collect_var_contexts(name, cond_expr, :boxed) ++
      collect_var_contexts(name, then_expr, branch_context) ++
      collect_var_contexts(name, else_expr, branch_context)
  end

  defp collect_var_contexts(
         name,
         %{op: :case, subject: subject, branches: branches},
         context
       ) do
    subject_contexts =
      cond do
        same_binding?(name, subject) and native_int_case_branches?(branches) ->
          [:native_container]

        same_binding?(name, subject) ->
          [:boxed]

        native_int_case_branches?(branches) ->
          collect_var_contexts(name, subject, :native)

        true ->
          collect_var_contexts(name, subject, context)
      end

    subject_contexts ++ collect_var_contexts(name, branches, context)
  end

  defp collect_var_contexts(name, %{op: :lambda, args: args, body: body}, _context)
       when is_list(args) do
    if Enum.any?(args, &same_binding?(name, &1)) do
      []
    else
      collect_var_contexts(name, body, :boxed)
    end
  end

  defp collect_var_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context
       ) do
    value_contexts = collect_var_contexts(name, value_expr, context)

    if same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_var_contexts(name, in_expr, context)
    end
  end

  defp collect_var_contexts(name, expr, context) when is_map(expr),
    do: collect_var_contexts_from_map(name, expr, context)

  defp collect_var_contexts(name, exprs, context) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_var_contexts(name, &1, context))

  defp collect_var_contexts(_name, _expr, _context), do: []

  defp collect_var_contexts_from_map(name, expr, context) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_var_contexts(name, &1, context))
  end

  defp collect_float_contexts(name, %{op: :var, name: var_name}, context) do
    if same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_float_contexts(name, %{op: :call, name: call_name, args: args}, _context)
       when call_name in ["__add__", "__sub__", "__mul__", "__fdiv__"] do
    Enum.flat_map(args, &collect_float_contexts(name, &1, :native))
  end

  defp collect_float_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context
       )
       when function in [
              "elmc_basics_to_float",
              "elmc_basics_sin",
              "elmc_basics_cos",
              "elmc_basics_tan",
              "elmc_basics_sqrt",
              "elmc_basics_abs",
              "elmc_basics_negate",
              "elmc_basics_round",
              "elmc_basics_floor",
              "elmc_basics_ceiling",
              "elmc_basics_truncate"
            ] do
    Enum.flat_map(args, &collect_float_contexts(name, &1, :native))
  end

  defp collect_float_contexts(
         name,
         %{op: :qualified_call, target: target, args: args} = expr,
         context
       ) do
    case special_value_from_target(target, args) do
      nil ->
        if qualified_builtin_operator_name(target) in [
             "__add__",
             "__sub__",
             "__mul__",
             "__fdiv__",
             "toFloat",
             "round",
             "floor",
             "ceiling",
             "truncate",
             "abs",
             "negate"
           ] do
          Enum.flat_map(args, &collect_float_contexts(name, &1, :native))
        else
          collect_float_contexts_from_map(name, expr, context)
        end

      rewritten ->
        collect_float_contexts(name, rewritten, context)
    end
  end

  defp collect_float_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context
       ) do
    value_contexts = collect_float_contexts(name, value_expr, context)

    if same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_float_contexts(name, in_expr, context)
    end
  end

  defp collect_float_contexts(name, %{op: :lambda, args: args, body: body}, _context)
       when is_list(args) do
    if Enum.any?(args, &same_binding?(name, &1)) do
      []
    else
      collect_float_contexts(name, body, :boxed)
    end
  end

  defp collect_float_contexts(name, expr, context) when is_map(expr),
    do: collect_float_contexts_from_map(name, expr, context)

  defp collect_float_contexts(name, exprs, context) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_float_contexts(name, &1, context))

  defp collect_float_contexts(_name, _expr, _context), do: []

  defp collect_float_contexts_from_map(name, expr, context) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_float_contexts(name, &1, context))
  end

  defp native_int_candidate_for_analysis?(name, %{op: :var, name: var_name}),
    do: same_binding?(name, var_name)

  defp native_int_candidate_for_analysis?(_name, %{op: :field_access}), do: true

  defp native_int_candidate_for_analysis?(name, %{
         op: :if,
         then_expr: then_expr,
         else_expr: else_expr
       }) do
    native_int_candidate_for_analysis?(name, then_expr) and
      native_int_candidate_for_analysis?(name, else_expr)
  end

  defp native_int_candidate_for_analysis?(name, %{op: :call, name: call_name, args: args})
       when call_name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] do
    length(args || []) == 2 and Enum.all?(args, &native_int_candidate_for_analysis?(name, &1))
  end

  defp native_int_candidate_for_analysis?(name, %{op: :call, name: call_name, args: args})
       when call_name in ["abs", "negate"] do
    length(args || []) == 1 and Enum.all?(args, &native_int_candidate_for_analysis?(name, &1))
  end

  defp native_int_candidate_for_analysis?(name, %{
         op: :runtime_call,
         function: function,
         args: args
       })
       when function in [
              "elmc_basics_min",
              "elmc_basics_max",
              "elmc_basics_mod_by",
              "elmc_basics_remainder_by"
            ] do
    length(args || []) == 2 and Enum.all?(args, &native_int_candidate_for_analysis?(name, &1))
  end

  defp native_int_candidate_for_analysis?(name, %{
         op: :runtime_call,
         function: function,
         args: args
       })
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    length(args || []) == 1 and Enum.all?(args, &native_int_candidate_for_analysis?(name, &1))
  end

  defp native_int_candidate_for_analysis?(name, %{op: :qualified_call, target: target, args: args}) do
    case special_value_from_target(normalize_special_target(target), args || []) do
      nil ->
        builtin = qualified_builtin_operator_name(normalize_special_target(target))
        native_int_candidate_for_analysis?(name, %{op: :call, name: builtin, args: args || []})

      rewritten ->
        native_int_candidate_for_analysis?(name, rewritten)
    end
  end

  defp native_int_candidate_for_analysis?(_name, expr), do: int_expr?(expr)

  defp same_binding?(left, right), do: binding_key(left) == binding_key(right)

  defp binding_key(value) when is_atom(value), do: Atom.to_string(value)
  defp binding_key(value) when is_binary(value), do: value
  defp binding_key(%{op: :var, name: name}), do: binding_key(name)
  defp binding_key(%{"op" => :var, "name" => name}), do: binding_key(name)
  defp binding_key(%{"op" => "var", "name" => name}), do: binding_key(name)
  defp binding_key(value), do: value

  defp top_level_function_closure(module_name, name, arity, out, next) do
    c_name = module_fn_name(module_name, name)
    signature = {:top_level_ref, module_name, name, arity}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_top_level_ref")

    if new? do
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures;
        (void)capture_count;
        return #{c_name}(args, argc);
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    code = """
    ElmcValue *cap_#{next}[1] = { NULL };
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{arity}, 0, cap_#{next});
    """

    {code, out, next}
  end

  defp partial_function_closure(module_name, name, arity, arg_vars, out, next) do
    c_name = module_fn_name(module_name, name)
    bound_count = length(arg_vars)
    remaining = max(arity - bound_count, 0)
    signature = {:partial_ref, module_name, name, arity, bound_count}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_partial_ref")

    call_bindings =
      0..(arity - 1)
      |> Enum.map_join("\n  ", fn index ->
        cond do
          index < bound_count ->
            "call_args[#{index}] = (capture_count > #{index}) ? captures[#{index}] : NULL;"

          true ->
            rest_index = index - bound_count
            "call_args[#{index}] = (argc > #{rest_index}) ? args[#{rest_index}] : NULL;"
        end
      end)

    if new? do
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)args;
        (void)argc;
        (void)captures;
        (void)capture_count;
        ElmcValue *call_args[#{max(arity, 1)}] = {0};
        #{call_bindings}
        return #{c_name}(call_args, #{arity});
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    capture_list =
      case arg_vars do
        [] -> "NULL"
        vars -> Enum.join(vars, ", ")
      end

    code = """
    ElmcValue *cap_#{next}[#{max(bound_count, 1)}] = { #{capture_list} };
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{remaining}, #{bound_count}, cap_#{next});
    """

    {code, out, next}
  end

  defp closure_function_name(signature, prefix) do
    defs = Process.get(:elmc_lambda_defs, %{})

    case Map.fetch(defs, signature) do
      {:ok, name} ->
        {name, false}

      :error ->
        closure_id = Process.get(:elmc_lambda_counter, 0) + 1
        Process.put(:elmc_lambda_counter, closure_id)
        name = "#{prefix}_#{closure_id}"
        Process.put(:elmc_lambda_defs, Map.put(defs, signature, name))
        {name, true}
    end
  end

  defp compile_function_call(module_name, name, args, env, counter) do
    function_arities = Map.get(env, :__function_arities__, %{})
    arity = Map.get(function_arities, {module_name, name}, length(args))
    c_name = module_fn_name(module_name, name)

    if length(args) == arity and native_function_call?(module_name, name, env) do
      compile_native_function_call(module_name, name, args, env, counter)
    else
      compile_boxed_function_call(module_name, name, args, env, counter, arity, c_name)
    end
  end

  defp compile_boxed_function_call(module_name, name, args, env, counter, arity, c_name) do
    before_args_probe =
      env |> draw_corners_call_probe(module_name, name, :before_args) |> agent_probe_region()

    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    argc = length(arg_vars)

    after_args_probe =
      env |> draw_corners_call_probe(module_name, name, :after_args) |> agent_probe_region()

    after_call_probe =
      env |> draw_corners_call_probe(module_name, name, :after_call) |> agent_probe_region()

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code =
      cond do
        arity > 0 and argc < arity ->
          {closure_code, _out, _next} =
            partial_function_closure(module_name, name, arity, arg_vars, out, next)

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            #{closure_code}
            #{after_call_probe}
            #{releases}
          """

        arity > 0 and argc > arity ->
          {first_vars, rest_vars} = Enum.split(arg_vars, arity)
          first_args = Enum.join(first_vars, ", ")
          rest_args = Enum.join(rest_vars, ", ")
          head_var = "head_#{next}"
          first_args_var = "call_args_#{next}"
          rest_args_var = "extra_args_#{next}"

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            ElmcValue *#{first_args_var}[#{max(length(first_vars), 1)}] = { #{first_args} };
            ElmcValue *#{head_var} = #{c_name}(#{first_args_var}, #{length(first_vars)});
            ElmcValue *#{rest_args_var}[#{max(length(rest_vars), 1)}] = { #{rest_args} };
            ElmcValue *#{out} = elmc_apply_extra(#{head_var}, #{rest_args_var}, #{length(rest_vars)});
            #{after_call_probe}
            elmc_release(#{head_var});
            #{releases}
          """

        true ->
          args_var = "call_args_#{next}"
          arg_list = Enum.join(arg_vars, ", ")

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
            ElmcValue *#{out} = #{c_name}(#{args_var}, #{argc});
            #{after_call_probe}
            #{releases}
          """
      end

    {code, out, next}
  end

  defp compile_native_function_call(module_name, name, args, env, counter) do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.fetch!({module_name, name})
    arg_kinds = native_function_arg_kinds(decl)

    {arg_code, arg_refs, release_refs, counter} =
      args
      |> Enum.zip(arg_kinds)
      |> Enum.reduce({"", [], [], counter}, fn {arg_expr, kind},
                                               {code_acc, refs_acc, releases_acc, c} ->
        case kind do
          :native_int ->
            {code, ref, c2} = compile_native_int_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

          :boxed ->
            {code, ref, c2} = compile_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ [ref], c2}
        end
      end)

    next = counter + 1
    out = "tmp_#{next}"
    c_name = module_fn_name(module_name, name)
    arg_list = Enum.join(arg_refs, ", ")

    releases =
      release_refs
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      ElmcValue *#{out} = #{c_name}_native(#{arg_list});
      #{releases}
    """

    {code, out, next}
  end

  defp native_function_call?(module_name, name, env) do
    env
    |> Map.get(:__program_decls__, %{})
    |> Map.get({module_name, name})
    |> case do
      nil -> false
      decl -> native_function_args?(decl)
    end
  end

  @spec compile_expr(map() | nil, map(), non_neg_integer()) ::
          {String.t(), String.t(), non_neg_integer()}
  defp compile_expr(%{op: :int_literal, value: 0}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_int_zero();", var, next}
  end

  defp compile_expr(%{op: :int_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(#{value});", var, next}
  end

  defp compile_expr(%{op: :string_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_string(\"#{escape_c_string(value)}\");", var, next}
  end

  defp compile_expr(%{op: :char_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_char(#{value});", var, next}
  end

  defp compile_expr(%{op: :cmd_none}, env, counter) do
    compile_expr(%{op: :int_literal, value: 0}, env, counter)
  end

  defp compile_expr(%{op: :var, name: name}, env, counter) do
    next = counter + 1
    var = "tmp_#{next}"

    case {native_int_binding(env, name), native_bool_binding(env, name),
          native_float_binding(env, name)} do
      {native_ref, _, _} when is_binary(native_ref) ->
        {"ElmcValue *#{var} = elmc_new_int(#{native_ref});", var, next}

      {_, native_ref, _} when is_binary(native_ref) ->
        {"ElmcValue *#{var} = elmc_new_bool(#{native_ref});", var, next}

      {_, _, native_ref} when is_binary(native_ref) ->
        {"ElmcValue *#{var} = elmc_new_float(#{native_ref});", var, next}

      {nil, nil, nil} ->
        case Map.fetch(env, name) do
          {:ok, source} ->
            if boxed_int_binding?(env, name) or boxed_string_binding?(env, name) do
              {"ElmcValue *#{var} = elmc_retain(#{source});", var, next}
            else
              {"ElmcValue *#{var} = #{source} ? elmc_retain(#{source}) : elmc_int_zero();", var,
               next}
            end

          :error ->
            case compile_builtin_operator_call(name, [], env, counter) do
              nil ->
                # Not a local variable – must be a same-module top-level declaration.
                module_name = Map.get(env, :__module__, "Main")
                function_arities = Map.get(env, :__function_arities__, %{})
                arity = Map.get(function_arities, {module_name, name}, 0)

                if arity > 0 do
                  top_level_function_closure(module_name, name, arity, var, next)
                else
                  c_name = module_fn_name(module_name, name)
                  {"ElmcValue *#{var} = #{c_name}(NULL, 0);", var, next}
                end

              result ->
                result
            end
        end
    end
  end

  defp compile_expr(%{op: :add_const, var: name, value: value}, env, counter) do
    if native_int_binding?(env, name) do
      compile_native_int_boxed(
        %{
          op: :call,
          name: "__add__",
          args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
        },
        env,
        counter
      )
    else
      source = Map.get(env, name, name)
      next = counter + 1
      var = "tmp_#{next}"
      {"ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{source}) + #{value});", var, next}
    end
  end

  defp compile_expr(%{op: :add_vars, left: left, right: right}, env, counter) do
    if native_int_binding?(env, left) or native_int_binding?(env, right) do
      compile_native_int_boxed(
        %{
          op: :call,
          name: "__add__",
          args: [%{op: :var, name: left}, %{op: :var, name: right}]
        },
        env,
        counter
      )
    else
      left_ref = Map.get(env, left, left)
      right_ref = Map.get(env, right, right)
      next = counter + 1
      var = "tmp_#{next}"

      {"ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{left_ref}) + elmc_as_int(#{right_ref}));",
       var, next}
    end
  end

  defp compile_expr(%{op: :sub_const, var: name, value: value}, env, counter) do
    if native_int_binding?(env, name) do
      compile_native_int_boxed(
        %{
          op: :call,
          name: "__sub__",
          args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
        },
        env,
        counter
      )
    else
      source = Map.get(env, name, name)
      next = counter + 1
      var = "tmp_#{next}"
      {"ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{source}) - #{value});", var, next}
    end
  end

  defp compile_expr(%{op: :tuple2, left: left, right: right}, env, counter) do
    if native_int_expr?(left, env) and native_int_expr?(right, env) do
      {left_code, left_ref, counter} = compile_native_int_expr(left, env, counter)
      {right_code, right_ref, counter} = compile_native_int_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{left_code}
        #{right_code}
        ElmcValue *#{out} = elmc_tuple2_ints(#{left_ref}, #{right_ref});
      """

      {code, out, next}
    else
      {left_code, left_var, counter} = compile_expr(left, env, counter)
      {right_code, right_var, counter} = compile_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{left_code}
        #{right_code}
        ElmcValue *#{out} = elmc_tuple2_take(#{left_var}, #{right_var});
      """

      {code, out, next}
    end
  end

  defp compile_expr(%{op: :list_literal, items: items}, env, counter) do
    {item_code, item_vars, counter} =
      Enum.reduce(items, {"", [], counter}, fn item, {acc_code, vars, c} ->
        {code, var, c1} = compile_expr(item, env, c)
        {acc_code <> "\n  " <> code, vars ++ [var], c1}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    count = length(item_vars)
    array_name = "list_items_#{next}"
    item_list = Enum.join(item_vars, ", ")
    list_probe = face_ops_list_literal_probe(env, out, next)

    code =
      if count == 0 do
        """
        ElmcValue *#{out} = elmc_list_nil();
          #{list_probe}
        """
      else
        """
        #{item_code}
          ElmcValue *#{array_name}[#{count}] = { #{item_list} };
          ElmcValue *#{out} = elmc_list_from_values_take(#{array_name}, #{count});
          #{list_probe}
        """
      end

    {code, out, next}
  end

  defp compile_expr(%{op: :tuple_second, arg: arg}, env, counter) do
    source = Map.get(env, arg, arg)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_tuple_second(#{source});", var, next}
  end

  defp compile_expr(%{op: :tuple_second_expr, arg: %{op: :var, name: name}}, env, counter) do
    source = Map.get(env, name, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_tuple_second(#{source});", var, next}
  end

  defp compile_expr(%{op: :tuple_second_expr, arg: arg_expr}, env, counter) do
    {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = elmc_tuple_second(#{arg_var});
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  defp compile_expr(%{op: :tuple_first, arg: arg}, env, counter) when is_binary(arg) do
    source = Map.get(env, arg, arg)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_tuple_first(#{source});", var, next}
  end

  defp compile_expr(%{op: :tuple_first, arg: arg_expr}, env, counter) when is_map(arg_expr) do
    compile_expr(%{op: :tuple_first_expr, arg: arg_expr}, env, counter)
  end

  defp compile_expr(%{op: :tuple_first_expr, arg: %{op: :var, name: name}}, env, counter) do
    source = Map.get(env, name, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_tuple_first(#{source});", var, next}
  end

  defp compile_expr(%{op: :tuple_first_expr, arg: arg_expr}, env, counter) do
    {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = elmc_tuple_first(#{arg_var});
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  defp compile_expr(%{op: :string_length, arg: arg}, env, counter) do
    source = Map.get(env, arg, arg)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(elmc_string_length(#{source}));", var, next}
  end

  defp compile_expr(%{op: :string_length_expr, arg: %{op: :var, name: name}}, env, counter) do
    source = Map.get(env, name, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(elmc_string_length(#{source}));", var, next}
  end

  defp compile_expr(%{op: :string_length_expr, arg: arg_expr}, env, counter) do
    {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = elmc_new_int(elmc_string_length(#{arg_var}));
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  defp compile_expr(%{op: :char_from_code, arg: arg}, env, counter) do
    source = Map.get(env, arg, arg)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_char(elmc_as_int(#{source}));", var, next}
  end

  defp compile_expr(%{op: :char_from_code_expr, arg: arg_expr}, env, counter) do
    {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = elmc_new_char(elmc_as_int(#{arg_var}));
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  defp compile_expr(%{op: :qualified_call, target: target, args: args}, env, counter) do
    case special_value_from_target(target, args) do
      nil ->
        case qualified_builtin_operator_name(target) do
          nil ->
            compile_cross_module_call(target, args, env, counter)

          builtin_name ->
            case compile_builtin_operator_call(builtin_name, args, env, counter) do
              nil -> compile_cross_module_call(target, args, env, counter)
              result -> result
            end
        end

      expr ->
        compile_expr(expr, env, counter)
    end
  end

  defp compile_expr(%{op: :constructor_call, target: target, args: args}, env, counter) do
    case special_value_from_target(target, args) do
      nil ->
        c_name = qualified_to_c_name(target)

        {arg_code, arg_vars, counter} =
          Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
            {code, var, c2} = compile_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
          end)

        next = counter + 1
        out = "tmp_#{next}"
        args_var = "call_args_#{next}"
        argc = length(arg_vars)
        arg_list = Enum.join(arg_vars, ", ")

        releases =
          arg_vars
          |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

        code = """
        #{arg_code}
          ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
          ElmcValue *#{out} = #{c_name}(#{args_var}, #{argc});
          #{releases}
        """

        {code, out, counter}

      expr ->
        compile_expr(expr, env, counter)
    end
  end

  defp compile_expr(%{op: :call, name: name, args: args}, env, counter) do
    case compile_builtin_operator_call(name, args, env, counter) do
      nil ->
        module_name = Map.get(env, :__module__, "Main")
        compile_function_call(module_name, name, args, env, counter)

      result ->
        result
    end
  end

  defp compile_expr(
         %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
         env,
         counter
       ) do
    compile_native_int_boxed(%{op: :call, name: "modBy", args: [base, value]}, env, counter)
  end

  defp compile_expr(
         %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
         env,
         counter
       ) do
    compile_native_int_boxed(%{op: :call, name: "remainderBy", args: [base, value]}, env, counter)
  end

  defp compile_expr(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr,
         env,
         counter
       ) do
    if native_int_expr?(value, env) do
      {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{value_code}
        ElmcValue *#{out} = elmc_string_from_native_int(#{value_ref});
      """

      {code, out, next}
    else
      compile_runtime_call(expr, env, counter)
    end
  end

  defp compile_expr(
         %{op: :runtime_call, function: function, args: [left, right]} = expr,
         env,
         counter
       )
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    if native_int_expr?(left, env) and native_int_expr?(right, env) do
      compile_native_int_boxed(
        %{op: :call, name: native_min_max_name(function), args: [left, right]},
        env,
        counter
      )
    else
      compile_runtime_call(expr, env, counter)
    end
  end

  defp compile_expr(
         %{op: :runtime_call, function: function, args: [value]} = expr,
         env,
         counter
       )
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    cond do
      native_int_expr?(value, env) ->
        compile_native_int_boxed(
          %{op: :call, name: native_unary_int_name(function), args: [value]},
          env,
          counter
        )

      native_float_expr?(expr, env) ->
        compile_native_float_boxed(expr, env, counter)

      true ->
        compile_runtime_call(expr, env, counter)
    end
  end

  defp compile_expr(
         %{op: :runtime_call, function: function, args: [_value]} = expr,
         env,
         counter
       )
       when function in [
              "elmc_basics_to_float",
              "elmc_basics_sin",
              "elmc_basics_cos",
              "elmc_basics_tan",
              "elmc_basics_sqrt",
              "elmc_basics_abs",
              "elmc_basics_negate"
            ] do
    if native_float_expr?(expr, env) do
      compile_native_float_boxed(expr, env, counter)
    else
      compile_runtime_call(expr, env, counter)
    end
  end

  defp compile_expr(%{op: :runtime_call, function: function, args: args}, env, counter) do
    compile_runtime_call(%{op: :runtime_call, function: function, args: args}, env, counter)
  end

  defp compile_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
         env,
         counter
       ) do
    cond do
      native_bool_let?(name, value_expr, in_expr) ->
        {value_code, value_ref, counter} = compile_native_bool_expr(value_expr, env, counter)
        next = counter + 1
        native_var = "native_bool_#{safe_c_suffix(name)}_#{next}"
        before_probe = face_ops_let_probe(env, name, :before)
        after_probe = face_ops_let_probe(env, name, :after)

        body_env =
          env
          |> Map.delete(name)
          |> remove_native_int_binding(name)
          |> put_native_bool_binding(name, native_var)
          |> remove_native_float_binding(name)
          |> put_boxed_int_binding(name, false)
          |> put_boxed_string_binding(name, false)

        {body_code, body_var, counter} = compile_expr(in_expr, body_env, next)

        code = """
        #{before_probe}
          #{value_code}
          const elmc_int_t #{native_var} = #{value_ref};
          #{after_probe}
          #{body_code}
        """

        {code, body_var, counter}

      pebble_angle_let?(name, value_expr, in_expr) ->
        body_env =
          env
          |> Map.delete(name)
          |> remove_native_int_binding(name)
          |> remove_native_bool_binding(name)
          |> remove_native_float_binding(name)
          |> put_pebble_angle_binding(name, value_expr)
          |> put_boxed_int_binding(name, false)
          |> put_boxed_string_binding(name, false)

        compile_expr(in_expr, body_env, counter)

      native_float_let?(name, value_expr, in_expr, env) ->
        {value_code, value_ref, counter} = compile_native_float_expr(value_expr, env, counter)
        next = counter + 1
        native_var = "native_float_#{safe_c_suffix(name)}_#{next}"
        before_probe = face_ops_let_probe(env, name, :before)
        after_probe = face_ops_let_probe(env, name, :after)

        body_env =
          env
          |> Map.delete(name)
          |> remove_native_int_binding(name)
          |> remove_native_bool_binding(name)
          |> put_native_float_binding(name, native_var)
          |> put_boxed_int_binding(name, false)
          |> put_boxed_string_binding(name, false)

        {body_code, body_var, counter} = compile_expr(in_expr, body_env, next)

        code = """
        #{before_probe}
          #{value_code}
          const double #{native_var} = #{value_ref};
          #{after_probe}
          #{body_code}
        """

        {code, body_var, counter}

      native_int_let?(name, value_expr, in_expr, env) ->
        {value_code, value_ref, counter} = compile_native_int_expr(value_expr, env, counter)
        next = counter + 1
        native_var = "native_let_#{safe_c_suffix(name)}_#{next}"
        before_probe = face_ops_let_probe(env, name, :before)
        after_probe = face_ops_let_probe(env, name, :after)

        body_env =
          env
          |> Map.delete(name)
          |> put_native_int_binding(name, native_var)
          |> remove_native_bool_binding(name)
          |> remove_native_float_binding(name)
          |> put_boxed_int_binding(name, false)
          |> put_boxed_string_binding(name, false)

        {body_code, body_var, counter} = compile_expr(in_expr, body_env, next)

        code = """
        #{before_probe}
          #{value_code}
          const elmc_int_t #{native_var} = #{value_ref};
          #{after_probe}
          #{body_code}
        """

        {code, body_var, counter}

      true ->
        {value_code, value_var, counter} = compile_expr(value_expr, env, counter)
        before_probe = face_ops_let_probe(env, name, :before)
        after_probe = face_ops_let_probe(env, name, :after)

        body_env =
          env
          |> Map.put(name, value_var)
          |> remove_native_int_binding(name)
          |> remove_native_bool_binding(name)
          |> remove_native_float_binding(name)
          |> put_boxed_int_binding(
            name,
            function_let_classification(env, name) == :boxed_int or
              native_int_expr?(value_expr, env)
          )
          |> put_boxed_string_binding(name, boxed_string_expr?(value_expr, env))
          |> put_record_shape(name, record_shape(value_expr, env))

        {body_code, body_var, counter} = compile_expr(in_expr, body_env, counter)

        code = """
        #{before_probe}
          #{value_code}
          #{after_probe}
          #{body_code}
          elmc_release(#{value_var});
        """

        {code, body_var, counter}
    end
  end

  defp compile_expr(
         %{
           op: :if,
           cond: %{op: :int_literal, value: value},
           then_expr: then_expr,
           else_expr: else_expr
         },
         env,
         counter
       ) do
    compile_expr(if(value != 0, do: then_expr, else: else_expr), env, counter)
  end

  defp compile_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    cond do
      native_bool_expr?(cond_expr, env) and native_int_expr?(then_expr, env) and
          native_int_expr?(else_expr, env) ->
        {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        {then_code, then_assignment, counter} =
          compile_branch_assignment(then_expr, out, env, next)

        {else_code, else_assignment, counter} =
          compile_branch_assignment(else_expr, out, env, counter)

        code = """
        #{cond_code}
          ElmcValue *#{out};
          if (#{cond_ref}) {
        #{indent(then_code, 4)}
              #{then_assignment}
          } else {
        #{indent(else_code, 4)}
              #{else_assignment}
          }
        """

        {code, out, counter}

      native_bool_expr?(cond_expr, env) and boxed_string_expr?(then_expr, env) and
          boxed_string_expr?(else_expr, env) ->
        {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        {then_code, then_assignment, counter} =
          compile_branch_assignment(then_expr, out, env, next)

        {else_code, else_assignment, counter} =
          compile_branch_assignment(else_expr, out, env, counter)

        code = """
        #{cond_code}
          ElmcValue *#{out};
          if (#{cond_ref}) {
        #{indent(then_code, 4)}
              #{then_assignment}
          } else {
        #{indent(else_code, 4)}
              #{else_assignment}
          }
        """

        {code, out, counter}

      native_bool_expr?(cond_expr, env) and boxed_non_null_expr?(then_expr, env) and
          boxed_non_null_expr?(else_expr, env) ->
        {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        {then_code, then_assignment, counter} =
          compile_branch_assignment(then_expr, out, env, next)

        {else_code, else_assignment, counter} =
          compile_branch_assignment(else_expr, out, env, counter)

        code = """
        #{cond_code}
          ElmcValue *#{out};
          if (#{cond_ref}) {
        #{indent(then_code, 4)}
              #{then_assignment}
          } else {
        #{indent(else_code, 4)}
              #{else_assignment}
          }
        """

        {code, out, counter}

      native_bool_expr?(cond_expr, env) ->
        {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        {then_code, then_assignment, counter} =
          compile_branch_assignment(then_expr, out, env, next)

        {else_code, else_assignment, counter} =
          compile_branch_assignment(else_expr, out, env, counter)

        code = """
        #{cond_code}
          ElmcValue *#{out};
          if (#{cond_ref}) {
        #{indent(then_code, 4)}
              #{then_assignment}
          } else {
        #{indent(else_code, 4)}
              #{else_assignment}
          }
        """

        {code, out, counter}

      true ->
        {cond_code, cond_var, counter} = compile_expr(cond_expr, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        {then_code, then_assignment, counter} =
          compile_branch_assignment(then_expr, out, env, next)

        {else_code, else_assignment, counter} =
          compile_branch_assignment(else_expr, out, env, counter)

        code = """
        #{cond_code}
          ElmcValue *#{out};
          if (elmc_as_int(#{cond_var}) != 0) {
        #{indent(then_code, 4)}
              #{then_assignment}
          } else {
        #{indent(else_code, 4)}
              #{else_assignment}
          }
          elmc_release(#{cond_var});
        """

        {code, out, counter}
    end
  end

  defp compile_expr(%{op: :compare, kind: kind, left: left, right: right}, env, counter) do
    operator =
      case kind do
        :eq -> "__eq__"
        :neq -> "__neq__"
        :gt -> "__gt__"
        :gte -> "__gte__"
        :lt -> "__lt__"
        :lte -> "__lte__"
        _ -> "__eq__"
      end

    compile_compare_operator(left, right, operator, env, counter)
  end

  defp compile_expr(%{op: :case, subject: subject, branches: branches}, env, counter) do
    subject_expr = case_subject_expr(subject)

    if native_int_expr?(subject_expr, env) and native_int_case_branches?(branches) do
      compile_native_int_case(subject_expr, branches, env, counter)
    else
      compile_boxed_case(subject, branches, env, counter)
    end
  end

  defp compile_expr(%{op: :float_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {"ElmcValue *#{var} = elmc_new_float(#{float_val});", var, next}
  end

  defp compile_expr(%{op: :record_literal, fields: fields}, env, counter) do
    sorted_fields = Enum.sort_by(fields, & &1.name)
    field_count = length(sorted_fields)

    names_array =
      sorted_fields |> Enum.map(fn f -> "\"#{escape_c_string(f.name)}\"" end) |> Enum.join(", ")

    if field_count > 0 and Enum.all?(sorted_fields, &native_int_expr?(&1.expr, env)) do
      {field_code, field_refs, counter} =
        Enum.reduce(sorted_fields, {"", [], counter}, fn field, {code_acc, refs_acc, c} ->
          {code, ref, c2} = compile_native_int_expr(field.expr, env, c)
          {code_acc <> "\n  " <> code, refs_acc ++ [ref], c2}
        end)

      next = counter + 1
      out = "tmp_#{next}"
      values_array = Enum.join(field_refs, ", ")

      code = """
      #{field_code}
        const char *rec_names_#{next}[#{field_count}] = { #{names_array} };
        elmc_int_t rec_values_#{next}[#{field_count}] = { #{values_array} };
        ElmcValue *#{out} = elmc_record_new_ints(#{field_count}, rec_names_#{next}, rec_values_#{next});
      """

      {code, out, next}
    else
      {field_code, field_vars, counter} =
        Enum.reduce(sorted_fields, {"", [], counter}, fn field, {code_acc, vars_acc, c} ->
          {code, var, c2} = compile_expr(field.expr, env, c)
          {code_acc <> "\n  " <> code, vars_acc ++ [{field.name, var}], c2}
        end)

      next = counter + 1
      out = "tmp_#{next}"
      values_array = field_vars |> Enum.map(fn {_name, var} -> var end) |> Enum.join(", ")

      code = """
      #{field_code}
        const char *rec_names_#{next}[#{max(field_count, 1)}] = { #{names_array} };
        ElmcValue *rec_values_#{next}[#{max(field_count, 1)}] = { #{values_array} };
        ElmcValue *#{out} = elmc_record_new_take(#{field_count}, rec_names_#{next}, rec_values_#{next});
      """

      {code, out, next}
    end
  end

  defp compile_expr(%{op: :record_update, base: base, fields: fields}, env, counter) do
    {base_code, base_var, counter} = compile_expr(base, env, counter)
    sorted_fields = Enum.sort_by(fields, & &1.name)

    {update_code, current_var, counter} =
      Enum.reduce(sorted_fields, {"", base_var, counter}, fn field, {code_acc, current, c} ->
        {field_code, field_var, c2} = compile_expr(field.expr, env, c)
        next = c2 + 1
        out = "tmp_#{next}"

        code = """
        #{field_code}
          ElmcValue *#{out} = elmc_record_update(#{current}, "#{escape_c_string(field.name)}", #{field_var});
          elmc_release(#{current});
          elmc_release(#{field_var});
        """

        {code_acc <> "\n  " <> code, out, next}
      end)

    {base_code <> update_code, current_var, counter}
  end

  defp compile_expr(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, source} ->
        next = counter + 1
        var = "tmp_#{next}"
        getter = record_get_expr(source, field, record_shape_for_var(env, arg))

        before_probe =
          env |> battery_alert_field_probe(arg, field, :before) |> agent_probe_region()

        after_probe = env |> battery_alert_field_probe(arg, field, :after) |> agent_probe_region()

        code = """
        #{before_probe}
          ElmcValue *#{var} = #{getter};
          #{after_probe}
        """

        {code, var, next}

      :error ->
        {arg_code, arg_var, counter} = compile_expr(%{op: :var, name: arg}, env, counter)
        next = counter + 1
        var = "tmp_#{next}"

        code = """
        #{arg_code}
          ElmcValue *#{var} = elmc_record_get(#{arg_var}, "#{escape_c_string(field)}");
          elmc_release(#{arg_var});
        """

        {code, var, next}
    end
  end

  defp compile_expr(
         %{op: :field_access, arg: %{op: :record_literal, fields: fields}, field: field},
         env,
         counter
       )
       when is_list(fields) do
    case Enum.find(fields, &(&1.name == field)) do
      %{expr: expr} -> compile_expr(expr, env, counter)
      nil -> compile_expr(%{op: :int_literal, value: 0}, env, counter)
    end
  end

  defp compile_expr(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         env,
         counter
       ) do
    case Map.fetch(env, name) do
      {:ok, source} ->
        next = counter + 1
        var = "tmp_#{next}"
        getter = record_get_expr(source, field, record_shape_for_var(env, name))

        before_probe =
          env |> battery_alert_field_probe(name, field, :before) |> agent_probe_region()

        after_probe =
          env |> battery_alert_field_probe(name, field, :after) |> agent_probe_region()

        code = """
        #{before_probe}
          ElmcValue *#{var} = #{getter};
          #{after_probe}
        """

        {code, var, next}

      :error ->
        compile_expr(%{op: :field_access, arg: name, field: field}, env, counter)
    end
  end

  defp compile_expr(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    case inline_record_field_expr(arg_expr, field, env) do
      nil ->
        {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
        next = counter + 1
        var = "tmp_#{next}"
        getter = record_get_expr(arg_var, field, record_shape(arg_expr, env))

        code = """
        #{arg_code}
          ElmcValue *#{var} = #{getter};
          elmc_release(#{arg_var});
        """

        {code, var, next}

      field_expr ->
        compile_expr(field_expr, env, counter)
    end
  end

  defp compile_expr(%{op: :field_call, arg: arg, field: field, args: args}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, source} ->
        next = counter + 1
        fn_var = "tmp_#{next}"

        {arg_code, arg_vars, counter2} =
          Enum.reduce(args, {"", [], next}, fn arg_expr, {code_acc, vars_acc, c} ->
            {code, var, c2} = compile_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
          end)

        next2 = counter2 + 1
        out = "tmp_#{next2}"
        argc = length(arg_vars)
        args_array = "call_args_#{next2}"
        arg_list = Enum.join(arg_vars, ", ")

        releases =
          arg_vars
          |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

        code = """
        ElmcValue *#{fn_var} = elmc_record_get(#{source}, "#{escape_c_string(field)}");
          #{arg_code}
          ElmcValue *#{args_array}[#{max(argc, 1)}] = { #{arg_list} };
          ElmcValue *#{out} = elmc_closure_call(#{fn_var}, #{args_array}, #{argc});
          elmc_release(#{fn_var});
          #{releases}
        """

        {code, out, next2}

      :error ->
        compile_expr(
          %{op: :field_call, arg: %{op: :var, name: arg}, field: field, args: args},
          env,
          counter
        )
    end
  end

  defp compile_expr(%{op: :lambda, args: lambda_args, body: body}, env, counter) do
    compile_general_lambda(lambda_args, body, env, counter)
  end

  defp compile_expr(%{op: :unsupported}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_int_zero();", var, next}
  end

  defp compile_expr(_expr, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_int_zero();", var, next}
  end

  defp compile_runtime_call(
         %{op: :runtime_call, function: "elmc_append", args: [left, right]},
         env,
         counter
       ) do
    if native_string_expr?(left, env) and native_string_expr?(right, env) do
      {left_code, left_ref, left_cleanup, counter} =
        compile_native_string_expr(left, env, counter)

      {right_code, right_ref, right_cleanup, counter} =
        compile_native_string_expr(right, env, counter)

      next = counter + 1
      out = "tmp_#{next}"

      releases =
        (left_cleanup ++ right_cleanup)
        |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

      code = """
      #{left_code}#{right_code}
        ElmcValue *#{out} = elmc_string_append_native(#{left_ref}, #{right_ref});
        #{releases}
        #{face_ops_append_probe(env, "elmc_append", out, next)}
      """

      {code, out, next}
    else
      compile_generic_runtime_call(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]},
        env,
        counter
      )
    end
  end

  defp compile_runtime_call(%{op: :runtime_call, function: function, args: args}, env, counter) do
    compile_generic_runtime_call(
      %{op: :runtime_call, function: function, args: args},
      env,
      counter
    )
  end

  defp compile_generic_runtime_call(
         %{op: :runtime_call, function: function, args: args},
         env,
         counter
       ) do
    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    call_args = Enum.join(arg_vars, ", ")

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      ElmcValue *#{out} = #{function}(#{call_args});
      #{releases}
      #{face_ops_append_probe(env, function, out, next)}
    """

    {code, out, next}
  end

  defp compile_boxed_case(subject, branches, env, counter) do
    subject_ref = Map.get(env, subject, subject)
    next = counter + 1
    out = "tmp_#{next}"

    {branch_code, final_counter} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({"", next}, fn {branch, branch_index}, {acc, c} ->
        last_branch? = branch_index == length(branches) - 1
        branch_env = bind_pattern(env, branch.pattern, subject_ref)

        {expr_code, assignment_code, c2} =
          compile_case_branch_assignment(branch.expr, out, branch_env, c)

        cond_code = pattern_condition(subject_ref, branch.pattern)

        enter_probe =
          env |> battery_alert_case_probe(branch_index, :enter) |> agent_probe_region()

        after_expr_probe =
          env |> battery_alert_case_probe(branch_index, :after_expr) |> agent_probe_region()

        branch_body = """
        #{indent(enter_probe, 4)}
        #{indent(expr_code, 4)}
        #{indent(after_expr_probe, 4)}
            #{assignment_code}
        """

        cond do
          cond_code == "0" ->
            {:cont, {acc, c2}}

          cond_code == "1" and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          last_branch? and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          cond_code == "1" ->
            snippet = """
            else {
            #{branch_body}
            }
            """

            {:halt, {acc <> snippet, c2}}

          last_branch? and acc != "" ->
            snippet = """
            else {
            #{branch_body}
            }
            """

            {:halt, {acc <> snippet, c2}}

          true ->
            snippet = """
            #{if acc == "", do: "if", else: "else if"} (#{cond_code}) {
            #{branch_body}
            }
            """

            {:cont, {acc <> snippet, c2}}
        end
      end)

    after_setup_probe =
      env |> battery_alert_case_probe(:case, :after_setup) |> agent_probe_region()

    after_branches_probe =
      env |> battery_alert_case_probe(:case, :after_branches) |> agent_probe_region()

    code = """
    ElmcValue *#{out};
      #{after_setup_probe}
      #{branch_code}
      #{after_branches_probe}
    """

    {code, out, final_counter}
  end

  defp compile_native_int_case(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = compile_native_int_expr(subject_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"
    exhaustive? = native_int_case_has_default?(branches)
    initial_value = if exhaustive?, do: nil, else: "elmc_int_zero()"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        {expr_code, assignment_code, c2} =
          compile_case_branch_assignment(branch.expr, out, env, c)

        label = native_int_case_label(branch.pattern)
        release_previous = if exhaustive?, do: "", else: "elmc_release(#{out});"

        snippet = """
        #{label}:
        #{indent(expr_code, 4)}
        #{indent(release_previous, 4)}
        #{indent(assignment_code, 4)}
            break;
        """

        {acc <> snippet, c2}
      end)

    code = """
    #{subject_code}
      #{native_int_case_result_decl(out, initial_value)}
      switch (#{subject_ref}) {
      #{branch_code}
      }
    """

    {code, out, final_counter}
  end

  defp compile_case_branch_assignment(%{op: :string_literal, value: value}, out, _env, counter) do
    {"", "#{out} = elmc_new_string(\"#{escape_c_string(value)}\");", counter}
  end

  defp compile_case_branch_assignment(%{op: :int_literal, value: 0}, out, _env, counter) do
    {"", "#{out} = elmc_int_zero();", counter}
  end

  defp compile_case_branch_assignment(%{op: :int_literal, value: value}, out, _env, counter)
       when is_integer(value) do
    {"", "#{out} = elmc_new_int(#{value});", counter}
  end

  defp compile_case_branch_assignment(expr, out, env, counter) do
    {expr_code, expr_var, counter} = compile_expr(expr, env, counter)
    {expr_code, "#{out} = #{expr_var};", counter}
  end

  defp compile_branch_assignment(%{op: :string_literal, value: value}, out, _env, counter) do
    {"", "#{out} = elmc_new_string(\"#{escape_c_string(value)}\");", counter}
  end

  defp compile_branch_assignment(%{op: :int_literal, value: 0}, out, _env, counter) do
    {"", "#{out} = elmc_int_zero();", counter}
  end

  defp compile_branch_assignment(%{op: :int_literal, value: value}, out, _env, counter)
       when is_integer(value) do
    {"", "#{out} = elmc_new_int(#{value});", counter}
  end

  defp compile_branch_assignment(expr, out, env, counter) do
    {expr_code, expr_var, counter} = compile_expr(expr, env, counter)
    {expr_code, "#{out} = #{expr_var};", counter}
  end

  defp case_subject_expr(subject) when is_binary(subject), do: %{op: :var, name: subject}
  defp case_subject_expr(subject), do: subject

  defp native_int_case_branches?(branches) when is_list(branches) do
    {int_values, wildcard_indexes} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({[], []}, fn {branch, index}, {ints, wildcards} ->
        case branch.pattern do
          %{kind: :int, value: value} when is_integer(value) ->
            {:cont, {[value | ints], wildcards}}

          %{kind: :wildcard} ->
            {:cont, {ints, [index | wildcards]}}

          _ ->
            {:halt, {:invalid, :invalid}}
        end
      end)

    case {int_values, wildcard_indexes} do
      {:invalid, :invalid} ->
        false

      {ints, wildcards} ->
        unique_ints? = length(ints) == length(Enum.uniq(ints))
        wildcard_last? = wildcards == [] or wildcards == [length(branches) - 1]
        unique_ints? and wildcard_last?
    end
  end

  defp native_int_case_branches?(_branches), do: false

  defp native_int_case_has_default?(branches) do
    Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end)
  end

  defp native_int_case_result_decl(out, nil), do: "ElmcValue *#{out};"

  defp native_int_case_result_decl(out, initial_value),
    do: "ElmcValue *#{out} = #{initial_value};"

  defp native_int_case_label(%{kind: :wildcard}), do: "default"

  defp native_int_case_label(%{kind: :int, value: value}) when is_integer(value),
    do: "case #{value}"

  defp compile_general_lambda(lambda_args, body, env, counter) do
    # Determine free variables captured from outer scope
    body_vars = used_vars(body)
    lambda_arg_set = MapSet.new(lambda_args || [])
    # Only capture variables that are actually resolvable in the current env.
    # Variables from case-branch bindings or other scopes that aren't in env
    # would generate undefined C identifiers, so we filter them out.
    env_keys = env |> Map.keys() |> Enum.filter(&is_binary/1) |> MapSet.new()

    free_vars =
      body_vars
      |> MapSet.difference(lambda_arg_set)
      |> MapSet.intersection(env_keys)
      |> MapSet.to_list()
      |> Enum.sort()

    next = counter + 1
    lambda_arg_names = lambda_args || []

    lambda_signature =
      if free_vars == [] do
        {:lambda, lambda_arg_names, body}
      else
        nil
      end

    closure_fn_name =
      case lambda_signature && Map.get(Process.get(:elmc_lambda_defs, %{}), lambda_signature) do
        name when is_binary(name) ->
          name

        _ ->
          lambda_id = Process.get(:elmc_lambda_counter, 0) + 1
          Process.put(:elmc_lambda_counter, lambda_id)
          "elmc_lambda_#{lambda_id}"
      end

    lambda_arg_bindings = c_arg_bindings(lambda_arg_names)
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    native_lambda_arg? = fn name ->
      usage = native_int_usage(name, body, module_name, decl_map)
      usage.total > 0 and usage.boxed == 0 and not binding_used_in_lambda?(name, body)
    end

    native_arg_names =
      lambda_arg_names
      |> Enum.filter(native_lambda_arg?)
      |> MapSet.new()

    native_free_vars =
      free_vars
      |> Enum.filter(native_lambda_arg?)
      |> MapSet.new()

    # Build arg bindings for the closure function body
    arg_bindings =
      lambda_arg_bindings
      |> Enum.map(fn {arg, c_arg, index} ->
        if MapSet.member?(native_arg_names, arg) do
          "const elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"
        else
          "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)
      |> Enum.join("\n  ")

    # Build capture bindings
    capture_bindings =
      free_vars
      |> Enum.with_index()
      |> Enum.map(fn {var_name, index} ->
        if MapSet.member?(native_free_vars, var_name) do
          "const elmc_int_t #{var_name} = (capture_count > #{index} && captures[#{index}]) ? elmc_as_int(captures[#{index}]) : 0;"
        else
          "ElmcValue *#{var_name} = (capture_count > #{index}) ? captures[#{index}] : NULL;"
        end
      end)
      |> Enum.join("\n  ")

    bind_lambda_value = fn acc, name, c_ref, native_names ->
      if MapSet.member?(native_names, name) do
        acc
        |> put_native_int_binding(name, c_ref)
        |> put_boxed_int_binding(name, false)
      else
        Map.put(acc, name, c_ref)
      end
    end

    # Build the body in a clean environment with just args and captures as names
    # Propagate __module__ context so intra-module calls resolve correctly
    body_env =
      lambda_arg_bindings
      |> Enum.reduce(%{}, fn {arg, c_arg, _index}, acc ->
        bind_lambda_value.(acc, arg, c_arg, native_arg_names)
      end)
      |> then(fn acc ->
        Enum.reduce(free_vars, acc, fn name, acc ->
          bind_lambda_value.(acc, name, name, native_free_vars)
        end)
      end)
      |> Map.put(:__module__, Map.get(env, :__module__, "Main"))
      |> Map.put(:__function_name__, Map.get(env, :__function_name__))
      |> Map.put(:__function_arities__, Map.get(env, :__function_arities__, %{}))
      |> Map.put(:__program_decls__, Map.get(env, :__program_decls__, %{}))

    {body_code, body_var, _body_counter} = compile_expr(body, body_env, 0)

    unless lambda_signature && Map.has_key?(Process.get(:elmc_lambda_defs, %{}), lambda_signature) do
      # Hoist the closure function to file scope via process dictionary.
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)args;
        (void)argc;
        (void)captures;
        (void)capture_count;
        #{arg_bindings}
        #{capture_bindings}
        #{body_code}
        return #{body_var};
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])

      if lambda_signature do
        lambda_defs = Process.get(:elmc_lambda_defs, %{})
        Process.put(:elmc_lambda_defs, Map.put(lambda_defs, lambda_signature, closure_fn_name))
      end
    end

    # Build the capture array and closure allocation at the call site
    capture_count = length(free_vars)

    capture_refs =
      free_vars
      |> Enum.map(fn var_name -> Map.get(env, var_name, var_name) end)

    capture_list = Enum.join(capture_refs, ", ")
    out = "tmp_#{next}"

    capture_array_code =
      if capture_count > 0 do
        "ElmcValue *cap_#{next}[#{capture_count}] = { #{capture_list} };"
      else
        "ElmcValue *cap_#{next}[1] = { NULL };"
      end

    code = """
      #{capture_array_code}
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{length(lambda_arg_names)}, #{capture_count}, cap_#{next});
    """

    {code, out, next}
  end

  @spec direct_command_decls(ElmEx.IR.t(), map()) :: String.t()
  defp direct_command_decls(ir, opts) do
    ir
    |> direct_command_targets(opts)
    |> Enum.map(fn {module_name, decl_name} ->
      c_name = module_fn_name(module_name, decl_name)
      macro = direct_command_macro(module_name, decl_name)

      """
      #define #{macro} 1
      int #{c_name}_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds);
      int #{c_name}_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip);
      """
    end)
    |> Enum.join("\n")
  end

  @spec direct_command_defs(ElmEx.IR.t(), map()) :: String.t()
  defp direct_command_defs(ir, opts) do
    targets = direct_command_targets(ir, opts)
    decl_map = function_decl_map(ir)

    if MapSet.size(targets) == 0 do
      ""
    else
      decls =
        ir.modules
        |> Enum.flat_map(fn mod ->
          mod.declarations
          |> Enum.filter(&(&1.kind == :function && MapSet.member?(targets, {mod.name, &1.name})))
          |> Enum.map(fn decl -> {mod, decl} end)
        end)

      prototypes =
        decls
        |> Enum.map_join("\n", fn {mod, decl} ->
          c_name = module_fn_name(mod.name, decl.name)

          native_proto =
            if native_direct_command_args?(decl) do
              "\nstatic int #{c_name}_commands_append_native(#{native_direct_command_params(decl)}, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted);"
            else
              ""
            end

          "static int #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted);#{native_proto}"
        end)

      defs =
        decls
        |> Enum.map_join("\n", fn {mod, decl} ->
          direct_command_def(mod, decl, targets, decl_map)
        end)

      prototypes <> "\n\n" <> defs
    end
  end

  defp function_decl_map(ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
    end)
    |> Map.new()
  end

  defp record_alias_shape_map(ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :type_alias))
      |> Enum.flat_map(fn decl ->
        case Map.get(decl, :expr) do
          %{op: :record_alias, fields: fields} when is_list(fields) ->
            shape = Enum.sort(Enum.map(fields, &to_string/1))
            [{{mod.name, decl.name}, shape}]

          _ ->
            []
        end
      end)
    end)
    |> Map.new()
  end

  @spec direct_command_prelude(boolean()) :: String.t()
  defp direct_command_prelude(false), do: ""

  defp direct_command_prelude(true) do
    """
    #include "elmc_pebble.h"
    #include <string.h>

    typedef ElmcPebbleDrawCmd ElmcGeneratedPebbleDrawCmd;

    static void elmc_generated_draw_init(ElmcGeneratedPebbleDrawCmd *cmd, int64_t kind) {
      memset(cmd, 0, sizeof(*cmd));
      cmd->kind = kind;
    }
    """
  end

  defp direct_command_targets(ir, opts) do
    decl_map =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    direct_command_targets(ir, opts, decl_map)
  end

  defp direct_command_targets(_ir, opts, decl_map) do
    candidates =
      Enum.reduce(decl_map, MapSet.new(), fn {{module_name, decl_name}, decl}, acc ->
        if direct_candidate_module?(module_name) and
             direct_supported?(decl.expr, module_name, decl_map, MapSet.new()) do
          MapSet.put(acc, {module_name, decl_name})
        else
          acc
        end
      end)
      |> filter_direct_targets(decl_map)
      |> filter_direct_targets(decl_map)

    validate_direct_render_only_targets!(opts, decl_map, candidates)

    if opts[:strip_dead_code] == false do
      candidates
    else
      roots = direct_entry_roots(candidates, decl_map, opts)
      direct_reachable_targets(roots, candidates, decl_map, MapSet.new())
    end
  end

  defp validate_direct_render_only_targets!(opts, decl_map, direct_targets) do
    entry_module = opts[:entry_module] || "Main"
    entry_view = {entry_module, "view"}

    if direct_render_only?(opts) and Map.has_key?(decl_map, entry_view) and
         not MapSet.member?(direct_targets, entry_view) do
      raise ArgumentError,
            "direct_render_only requires #{entry_module}.view to be supported by direct Pebble command generation"
    end
  end

  defp direct_entry_roots(candidates, decl_map, opts) do
    decl_map
    |> generic_entry_roots(opts)
    |> Enum.filter(&MapSet.member?(candidates, &1))
  end

  defp direct_reachable_targets([], _candidates, _decl_map, seen), do: seen

  defp direct_reachable_targets([target | rest], candidates, decl_map, seen) do
    cond do
      MapSet.member?(seen, target) ->
        direct_reachable_targets(rest, candidates, decl_map, seen)

      not MapSet.member?(candidates, target) ->
        direct_reachable_targets(rest, candidates, decl_map, seen)

      true ->
        decl = Map.fetch!(decl_map, target)
        module_name = elem(target, 0)
        callees = direct_expr_callees(decl.expr, module_name, candidates, decl_map)
        direct_reachable_targets(rest ++ callees, candidates, decl_map, MapSet.put(seen, target))
    end
  end

  defp direct_expr_callees(expr, module_name, candidates, decl_map) do
    expr
    |> direct_expr_callees_list(module_name, candidates, decl_map)
    |> Enum.uniq()
  end

  defp direct_expr_callees_list(expr, module_name, candidates, decl_map) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: "__append__"} ->
          []

        %{op: :call, name: name} ->
          target = {module_name, name}
          if MapSet.member?(candidates, target), do: [target], else: []

        %{op: :qualified_call, target: target, args: args} ->
          normalized = normalize_special_target(target)

          case special_value_from_target(normalized, args || []) do
            nil ->
              case split_qualified_function_target(normalized) do
                nil ->
                  []

                target_key ->
                  if MapSet.member?(candidates, target_key), do: [target_key], else: []
              end

            rewritten ->
              direct_expr_callees(rewritten, module_name, candidates, decl_map)
          end

        %{op: :var, name: name} ->
          target = {module_name, name}
          if MapSet.member?(candidates, target), do: [target], else: []

        _ ->
          []
      end

    child_callees =
      expr
      |> Map.values()
      |> Enum.flat_map(&direct_expr_callees_list(&1, module_name, candidates, decl_map))

    own ++ child_callees
  end

  defp direct_expr_callees_list(values, module_name, candidates, decl_map) when is_list(values) do
    Enum.flat_map(values, &direct_expr_callees_list(&1, module_name, candidates, decl_map))
  end

  defp direct_expr_callees_list(_value, _module_name, _candidates, _decl_map), do: []

  defp direct_candidate_module?(module_name) do
    not core_library_module?(module_name) and
      not String.starts_with?(module_name, "Pebble.Ui") and
      not String.starts_with?(module_name, "Pebble.Platform") and
      not String.starts_with?(module_name, "Pebble.Events") and
      not String.starts_with?(module_name, "Pebble.Frame") and
      not String.starts_with?(module_name, "Pebble.Button") and
      not String.starts_with?(module_name, "Pebble.Storage") and
      not String.starts_with?(module_name, "Pebble.Cmd") and
      not String.starts_with?(module_name, "Elm.Kernel.")
  end

  defp core_library_module?(module_name) do
    module_name in [
      "Basics",
      "Bitwise",
      "Char",
      "Debug",
      "Dict",
      "Json.Decode",
      "Json.Encode",
      "List",
      "Maybe",
      "Platform",
      "Platform.Cmd",
      "Platform.Sub",
      "Random",
      "Result",
      "Set",
      "String",
      "Sub",
      "Tuple"
    ]
  end

  defp generic_function_targets(ir, opts) do
    decl_map =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    direct_targets = direct_command_targets(ir, opts, decl_map)

    direct_runtime_roots =
      if direct_render_only?(opts) do
        generic_callees_from_direct_targets(direct_targets, decl_map)
        |> Enum.reject(&MapSet.member?(direct_targets, &1))
      else
        generic_callees_from_direct_targets(direct_targets, decl_map)
      end

    roots =
      if opts[:strip_dead_code] == false do
        decl_map
        |> Map.keys()
      else
        generic_entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Enum.reject(&MapSet.member?(direct_targets, &1))

    generic_reachable_targets(
      roots,
      decl_map,
      direct_render_excluded_targets(opts, direct_targets, decl_map),
      MapSet.new()
    )
  end

  defp generic_wrapper_targets(ir, opts) do
    if opts[:prune_native_wrappers] == true do
      decl_map = function_decl_map(ir)
      direct_targets = direct_command_targets(ir, opts, decl_map)
      generic_wrapper_targets(ir, opts, decl_map, direct_targets)
    else
      generic_function_targets(ir, opts)
    end
  end

  defp generic_wrapper_targets(ir, opts, decl_map, direct_targets) do
    if opts[:prune_native_wrappers] == true do
      do_generic_wrapper_targets(opts, decl_map, direct_targets)
    else
      generic_function_targets(ir, opts)
    end
  end

  defp do_generic_wrapper_targets(opts, decl_map, direct_targets) do
    direct_runtime_roots =
      if direct_render_only?(opts) do
        generic_wrapper_callees_from_direct_targets(direct_targets, decl_map)
        |> Enum.reject(&MapSet.member?(direct_targets, &1))
      else
        generic_wrapper_callees_from_direct_targets(direct_targets, decl_map)
      end

    roots =
      if opts[:strip_dead_code] == false do
        decl_map
        |> Map.keys()
      else
        generic_entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Enum.reject(&MapSet.member?(direct_targets, &1))

    generic_wrapper_reachable_targets(
      roots,
      decl_map,
      direct_render_excluded_targets(opts, direct_targets, decl_map),
      MapSet.new()
    )
  end

  defp direct_render_only?(opts), do: opts[:direct_render_only] == true

  defp direct_render_excluded_targets(opts, direct_targets, decl_map) do
    if direct_render_only?(opts) do
      decl_map
      |> Map.keys()
      |> Enum.filter(&generic_render_helper_target?/1)
      |> MapSet.new()
      |> MapSet.union(direct_targets)
    else
      MapSet.new()
    end
  end

  defp generic_render_helper_target?({module_name, _decl_name}) when is_binary(module_name) do
    module_name == "Pebble.Ui" or String.starts_with?(module_name, "Pebble.Ui.")
  end

  defp generic_render_helper_target?(_target), do: false

  defp generic_callees_from_direct_targets(direct_targets, decl_map) do
    direct_targets
    |> Enum.flat_map(fn {module_name, _decl_name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> generic_expr_callees(decl.expr, module_name, decl_map)
        :error -> []
      end
    end)
    |> Enum.reject(&generic_render_helper_target?/1)
  end

  defp generic_wrapper_callees_from_direct_targets(direct_targets, decl_map) do
    direct_targets
    |> Enum.flat_map(fn {module_name, _decl_name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> generic_expr_wrapper_callees(decl.expr, module_name, decl_map)
        :error -> []
      end
    end)
    |> Enum.reject(&generic_render_helper_target?/1)
  end

  defp generic_entry_roots(decl_map, opts) do
    entry_module = opts[:entry_module] || "Main"

    entry_roots =
      ["init", "update", "subscriptions", "view", "main"]
      |> Enum.map(&{entry_module, &1})

    exported_runtime_roots =
      decl_map
      |> Map.keys()
      |> Enum.filter(fn {_module_name, decl_name} ->
        String.ends_with?(decl_name, "_commands_from")
      end)

    (entry_roots ++ exported_runtime_roots)
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(decl_map, &1))
  end

  defp generic_reachable_targets([], _decl_map, _excluded_targets, seen), do: seen

  defp generic_reachable_targets([target | rest], decl_map, excluded_targets, seen) do
    cond do
      MapSet.member?(excluded_targets, target) ->
        generic_reachable_targets(rest, decl_map, excluded_targets, seen)

      MapSet.member?(seen, target) ->
        generic_reachable_targets(rest, decl_map, excluded_targets, seen)

      not Map.has_key?(decl_map, target) ->
        generic_reachable_targets(rest, decl_map, excluded_targets, seen)

      true ->
        decl = Map.fetch!(decl_map, target)
        callees = generic_expr_callees(decl.expr, elem(target, 0), decl_map)

        generic_reachable_targets(
          rest ++ callees,
          decl_map,
          excluded_targets,
          MapSet.put(seen, target)
        )
    end
  end

  defp generic_wrapper_reachable_targets([], _decl_map, _excluded_targets, seen), do: seen

  defp generic_wrapper_reachable_targets([target | rest], decl_map, excluded_targets, seen) do
    cond do
      MapSet.member?(excluded_targets, target) ->
        generic_wrapper_reachable_targets(rest, decl_map, excluded_targets, seen)

      MapSet.member?(seen, target) ->
        generic_wrapper_reachable_targets(rest, decl_map, excluded_targets, seen)

      not Map.has_key?(decl_map, target) ->
        generic_wrapper_reachable_targets(rest, decl_map, excluded_targets, seen)

      true ->
        decl = Map.fetch!(decl_map, target)
        callees = generic_expr_wrapper_callees(decl.expr, elem(target, 0), decl_map)

        generic_wrapper_reachable_targets(
          rest ++ callees,
          decl_map,
          excluded_targets,
          MapSet.put(seen, target)
        )
    end
  end

  defp generic_expr_callees(expr, module_name, decl_map) do
    expr
    |> generic_expr_callees_list(module_name, decl_map)
    |> Enum.uniq()
  end

  defp generic_expr_wrapper_callees(expr, module_name, decl_map) do
    expr
    |> generic_expr_wrapper_callees_list(module_name, decl_map)
    |> Enum.uniq()
  end

  defp generic_expr_wrapper_callees_list(expr, module_name, decl_map) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: name, args: args} ->
          target = {module_name, name}

          cond do
            not Map.has_key?(decl_map, target) -> []
            native_function_call_target?(target, args || [], decl_map) -> []
            true -> [target]
          end

        %{op: :qualified_call, target: target, args: args} ->
          case special_value_from_target(target, args || []) do
            nil ->
              case split_qualified_function_target(normalize_special_target(target)) do
                nil ->
                  []

                target_key ->
                  cond do
                    not Map.has_key?(decl_map, target_key) -> []
                    native_function_call_target?(target_key, args || [], decl_map) -> []
                    true -> [target_key]
                  end
              end

            rewritten ->
              generic_expr_wrapper_callees_list(rewritten, module_name, decl_map)
          end

        %{op: :var, name: name} ->
          target = {module_name, name}
          if Map.has_key?(decl_map, target), do: [target], else: []

        _ ->
          []
      end

    child_callees =
      expr
      |> wrapper_callee_child_values()
      |> Enum.flat_map(&generic_expr_wrapper_callees_list(&1, module_name, decl_map))

    own ++ child_callees
  end

  defp generic_expr_wrapper_callees_list(values, module_name, decl_map) when is_list(values) do
    Enum.flat_map(values, &generic_expr_wrapper_callees_list(&1, module_name, decl_map))
  end

  defp generic_expr_wrapper_callees_list(_value, _module_name, _decl_map), do: []

  defp wrapper_callee_child_values(%{op: op, args: args})
       when op in [:call, :qualified_call, :runtime_call, :constructor_call, :field_call] and
              is_list(args),
       do: args

  defp wrapper_callee_child_values(expr), do: Map.values(expr)

  defp native_function_call_target?(target, args, decl_map) do
    case Map.fetch(decl_map, target) do
      {:ok, decl} ->
        length(args || []) == length(decl.args || []) and native_function_args?(decl)

      :error ->
        false
    end
  end

  defp generic_expr_callees_list(expr, module_name, decl_map) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: name} ->
          target = {module_name, name}
          if Map.has_key?(decl_map, target), do: [target], else: []

        %{op: :qualified_call, target: target, args: args} ->
          case special_value_from_target(target, args || []) do
            nil ->
              case split_qualified_function_target(normalize_special_target(target)) do
                nil ->
                  []

                target_key ->
                  if Map.has_key?(decl_map, target_key), do: [target_key], else: []
              end

            rewritten ->
              generic_expr_callees_list(rewritten, module_name, decl_map)
          end

        %{op: :var, name: name} ->
          target = {module_name, name}
          if Map.has_key?(decl_map, target), do: [target], else: []

        _ ->
          []
      end

    child_callees =
      expr
      |> Map.values()
      |> Enum.flat_map(&generic_expr_callees_list(&1, module_name, decl_map))

    own ++ child_callees
  end

  defp generic_expr_callees_list(values, module_name, decl_map) when is_list(values) do
    Enum.flat_map(values, &generic_expr_callees_list(&1, module_name, decl_map))
  end

  defp generic_expr_callees_list(_value, _module_name, _decl_map), do: []

  defp filter_direct_targets(targets, decl_map) do
    Enum.reduce(targets, MapSet.new(), fn {module_name, _decl_name} = target, acc ->
      decl = Map.fetch!(decl_map, target)

      if direct_supported?(decl.expr, module_name, decl_map, MapSet.new()) do
        env =
          (decl.args || [])
          |> Enum.reduce(%{__module__: module_name, __direct_targets__: targets}, fn arg, env ->
            Map.put(env, arg, arg)
          end)

        case direct_emit_expr(decl.expr, env, 0) do
          {:ok, _code, _counter} -> MapSet.put(acc, target)
          :error -> acc
        end
      else
        acc
      end
    end)
  end

  defp direct_supported?(expr, module_name, decl_map, seen) do
    case expr do
      %{op: :list_literal, items: items} ->
        Enum.all?(items, &direct_supported?(&1, module_name, decl_map, seen))

      %{op: :let_in, in_expr: in_expr} ->
        direct_supported?(in_expr, module_name, decl_map, seen)

      %{op: :case, branches: branches} ->
        Enum.all?(branches, &direct_supported?(&1.expr, module_name, decl_map, seen))

      %{op: :if, then_expr: then_expr, else_expr: else_expr} ->
        direct_supported?(then_expr, module_name, decl_map, seen) and
          direct_supported?(else_expr, module_name, decl_map, seen)

      %{op: :lambda, body: body} ->
        direct_supported?(body, module_name, decl_map, seen)

      %{op: :call, name: "__append__", args: [left, right]} ->
        direct_supported?(left, module_name, decl_map, seen) and
          direct_supported?(right, module_name, decl_map, seen)

      %{op: :call, name: name} ->
        target = {module_name, name}

        Map.has_key?(decl_map, target) and not MapSet.member?(seen, target) and
          direct_supported?(
            decl_map[target].expr,
            module_name,
            decl_map,
            MapSet.put(seen, target)
          )

      %{op: :var} ->
        true

      %{op: :qualified_call, target: target, args: args} ->
        direct_qualified_supported?(
          normalize_special_target(target),
          args,
          module_name,
          decl_map,
          seen
        )

      _ ->
        false
    end
  end

  defp direct_qualified_supported?(target, args, module_name, decl_map, seen) do
    case {target, args} do
      {"Pebble.Ui.toUiNode", [expr]} ->
        direct_supported?(expr, module_name, decl_map, seen)

      {"Pebble.Ui.windowStack", [%{op: :list_literal, items: items}]} ->
        Enum.all?(items, &direct_supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.window", [_id, %{op: :list_literal, items: items}]} ->
        Enum.all?(items, &direct_supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.canvasLayer", [_id, %{op: :list_literal, items: items}]} ->
        Enum.all?(items, &direct_supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.group", [%{op: :qualified_call, target: ctx_target, args: ctx_args}]} ->
        direct_context_supported?(
          normalize_special_target(ctx_target),
          ctx_args,
          module_name,
          decl_map,
          seen
        )

      {"String.append", [left, right]} ->
        direct_supported?(left, module_name, decl_map, seen) and
          direct_supported?(right, module_name, decl_map, seen)

      {"List.concat", [%{op: :list_literal, items: items}]} ->
        Enum.all?(items, &direct_supported?(&1, module_name, decl_map, seen))

      {"List.indexedMap", [fun_expr, _list_expr]} ->
        direct_function_target(fun_expr, module_name, decl_map, seen) != nil

      {"List.concatMap", [fun_expr, _list_expr]} ->
        direct_function_target(fun_expr, module_name, decl_map, seen) != nil or
          direct_lambda_supported?(fun_expr, module_name, decl_map, seen)

      {"List.map", [fun_expr, _list_expr]} ->
        direct_function_target(fun_expr, module_name, decl_map, seen) != nil or
          direct_lambda_supported?(fun_expr, module_name, decl_map, seen)

      {target, _args}
      when target in [
             "Pebble.Ui.clear",
             "Pebble.Ui.pixel",
             "Pebble.Ui.line",
             "Pebble.Ui.rect",
             "Pebble.Ui.fillRect",
             "Pebble.Ui.circle",
             "Pebble.Ui.fillCircle",
             "Pebble.Ui.textInt",
             "Pebble.Ui.textLabel",
             "Pebble.Ui.text",
             "Pebble.Ui.roundRect",
             "Pebble.Ui.arc",
             "Pebble.Ui.fillRadial",
             "Pebble.Ui.drawBitmapInRect",
             "Pebble.Ui.drawRotatedBitmap"
           ] ->
        true

      {target, [%{op: :qualified_call, target: path_target, args: path_args}]}
      when target in [
             "Pebble.Ui.pathFilled",
             "Pebble.Ui.pathOutline",
             "Pebble.Ui.pathOutlineOpen"
           ] ->
        direct_path_supported?(normalize_special_target(path_target), path_args)

      {target, _args} ->
        case direct_qualified_function_target(target, decl_map) do
          nil ->
            false

          target_key ->
            Map.has_key?(decl_map, target_key) and
              not MapSet.member?(seen, target_key) and
              direct_supported?(
                decl_map[target_key].expr,
                elem(target_key, 0),
                decl_map,
                MapSet.put(seen, target_key)
              )
        end
    end
  end

  defp direct_context_supported?(
         "Pebble.Ui.context",
         [%{op: :list_literal, items: settings}, %{op: :list_literal, items: commands}],
         module_name,
         decl_map,
         seen
       ) do
    Enum.all?(settings, &direct_setting_supported?/1) and
      Enum.all?(commands, &direct_supported?(&1, module_name, decl_map, seen))
  end

  defp direct_context_supported?(_, _, _, _, _), do: false

  defp direct_setting_supported?(%{op: :qualified_call, target: target, args: [_]}) do
    normalize_special_target(target) in [
      "Pebble.Ui.strokeWidth",
      "Pebble.Ui.antialiased",
      "Pebble.Ui.strokeColor",
      "Pebble.Ui.fillColor",
      "Pebble.Ui.textColor",
      "Pebble.Ui.compositingMode"
    ]
  end

  defp direct_setting_supported?(_), do: false

  defp direct_path_supported?("Pebble.Ui.path", [
         %{op: :list_literal, items: points},
         offset,
         _rotation
       ]) do
    (length(points) <= 16 and
       Enum.all?(points, &(record_field_expr(&1, "x") && record_field_expr(&1, "y"))) and
       record_field_expr(offset, "x")) && record_field_expr(offset, "y")
  end

  defp direct_path_supported?(_, _), do: false

  defp direct_function_target(%{op: :var, name: name}, module_name, decl_map, seen) do
    target = {module_name, name}

    if Map.has_key?(decl_map, target) and
         not MapSet.member?(seen, target) and
         direct_supported?(decl_map[target].expr, module_name, decl_map, MapSet.put(seen, target)) do
      {module_name, name, []}
    end
  end

  defp direct_function_target(%{op: :call, name: name, args: args}, module_name, decl_map, seen) do
    case direct_function_target(%{op: :var, name: name}, module_name, decl_map, seen) do
      {target_module, target_name, []} -> {target_module, target_name, args}
      other -> other
    end
  end

  defp direct_function_target(
         %{op: :qualified_call, target: target, args: args},
         _module_name,
         decl_map,
         seen
       ) do
    with {target_module, target_name} = target_key <-
           direct_qualified_function_target(normalize_special_target(target), decl_map),
         true <- Map.has_key?(decl_map, target_key),
         true <- not MapSet.member?(seen, target_key),
         true <-
           direct_supported?(
             decl_map[target_key].expr,
             target_module,
             decl_map,
             MapSet.put(seen, target_key)
           ) do
      {target_module, target_name, args}
    else
      _ -> nil
    end
  end

  defp direct_function_target(_expr, _module_name, _decl_map, _seen), do: nil

  defp direct_lambda_supported?(
         %{op: :lambda, args: [_arg], body: body},
         module_name,
         decl_map,
         seen
       ) do
    direct_supported?(body, module_name, decl_map, seen)
  end

  defp direct_lambda_supported?(_expr, _module_name, _decl_map, _seen), do: false

  defp direct_qualified_function_target(target, candidates) when is_binary(target) do
    candidate_keys =
      cond do
        match?(%MapSet{}, candidates) -> MapSet.to_list(candidates)
        is_map(candidates) -> Map.keys(candidates)
        true -> Enum.to_list(candidates)
      end

    Enum.find_value(candidate_keys, fn {module_name, decl_name} = key ->
      if target == "#{module_name}.#{decl_name}", do: key
    end)
  end

  defp split_qualified_function_target(target) when is_binary(target) do
    case String.split(target, ".") do
      [_single] ->
        nil

      parts ->
        {name_parts, [function_name]} = Enum.split(parts, -1)
        {Enum.join(name_parts, "."), function_name}
    end
  end

  defp direct_command_def(mod, decl, targets, decl_map) do
    c_name = module_fn_name(mod.name, decl.name)
    arg_names = decl.args || []
    c_arg_bindings = c_arg_bindings(arg_names)
    arg_kinds = direct_command_arg_kinds(decl)

    if Enum.any?(arg_kinds, &(&1 != :boxed)) do
      direct_command_native_def(mod, decl, targets, decl_map, c_name, c_arg_bindings, arg_kinds)
    else
      direct_command_boxed_def(mod, decl, targets, decl_map, c_name, c_arg_bindings)
    end
  end

  defp direct_command_boxed_def(mod, decl, targets, decl_map, c_name, c_arg_bindings) do
    arg_bindings =
      c_arg_bindings
      |> Enum.map_join("\n  ", fn {_arg, c_arg, index} ->
        "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)

    unused_casts =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    env =
      c_arg_bindings
      |> Enum.reduce(
        %{__module__: mod.name, __direct_targets__: targets, __program_decls__: decl_map},
        fn arg, acc ->
          {source_arg, c_arg, _index} = arg
          Map.put(acc, source_arg, c_arg)
        end
      )
      |> put_typed_arg_bindings(c_arg_bindings, decl.type)

    {:ok, body_code, _counter} = direct_emit_expr(decl.expr, env, 0)

    """
    static int #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted) {
      (void)args;
      (void)argc;
      #{arg_bindings}
      #{unused_casts}
      if (!out_cmds || !count || !emitted || max_cmds <= 0) return -1;
      #{body_code}
      return 0;
    }

    int #{c_name}_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds) {
      return #{c_name}_commands_from(args, argc, out_cmds, max_cmds, 0);
    }

    int #{c_name}_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip) {
      int count = 0;
      int emitted = 0;
      if (!out_cmds || max_cmds <= 0) return -1;
      if (skip < 0) return -1;
      int rc = #{c_name}_commands_append(args, argc, (ElmcGeneratedPebbleDrawCmd *)out_cmds, max_cmds, skip, &count, &emitted);
      return rc < 0 ? rc : count;
    }
    """
  end

  defp direct_command_native_def(mod, decl, targets, decl_map, c_name, c_arg_bindings, arg_kinds) do
    wrapper_bindings =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.map_join("\n  ", fn {{_arg, c_arg, index}, kind} ->
        case kind do
          :native_int ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"

          :native_string ->
            """
            const char *#{c_arg} =
              (argc > #{index} && args[#{index}] && args[#{index}]->tag == ELMC_TAG_STRING && args[#{index}]->payload)
                ? (const char *)args[#{index}]->payload
                : "";
            """

          :boxed ->
            "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    native_env =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.reduce(
        %{__module__: mod.name, __direct_targets__: targets, __program_decls__: decl_map},
        fn {{source_arg, c_arg, _index}, kind}, acc ->
          case kind do
            :native_int -> put_native_int_binding(acc, source_arg, c_arg)
            :native_string -> put_native_string_binding(acc, source_arg, c_arg)
            :boxed -> Map.put(acc, source_arg, c_arg)
          end
        end
      )
      |> put_typed_arg_bindings(c_arg_bindings, decl.type)

    unused_casts =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    {:ok, body_code, _counter} = direct_emit_expr(decl.expr, native_env, 0)

    """
    static int #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted) {
      (void)args;
      (void)argc;
      #{wrapper_bindings}
      return #{c_name}_commands_append_native(#{native_args}, out_cmds, max_cmds, skip, count, emitted);
    }

    static int #{c_name}_commands_append_native(#{native_direct_command_params(decl)}, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted) {
      #{unused_casts}
      if (!out_cmds || !count || !emitted || max_cmds <= 0) return -1;
      #{body_code}
      return 0;
    }

    int #{c_name}_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds) {
      return #{c_name}_commands_from(args, argc, out_cmds, max_cmds, 0);
    }

    int #{c_name}_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip) {
      int count = 0;
      int emitted = 0;
      if (!out_cmds || max_cmds <= 0) return -1;
      if (skip < 0) return -1;
      int rc = #{c_name}_commands_append(args, argc, (ElmcGeneratedPebbleDrawCmd *)out_cmds, max_cmds, skip, &count, &emitted);
      return rc < 0 ? rc : count;
    }
    """
  end

  defp native_direct_command_args?(decl) do
    decl
    |> direct_command_arg_kinds()
    |> Enum.any?(&(&1 != :boxed))
  end

  defp native_direct_command_params(decl) do
    c_arg_bindings(decl.args || [])
    |> Enum.zip(direct_command_arg_kinds(decl))
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> "const elmc_int_t #{c_arg}"
        :native_string -> "const char * const #{c_arg}"
        :boxed -> "ElmcValue * const #{c_arg}"
      end
    end)
  end

  defp direct_command_arg_kinds(%{args: args, type: type})
       when is_list(args) and is_binary(type) do
    arg_types = function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {_arg, index} ->
      case Enum.at(arg_types, index) |> normalize_type_name() do
        "Int" ->
          :native_int

        "Pebble.Ui.Color.Color" ->
          :native_int

        "String" ->
          :native_string

        _other ->
          :boxed
      end
    end)
  end

  defp direct_command_arg_kinds(%{args: args}) when is_list(args),
    do: Enum.map(args, fn _ -> :boxed end)

  defp direct_command_arg_kinds(_decl), do: []

  defp direct_emit_expr(%{op: :list_literal, items: items}, env, counter) do
    Enum.reduce_while(items, {:ok, "", counter}, fn item, {:ok, acc, c} ->
      case direct_emit_expr(item, env, c) do
        {:ok, code, c2} -> {:cont, {:ok, acc <> "\n" <> code, c2}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp direct_emit_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
         env,
         counter
       ) do
    cond do
      direct_fragment_expr?(value_expr, env) ->
        direct_emit_expr(in_expr, Map.put(env, name, {:direct_fragment, value_expr}), counter)

      direct_native_int_let?(name, value_expr, in_expr, env) ->
        {value_code, value_ref, counter} = compile_native_int_expr(value_expr, env, counter)
        next = counter + 1
        native_var = "direct_native_let_#{safe_c_suffix(name)}_#{next}"

        body_env =
          env
          |> Map.delete(name)
          |> put_native_int_binding(name, native_var)
          |> remove_native_bool_binding(name)
          |> put_boxed_int_binding(name, false)

        case direct_emit_expr(in_expr, body_env, next) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
               const elmc_int_t #{native_var} = #{value_ref};
             #{indent(body_code, 2)}
             """, counter}

          :error ->
            :error
        end

      direct_native_string_let?(name, value_expr, in_expr, env) ->
        {value_code, value_ref, cleanup_refs, counter} =
          compile_native_string_expr(value_expr, env, counter)

        body_env =
          env
          |> Map.delete(name)
          |> put_native_string_binding(name, value_ref)

        cleanup_code =
          cleanup_refs
          |> Enum.map_join("\n  ", fn ref -> "elmc_release(#{ref});" end)

        case direct_emit_expr(in_expr, body_env, counter) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
             #{indent(body_code, 2)}
               #{cleanup_code}
             """, counter}

          :error ->
            :error
        end

      true ->
        {value_code, value_var, counter} = compile_expr(value_expr, env, counter)

        body_env =
          env
          |> Map.put(name, value_var)
          |> put_boxed_int_binding(name, native_int_expr?(value_expr, env))
          |> put_record_shape(name, record_shape(value_expr, env))

        case direct_emit_expr(in_expr, body_env, counter) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
               #{body_code}
               elmc_release(#{value_var});
             """, counter}

          :error ->
            :error
        end
    end
  end

  defp direct_emit_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    {cond_code, cond_ref, cond_release, counter} =
      if native_bool_expr?(cond_expr, env) do
        {code, ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
        {code, ref, "", counter}
      else
        {code, var, counter} = compile_expr(cond_expr, env, counter)
        {code, "elmc_as_int(#{var}) != 0", "  elmc_release(#{var});", counter}
      end

    with {:ok, then_code, counter} <- direct_emit_expr(then_expr, env, counter),
         {:ok, else_code, counter} <- direct_emit_expr(else_expr, env, counter) do
      {:ok, direct_emit_if_code(cond_code, cond_ref, then_code, else_code, cond_release), counter}
    else
      _ -> :error
    end
  end

  defp direct_emit_expr(%{op: :case, subject: subject, branches: branches}, env, counter) do
    subject_ref = Map.get(env, subject, subject)

    result =
      Enum.reduce_while(branches, {:ok, "", counter}, fn branch, {:ok, acc, c} ->
        branch_env =
          env
          |> bind_pattern(branch.pattern, subject_ref)
          |> Map.put(:__direct_targets__, Map.get(env, :__direct_targets__, MapSet.new()))

        case direct_emit_expr(branch.expr, branch_env, c) do
          {:ok, expr_code, c2} ->
            cond_code = pattern_condition(subject_ref, branch.pattern)

            cond do
              cond_code == "0" ->
                {:cont, {:ok, acc, c2}}

              cond_code == "1" and acc == "" ->
                {:halt, {:ok, acc <> expr_code, c2}}

              cond_code == "1" ->
                snippet = """
                else {
                #{indent(expr_code, 4)}
                }
                """

                {:halt, {:ok, acc <> snippet, c2}}

              true ->
                snippet = """
                #{if acc == "", do: "if", else: "else if"} (#{cond_code}) {
                #{indent(expr_code, 4)}
                }
                """

                {:cont, {:ok, acc <> snippet, c2}}
            end

          :error ->
            {:halt, :error}
        end
      end)

    case result do
      {:ok, branch_code, counter} -> {:ok, branch_code, counter}
      :error -> :error
    end
  end

  defp direct_emit_expr(%{op: :call, name: name, args: args}, env, counter) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())

    cond do
      name == "__append__" and length(args) == 2 ->
        [left, right] = args

        with {:ok, left_code, counter} <- direct_emit_expr(left, env, counter),
             {:ok, right_code, counter} <- direct_emit_expr(right, env, counter) do
          {:ok, left_code <> right_code, counter}
        else
          _ -> :error
        end

      MapSet.member?(targets, {module_name, name}) ->
        direct_emit_command_call({module_name, name}, args, env, counter)

      true ->
        :error
    end
  end

  defp direct_emit_expr(%{op: :var, name: name}, env, counter) do
    case Map.get(env, name) do
      {:direct_fragment, expr} -> direct_emit_expr(expr, Map.delete(env, name), counter)
      _ -> :error
    end
  end

  defp direct_emit_expr(%{op: :qualified_call, target: target, args: args}, env, counter) do
    direct_emit_qualified(normalize_special_target(target), args, env, counter)
  end

  defp direct_emit_expr(_expr, _env, _counter), do: :error

  defp direct_emit_if_code(cond_code, cond_ref, then_code, else_code, cond_release) do
    then_empty? = direct_empty_code?(then_code)
    else_empty? = direct_empty_code?(else_code)

    body =
      cond do
        then_empty? and else_empty? ->
          ""

        then_empty? ->
          """
            if (!(#{cond_ref})) {
          #{indent(else_code, 4)}
            }
          """

        else_empty? ->
          """
            if (#{cond_ref}) {
          #{indent(then_code, 4)}
            }
          """

        true ->
          """
            if (#{cond_ref}) {
          #{indent(then_code, 4)}
            } else {
          #{indent(else_code, 4)}
            }
          """
      end

    """
    #{cond_code}
    #{body}
    #{cond_release}
    """
  end

  defp direct_empty_code?(code), do: String.trim(code || "") == ""

  defp direct_native_int_let?(name, value_expr, in_expr, env)
       when is_binary(name) or is_atom(name) do
    usage = direct_native_int_usage(name, in_expr, env)

    native_int_expr?(value_expr, env) and usage.total > 0 and usage.boxed == 0 and
      not binding_used_in_lambda?(name, in_expr)
  end

  defp direct_native_int_let?(_name, _value_expr, _in_expr, _env), do: false

  defp direct_native_string_let?(name, value_expr, in_expr, env)
       when is_binary(name) or is_atom(name) do
    usage = direct_native_string_usage(name, in_expr, env)

    native_string_expr?(value_expr, env) and usage.total > 0 and usage.boxed == 0 and
      usage.native_string > 0 and not binding_used_in_lambda?(name, in_expr)
  end

  defp direct_native_string_let?(_name, _value_expr, _in_expr, _env), do: false

  defp direct_native_string_usage(name, expr, env) do
    name
    |> collect_direct_var_contexts(expr, :boxed, env)
    |> Enum.reduce(%{total: 0, boxed: 0, native_string: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
        native_string: acc.native_string + if(context == :native_string, do: 1, else: 0)
      }
    end)
  end

  defp direct_native_int_usage(name, expr, env) do
    name
    |> collect_direct_var_contexts(expr, :boxed, env)
    |> Enum.reduce(%{total: 0, boxed: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0)
      }
    end)
  end

  defp collect_direct_var_contexts(name, %{op: :var, name: var_name}, context, _env) do
    if same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_direct_var_contexts(name, %{op: :add_const, var: var_name}, _context, _env) do
    if same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_direct_var_contexts(name, %{op: :sub_const, var: var_name}, _context, _env) do
    if same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :add_vars, left: left, right: right},
         _context,
         _env
       ) do
    [left, right]
    |> Enum.filter(&same_binding?(name, &1))
    |> Enum.map(fn _ -> :native end)
  end

  defp collect_direct_var_contexts(name, %{op: :call, name: call_name, args: args}, context, env) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    decl_map = Map.get(env, :__program_decls__, %{})

    cond do
      call_name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] ->
        Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))

      MapSet.member?(targets, {module_name, call_name}) ->
        collect_direct_command_arg_contexts(name, {module_name, call_name}, args, env)

      native_call =
          native_function_call_arg_kinds(
            %{op: :call, name: call_name, args: args},
            module_name,
            decl_map
          ) ->
        {_call_args, arg_kinds} = native_call
        collect_direct_function_arg_contexts(name, args, arg_kinds, env)

      true ->
        collect_direct_var_contexts_from_map(
          name,
          %{op: :call, name: call_name, args: args},
          context,
          env
        )
    end
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context,
         env
       )
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context,
         env
       )
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :qualified_call, target: target, args: args} = expr,
         context,
         env
       ) do
    normalized = normalize_special_target(target)
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    decl_map = Map.get(env, :__program_decls__, %{})

    case special_value_from_target(normalized, args) do
      nil ->
        cond do
          normalized == "Pebble.Ui.text" and length(args || []) == 3 ->
            collect_direct_function_arg_contexts(
              name,
              args,
              [:boxed, :boxed, :native_string],
              env
            )

          qualified_builtin_operator_name(normalized) in [
            "__add__",
            "__sub__",
            "__mul__",
            "__idiv__",
            "modBy",
            "remainderBy"
          ] ->
            Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))

          match?({_module, _function}, split_qualified_function_target(normalized)) ->
            case split_qualified_function_target(normalized) do
              {target_module, target_name} ->
                cond do
                  MapSet.member?(targets, {target_module, target_name}) ->
                    collect_direct_command_arg_contexts(
                      name,
                      {target_module, target_name},
                      args,
                      env
                    )

                  native_call = native_function_call_arg_kinds(expr, nil, decl_map) ->
                    {_call_args, arg_kinds} = native_call
                    collect_direct_function_arg_contexts(name, args, arg_kinds, env)

                  true ->
                    collect_direct_var_contexts_from_map(name, expr, context, env)
                end

              nil ->
                collect_direct_var_contexts_from_map(name, expr, context, env)
            end

          true ->
            collect_direct_var_contexts_from_map(name, expr, context, env)
        end

      rewritten ->
        collect_direct_var_contexts(name, rewritten, context, env)
    end
  end

  defp collect_direct_var_contexts(name, %{op: :tuple2, left: left, right: right}, _context, env) do
    left_context = if native_int_candidate_for_analysis?(name, left), do: :native, else: :boxed
    right_context = if native_int_candidate_for_analysis?(name, right), do: :native, else: :boxed

    collect_direct_var_contexts(name, left, left_context, env) ++
      collect_direct_var_contexts(name, right, right_context, env)
  end

  defp collect_direct_var_contexts(name, %{op: :record_literal, fields: fields}, _context, env)
       when is_list(fields) do
    Enum.flat_map(fields, fn field ->
      context = if native_int_candidate_for_analysis?(name, field.expr), do: :native, else: :boxed
      collect_direct_var_contexts(name, field.expr, context, env)
    end)
  end

  defp collect_direct_var_contexts(name, %{op: :compare, left: left, right: right}, _context, env) do
    context =
      if native_int_candidate_for_analysis?(name, left) and
           native_int_candidate_for_analysis?(name, right),
         do: :native,
         else: :boxed

    collect_direct_var_contexts(name, left, context, env) ++
      collect_direct_var_contexts(name, right, context, env)
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         _context,
         env
       ) do
    branch_context =
      if native_int_candidate_for_analysis?(name, then_expr) and
           native_int_candidate_for_analysis?(name, else_expr),
         do: :native,
         else: :boxed

    collect_direct_var_contexts(name, cond_expr, :boxed, env) ++
      collect_direct_var_contexts(name, then_expr, branch_context, env) ++
      collect_direct_var_contexts(name, else_expr, branch_context, env)
  end

  defp collect_direct_var_contexts(name, %{op: :lambda, args: args, body: body}, _context, env)
       when is_list(args) do
    if Enum.any?(args, &same_binding?(name, &1)) do
      []
    else
      collect_direct_var_contexts(name, body, :boxed, env)
    end
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context,
         env
       ) do
    value_contexts = collect_direct_var_contexts(name, value_expr, context, env)

    if same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_direct_var_contexts(name, in_expr, context, env)
    end
  end

  defp collect_direct_var_contexts(name, expr, context, env) when is_map(expr),
    do: collect_direct_var_contexts_from_map(name, expr, context, env)

  defp collect_direct_var_contexts(name, exprs, context, env) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_direct_var_contexts(name, &1, context, env))

  defp collect_direct_var_contexts(_name, _expr, _context, _env), do: []

  defp collect_direct_var_contexts_from_map(name, expr, context, env) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_direct_var_contexts(name, &1, context, env))
  end

  defp collect_direct_command_arg_contexts(name, target_key, args, env) do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.get(target_key)

    arg_kinds =
      if decl, do: direct_command_arg_kinds(decl), else: Enum.map(args, fn _ -> :boxed end)

    collect_direct_function_arg_contexts(name, args, arg_kinds, env)
  end

  defp collect_direct_function_arg_contexts(name, args, arg_kinds, env) do
    args
    |> Enum.zip(arg_kinds)
    |> Enum.flat_map(fn {arg, kind} ->
      context =
        case kind do
          :native_int -> :native
          :native_string -> :native_string
          _ -> :boxed
        end

      collect_direct_var_contexts(name, arg, context, env)
    end)
  end

  defp direct_fragment_expr?(%{op: :list_literal}, _env), do: true
  defp direct_fragment_expr?(%{op: :case}, _env), do: true

  defp direct_fragment_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: direct_fragment_expr?(then_expr, env) and direct_fragment_expr?(else_expr, env)

  defp direct_fragment_expr?(%{op: :call, name: name}, env) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    MapSet.member?(targets, {module_name, name})
  end

  defp direct_fragment_expr?(%{op: :qualified_call, target: target}, _env) do
    normalize_special_target(target) in [
      "Pebble.Ui.toUiNode",
      "String.append",
      "Pebble.Ui.clear",
      "Pebble.Ui.pixel",
      "Pebble.Ui.line",
      "Pebble.Ui.rect",
      "Pebble.Ui.fillRect",
      "Pebble.Ui.circle",
      "Pebble.Ui.fillCircle",
      "Pebble.Ui.textInt",
      "Pebble.Ui.textLabel",
      "Pebble.Ui.text",
      "Pebble.Ui.group",
      "Pebble.Ui.pathFilled",
      "Pebble.Ui.pathOutline",
      "Pebble.Ui.pathOutlineOpen",
      "Pebble.Ui.roundRect",
      "Pebble.Ui.arc",
      "Pebble.Ui.fillRadial",
      "Pebble.Ui.drawBitmapInRect",
      "Pebble.Ui.drawRotatedBitmap"
    ]
  end

  defp direct_fragment_expr?(_, _env), do: false

  defp direct_emit_qualified("Pebble.Ui.toUiNode", [expr], env, counter),
    do: direct_emit_expr(expr, env, counter)

  defp direct_emit_qualified("String.append", [left, right], env, counter) do
    with {:ok, left_code, counter} <- direct_emit_expr(left, env, counter),
         {:ok, right_code, counter} <- direct_emit_expr(right, env, counter) do
      {:ok, left_code <> right_code, counter}
    else
      _ -> :error
    end
  end

  defp direct_emit_qualified("List.concat", [%{op: :list_literal, items: items}], env, counter) do
    direct_emit_expr(%{op: :list_literal, items: items}, env, counter)
  end

  defp direct_emit_qualified("List.indexedMap", [fun_expr, list_expr], env, counter) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())

    with {target_module, target_name, prefix_args} <-
           direct_emit_function_target(fun_expr, module_name),
         true <- MapSet.member?(targets, {target_module, target_name}) do
      {prefix_code, prefix_vars, counter} = direct_compile_arg_values(prefix_args, env, counter)
      next = counter + 1
      c_name = module_fn_name(target_module, target_name)
      prefix_count = length(prefix_vars)

      prefix_bindings =
        prefix_vars
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {var, index} ->
          "      direct_call_args_#{next}[#{index}] = #{var};"
        end)

      prefix_releases = direct_release_vars(prefix_vars, "        ")

      case direct_range_bounds(list_expr, env, counter) do
        {:ok, range_code, first_ref, last_ref, counter} ->
          {:ok,
           """
           #{prefix_code}
           #{range_code}
            elmc_int_t direct_index_#{next} = 0;
            elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
            for (elmc_int_t direct_item_i_#{next} = #{first_ref}; ; direct_item_i_#{next} += direct_step_#{next}) {
               ElmcValue *direct_index_value_#{next} = elmc_new_int(direct_index_#{next});
               ElmcValue *direct_item_value_#{next} = elmc_new_int(direct_item_i_#{next});
               ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
           #{prefix_bindings}
               direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
               direct_call_args_#{next}[#{prefix_count + 1}] = direct_item_value_#{next};
               int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, out_cmds, max_cmds, skip, count, emitted);
               elmc_release(direct_index_value_#{next});
               elmc_release(direct_item_value_#{next});
               if (direct_rc_#{next} < 0) {
           #{prefix_releases}
                 return direct_rc_#{next};
               }
               if (*count >= max_cmds) {
           #{prefix_releases}
                 return 0;
               }
               if (direct_item_i_#{next} == #{last_ref}) break;
               direct_index_#{next} += 1;
             }
           #{prefix_releases}
           """, counter}

        :error ->
          {list_code, list_var, counter} = compile_expr(list_expr, env, counter)

          {:ok,
           """
           #{list_code}
           #{prefix_code}
             ElmcValue *direct_cursor_#{next} = #{list_var};
            elmc_int_t direct_index_#{next} = 0;
             while (direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
               ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
               ElmcValue *direct_index_value_#{next} = elmc_new_int(direct_index_#{next});
               ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
           #{prefix_bindings}
               direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
               direct_call_args_#{next}[#{prefix_count + 1}] = direct_node_#{next}->head;
               int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, out_cmds, max_cmds, skip, count, emitted);
               elmc_release(direct_index_value_#{next});
               if (direct_rc_#{next} < 0) {
                 elmc_release(#{list_var});
           #{prefix_releases}
                 return direct_rc_#{next};
               }
               if (*count >= max_cmds) {
                 elmc_release(#{list_var});
           #{prefix_releases}
                 return 0;
               }
               direct_index_#{next} += 1;
               direct_cursor_#{next} = direct_node_#{next}->tail;
             }
             elmc_release(#{list_var});
           #{prefix_releases}
           """, counter}
      end
    else
      _ -> :error
    end
  end

  defp direct_emit_qualified(
         "List.map",
         [%{op: :lambda, args: [arg], body: body}, list_expr],
         env,
         counter
       ) do
    direct_emit_lambda_map(arg, body, list_expr, env, counter)
  end

  defp direct_emit_qualified("List.map", [fun_expr, list_expr], env, counter) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())

    with {target_module, target_name, prefix_args} <-
           direct_emit_function_target(fun_expr, module_name),
         true <- MapSet.member?(targets, {target_module, target_name}) do
      {prefix_code, prefix_vars, counter} = direct_compile_arg_values(prefix_args, env, counter)
      next = counter + 1
      c_name = module_fn_name(target_module, target_name)
      prefix_count = length(prefix_vars)

      prefix_bindings =
        prefix_vars
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {var, index} ->
          "      direct_call_args_#{next}[#{index}] = #{var};"
        end)

      prefix_releases = direct_release_vars(prefix_vars, "        ")

      case direct_range_bounds(list_expr, env, counter) do
        {:ok, range_code, first_ref, last_ref, counter} ->
          {:ok,
           """
           #{prefix_code}
           #{range_code}
            elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
            for (elmc_int_t direct_item_i_#{next} = #{first_ref}; ; direct_item_i_#{next} += direct_step_#{next}) {
               ElmcValue *direct_item_value_#{next} = elmc_new_int(direct_item_i_#{next});
               ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
           #{prefix_bindings}
               direct_call_args_#{next}[#{prefix_count}] = direct_item_value_#{next};
               int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, out_cmds, max_cmds, skip, count, emitted);
               elmc_release(direct_item_value_#{next});
               if (direct_rc_#{next} < 0) {
           #{prefix_releases}
                 return direct_rc_#{next};
               }
               if (*count >= max_cmds) {
           #{prefix_releases}
                 return 0;
               }
               if (direct_item_i_#{next} == #{last_ref}) break;
             }
           #{prefix_releases}
           """, counter}

        :error ->
          {list_code, list_var, counter} = compile_expr(list_expr, env, counter)

          {:ok,
           """
           #{list_code}
           #{prefix_code}
             ElmcValue *direct_cursor_#{next} = #{list_var};
             while (direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
               ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
               ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
           #{prefix_bindings}
               direct_call_args_#{next}[#{prefix_count}] = direct_node_#{next}->head;
               int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, out_cmds, max_cmds, skip, count, emitted);
               if (direct_rc_#{next} < 0) {
                 elmc_release(#{list_var});
           #{prefix_releases}
                 return direct_rc_#{next};
               }
               if (*count >= max_cmds) {
                 elmc_release(#{list_var});
           #{prefix_releases}
                 return 0;
               }
               direct_cursor_#{next} = direct_node_#{next}->tail;
             }
             elmc_release(#{list_var});
           #{prefix_releases}
           """, counter}
      end
    else
      _ -> :error
    end
  end

  defp direct_emit_qualified("List.concatMap", [fun_expr, list_expr], env, counter) do
    direct_emit_qualified("List.map", [fun_expr, list_expr], env, counter)
  end

  defp direct_emit_qualified(
         "Pebble.Ui.windowStack",
         [%{op: :list_literal, items: items}],
         env,
         counter
       ),
       do: direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

  defp direct_emit_qualified(
         "Pebble.Ui.window",
         [_id, %{op: :list_literal, items: items}],
         env,
         counter
       ),
       do: direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

  defp direct_emit_qualified(
         "Pebble.Ui.canvasLayer",
         [_id, %{op: :list_literal, items: items}],
         env,
         counter
       ),
       do: direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

  defp direct_emit_qualified(
         "Pebble.Ui.group",
         [%{op: :qualified_call, target: ctx_target, args: ctx_args}],
         env,
         counter
       ) do
    case {normalize_special_target(ctx_target), ctx_args} do
      {"Pebble.Ui.context",
       [%{op: :list_literal, items: settings}, %{op: :list_literal, items: commands}]} ->
        with {:ok, push_code, counter} <-
               direct_append_command(draw_kind(:push_context), [], env, counter),
             {:ok, settings_code, counter} <- direct_emit_settings(settings, env, counter),
             {:ok, command_code, counter} <-
               direct_emit_expr(%{op: :list_literal, items: commands}, env, counter),
             {:ok, pop_code, counter} <-
               direct_append_command(draw_kind(:pop_context), [], env, counter) do
          {:ok, push_code <> settings_code <> command_code <> pop_code, counter}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp direct_emit_qualified("Pebble.Ui.clear", [color], env, counter),
    do: direct_append_command(draw_kind(:clear), [color], env, counter)

  defp direct_emit_qualified("Pebble.Ui.pixel", [pos, color], env, counter),
    do:
      direct_append_command(
        draw_kind(:pixel),
        [field_access_expr(pos, "x"), field_access_expr(pos, "y"), color],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.line", [start_pos, end_pos, color], env, counter),
    do:
      direct_append_command(
        draw_kind(:line),
        [
          field_access_expr(start_pos, "x"),
          field_access_expr(start_pos, "y"),
          field_access_expr(end_pos, "x"),
          field_access_expr(end_pos, "y"),
          color
        ],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.rect", [bounds, color], env, counter),
    do: direct_bounds_command(draw_kind(:rect), bounds, [color], env, counter)

  defp direct_emit_qualified("Pebble.Ui.fillRect", [bounds, color], env, counter),
    do: direct_bounds_command(draw_kind(:fill_rect), bounds, [color], env, counter)

  defp direct_emit_qualified("Pebble.Ui.circle", [center, radius, color], env, counter),
    do:
      direct_append_command(
        draw_kind(:circle),
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.fillCircle", [center, radius, color], env, counter),
    do:
      direct_append_command(
        draw_kind(:fill_circle),
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.textInt", [font, pos, value], env, counter),
    do:
      direct_append_command(
        draw_kind(:text_int_with_font),
        [font, field_access_expr(pos, "x"), field_access_expr(pos, "y"), value],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.textLabel", [font, pos, label], env, counter),
    do:
      direct_append_command(
        draw_kind(:text_label_with_font),
        [font, field_access_expr(pos, "x"), field_access_expr(pos, "y"), label],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.text", [font, bounds, value], env, counter),
    do:
      direct_append_text_command(
        draw_kind(:text),
        [
          font,
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h")
        ],
        value,
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.roundRect", [bounds, radius, color], env, counter),
    do: direct_bounds_command(draw_kind(:round_rect), bounds, [radius, color], env, counter)

  defp direct_emit_qualified("Pebble.Ui.arc", [bounds, start_angle, end_angle], env, counter),
    do: direct_bounds_command(draw_kind(:arc), bounds, [start_angle, end_angle], env, counter)

  defp direct_emit_qualified(
         "Pebble.Ui.fillRadial",
         [bounds, start_angle, end_angle],
         env,
         counter
       ),
       do:
         direct_bounds_command(
           draw_kind(:fill_radial),
           bounds,
           [start_angle, end_angle],
           env,
           counter
         )

  defp direct_emit_qualified("Pebble.Ui.drawBitmapInRect", [bitmap, bounds], env, counter),
    do:
      direct_append_command(
        draw_kind(:bitmap_in_rect),
        [
          bitmap,
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h")
        ],
        env,
        counter
      )

  defp direct_emit_qualified("Pebble.Ui.drawRotatedBitmap", args, env, counter),
    do: direct_append_command(draw_kind(:rotated_bitmap), args, env, counter)

  defp direct_emit_qualified("Pebble.Ui.pathFilled", [path], env, counter),
    do: direct_path_command(draw_kind(:path_filled), path, env, counter)

  defp direct_emit_qualified("Pebble.Ui.pathOutline", [path], env, counter),
    do: direct_path_command(draw_kind(:path_outline), path, env, counter)

  defp direct_emit_qualified("Pebble.Ui.pathOutlineOpen", [path], env, counter),
    do: direct_path_command(draw_kind(:path_outline_open), path, env, counter)

  defp direct_emit_qualified(target, args, env, counter) do
    targets = Map.get(env, :__direct_targets__, MapSet.new())

    with {target_module, target_name} <- direct_qualified_function_target(target, targets),
         true <- MapSet.member?(targets, {target_module, target_name}) do
      direct_emit_command_call({target_module, target_name}, args, env, counter)
    else
      _ -> :error
    end
  end

  defp direct_emit_command_call(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})
    decl = Map.get(decl_map, target_key)

    arg_kinds =
      if decl, do: direct_command_arg_kinds(decl), else: Enum.map(args, fn _ -> :boxed end)

    {arg_code, arg_refs, release_refs, counter} =
      args
      |> Enum.zip(arg_kinds)
      |> Enum.reduce({"", [], [], counter}, fn {arg_expr, kind},
                                               {code_acc, refs_acc, releases_acc, c} ->
        case kind do
          :native_int ->
            {code, ref, c2} = compile_native_int_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

          :native_string ->
            {code, ref, cleanup, c2} = compile_native_string_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ cleanup, c2}

          :boxed ->
            {code, ref, c2} = compile_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ [ref], c2}
        end
      end)

    next = counter + 1
    c_name = module_fn_name(elem(target_key, 0), elem(target_key, 1))
    argc = length(arg_refs)
    arg_list = Enum.join(arg_refs, ", ")
    releases = direct_release_vars(release_refs, "  ")

    if Enum.any?(arg_kinds, &(&1 != :boxed)) do
      {:ok,
       """
       #{arg_code}
         int direct_rc_#{next} = #{c_name}_commands_append_native(#{arg_list}, out_cmds, max_cmds, skip, count, emitted);
       #{releases}
         if (direct_rc_#{next} < 0) return direct_rc_#{next};
       """, next}
    else
      {:ok,
       """
       #{arg_code}
         ElmcValue *direct_call_args_#{next}[#{max(argc, 1)}] = { #{arg_list} };
         int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{argc}, out_cmds, max_cmds, skip, count, emitted);
       #{releases}
         if (direct_rc_#{next} < 0) return direct_rc_#{next};
       """, next}
    end
  end

  defp direct_emit_function_target(%{op: :var, name: name}, module_name),
    do: {module_name, name, []}

  defp direct_emit_function_target(%{op: :call, name: name, args: args}, module_name),
    do: {module_name, name, args}

  defp direct_emit_function_target(
         %{op: :qualified_call, target: target, args: args},
         _module_name
       ) do
    case split_qualified_function_target(normalize_special_target(target)) do
      nil -> nil
      {target_module, target_name} -> {target_module, target_name, args}
    end
  end

  defp direct_emit_function_target(_expr, _module_name), do: nil

  defp direct_compile_arg_values(args, env, counter) do
    Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
      {code, var, c2} = compile_expr(arg_expr, env, c)
      {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
    end)
  end

  defp direct_release_vars([], _indent), do: ""

  defp direct_release_vars(vars, indent) do
    vars
    |> Enum.map_join("\n", fn var -> "#{indent}elmc_release(#{var});" end)
  end

  defp direct_emit_settings(settings, env, counter) do
    Enum.reduce_while(settings, {:ok, "", counter}, fn setting, {:ok, acc, c} ->
      case direct_setting_command(setting, env, c) do
        {:ok, code, c2} -> {:cont, {:ok, acc <> code, c2}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp direct_emit_lambda_map(arg, body, list_expr, env, counter) do
    next = counter + 1

    case direct_range_bounds(list_expr, env, counter) do
      {:ok, range_code, first_ref, last_ref, counter} ->
        item_ref = "direct_item_i_#{next}"

        body_env =
          env
          |> Map.delete(arg)
          |> put_native_int_binding(arg, item_ref)
          |> put_boxed_int_binding(arg, false)

        with {:ok, body_code, counter} <- direct_emit_expr(body, body_env, counter) do
          {:ok,
           """
           #{range_code}
            elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
            for (elmc_int_t direct_item_i_#{next} = #{first_ref}; ; direct_item_i_#{next} += direct_step_#{next}) {
           #{indent(body_code, 4)}
               if (*count >= max_cmds) return 0;
               if (direct_item_i_#{next} == #{last_ref}) break;
             }
           """, counter}
        else
          _ -> :error
        end

      :error ->
        {list_code, list_var, counter} = compile_expr(list_expr, env, counter)
        item_var = "direct_node_#{next}->head"
        body_env = Map.put(env, arg, item_var)

        with {:ok, body_code, counter} <- direct_emit_expr(body, body_env, counter) do
          {:ok,
           """
           #{list_code}
             ElmcValue *direct_cursor_#{next} = #{list_var};
             while (direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
               ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
           #{indent(body_code, 4)}
               if (*count >= max_cmds) {
                 elmc_release(#{list_var});
                 return 0;
               }
               direct_cursor_#{next} = direct_node_#{next}->tail;
             }
             elmc_release(#{list_var});
           """, counter}
        else
          _ -> :error
        end
    end
  end

  defp direct_setting_command(%{op: :qualified_call, target: target, args: [value]}, env, counter) do
    kind =
      case normalize_special_target(target) do
        "Pebble.Ui.strokeWidth" -> draw_kind(:stroke_width)
        "Pebble.Ui.antialiased" -> draw_kind(:antialiased)
        "Pebble.Ui.strokeColor" -> draw_kind(:stroke_color)
        "Pebble.Ui.fillColor" -> draw_kind(:fill_color)
        "Pebble.Ui.textColor" -> draw_kind(:text_color)
        "Pebble.Ui.compositingMode" -> draw_kind(:compositing_mode)
        _ -> nil
      end

    if kind, do: direct_append_command(kind, [value], env, counter), else: :error
  end

  defp direct_setting_command(_, _, _), do: :error

  defp direct_bounds_command(kind, bounds, extra_args, env, counter) do
    {bounds_code, bounds_values, counter} = direct_bounds_values(bounds, env, counter)

    {extra_code, extra_values, counter} =
      Enum.reduce(extra_args, {"", [], counter}, fn arg, {acc, vars, c} ->
        {arg_code, value_ref, c2} = direct_int_value(arg, env, c)
        {acc <> arg_code, vars ++ [value_ref], c2}
      end)

    direct_command_code(kind, bounds_code <> extra_code, bounds_values ++ extra_values, counter)
  end

  defp direct_append_command(kind, args, env, counter) do
    {code, values, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg, {acc, vars, c} ->
        {arg_code, value_ref, c2} = direct_int_value(arg, env, c)
        {acc <> arg_code, vars ++ [value_ref], c2}
      end)

    direct_command_code(kind, code, values, counter)
  end

  defp direct_command_code(kind, code, values, counter) do
    next = counter + 1

    assignments =
      values
      |> Enum.with_index()
      |> Enum.map_join("\n  ", fn {value, index} -> "out_cmds[*count].p#{index} = #{value};" end)

    {:ok,
     """
      if (*emitted >= skip && *count < max_cmds) {
     #{indent(code, 4)}
        elmc_generated_draw_init(&out_cmds[*count], #{draw_kind_c_name(kind)});
         #{assignments}
         *count += 1;
       }
      *emitted += 1;
      if (*count >= max_cmds) return 0;
     """, next}
  end

  defp direct_bounds_values(%{op: :call, name: name, args: args} = bounds, env, counter) do
    module_name = Map.get(env, :__module__, "Main")

    case direct_inline_bounds_values({module_name, name}, args, env, counter) do
      :error -> direct_runtime_bounds_values(bounds, env, counter)
      result -> result
    end
  end

  defp direct_bounds_values(
         %{op: :qualified_call, target: target, args: args} = bounds,
         env,
         counter
       ) do
    case split_qualified_function_target(normalize_special_target(target)) do
      nil ->
        direct_runtime_bounds_values(bounds, env, counter)

      target_key ->
        case direct_inline_bounds_values(target_key, args, env, counter) do
          :error -> direct_runtime_bounds_values(bounds, env, counter)
          result -> result
        end
    end
  end

  defp direct_bounds_values(bounds, env, counter) do
    direct_runtime_bounds_values(bounds, env, counter)
  end

  defp direct_inline_bounds_values(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with %{args: arg_names, expr: expr} when is_list(arg_names) <- Map.get(decl_map, target_key),
         true <- length(arg_names) == length(args),
         substituted <- substitute_expr(expr, Map.new(Enum.zip(arg_names, args))),
         %{op: :record_literal} <- substituted,
         true <- bounds_record_literal?(substituted) do
      direct_runtime_bounds_values(substituted, env, counter)
    else
      _ -> :error
    end
  end

  defp bounds_record_literal?(%{op: :record_literal} = expr) do
    Enum.all?(["x", "y", "w", "h"], &record_field_expr(expr, &1))
  end

  defp direct_runtime_bounds_values(bounds, env, counter) do
    fields = ["x", "y", "w", "h"]

    inlined =
      Enum.map(fields, &record_field_expr(bounds, &1))

    if Enum.all?(inlined) do
      Enum.reduce(inlined, {"", [], counter}, fn field_expr, {acc, vars, c} ->
        {field_code, field_ref, c2} = direct_int_value(field_expr, env, c)
        {acc <> field_code, vars ++ [field_ref], c2}
      end)
    else
      case bounds do
        %{op: :var} ->
          Enum.reduce(fields, {"", [], counter}, fn field, {acc, vars, c} ->
            {field_code, field_ref, c2} =
              direct_int_value(%{op: :field_access, arg: bounds, field: field}, env, c)

            {acc <> field_code, vars ++ [field_ref], c2}
          end)

        _ ->
          {bounds_code, bounds_var, counter} = compile_expr(bounds, env, counter)
          next = counter + 1
          shape = record_shape(bounds, env)

          field_refs =
            Enum.map(fields, fn field ->
              "direct_bounds_#{field}_#{next}"
            end)

          field_code =
            fields
            |> Enum.zip(field_refs)
            |> Enum.map_join("\n", fn {field, ref} ->
              "  const elmc_int_t #{ref} = #{record_get_int_expr(bounds_var, field, shape)};"
            end)

          code = """
          #{bounds_code}
          #{field_code}
            elmc_release(#{bounds_var});
          """

          {code, field_refs, next}
      end
    end
  end

  defp direct_append_text_command(kind, args, text_expr, env, counter) do
    {code, values, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg, {acc, vars, c} ->
        {arg_code, value_ref, c2} = direct_int_value(arg, env, c)
        {acc <> arg_code, vars ++ [value_ref], c2}
      end)

    {text_code, text_copy_code, text_release_code, counter} =
      direct_text_copy_code(text_expr, env, counter)

    assignments =
      values
      |> Enum.with_index()
      |> Enum.map_join("\n  ", fn {value, index} -> "out_cmds[*count].p#{index} = #{value};" end)

    {:ok,
     """
      if (*emitted >= skip && *count < max_cmds) {
     #{indent(code, 2)}
     #{indent(text_code, 2)}
        elmc_generated_draw_init(&out_cmds[*count], #{draw_kind_c_name(kind)});
         #{assignments}
     #{indent(text_copy_code, 4)}
         *count += 1;
     #{indent(text_release_code, 4)}
       }
       *emitted += 1;
       if (*count >= max_cmds) return 0;
     """, counter}
  end

  defp direct_text_copy_code(%{op: :string_literal, value: value}, _env, counter) do
    escaped = escape_c_string(value)

    {"", direct_text_copy_from("\"#{escaped}\""), "", counter}
  end

  defp direct_text_copy_code(%{op: :var, name: name}, env, counter) do
    expr = %{op: :var, name: name}

    case native_string_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", direct_text_copy_from(native_ref), "", counter}

      nil ->
        if typed_string_expr?(expr, env) do
          {text_code, text_ref, cleanup, counter} = compile_native_string_expr(expr, env, counter)
          cleanup_code = Enum.map_join(cleanup, "\n", fn var -> "elmc_release(#{var});" end)
          {text_code, direct_text_copy_from(text_ref), cleanup_code, counter}
        else
          direct_text_copy_boxed_code(expr, env, counter)
        end
    end
  end

  defp direct_text_copy_code(text_expr, env, counter) do
    if native_string_expr?(text_expr, env) do
      {text_code, text_ref, cleanup, counter} =
        compile_native_string_expr(text_expr, env, counter)

      cleanup_code = Enum.map_join(cleanup, "\n", fn var -> "elmc_release(#{var});" end)
      {text_code, direct_text_copy_from(text_ref), cleanup_code, counter}
    else
      direct_text_copy_boxed_code(text_expr, env, counter)
    end
  end

  defp direct_text_copy_boxed_code(text_expr, env, counter) do
    {text_code, text_var, counter} = compile_expr(text_expr, env, counter)

    copy_code = """
    if (#{text_var} && #{text_var}->tag == ELMC_TAG_STRING && #{text_var}->payload) {
      const char *direct_text = (const char *)#{text_var}->payload;
    #{indent(direct_text_copy_body(), 2)}
    }
    """

    {text_code, copy_code, "elmc_release(#{text_var});", counter}
  end

  defp direct_text_copy_from(source) do
    """
    {
      const char *direct_text = #{source};
    #{indent(direct_text_copy_body(), 2)}
    }
    """
  end

  defp direct_text_copy_body do
    """
    int direct_text_i = 0;
    while (direct_text[direct_text_i] && direct_text_i < 63) {
      out_cmds[*count].text[direct_text_i] = direct_text[direct_text_i];
      direct_text_i++;
    }
    out_cmds[*count].text[direct_text_i] = '\\0';
    """
  end

  defp direct_path_command(kind, %{op: :qualified_call, target: target, args: args}, env, counter) do
    with "Pebble.Ui.path" <- normalize_special_target(target),
         [%{op: :list_literal, items: points}, offset, rotation] <- args,
         true <- length(points) <= 16 do
      {code, point_assignments, counter} =
        points
        |> Enum.with_index()
        |> Enum.reduce({"", [], counter}, fn {point, index}, {acc, assignments, c} ->
          {x_code, x_ref, c} = direct_int_value(record_field_expr(point, "x"), env, c)
          {y_code, y_ref, c} = direct_int_value(record_field_expr(point, "y"), env, c)

          assignment = """
              out_cmds[*count].path_x[#{index}] = #{x_ref};
              out_cmds[*count].path_y[#{index}] = #{y_ref};
          """

          {acc <> x_code <> y_code, assignments ++ [assignment], c}
        end)

      {offset_x_code, offset_x, counter} =
        direct_int_value(record_field_expr(offset, "x"), env, counter)

      {offset_y_code, offset_y, counter} =
        direct_int_value(record_field_expr(offset, "y"), env, counter)

      {rotation_code, rotation_ref, counter} = direct_int_value(rotation, env, counter)

      {:ok,
       """
         if (*emitted >= skip && *count < max_cmds) {
       #{indent(code, 4)}
       #{indent(offset_x_code, 4)}
       #{indent(offset_y_code, 4)}
       #{indent(rotation_code, 4)}
          elmc_generated_draw_init(&out_cmds[*count], #{draw_kind_c_name(kind)});
           out_cmds[*count].path_point_count = #{length(points)};
           out_cmds[*count].path_offset_x = #{offset_x};
           out_cmds[*count].path_offset_y = #{offset_y};
           out_cmds[*count].path_rotation = #{rotation_ref};
       #{Enum.join(point_assignments, "\n")}
           *count += 1;
         }
         *emitted += 1;
         if (*count >= max_cmds) return 0;
       """, counter}
    else
      _ -> :error
    end
  end

  defp direct_path_command(_, _, _, _), do: :error

  defp direct_range_bounds(
         %{op: :qualified_call, target: target, args: [first, last]},
         env,
         counter
       )
       when target in ["List.range", "Elm.Kernel.List.range"] do
    {first_code, first_ref, counter} = direct_int_value(first, env, counter)
    {last_code, last_ref, counter} = direct_int_value(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp direct_range_bounds(%{op: :call, name: "range", args: [first, last]}, env, counter) do
    {first_code, first_ref, counter} = direct_int_value(first, env, counter)
    {last_code, last_ref, counter} = direct_int_value(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp direct_range_bounds(_expr, _env, _counter), do: :error

  defp direct_int_value(nil, _env, counter), do: {"", "0", counter}

  defp direct_int_value(%{op: :int_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  defp direct_int_value(%{op: :char_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  defp direct_int_value(%{op: :var, name: name} = expr, env, counter) do
    case Map.fetch(env, name) do
      {:ok, {:direct_fragment, fragment}} ->
        direct_int_value(fragment, env, counter)

      {:ok, source} when is_binary(source) ->
        {"", "elmc_as_int(#{source})", counter}

      _ ->
        direct_runtime_int_value(expr, env, counter)
    end
  end

  defp direct_int_value(%{op: :call, name: name, args: args} = expr, env, counter) do
    case direct_int_builtin(name, args, env, counter) do
      {:ok, code, value, counter} -> {code, value, counter}
      :error -> direct_runtime_int_value(expr, env, counter)
    end
  end

  defp direct_int_value(%{op: :qualified_call, target: target, args: args}, env, counter) do
    case special_value_from_target(target, args) do
      %{op: :int_literal, value: value} ->
        {"", "#{value}", counter}

      %{op: :field_access} = field ->
        direct_int_value(field, env, counter)

      nil ->
        with builtin when not is_nil(builtin) <- qualified_builtin_operator_name(target),
             {:ok, code, value, counter} <- direct_int_builtin(builtin, args, env, counter) do
          {code, value, counter}
        else
          _ ->
            direct_runtime_int_value(
              %{op: :qualified_call, target: target, args: args},
              env,
              counter
            )
        end

      expr ->
        direct_int_value(expr, env, counter)
    end
  end

  defp direct_int_value(%{op: :field_access, arg: arg, field: field}, env, counter) do
    source =
      case arg do
        %{op: :var, name: name} ->
          case Map.get(env, name) do
            {:direct_fragment, fragment} -> fragment
            _ -> arg
          end

        _ ->
          arg
      end

    cond do
      field_expr = record_field_expr(source, field) ->
        direct_int_value(field_expr, env, counter)

      field_expr = inline_record_field_expr(source, field, env) ->
        direct_int_value(field_expr, env, counter)

      true ->
        direct_runtime_int_value(%{op: :field_access, arg: arg, field: field}, env, counter)
    end
  end

  defp direct_int_value(expr, env, counter), do: direct_runtime_int_value(expr, env, counter)

  defp direct_int_builtin(name, [left, right], env, counter)
       when name in ["__add__", "__sub__", "__mul__"] do
    op = %{"__add__" => "+", "__sub__" => "-", "__mul__" => "*"}[name]
    {left_code, left_value, counter} = direct_int_value(left, env, counter)
    {right_code, right_value, counter} = direct_int_value(right, env, counter)
    {:ok, left_code <> right_code, "(#{left_value} #{op} #{right_value})", counter}
  end

  defp direct_int_builtin("__idiv__", [left, right], env, counter) do
    {left_code, left_value, counter} = direct_int_value(left, env, counter)
    {right_code, right_value, counter} = direct_int_value(right, env, counter)
    next = counter + 1
    denom = "direct_den_#{next}"

    code = """
    #{left_code}#{right_code}
      elmc_int_t #{denom} = #{right_value};
    """

    {:ok, code, "(#{denom} == 0 ? 0 : (#{left_value} / #{denom}))", next}
  end

  defp direct_int_builtin("modBy", [base, value], env, counter) do
    {base_code, base_value, counter} = direct_int_value(base, env, counter)
    {value_code, value_value, counter} = direct_int_value(value, env, counter)
    next = counter + 1
    base_var = "direct_mod_base_#{next}"

    code = """
    #{base_code}#{value_code}
      elmc_int_t #{base_var} = #{base_value};
    """

    {:ok, code, "(#{base_var} == 0 ? 0 : (#{value_value} % #{base_var}))", next}
  end

  defp direct_int_builtin("max", [left, right], env, counter) do
    direct_int_min_max(left, right, ">=", env, counter)
  end

  defp direct_int_builtin("min", [left, right], env, counter) do
    direct_int_min_max(left, right, "<=", env, counter)
  end

  defp direct_int_builtin("clamp", [low, high, value], env, counter) do
    {low_code, low_value, counter} = direct_int_value(low, env, counter)
    {high_code, high_value, counter} = direct_int_value(high, env, counter)
    {value_code, value_value, counter} = direct_int_value(value, env, counter)
    next = counter + 1
    low_var = "direct_low_#{next}"
    high_var = "direct_high_#{next}"
    value_var = "direct_value_#{next}"

    code = """
    #{low_code}#{high_code}#{value_code}
      int64_t #{low_var} = #{low_value};
      int64_t #{high_var} = #{high_value};
      int64_t #{value_var} = #{value_value};
    """

    {:ok, code,
     "(#{value_var} < #{low_var} ? #{low_var} : (#{value_var} > #{high_var} ? #{high_var} : #{value_var}))",
     next}
  end

  defp direct_int_builtin(_name, _args, _env, _counter), do: :error

  defp direct_int_min_max(left, right, op, env, counter) do
    {left_code, left_value, counter} = direct_int_value(left, env, counter)
    {right_code, right_value, counter} = direct_int_value(right, env, counter)
    next = counter + 1
    left_var = "direct_left_#{next}"
    right_var = "direct_right_#{next}"

    code = """
    #{left_code}#{right_code}
      int64_t #{left_var} = #{left_value};
      int64_t #{right_var} = #{right_value};
    """

    {:ok, code, "(#{left_var} #{op} #{right_var} ? #{left_var} : #{right_var})", next}
  end

  defp direct_runtime_int_value(expr, env, counter) do
    if native_int_expr?(expr, env) do
      compile_native_int_expr(expr, env, counter)
    else
      {expr_code, expr_var, counter} = compile_expr(expr, env, counter)
      next = counter + 1
      int_var = "direct_i_#{next}"

      {
        """
        #{expr_code}
          int64_t #{int_var} = elmc_as_int(#{expr_var});
          elmc_release(#{expr_var});
        """,
        int_var,
        next
      }
    end
  end

  defp compile_native_string_expr(%{op: :string_literal, value: value}, _env, counter) do
    {"", "\"#{escape_c_string(value)}\"", [], counter}
  end

  defp compile_native_string_expr(%{op: :var, name: name} = expr, env, counter) do
    case native_string_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, [], counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            next = counter + 1
            out = "native_string_#{next}"

            {
              native_string_value_code(expr, env, source, out),
              out,
              [],
              next
            }

          _ ->
            compile_native_string_fallback(expr, env, counter)
        end
    end
  end

  defp compile_native_string_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr} = expr,
         env,
         counter
       ) do
    if native_string_expr?(then_expr, env) and native_string_expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)

      {then_code, then_ref, _then_cleanup, counter} =
        compile_native_string_expr(then_expr, env, counter)

      {else_code, else_ref, _else_cleanup, counter} =
        compile_native_string_expr(else_expr, env, counter)

      next = counter + 1
      out = "native_string_if_#{next}"

      code = """
      #{cond_code}#{then_code}#{else_code}
        const char *#{out} = #{cond_ref} ? #{then_ref} : #{else_ref};
      """

      {code, out, [], next}
    else
      compile_native_string_fallback(expr, env, counter)
    end
  end

  defp compile_native_string_expr(
         %{op: :qualified_call, target: target, args: args} = expr,
         env,
         counter
       ) do
    case special_value_from_target(normalize_special_target(target), args || []) do
      nil -> compile_native_string_fallback(expr, env, counter)
      rewritten -> compile_native_string_expr(rewritten, env, counter)
    end
  end

  defp compile_native_string_expr(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr,
         env,
         counter
       ) do
    if native_int_expr?(value, env) do
      {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
      next = counter + 1
      buffer = "native_string_buf_#{next}"
      out = "native_string_#{next}"

      code = """
      #{value_code}
        char #{buffer}[32];
        snprintf(#{buffer}, sizeof(#{buffer}), "%lld", (long long)#{value_ref});
        const char *#{out} = #{buffer};
      """

      {code, out, [], next}
    else
      compile_native_string_fallback(expr, env, counter)
    end
  end

  defp compile_native_string_expr(expr, env, counter),
    do: compile_native_string_fallback(expr, env, counter)

  defp compile_native_string_fallback(expr, env, counter) do
    {code, var, counter} = compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_string_#{next}"
    value_code = native_string_value_code(expr, env, var, out)

    {
      """
      #{code}
      #{value_code}
      """,
      out,
      [var],
      next
    }
  end

  defp native_string_value_code(expr, env, var, out) do
    if typed_string_expr?(expr, env) or boxed_string_expr?(expr, env) do
      "  const char *#{out} = (const char *)#{var}->payload;"
    else
      """
        const char *#{out} =
          (#{var} && #{var}->tag == ELMC_TAG_STRING && #{var}->payload)
            ? (const char *)#{var}->payload
            : "";
      """
    end
  end

  defp native_string_expr?(%{op: :string_literal}, _env), do: true

  defp native_string_expr?(%{op: :var, name: name} = expr, env)
       when is_binary(name) or is_atom(name),
       do:
         is_binary(native_string_binding(env, name)) or boxed_string_binding?(env, name) or
           typed_string_expr?(expr, env)

  defp native_string_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: native_string_expr?(then_expr, env) and native_string_expr?(else_expr, env)

  defp native_string_expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case special_value_from_target(normalize_special_target(target), args || []) do
      nil -> typed_string_expr?(%{op: :qualified_call, target: target, args: args}, env)
      rewritten -> native_string_expr?(rewritten, env)
    end
  end

  defp native_string_expr?(%{op: :call} = expr, env), do: typed_string_expr?(expr, env)

  defp native_string_expr?(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         env
       ),
       do: native_int_expr?(value, env)

  defp native_string_expr?(
         %{op: :runtime_call, function: "elmc_append", args: [left, right]},
         env
       ),
       do: native_string_expr?(left, env) and native_string_expr?(right, env)

  defp native_string_expr?(_expr, _env), do: false

  defp boxed_string_expr?(%{op: :string_literal}, _env), do: true

  defp boxed_string_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: boxed_string_expr?(then_expr, env) and boxed_string_expr?(else_expr, env)

  defp boxed_string_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: boxed_string_binding?(env, name) or typed_string_expr?(%{op: :var, name: name}, env)

  defp boxed_string_expr?(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         env
       ),
       do: native_int_expr?(value, env)

  defp boxed_string_expr?(
         %{op: :runtime_call, function: "elmc_append", args: [left, right]},
         env
       ),
       do: native_string_expr?(left, env) and native_string_expr?(right, env)

  defp boxed_string_expr?(expr, env), do: typed_string_expr?(expr, env)

  defp boxed_non_null_expr?(%{op: :int_literal}, _env), do: true
  defp boxed_non_null_expr?(%{op: :string_literal}, _env), do: true
  defp boxed_non_null_expr?(%{op: :char_literal}, _env), do: true
  defp boxed_non_null_expr?(%{op: :float_literal}, _env), do: true
  defp boxed_non_null_expr?(%{op: :compare}, _env), do: true

  defp boxed_non_null_expr?(%{op: :call, name: name, args: [_left, _right]}, _env)
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"],
       do: true

  defp boxed_non_null_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: boxed_non_null_expr?(then_expr, env) and boxed_non_null_expr?(else_expr, env)

  defp boxed_non_null_expr?(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    case special_value_from_target(normalize_special_target(target), args || []) do
      nil ->
        qualified_builtin_operator_name(normalize_special_target(target)) in [
          "__eq__",
          "__neq__",
          "__lt__",
          "__lte__",
          "__gt__",
          "__gte__"
        ] and length(args || []) == 2

      rewritten ->
        boxed_non_null_expr?(rewritten, env)
    end
  end

  defp boxed_non_null_expr?(%{op: :constructor_call, target: target, args: args}, env)
       when is_binary(target) do
    case special_value_from_target(normalize_special_target(target), args || []) do
      nil -> false
      rewritten -> boxed_non_null_expr?(rewritten, env)
    end
  end

  defp boxed_non_null_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: boxed_int_binding?(env, name) or boxed_string_binding?(env, name)

  defp boxed_non_null_expr?(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         env
       ),
       do: native_int_expr?(value, env)

  defp boxed_non_null_expr?(
         %{op: :runtime_call, function: "elmc_append", args: [left, right]},
         env
       ),
       do: native_string_expr?(left, env) and native_string_expr?(right, env)

  defp boxed_non_null_expr?(_expr, _env), do: false

  defp typed_string_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    typed_function_return?({module_name, name}, env, length(args || []), "String")
  end

  defp typed_string_expr?(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    target
    |> normalize_special_target()
    |> split_qualified_function_target()
    |> typed_function_return?(env, length(args || []), "String")
  end

  defp typed_string_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    module_name = Map.get(env, :__module__, "Main")
    typed_function_return?({module_name, to_string(name)}, env, 0, "String")
  end

  defp typed_string_expr?(_expr, _env), do: false

  defp typed_bool_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    typed_function_return?({module_name, name}, env, length(args || []), "Bool")
  end

  defp typed_bool_expr?(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    target
    |> normalize_special_target()
    |> split_qualified_function_target()
    |> typed_function_return?(env, length(args || []), "Bool")
  end

  defp typed_bool_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    module_name = Map.get(env, :__module__, "Main")
    typed_function_return?({module_name, to_string(name)}, env, 0, "Bool")
  end

  defp typed_bool_expr?(_expr, _env), do: false

  defp typed_function_return?(nil, _env, _arg_count, _return_type), do: false

  defp typed_function_return?(target, env, arg_count, return_type) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target) do
      %{type: type} ->
        length(function_arg_types(type)) == arg_count and
          function_return_type(type) == return_type

      _ ->
        false
    end
  end

  defp record_field_expr(%{op: :record_literal, fields: fields}, field) do
    fields
    |> Enum.find(&(&1.name == field))
    |> case do
      nil -> nil
      %{expr: expr} -> expr
    end
  end

  defp record_field_expr(%{op: :record_update, base: base, fields: fields}, field) do
    fields
    |> Enum.find(&(&1.name == field))
    |> case do
      nil -> %{op: :field_access, arg: base, field: field}
      %{expr: expr} -> expr
    end
  end

  defp record_field_expr(%{op: :var}, _field), do: nil

  defp record_field_expr(%{op: :field_access}, _field), do: nil

  defp record_field_expr(_expr, _field), do: nil

  defp direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
  end

  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)
  defp draw_kind_c_name(kind), do: Elmc.Backend.Pebble.draw_kind_c_name!(kind)
  defp command_kind(kind), do: Elmc.Backend.Pebble.command_kind_id!(kind)
  defp ui_node_kind(kind), do: Elmc.Backend.Pebble.ui_node_kind_id!(kind)

  @spec special_value_from_target(String.t(), [map()]) :: map() | nil
  defp special_value_from_target("Pebble.Ui.clear", args),
    do: encoded_cmd_expr(draw_kind(:clear), args, 1)

  defp special_value_from_target("Pebble.Ui.pixel", [pos, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:pixel),
        [field_access_expr(pos, "x"), field_access_expr(pos, "y"), color],
        3
      )

  defp special_value_from_target("Pebble.Ui.pixel", args),
    do: encoded_cmd_expr(draw_kind(:pixel), args, 3)

  defp special_value_from_target("Pebble.Ui.line", [start_pos, end_pos, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:line),
        [
          field_access_expr(start_pos, "x"),
          field_access_expr(start_pos, "y"),
          field_access_expr(end_pos, "x"),
          field_access_expr(end_pos, "y"),
          color
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.line", args),
    do: encoded_cmd_expr(draw_kind(:line), args, 5)

  defp special_value_from_target("Pebble.Ui.rect", [bounds, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:rect),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.rect", args),
    do: encoded_cmd_expr(draw_kind(:rect), args, 5)

  defp special_value_from_target("Pebble.Ui.fillRect", [bounds, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:fill_rect),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.fillRect", args),
    do: encoded_cmd_expr(draw_kind(:fill_rect), args, 5)

  defp special_value_from_target("Pebble.Ui.circle", [center, radius, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:circle),
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        4
      )

  defp special_value_from_target("Pebble.Ui.circle", args),
    do: encoded_cmd_expr(draw_kind(:circle), args, 4)

  defp special_value_from_target("Pebble.Ui.fillCircle", [center, radius, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:fill_circle),
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        4
      )

  defp special_value_from_target("Pebble.Ui.fillCircle", args),
    do: encoded_cmd_expr(draw_kind(:fill_circle), args, 4)

  defp special_value_from_target("Pebble.Ui.textInt", [font_id, pos, value]),
    do:
      encoded_cmd_expr(
        draw_kind(:text_int_with_font),
        [font_id, field_access_expr(pos, "x"), field_access_expr(pos, "y"), value],
        4
      )

  defp special_value_from_target("Pebble.Ui.textLabel", [font_id, pos, label]),
    do:
      encoded_cmd_expr(
        draw_kind(:text_label_with_font),
        [font_id, field_access_expr(pos, "x"), field_access_expr(pos, "y"), label],
        4
      )

  defp special_value_from_target("Pebble.Ui.text", [font_id, bounds, value]),
    do:
      encoded_text_cmd_expr(
        draw_kind(:text),
        [
          font_id,
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          value
        ]
      )

  defp special_value_from_target("Pebble.Ui.Color.indexed", [value]), do: value

  defp special_value_from_target("Pebble.Ui.Color.toInt", [value]), do: value

  defp special_value_from_target("Pebble.Ui.rotationFromPebbleAngle", [angle]), do: angle

  defp special_value_from_target("Pebble.Ui.rotationFromDegrees", [
         %{op: :int_literal, value: degrees}
       ]),
       do: %{op: :int_literal, value: round(degrees * 65_536 / 360)}

  defp special_value_from_target("Pebble.Ui.rotationFromDegrees", [
         %{op: :float_literal, value: degrees}
       ]),
       do: %{op: :int_literal, value: round(degrees * 65_536 / 360)}

  defp special_value_from_target("Pebble.Ui.Color." <> name, []) do
    case Map.fetch(@pebble_color_constants, name) do
      {:ok, value} -> %{op: :int_literal, value: value}
      :error -> nil
    end
  end

  defp special_value_from_target("Pebble.Time.Monday", []), do: %{op: :int_literal, value: 0}
  defp special_value_from_target("Pebble.Time.Tuesday", []), do: %{op: :int_literal, value: 1}
  defp special_value_from_target("Pebble.Time.Wednesday", []), do: %{op: :int_literal, value: 2}
  defp special_value_from_target("Pebble.Time.Thursday", []), do: %{op: :int_literal, value: 3}
  defp special_value_from_target("Pebble.Time.Friday", []), do: %{op: :int_literal, value: 4}
  defp special_value_from_target("Pebble.Time.Saturday", []), do: %{op: :int_literal, value: 5}
  defp special_value_from_target("Pebble.Time.Sunday", []), do: %{op: :int_literal, value: 6}

  defp special_value_from_target("PushContext", args),
    do: encoded_cmd_expr(draw_kind(:push_context), args, 0)

  defp special_value_from_target("PopContext", args),
    do: encoded_cmd_expr(draw_kind(:pop_context), args, 0)

  defp special_value_from_target("Pebble.Ui.strokeWidth", [value]),
    do: tagged_value_expr(1, value)

  defp special_value_from_target("Pebble.Ui.antialiased", [value]),
    do: tagged_value_expr(2, value)

  defp special_value_from_target("Pebble.Ui.strokeColor", [value]),
    do: tagged_value_expr(3, value)

  defp special_value_from_target("Pebble.Ui.fillColor", [value]), do: tagged_value_expr(4, value)
  defp special_value_from_target("Pebble.Ui.textColor", [value]), do: tagged_value_expr(5, value)

  defp special_value_from_target("Pebble.Ui.compositingMode", [value]),
    do: tagged_value_expr(6, value)

  defp special_value_from_target("Pebble.Ui.context", [settings, commands]),
    do: %{op: :tuple2, left: settings, right: commands}

  defp special_value_from_target("Pebble.Ui.group", [context]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: draw_kind(:context_group)},
      right: context
    }

  defp special_value_from_target("Pebble.Ui.path", [points, offset_x, offset_y, rotation]),
    do: path_expr(points, offset_x, offset_y, rotation)

  defp special_value_from_target("Pebble.Ui.pathFilled", [path]),
    do: %{op: :tuple2, left: %{op: :int_literal, value: draw_kind(:path_filled)}, right: path}

  defp special_value_from_target("Pebble.Ui.pathOutline", [path]),
    do: %{op: :tuple2, left: %{op: :int_literal, value: draw_kind(:path_outline)}, right: path}

  defp special_value_from_target("Pebble.Ui.pathOutlineOpen", [path]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: draw_kind(:path_outline_open)},
      right: path
    }

  defp special_value_from_target("Pebble.Ui.roundRect", [bounds, radius, color]),
    do:
      encoded_cmd_expr(
        draw_kind(:round_rect),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          radius,
          color
        ],
        6
      )

  defp special_value_from_target("Pebble.Ui.roundRect", args),
    do: encoded_cmd_expr(draw_kind(:round_rect), args, 6)

  defp special_value_from_target("Pebble.Ui.arc", [bounds, start_angle, end_angle]),
    do:
      encoded_cmd_expr(
        draw_kind(:arc),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          start_angle,
          end_angle
        ],
        6
      )

  defp special_value_from_target("Pebble.Ui.arc", args),
    do: encoded_cmd_expr(draw_kind(:arc), args, 6)

  defp special_value_from_target("Pebble.Ui.fillRadial", [bounds, start_angle, end_angle]),
    do:
      encoded_cmd_expr(
        draw_kind(:fill_radial),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          start_angle,
          end_angle
        ],
        6
      )

  defp special_value_from_target("Pebble.Ui.fillRadial", args),
    do: encoded_cmd_expr(draw_kind(:fill_radial), args, 6)

  defp special_value_from_target("Pebble.Ui.drawBitmapInRect", [bitmap, bounds]),
    do:
      encoded_cmd_expr(
        draw_kind(:bitmap_in_rect),
        [
          bitmap,
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h")
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.drawBitmapInRect", args),
    do: encoded_cmd_expr(draw_kind(:bitmap_in_rect), args, 5)

  defp special_value_from_target("Pebble.Ui.drawRotatedBitmap", args),
    do: encoded_cmd_expr(draw_kind(:rotated_bitmap), args, 6)

  defp special_value_from_target("Pebble.Ui.windowStack", [windows]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: ui_node_kind(:window_stack)},
      right: windows
    }

  defp special_value_from_target("Pebble.Ui.window", [window_id, layers]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: ui_node_kind(:window_node)},
      right: %{op: :tuple2, left: window_id, right: layers}
    }

  defp special_value_from_target("Pebble.Ui.canvasLayer", [layer_id, ops]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: ui_node_kind(:canvas_layer)},
      right: %{op: :tuple2, left: layer_id, right: ops}
    }

  defp special_value_from_target("List.cons", [head, tail]),
    do: %{op: :runtime_call, function: "elmc_list_cons", args: [head, tail]}

  defp special_value_from_target("Pebble.Cmd.none", _args),
    do: %{op: :int_literal, value: command_kind(:none)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.none", _args),
    do: %{op: :int_literal, value: command_kind(:none)}

  defp special_value_from_target("Pebble.Cmd.timerAfter", args),
    do: encoded_cmd_expr(command_kind(:timer_after_ms), args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.timerAfter", args),
    do: encoded_cmd_expr(command_kind(:timer_after_ms), args, 1)

  defp special_value_from_target("Pebble.Cmd.storageWriteInt", args),
    do: encoded_cmd_expr(command_kind(:storage_write_int), args, 2)

  defp special_value_from_target("Pebble.Storage.writeInt", args),
    do: encoded_cmd_expr(command_kind(:storage_write_int), args, 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteInt", args),
    do: encoded_cmd_expr(command_kind(:storage_write_int), args, 2)

  defp special_value_from_target("Pebble.Cmd.storageReadInt", [key, to_msg]),
    do: encoded_cmd_expr(command_kind(:storage_read_int), [key, constructor_tag_expr(to_msg)], 2)

  defp special_value_from_target("Pebble.Storage.readInt", [key, to_msg]),
    do: encoded_cmd_expr(command_kind(:storage_read_int), [key, constructor_tag_expr(to_msg)], 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageReadInt", [key, to_msg]),
    do: encoded_cmd_expr(command_kind(:storage_read_int), [key, constructor_tag_expr(to_msg)], 2)

  defp special_value_from_target("Pebble.Cmd.storageDelete", args),
    do: encoded_cmd_expr(command_kind(:storage_delete), args, 1)

  defp special_value_from_target("Pebble.Storage.delete", args),
    do: encoded_cmd_expr(command_kind(:storage_delete), args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageDelete", args),
    do: encoded_cmd_expr(command_kind(:storage_delete), args, 1)

  defp special_value_from_target("Pebble.Storage.writeString", args),
    do: encoded_cmd_expr(command_kind(:storage_write_string), args, 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteString", args),
    do: encoded_cmd_expr(command_kind(:storage_write_string), args, 2)

  defp special_value_from_target("Pebble.Storage.readString", [key, to_msg]),
    do:
      encoded_cmd_expr(command_kind(:storage_read_string), [key, constructor_tag_expr(to_msg)], 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageReadString", [key, to_msg]),
    do:
      encoded_cmd_expr(command_kind(:storage_read_string), [key, constructor_tag_expr(to_msg)], 2)

  defp special_value_from_target("Random.generate", [to_msg, _generator]),
    do: encoded_cmd_expr(command_kind(:random_generate), [constructor_tag_expr(to_msg)], 1)

  defp special_value_from_target("Elm.Kernel.Random.generate", [to_msg, _generator]),
    do: encoded_cmd_expr(command_kind(:random_generate), [constructor_tag_expr(to_msg)], 1)

  defp special_value_from_target("Pebble.Internal.Companion.companionSend", args),
    do: encoded_cmd_expr(command_kind(:companion_send), args, 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.companionSend", args),
    do: encoded_cmd_expr(command_kind(:companion_send), args, 2)

  defp special_value_from_target("Pebble.Cmd.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  defp special_value_from_target("Pebble.Cmd.getCurrentTimeString", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_current_time_string)}

  defp special_value_from_target("Pebble.Time.currentTimeString", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_current_time_string)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentTimeString", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_current_time_string)}

  defp special_value_from_target("Pebble.Cmd.getCurrentDateTime", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_current_date_time)}

  defp special_value_from_target("Pebble.Time.currentDateTime", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_current_date_time)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentDateTime", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_current_date_time)}

  defp special_value_from_target("Pebble.System.batteryLevel", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_battery_level)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getBatteryLevel", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_battery_level)}

  defp special_value_from_target("Pebble.System.connectionStatus", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_connection_status)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getConnectionStatus", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_connection_status)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.healthValue", [metric, to_msg]),
    do:
      encoded_cmd_expr(
        command_kind(:health_value),
        [metric, constructor_tag_expr(to_msg)],
        2
      )

  defp special_value_from_target("Elm.Kernel.PebbleWatch.healthSumToday", [metric, to_msg]),
    do:
      encoded_cmd_expr(
        command_kind(:health_sum_today),
        [metric, constructor_tag_expr(to_msg)],
        2
      )

  defp special_value_from_target("Elm.Kernel.PebbleWatch.healthSum", [
         metric,
         start_seconds,
         end_seconds,
         to_msg
       ]),
       do:
         encoded_cmd_expr(
           command_kind(:health_sum),
           [metric, start_seconds, end_seconds, constructor_tag_expr(to_msg)],
           4
         )

  defp special_value_from_target("Elm.Kernel.PebbleWatch.healthAccessible", [
         metric,
         start_seconds,
         end_seconds,
         to_msg
       ]),
       do:
         encoded_cmd_expr(
           command_kind(:health_accessible),
           [metric, start_seconds, end_seconds, constructor_tag_expr(to_msg)],
           4
         )

  defp special_value_from_target("Pebble.Cmd.getClockStyle24h", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_clock_style_24h)}

  defp special_value_from_target("Pebble.Time.clockStyle24h", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_clock_style_24h)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getClockStyle24h", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_clock_style_24h)}

  defp special_value_from_target("Pebble.Cmd.getTimezoneIsSet", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_timezone_is_set)}

  defp special_value_from_target("Pebble.Time.timezoneIsSet", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_timezone_is_set)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getTimezoneIsSet", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_timezone_is_set)}

  defp special_value_from_target("Pebble.Cmd.getTimezone", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_timezone)}

  defp special_value_from_target("Pebble.Time.timezone", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_timezone)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getTimezone", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_timezone)}

  defp special_value_from_target("Pebble.Cmd.getWatchModel", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_watch_model)}

  defp special_value_from_target("Pebble.WatchInfo.getModel", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_watch_model)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getWatchModel", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_watch_model)}

  defp special_value_from_target("Pebble.Cmd.getFirmwareVersion", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_firmware_version)}

  defp special_value_from_target("Pebble.WatchInfo.getFirmwareVersion", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_firmware_version)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getFirmwareVersion", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_firmware_version)}

  defp special_value_from_target("Pebble.WatchInfo.getColor", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_watch_color)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getColor", [_to_msg]),
    do: %{op: :int_literal, value: command_kind(:get_watch_color)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.wakeupScheduleAfterSeconds", args),
    do: encoded_cmd_expr(command_kind(:wakeup_schedule_after_seconds), args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.wakeupCancel", args),
    do: encoded_cmd_expr(command_kind(:wakeup_cancel), args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.logInfoCode", args),
    do: encoded_cmd_expr(command_kind(:log_info_code), args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.logWarnCode", args),
    do: encoded_cmd_expr(command_kind(:log_warn_code), args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.logErrorCode", args),
    do: encoded_cmd_expr(command_kind(:log_error_code), args, 1)

  defp special_value_from_target("Pebble.Cmd.vibesCancel", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_cancel)}

  defp special_value_from_target("Pebble.Vibes.cancel", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_cancel)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesCancel", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_cancel)}

  defp special_value_from_target("Pebble.Cmd.vibesShortPulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_short_pulse)}

  defp special_value_from_target("Pebble.Vibes.shortPulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_short_pulse)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesShortPulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_short_pulse)}

  defp special_value_from_target("Pebble.Cmd.vibesLongPulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_long_pulse)}

  defp special_value_from_target("Pebble.Vibes.longPulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_long_pulse)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesLongPulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_long_pulse)}

  defp special_value_from_target("Pebble.Cmd.vibesDoublePulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_double_pulse)}

  defp special_value_from_target("Pebble.Vibes.doublePulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_double_pulse)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesDoublePulse", _args),
    do: %{op: :int_literal, value: command_kind(:vibes_double_pulse)}

  defp special_value_from_target("Pebble.Events.onTick", _args), do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Pebble.Events.onSecondChange", _args),
    do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onTick", _args),
    do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onSecondChange", _args),
    do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Pebble.Frame.every", [%{op: :int_literal, value: ms}, _to_msg])
       when is_integer(ms),
       do: %{op: :int_literal, value: 8192 + Bitwise.bsl(clamp_frame_interval_ms(ms), 16)}

  defp special_value_from_target("Pebble.Frame.every", _args),
    do: %{op: :int_literal, value: 8192 + Bitwise.bsl(33, 16)}

  defp special_value_from_target("Pebble.Frame.atFps", [%{op: :int_literal, value: fps}, _to_msg])
       when is_integer(fps),
       do: %{
         op: :int_literal,
         value: 8192 + Bitwise.bsl(clamp_frame_interval_ms(div(1000, max(fps, 1))), 16)
       }

  defp special_value_from_target("Pebble.Frame.atFps", _args),
    do: %{op: :int_literal, value: 8192 + Bitwise.bsl(33, 16)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onFrame", [
         %{op: :int_literal, value: ms},
         _to_msg
       ])
       when is_integer(ms),
       do: %{op: :int_literal, value: 8192 + Bitwise.bsl(clamp_frame_interval_ms(ms), 16)}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onFrame", _args),
    do: %{op: :int_literal, value: 8192 + Bitwise.bsl(33, 16)}

  defp special_value_from_target("Pebble.Events.onHourChange", _args),
    do: %{op: :int_literal, value: 1024}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onHourChange", _args),
    do: %{op: :int_literal, value: 1024}

  defp special_value_from_target("Pebble.Events.onMinuteChange", _args),
    do: %{op: :int_literal, value: 2048}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onMinuteChange", _args),
    do: %{op: :int_literal, value: 2048}

  defp special_value_from_target("Pebble.Button.onPress", _args),
    do: %{op: :int_literal, value: 16384}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonUp", _args),
    do: %{op: :int_literal, value: 2}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonSelect", _args),
    do: %{op: :int_literal, value: 4}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonDown", _args),
    do: %{op: :int_literal, value: 8}

  defp special_value_from_target("Pebble.Button.on", _args),
    do: %{op: :int_literal, value: 16384}

  defp special_value_from_target("Pebble.Button.onRelease", _args),
    do: %{op: :int_literal, value: 16384}

  defp special_value_from_target("Pebble.Button.onLongPress", _args),
    do: %{op: :int_literal, value: 16384}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonRaw", _args),
    do: %{op: :int_literal, value: 16384}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongUp", _args),
    do: %{op: :int_literal, value: 128}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongSelect", _args),
    do: %{op: :int_literal, value: 256}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongDown", _args),
    do: %{op: :int_literal, value: 512}

  defp special_value_from_target("Pebble.Accel.onTap", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onAccelTap", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Pebble.Accel.onData", _args),
    do: %{op: :int_literal, value: 32768}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onAccelData", _args),
    do: %{op: :int_literal, value: 32768}

  defp special_value_from_target("Pebble.System.onBatteryChange", _args),
    do: %{op: :int_literal, value: 32}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onBatteryChange", _args),
    do: %{op: :int_literal, value: 32}

  defp special_value_from_target("Pebble.System.onConnectionChange", _args),
    do: %{op: :int_literal, value: 64}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onConnectionChange", _args),
    do: %{op: :int_literal, value: 64}

  defp special_value_from_target("Pebble.Health.onEvent", _args),
    do: %{op: :int_literal, value: 2_147_483_648}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onHealthEvent", _args),
    do: %{op: :int_literal, value: 2_147_483_648}

  defp special_value_from_target("Companion.Watch.onPhoneToWatch", _args),
    do: %{op: :int_literal, value: 4096}

  defp special_value_from_target("Pebble.Events.batch", args), do: subscription_batch_expr(args)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.batch", args),
    do: subscription_batch_expr(args)

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpGet", [url, to_msg]),
    do: http_request_constructor_expr("GET", url, to_msg)

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpPost", [url, to_msg]),
    do: http_request_constructor_expr("POST", url, to_msg)

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpPut", [url, to_msg]),
    do: http_request_constructor_expr("PUT", url, to_msg)

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpDelete", [url, to_msg]),
    do: http_request_constructor_expr("DELETE", url, to_msg)

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpRequest", [method, url]),
    do: %{op: :qualified_call, target: "Pebble.Http.requestImpl", args: [method, url]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpWithHeader", [name, value, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withHeaderImpl", args: [name, value, req]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpWithTimeout", [timeout, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withTimeoutImpl", args: [timeout, req]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpWithBody", [body, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withBodyImpl", args: [body, req]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpExpectString", [to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectStringImpl", args: [to_msg, req]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpExpectJson", [decoder, to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectJsonImpl", args: [decoder, to_msg, req]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.httpExpectBytes", [to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectBytesImpl", args: [to_msg, req]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageSave", [key, value, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Save", args: [key, value, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageLoad", [key, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Load", args: [key, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageRemove", [key, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Remove", args: [key, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageClear", [to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Clear", args: [to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageSaveJson", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveJsonImpl", args: [key, value, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageLoadJson", [key, decoder, to_msg]),
       do: %{
         op: :qualified_call,
         target: "Pebble.Storage.loadJsonImpl",
         args: [key, decoder, to_msg]
       }

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageSaveInt", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveIntImpl", args: [key, value, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageLoadInt", [key, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.loadIntImpl", args: [key, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageSaveBool", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveBoolImpl", args: [key, value, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.storageLoadBool", [key, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.loadBoolImpl", args: [key, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.webSocketConnect", [url, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Connect", args: [url, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.webSocketDisconnect", [to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Disconnect", args: [to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.webSocketSend", [message, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Send", args: [message, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.webSocketSendJson", [json_data, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.SendJson", args: [json_data, to_msg]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.webSocketIsConnected", [state]),
    do: %{op: :qualified_call, target: "Pebble.WebSocket.isConnectedImpl", args: [state]}

  defp special_value_from_target("Elm.Kernel.PebblePhone.webSocketGetState", [state]),
    do: %{op: :qualified_call, target: "Pebble.WebSocket.getStateImpl", args: [state]}

  defp special_value_from_target("Basics.max", [left, right]),
    do: %{op: :runtime_call, function: "elmc_basics_max", args: [left, right]}

  defp special_value_from_target("Basics.min", [left, right]),
    do: %{op: :runtime_call, function: "elmc_basics_min", args: [left, right]}

  defp special_value_from_target("Basics.clamp", [low, high, value]),
    do: %{op: :runtime_call, function: "elmc_basics_clamp", args: [low, high, value]}

  defp special_value_from_target("Basics.modBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]}

  defp special_value_from_target("Basics.remainderBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]}

  defp special_value_from_target("Bitwise.and", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_and", args: [left, right]}

  defp special_value_from_target("Bitwise.or", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_or", args: [left, right]}

  defp special_value_from_target("Bitwise.xor", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_xor", args: [left, right]}

  defp special_value_from_target("Bitwise.complement", [value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_complement", args: [value]}

  defp special_value_from_target("Bitwise.shiftLeftBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_left_by", args: [bits, value]}

  defp special_value_from_target("Bitwise.shiftRightBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_right_by", args: [bits, value]}

  defp special_value_from_target("Bitwise.shiftRightZfBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_right_zf_by", args: [bits, value]}

  defp special_value_from_target("Char.toCode", [value]),
    do: %{op: :runtime_call, function: "elmc_char_to_code", args: [value]}

  defp special_value_from_target("Debug.log", [label, value]),
    do: %{op: :runtime_call, function: "elmc_debug_log", args: [label, value]}

  defp special_value_from_target("Debug.todo", [label]),
    do: %{op: :runtime_call, function: "elmc_debug_todo", args: [label]}

  defp special_value_from_target("Debug.toString", [value]),
    do: %{op: :runtime_call, function: "elmc_debug_to_string", args: [value]}

  defp special_value_from_target("String.append", [left, right]),
    do: %{op: :runtime_call, function: "elmc_append", args: [left, right]}

  defp special_value_from_target("String.isEmpty", [value]),
    do: %{op: :runtime_call, function: "elmc_string_is_empty", args: [value]}

  defp special_value_from_target("Tuple.pair", [left, right]),
    do: %{op: :tuple2, left: left, right: right}

  defp special_value_from_target("Tuple.pair", []),
    do: %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{op: :tuple2, left: %{op: :var, name: "__a"}, right: %{op: :var, name: "__b"}}
    }

  defp special_value_from_target("Tuple.pair", [left]),
    do: %{
      op: :lambda,
      args: ["__b"],
      body: %{op: :tuple2, left: left, right: %{op: :var, name: "__b"}}
    }

  defp special_value_from_target("Dict.empty", []), do: %{op: :list_literal, items: []}

  defp special_value_from_target("Dict.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_dict_from_list", args: [items]}

  defp special_value_from_target("Dict.insert", [key, value, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_insert", args: [key, value, dict]}

  defp special_value_from_target("Dict.get", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_get", args: [key, dict]}

  defp special_value_from_target("Dict.member", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_member", args: [key, dict]}

  defp special_value_from_target("Dict.size", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_size", args: [dict]}

  defp special_value_from_target("Set.empty", []), do: %{op: :list_literal, items: []}

  defp special_value_from_target("Set.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_set_from_list", args: [items]}

  defp special_value_from_target("Set.insert", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_insert", args: [value, set]}

  defp special_value_from_target("Set.member", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_member", args: [value, set]}

  defp special_value_from_target("Set.size", [set]),
    do: %{op: :runtime_call, function: "elmc_set_size", args: [set]}

  defp special_value_from_target("Array.empty", []),
    do: %{op: :runtime_call, function: "elmc_array_empty", args: []}

  defp special_value_from_target("Array.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_array_from_list", args: [items]}

  defp special_value_from_target("Array.length", [array]),
    do: %{op: :runtime_call, function: "elmc_array_length", args: [array]}

  defp special_value_from_target("Array.get", [index, array]),
    do: %{op: :runtime_call, function: "elmc_array_get", args: [index, array]}

  defp special_value_from_target("Array.set", [index, value, array]),
    do: %{op: :runtime_call, function: "elmc_array_set", args: [index, value, array]}

  defp special_value_from_target("Array.push", [value, array]),
    do: %{op: :runtime_call, function: "elmc_array_push", args: [value, array]}

  defp special_value_from_target("Task.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [value]}

  defp special_value_from_target("Task.fail", [value]),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [value]}

  defp special_value_from_target("Process.spawn", [task]),
    do: %{op: :runtime_call, function: "elmc_process_spawn", args: [task]}

  defp special_value_from_target("Process.sleep", [milliseconds]),
    do: %{op: :runtime_call, function: "elmc_process_sleep", args: [milliseconds]}

  defp special_value_from_target("Process.kill", [pid]),
    do: %{op: :runtime_call, function: "elmc_process_kill", args: [pid]}

  defp special_value_from_target("Elm.Kernel.Time.nowMillis", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  defp special_value_from_target("Elm.Kernel.Time.zoneOffsetMinutes", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_zone_offset_minutes", args: []}

  defp special_value_from_target("Elm.Kernel.Time.every", _args),
    do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Cmd.none", _args), do: %{op: :int_literal, value: 0}

  defp special_value_from_target("Cmd.batch", [%{op: :list_literal, items: []}]),
    do: %{op: :int_literal, value: 0}

  defp special_value_from_target("Cmd.batch", [%{op: :list_literal, items: [command]}]),
    do: command

  defp special_value_from_target("Cmd.batch", [commands]), do: commands

  defp special_value_from_target("Sub.none", _args), do: %{op: :int_literal, value: 0}
  defp special_value_from_target("Sub.batch", args), do: subscription_batch_expr(args)

  defp special_value_from_target("Platform.worker", _args), do: %{op: :int_literal, value: 0}

  defp special_value_from_target("Pebble.Platform.application", _args),
    do: %{op: :int_literal, value: 0}

  defp special_value_from_target("Pebble.Platform.watchface", _args),
    do: %{op: :int_literal, value: 0}

  defp special_value_from_target("PebblePlatform.application", _args),
    do: %{op: :int_literal, value: 0}

  defp special_value_from_target("PebblePlatform.watchface", _args),
    do: %{op: :int_literal, value: 0}

  # --- Partial application: zero-arg references to known stdlib functions ---
  # When a qualified call is used as a value (0 args), wrap it in a lambda.
  defp special_value_from_target("List.head", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_head", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.tail", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_tail", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.reverse", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_reverse", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.length", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_length", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.isEmpty", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_is_empty", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.sum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_sum", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.product", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_product", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.maximum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_maximum", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.minimum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_minimum", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.sort", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_sort", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("List.concat", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_concat", args: [%{op: :var, name: "__l"}]}
    }

  defp special_value_from_target("Maybe.withDefault", [default_val]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{
        op: :runtime_call,
        function: "elmc_maybe_with_default",
        args: [default_val, %{op: :var, name: "__m"}]
      }
    }

  defp special_value_from_target("Maybe.map", [f]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{op: :runtime_call, function: "elmc_maybe_map", args: [f, %{op: :var, name: "__m"}]}
    }

  defp special_value_from_target("Maybe.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{
        op: :runtime_call,
        function: "elmc_maybe_and_then",
        args: [f, %{op: :var, name: "__m"}]
      }
    }

  defp special_value_from_target("Result.map", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{op: :runtime_call, function: "elmc_result_map", args: [f, %{op: :var, name: "__r"}]}
    }

  defp special_value_from_target("Result.mapError", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_map_error",
        args: [f, %{op: :var, name: "__r"}]
      }
    }

  defp special_value_from_target("Result.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_and_then",
        args: [f, %{op: :var, name: "__r"}]
      }
    }

  defp special_value_from_target("Result.withDefault", [default_val]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_with_default",
        args: [default_val, %{op: :var, name: "__r"}]
      }
    }

  defp special_value_from_target("Result.toMaybe", []),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_to_maybe",
        args: [%{op: :var, name: "__r"}]
      }
    }

  defp special_value_from_target("String.fromInt", []),
    do: %{
      op: :lambda,
      args: ["__n"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_from_int",
        args: [%{op: :var, name: "__n"}]
      }
    }

  defp special_value_from_target("String.fromFloat", []),
    do: %{
      op: :lambda,
      args: ["__f"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_from_float",
        args: [%{op: :var, name: "__f"}]
      }
    }

  defp special_value_from_target("String.toInt", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_to_int", args: [%{op: :var, name: "__s"}]}
    }

  defp special_value_from_target("String.toFloat", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_float",
        args: [%{op: :var, name: "__s"}]
      }
    }

  defp special_value_from_target("String.isEmpty", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_is_empty",
        args: [%{op: :var, name: "__s"}]
      }
    }

  defp special_value_from_target("String.length", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_length_val",
        args: [%{op: :var, name: "__s"}]
      }
    }

  defp special_value_from_target("String.reverse", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_reverse",
        args: [%{op: :var, name: "__s"}]
      }
    }

  defp special_value_from_target("String.toUpper", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_upper",
        args: [%{op: :var, name: "__s"}]
      }
    }

  defp special_value_from_target("String.toLower", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_lower",
        args: [%{op: :var, name: "__s"}]
      }
    }

  defp special_value_from_target("String.trim", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_trim", args: [%{op: :var, name: "__s"}]}
    }

  defp special_value_from_target("String.words", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_words", args: [%{op: :var, name: "__s"}]}
    }

  defp special_value_from_target("String.lines", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_lines", args: [%{op: :var, name: "__s"}]}
    }

  defp special_value_from_target("Basics.identity", []),
    do: %{op: :lambda, args: ["__x"], body: %{op: :var, name: "__x"}}

  defp special_value_from_target("Basics.always", []),
    do: %{op: :lambda, args: ["__a", "__b"], body: %{op: :var, name: "__a"}}

  defp special_value_from_target("Basics.always", [x]),
    do: %{op: :lambda, args: ["__ignored"], body: x}

  defp special_value_from_target("Basics.negate", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_negate", args: [%{op: :var, name: "__x"}]}
    }

  defp special_value_from_target("Basics.not", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_not", args: [%{op: :var, name: "__x"}]}
    }

  defp special_value_from_target("Basics.abs", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_abs", args: [%{op: :var, name: "__x"}]}
    }

  defp special_value_from_target("Basics.toFloat", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_to_float",
        args: [%{op: :var, name: "__x"}]
      }
    }

  defp special_value_from_target("Basics.sqrt", []), do: unary_runtime_lambda("elmc_basics_sqrt")

  defp special_value_from_target("Basics.logBase", []),
    do: binary_runtime_lambda("elmc_basics_log_base")

  defp special_value_from_target("Basics.logBase", [base]),
    do: bound_binary_runtime_lambda("elmc_basics_log_base", base)

  defp special_value_from_target("Basics.cos", []), do: unary_runtime_lambda("elmc_basics_cos")
  defp special_value_from_target("Basics.sin", []), do: unary_runtime_lambda("elmc_basics_sin")
  defp special_value_from_target("Basics.tan", []), do: unary_runtime_lambda("elmc_basics_tan")
  defp special_value_from_target("Basics.acos", []), do: unary_runtime_lambda("elmc_basics_acos")
  defp special_value_from_target("Basics.asin", []), do: unary_runtime_lambda("elmc_basics_asin")
  defp special_value_from_target("Basics.atan", []), do: unary_runtime_lambda("elmc_basics_atan")

  defp special_value_from_target("Basics.atan2", []),
    do: binary_runtime_lambda("elmc_basics_atan2")

  defp special_value_from_target("Basics.atan2", [y]),
    do: bound_binary_runtime_lambda("elmc_basics_atan2", y)

  defp special_value_from_target("Basics.degrees", []),
    do: unary_runtime_lambda("elmc_basics_degrees")

  defp special_value_from_target("Basics.radians", []),
    do: unary_runtime_lambda("elmc_basics_radians")

  defp special_value_from_target("Basics.turns", []),
    do: unary_runtime_lambda("elmc_basics_turns")

  defp special_value_from_target("Basics.fromPolar", []),
    do: unary_runtime_lambda("elmc_basics_from_polar")

  defp special_value_from_target("Basics.toPolar", []),
    do: unary_runtime_lambda("elmc_basics_to_polar")

  defp special_value_from_target("Basics.isNaN", []),
    do: unary_runtime_lambda("elmc_basics_is_nan")

  defp special_value_from_target("Basics.isInfinite", []),
    do: unary_runtime_lambda("elmc_basics_is_infinite")

  defp special_value_from_target("Basics.round", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_round", args: [%{op: :var, name: "__x"}]}
    }

  defp special_value_from_target("Basics.floor", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_floor", args: [%{op: :var, name: "__x"}]}
    }

  defp special_value_from_target("Basics.ceiling", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_ceiling",
        args: [%{op: :var, name: "__x"}]
      }
    }

  defp special_value_from_target("Basics.max", []), do: binary_runtime_lambda("elmc_basics_max")

  defp special_value_from_target("Basics.max", [left]),
    do: bound_binary_runtime_lambda("elmc_basics_max", left)

  defp special_value_from_target("Basics.min", []), do: binary_runtime_lambda("elmc_basics_min")

  defp special_value_from_target("Basics.min", [left]),
    do: bound_binary_runtime_lambda("elmc_basics_min", left)

  defp special_value_from_target("Basics.clamp", []),
    do: ternary_runtime_lambda("elmc_basics_clamp")

  defp special_value_from_target("Basics.clamp", [low]),
    do: bound_ternary_runtime_lambda("elmc_basics_clamp", low)

  defp special_value_from_target("Basics.clamp", [low, high]),
    do: bound_ternary_runtime_lambda("elmc_basics_clamp", low, high)

  defp special_value_from_target("Basics.modBy", []),
    do: binary_runtime_lambda("elmc_basics_mod_by")

  defp special_value_from_target("Basics.modBy", [base]),
    do: bound_binary_runtime_lambda("elmc_basics_mod_by", base)

  defp special_value_from_target("Basics.remainderBy", []),
    do: binary_runtime_lambda("elmc_basics_remainder_by")

  defp special_value_from_target("Basics.remainderBy", [base]),
    do: bound_binary_runtime_lambda("elmc_basics_remainder_by", base)

  defp special_value_from_target("Basics.xor", []), do: binary_runtime_lambda("elmc_basics_xor")

  defp special_value_from_target("Basics.xor", [a]),
    do: bound_binary_runtime_lambda("elmc_basics_xor", a)

  defp special_value_from_target("Basics.compare", []),
    do: binary_runtime_lambda("elmc_basics_compare")

  defp special_value_from_target("Basics.compare", [a]),
    do: bound_binary_runtime_lambda("elmc_basics_compare", a)

  defp special_value_from_target("Basics.truncate", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_truncate",
        args: [%{op: :var, name: "__x"}]
      }
    }

  defp special_value_from_target("Json.Decode.string", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_string_decoder", args: []}

  defp special_value_from_target("Json.Decode.int", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_int_decoder", args: []}

  defp special_value_from_target("Json.Decode.float", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_float_decoder", args: []}

  defp special_value_from_target("Json.Decode.bool", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_bool_decoder", args: []}

  defp special_value_from_target("Json.Decode.value", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_value_decoder", args: []}

  defp special_value_from_target("Json.Encode.null", _args),
    do: %{op: :runtime_call, function: "elmc_json_encode_null", args: []}

  defp special_value_from_target("Char.toCode", []),
    do: %{
      op: :lambda,
      args: ["__ch"],
      body: %{op: :runtime_call, function: "elmc_char_to_code", args: [%{op: :var, name: "__ch"}]}
    }

  defp special_value_from_target("Char.fromCode", []),
    do: %{
      op: :lambda,
      args: ["__c"],
      body: %{op: :runtime_call, function: "elmc_new_char", args: [%{op: :var, name: "__c"}]}
    }

  defp special_value_from_target("Debug.toString", []),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_to_string",
        args: [%{op: :var, name: "__v"}]
      }
    }

  defp special_value_from_target("Debug.log", [label]),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_log",
        args: [label, %{op: :var, name: "__v"}]
      }
    }

  # --- elm/core: List ---
  defp special_value_from_target("List.head", [list]),
    do: %{op: :runtime_call, function: "elmc_list_head", args: [list]}

  defp special_value_from_target("List.tail", [list]),
    do: %{op: :runtime_call, function: "elmc_list_tail", args: [list]}

  defp special_value_from_target("List.isEmpty", [list]),
    do: %{op: :runtime_call, function: "elmc_list_is_empty", args: [list]}

  defp special_value_from_target("List.length", [list]),
    do: %{op: :runtime_call, function: "elmc_list_length", args: [list]}

  defp special_value_from_target("List.reverse", [list]),
    do: %{op: :runtime_call, function: "elmc_list_reverse", args: [list]}

  defp special_value_from_target("List.member", [value, list]),
    do: %{op: :runtime_call, function: "elmc_list_member", args: [value, list]}

  defp special_value_from_target("List.map", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_map", args: [f, list]}

  defp special_value_from_target("List.filter", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_filter", args: [f, list]}

  defp special_value_from_target("List.foldl", [f, acc, list]),
    do: %{op: :runtime_call, function: "elmc_list_foldl", args: [f, acc, list]}

  defp special_value_from_target("List.foldr", [f, acc, list]),
    do: %{op: :runtime_call, function: "elmc_list_foldr", args: [f, acc, list]}

  defp special_value_from_target("List.append", [a, b]),
    do: %{op: :runtime_call, function: "elmc_list_append", args: [a, b]}

  defp special_value_from_target("List.concat", [lists]),
    do: %{op: :runtime_call, function: "elmc_list_concat", args: [lists]}

  defp special_value_from_target("List.concatMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_concat_map", args: [f, list]}

  defp special_value_from_target("List.indexedMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_indexed_map", args: [f, list]}

  defp special_value_from_target("List.filterMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_filter_map", args: [f, list]}

  defp special_value_from_target("List.sum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_sum", args: [list]}

  defp special_value_from_target("List.product", [list]),
    do: %{op: :runtime_call, function: "elmc_list_product", args: [list]}

  defp special_value_from_target("List.maximum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_maximum", args: [list]}

  defp special_value_from_target("List.minimum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_minimum", args: [list]}

  defp special_value_from_target("List.any", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_any", args: [f, list]}

  defp special_value_from_target("List.all", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_all", args: [f, list]}

  defp special_value_from_target("List.sort", [list]),
    do: %{op: :runtime_call, function: "elmc_list_sort", args: [list]}

  defp special_value_from_target("List.sortBy", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_sort_by", args: [f, list]}

  defp special_value_from_target("List.sortWith", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_sort_with", args: [f, list]}

  defp special_value_from_target("List.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_list_singleton", args: [value]}

  defp special_value_from_target("List.range", [lo, hi]),
    do: %{op: :runtime_call, function: "elmc_list_range", args: [lo, hi]}

  defp special_value_from_target("List.repeat", [n, value]),
    do: %{op: :runtime_call, function: "elmc_list_repeat", args: [n, value]}

  defp special_value_from_target("List.take", [n, list]),
    do: %{op: :runtime_call, function: "elmc_list_take", args: [n, list]}

  defp special_value_from_target("List.drop", [n, list]),
    do: %{op: :runtime_call, function: "elmc_list_drop", args: [n, list]}

  defp special_value_from_target("List.partition", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_partition", args: [f, list]}

  defp special_value_from_target("List.unzip", [list]),
    do: %{op: :runtime_call, function: "elmc_list_unzip", args: [list]}

  defp special_value_from_target("List.intersperse", [sep, list]),
    do: %{op: :runtime_call, function: "elmc_list_intersperse", args: [sep, list]}

  defp special_value_from_target("List.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_list_map2", args: [f, a, b]}

  defp special_value_from_target("List.map3", [f, a, b, c]),
    do: %{op: :runtime_call, function: "elmc_list_map3", args: [f, a, b, c]}

  # --- elm/core: Maybe ---
  defp special_value_from_target("Maybe.withDefault", [default_val, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, maybe]}

  defp special_value_from_target("Maybe.map", [f, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_map", args: [f, maybe]}

  defp special_value_from_target("Maybe.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_maybe_map2", args: [f, a, b]}

  defp special_value_from_target("Maybe.andThen", [f, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_and_then", args: [f, maybe]}

  # --- elm/core: Result ---
  defp special_value_from_target("Result.map", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_map", args: [f, result]}

  defp special_value_from_target("Result.mapError", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_map_error", args: [f, result]}

  defp special_value_from_target("Result.andThen", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_and_then", args: [f, result]}

  defp special_value_from_target("Result.withDefault", [default_val, result]),
    do: %{op: :runtime_call, function: "elmc_result_with_default", args: [default_val, result]}

  defp special_value_from_target("Result.toMaybe", [result]),
    do: %{op: :runtime_call, function: "elmc_result_to_maybe", args: [result]}

  defp special_value_from_target("Result.fromMaybe", [err, maybe]),
    do: %{op: :runtime_call, function: "elmc_result_from_maybe", args: [err, maybe]}

  # --- elm/core: String (extended) ---
  defp special_value_from_target("String.length", [s]),
    do: %{op: :runtime_call, function: "elmc_string_length_val", args: [s]}

  defp special_value_from_target("String.reverse", [s]),
    do: %{op: :runtime_call, function: "elmc_string_reverse", args: [s]}

  defp special_value_from_target("String.repeat", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_repeat", args: [n, s]}

  defp special_value_from_target("String.replace", [old, new_s, s]),
    do: %{op: :runtime_call, function: "elmc_string_replace", args: [old, new_s, s]}

  defp special_value_from_target("String.fromInt", [n]),
    do: %{op: :runtime_call, function: "elmc_string_from_int", args: [n]}

  defp special_value_from_target("String.toInt", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_int", args: [s]}

  defp special_value_from_target("String.fromFloat", [f]),
    do: %{op: :runtime_call, function: "elmc_string_from_float", args: [f]}

  defp special_value_from_target("String.toFloat", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_float", args: [s]}

  defp special_value_from_target("String.toUpper", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_upper", args: [s]}

  defp special_value_from_target("String.toLower", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_lower", args: [s]}

  defp special_value_from_target("String.trim", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim", args: [s]}

  defp special_value_from_target("String.trimLeft", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim_left", args: [s]}

  defp special_value_from_target("String.trimRight", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim_right", args: [s]}

  defp special_value_from_target("String.contains", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_contains", args: [sub, s]}

  defp special_value_from_target("String.startsWith", [prefix, s]),
    do: %{op: :runtime_call, function: "elmc_string_starts_with", args: [prefix, s]}

  defp special_value_from_target("String.endsWith", [suffix, s]),
    do: %{op: :runtime_call, function: "elmc_string_ends_with", args: [suffix, s]}

  defp special_value_from_target("String.split", [sep, s]),
    do: %{op: :runtime_call, function: "elmc_string_split", args: [sep, s]}

  defp special_value_from_target("String.join", [sep, list]),
    do: %{op: :runtime_call, function: "elmc_string_join", args: [sep, list]}

  defp special_value_from_target("String.words", [s]),
    do: %{op: :runtime_call, function: "elmc_string_words", args: [s]}

  defp special_value_from_target("String.lines", [s]),
    do: %{op: :runtime_call, function: "elmc_string_lines", args: [s]}

  defp special_value_from_target("String.slice", [start, end_idx, s]),
    do: %{op: :runtime_call, function: "elmc_string_slice", args: [start, end_idx, s]}

  defp special_value_from_target("String.left", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_left", args: [n, s]}

  defp special_value_from_target("String.right", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_right", args: [n, s]}

  defp special_value_from_target("String.dropLeft", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_drop_left", args: [n, s]}

  defp special_value_from_target("String.dropRight", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_drop_right", args: [n, s]}

  defp special_value_from_target("String.cons", [ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_cons", args: [ch, s]}

  defp special_value_from_target("String.uncons", [s]),
    do: %{op: :runtime_call, function: "elmc_string_uncons", args: [s]}

  defp special_value_from_target("String.toList", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_list", args: [s]}

  defp special_value_from_target("String.fromList", [list]),
    do: %{op: :runtime_call, function: "elmc_string_from_list", args: [list]}

  defp special_value_from_target("String.fromChar", [ch]),
    do: %{op: :runtime_call, function: "elmc_string_from_char", args: [ch]}

  defp special_value_from_target("String.pad", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad", args: [n, ch, s]}

  defp special_value_from_target("String.padLeft", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad_left", args: [n, ch, s]}

  defp special_value_from_target("String.padRight", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad_right", args: [n, ch, s]}

  defp special_value_from_target("String.map", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_map", args: [f, s]}

  defp special_value_from_target("String.filter", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_filter", args: [f, s]}

  defp special_value_from_target("String.foldl", [f, acc, s]),
    do: %{op: :runtime_call, function: "elmc_string_foldl", args: [f, acc, s]}

  defp special_value_from_target("String.foldr", [f, acc, s]),
    do: %{op: :runtime_call, function: "elmc_string_foldr", args: [f, acc, s]}

  defp special_value_from_target("String.any", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_any", args: [f, s]}

  defp special_value_from_target("String.all", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_all", args: [f, s]}

  defp special_value_from_target("String.indexes", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_indexes", args: [sub, s]}

  defp special_value_from_target("String.indices", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_indexes", args: [sub, s]}

  # --- elm/core: Tuple ---
  defp special_value_from_target("Tuple.first", [t]),
    do: %{op: :runtime_call, function: "elmc_tuple_first", args: [t]}

  defp special_value_from_target("Tuple.second", [t]),
    do: %{op: :runtime_call, function: "elmc_tuple_second", args: [t]}

  defp special_value_from_target("Tuple.mapFirst", [f, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_first", args: [f, t]}

  defp special_value_from_target("Tuple.mapSecond", [f, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_second", args: [f, t]}

  defp special_value_from_target("Tuple.mapBoth", [f, g, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_both", args: [f, g, t]}

  # --- elm/core: Basics (extended) ---
  defp special_value_from_target("Basics.identity", [x]), do: x

  defp special_value_from_target("Basics.always", [x, _y]), do: x

  defp special_value_from_target("Basics.not", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_not", args: [x]}

  defp special_value_from_target("Basics.negate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_negate", args: [x]}

  defp special_value_from_target("Basics.abs", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_abs", args: [x]}

  defp special_value_from_target("Basics.toFloat", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_to_float", args: [x]}

  defp special_value_from_target("Basics.e", _args),
    do: %{op: :float_literal, value: 2.718281828459045}

  defp special_value_from_target("Basics.pi", _args),
    do: %{op: :float_literal, value: 3.141592653589793}

  defp special_value_from_target("Basics.sqrt", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_sqrt", args: [x]}

  defp special_value_from_target("Basics.logBase", [base, x]),
    do: %{op: :runtime_call, function: "elmc_basics_log_base", args: [base, x]}

  defp special_value_from_target("Basics.sin", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_sin", args: [x]}

  defp special_value_from_target("Basics.cos", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_cos", args: [x]}

  defp special_value_from_target("Basics.tan", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_tan", args: [x]}

  defp special_value_from_target("Basics.acos", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_acos", args: [x]}

  defp special_value_from_target("Basics.asin", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_asin", args: [x]}

  defp special_value_from_target("Basics.atan", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_atan", args: [x]}

  defp special_value_from_target("Basics.atan2", [y, x]),
    do: %{op: :runtime_call, function: "elmc_basics_atan2", args: [y, x]}

  defp special_value_from_target("Basics.degrees", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_degrees", args: [x]}

  defp special_value_from_target("Basics.radians", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_radians", args: [x]}

  defp special_value_from_target("Basics.turns", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_turns", args: [x]}

  defp special_value_from_target("Basics.fromPolar", [polar]),
    do: %{op: :runtime_call, function: "elmc_basics_from_polar", args: [polar]}

  defp special_value_from_target("Basics.toPolar", [point]),
    do: %{op: :runtime_call, function: "elmc_basics_to_polar", args: [point]}

  defp special_value_from_target("Basics.isNaN", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_is_nan", args: [x]}

  defp special_value_from_target("Basics.isInfinite", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_is_infinite", args: [x]}

  defp special_value_from_target("Basics.round", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_round", args: [x]}

  defp special_value_from_target("Basics.floor", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_floor", args: [x]}

  defp special_value_from_target("Basics.ceiling", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_ceiling", args: [x]}

  defp special_value_from_target("Basics.truncate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_truncate", args: [x]}

  defp special_value_from_target("Basics.xor", [a, b]),
    do: %{op: :runtime_call, function: "elmc_basics_xor", args: [a, b]}

  defp special_value_from_target("Basics.compare", [a, b]),
    do: %{op: :runtime_call, function: "elmc_basics_compare", args: [a, b]}

  # --- elm/core: Char (extended) ---
  defp special_value_from_target("Char.fromCode", [code]),
    do: %{op: :runtime_call, function: "elmc_new_char", args: [code]}

  defp special_value_from_target("Char.isUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_upper", args: [ch]}

  defp special_value_from_target("Char.isLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_lower", args: [ch]}

  defp special_value_from_target("Char.isAlpha", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_alpha", args: [ch]}

  defp special_value_from_target("Char.isAlphaNum", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_alpha_num", args: [ch]}

  defp special_value_from_target("Char.isDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_digit", args: [ch]}

  defp special_value_from_target("Char.isOctDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_oct_digit", args: [ch]}

  defp special_value_from_target("Char.isHexDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_hex_digit", args: [ch]}

  defp special_value_from_target("Char.toUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_upper", args: [ch]}

  defp special_value_from_target("Char.toLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_lower", args: [ch]}

  defp special_value_from_target("Char.toLocaleUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_upper", args: [ch]}

  defp special_value_from_target("Char.toLocaleLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_lower", args: [ch]}

  # --- elm/core: Dict (extended) ---
  defp special_value_from_target("Dict.remove", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_remove", args: [key, dict]}

  defp special_value_from_target("Dict.isEmpty", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_is_empty", args: [dict]}

  defp special_value_from_target("Dict.keys", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_keys", args: [dict]}

  defp special_value_from_target("Dict.values", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_values", args: [dict]}

  defp special_value_from_target("Dict.toList", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_to_list", args: [dict]}

  defp special_value_from_target("Dict.map", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_map", args: [f, dict]}

  defp special_value_from_target("Dict.foldl", [f, acc, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_foldl", args: [f, acc, dict]}

  defp special_value_from_target("Dict.foldr", [f, acc, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_foldr", args: [f, acc, dict]}

  defp special_value_from_target("Dict.filter", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_filter", args: [f, dict]}

  defp special_value_from_target("Dict.partition", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_partition", args: [f, dict]}

  defp special_value_from_target("Dict.union", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_union", args: [a, b]}

  defp special_value_from_target("Dict.intersect", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_intersect", args: [a, b]}

  defp special_value_from_target("Dict.diff", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_diff", args: [a, b]}

  defp special_value_from_target("Dict.merge", [left_fn, both_fn, right_fn, a, b]),
    do: %{
      op: :runtime_call,
      function: "elmc_dict_merge",
      args: [left_fn, both_fn, right_fn, a, b]
    }

  defp special_value_from_target("Dict.update", [key, f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_update", args: [key, f, dict]}

  defp special_value_from_target("Dict.singleton", [key, value]),
    do: %{op: :runtime_call, function: "elmc_dict_singleton", args: [key, value]}

  # --- elm/core: Set (extended) ---
  defp special_value_from_target("Set.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_set_singleton", args: [value]}

  defp special_value_from_target("Set.remove", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_remove", args: [value, set]}

  defp special_value_from_target("Set.isEmpty", [set]),
    do: %{op: :runtime_call, function: "elmc_set_is_empty", args: [set]}

  defp special_value_from_target("Set.toList", [set]),
    do: %{op: :runtime_call, function: "elmc_set_to_list", args: [set]}

  defp special_value_from_target("Set.union", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_union", args: [a, b]}

  defp special_value_from_target("Set.intersect", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_intersect", args: [a, b]}

  defp special_value_from_target("Set.diff", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_diff", args: [a, b]}

  defp special_value_from_target("Set.map", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_map", args: [f, set]}

  defp special_value_from_target("Set.foldl", [f, acc, set]),
    do: %{op: :runtime_call, function: "elmc_set_foldl", args: [f, acc, set]}

  defp special_value_from_target("Set.foldr", [f, acc, set]),
    do: %{op: :runtime_call, function: "elmc_set_foldr", args: [f, acc, set]}

  defp special_value_from_target("Set.filter", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_filter", args: [f, set]}

  defp special_value_from_target("Set.partition", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_partition", args: [f, set]}

  # --- elm/core: Array (extended) ---
  defp special_value_from_target("Array.initialize", [n, f]),
    do: %{op: :runtime_call, function: "elmc_array_initialize", args: [n, f]}

  defp special_value_from_target("Array.repeat", [n, value]),
    do: %{op: :runtime_call, function: "elmc_array_repeat", args: [n, value]}

  defp special_value_from_target("Array.isEmpty", [array]),
    do: %{op: :runtime_call, function: "elmc_array_is_empty", args: [array]}

  defp special_value_from_target("Array.toList", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_list", args: [array]}

  defp special_value_from_target("Array.toIndexedList", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_indexed_list", args: [array]}

  defp special_value_from_target("Array.map", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_map", args: [f, array]}

  defp special_value_from_target("Array.indexedMap", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_indexed_map", args: [f, array]}

  defp special_value_from_target("Array.foldl", [f, acc, array]),
    do: %{op: :runtime_call, function: "elmc_array_foldl", args: [f, acc, array]}

  defp special_value_from_target("Array.foldr", [f, acc, array]),
    do: %{op: :runtime_call, function: "elmc_array_foldr", args: [f, acc, array]}

  defp special_value_from_target("Array.filter", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_filter", args: [f, array]}

  defp special_value_from_target("Array.append", [a, b]),
    do: %{op: :runtime_call, function: "elmc_array_append", args: [a, b]}

  defp special_value_from_target("Array.slice", [start, end_idx, array]),
    do: %{op: :runtime_call, function: "elmc_array_slice", args: [start, end_idx, array]}

  # --- elm/json: Json.Decode ---
  defp special_value_from_target("Json.Decode.decodeValue", [decoder, value]),
    do: %{op: :runtime_call, function: "elmc_json_decode_value", args: [decoder, value]}

  defp special_value_from_target("Json.Decode.decodeString", [decoder, s]),
    do: %{op: :runtime_call, function: "elmc_json_decode_string", args: [decoder, s]}

  defp special_value_from_target("Json.Decode.null", [default_val]),
    do: %{op: :runtime_call, function: "elmc_json_decode_null", args: [default_val]}

  defp special_value_from_target("Json.Decode.nullable", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_nullable", args: [decoder]}

  defp special_value_from_target("Json.Decode.list", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_list", args: [decoder]}

  defp special_value_from_target("Json.Decode.array", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_array", args: [decoder]}

  defp special_value_from_target("Json.Decode.field", [name, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_field", args: [name, decoder]}

  defp special_value_from_target("Json.Decode.at", [path, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_at", args: [path, decoder]}

  defp special_value_from_target("Json.Decode.index", [idx, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_index", args: [idx, decoder]}

  defp special_value_from_target("Json.Decode.map", [f, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map", args: [f, decoder]}

  defp special_value_from_target("Json.Decode.map2", [f, d1, d2]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map2", args: [f, d1, d2]}

  defp special_value_from_target("Json.Decode.map3", [f, d1, d2, d3]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map3", args: [f, d1, d2, d3]}

  defp special_value_from_target("Json.Decode.map4", [f, d1, d2, d3, d4]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map4", args: [f, d1, d2, d3, d4]}

  defp special_value_from_target("Json.Decode.map5", [f, d1, d2, d3, d4, d5]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map5", args: [f, d1, d2, d3, d4, d5]}

  defp special_value_from_target("Json.Decode.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_json_decode_succeed", args: [value]}

  defp special_value_from_target("Json.Decode.fail", [msg]),
    do: %{op: :runtime_call, function: "elmc_json_decode_fail", args: [msg]}

  defp special_value_from_target("Json.Decode.andThen", [f, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_and_then", args: [f, decoder]}

  defp special_value_from_target("Json.Decode.oneOf", [decoders]),
    do: %{op: :runtime_call, function: "elmc_json_decode_one_of", args: [decoders]}

  defp special_value_from_target("Json.Decode.maybe", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_maybe", args: [decoder]}

  defp special_value_from_target("Json.Decode.lazy", [thunk]),
    do: %{op: :runtime_call, function: "elmc_json_decode_lazy", args: [thunk]}

  defp special_value_from_target("Json.Decode.errorToString", [err]),
    do: %{op: :runtime_call, function: "elmc_json_decode_error_to_string", args: [err]}

  defp special_value_from_target("Json.Decode.errorToString", []),
    do: %{
      op: :lambda,
      args: ["__err"],
      body: %{
        op: :runtime_call,
        function: "elmc_json_decode_error_to_string",
        args: [%{op: :var, name: "__err"}]
      }
    }

  defp special_value_from_target("Json.Decode.keyValuePairs", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_key_value_pairs", args: [decoder]}

  defp special_value_from_target("Json.Decode.dict", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_dict", args: [decoder]}

  # --- elm/json: Json.Encode ---
  defp special_value_from_target("Json.Encode.string", [s]),
    do: %{op: :runtime_call, function: "elmc_json_encode_string", args: [s]}

  defp special_value_from_target("Json.Encode.int", [n]),
    do: %{op: :runtime_call, function: "elmc_json_encode_int", args: [n]}

  defp special_value_from_target("Json.Encode.float", [f]),
    do: %{op: :runtime_call, function: "elmc_json_encode_float", args: [f]}

  defp special_value_from_target("Json.Encode.bool", [b]),
    do: %{op: :runtime_call, function: "elmc_json_encode_bool", args: [b]}

  defp special_value_from_target("Json.Encode.list", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_list", args: [f, items]}

  defp special_value_from_target("Json.Encode.array", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_array", args: [f, items]}

  defp special_value_from_target("Json.Encode.set", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_set", args: [f, items]}

  defp special_value_from_target("Json.Encode.object", [pairs]),
    do: %{op: :runtime_call, function: "elmc_json_encode_object", args: [pairs]}

  defp special_value_from_target("Json.Encode.dict", [key_fn, val_fn, dict]),
    do: %{op: :runtime_call, function: "elmc_json_encode_dict", args: [key_fn, val_fn, dict]}

  defp special_value_from_target("Json.Encode.encode", [indent, value]),
    do: %{op: :runtime_call, function: "elmc_json_encode_encode", args: [indent, value]}

  defp special_value_from_target(target, []) when is_binary(target) do
    cond do
      target in ["True", "Basics.True"] or String.ends_with?(target, ".True") ->
        %{op: :int_literal, value: 1}

      target in ["False", "Basics.False"] or String.ends_with?(target, ".False") ->
        %{op: :int_literal, value: 0}

      target in ["LT", "Basics.LT"] or String.ends_with?(target, ".LT") ->
        %{op: :int_literal, value: -1}

      target in ["EQ", "Basics.EQ"] or String.ends_with?(target, ".EQ") ->
        %{op: :int_literal, value: 0}

      target in ["GT", "Basics.GT"] or String.ends_with?(target, ".GT") ->
        %{op: :int_literal, value: 1}

      target in ["e", "Basics.e"] or String.ends_with?(target, ".e") ->
        %{op: :float_literal, value: 2.718281828459045}

      target in ["pi", "Basics.pi"] or String.ends_with?(target, ".pi") ->
        %{op: :float_literal, value: 3.141592653589793}

      true ->
        nil
    end
  end

  defp special_value_from_target(target, nil) when is_binary(target),
    do: special_value_from_target(target, [])

  defp special_value_from_target(target, args) when is_binary(target) and is_list(args) do
    normalized = normalize_special_target(target)
    if normalized == target, do: nil, else: special_value_from_target(normalized, args)
  end

  defp special_value_from_target(_, _), do: nil

  @spec clamp_frame_interval_ms(integer()) :: pos_integer()
  defp clamp_frame_interval_ms(ms) when is_integer(ms) do
    ms
    |> max(1)
    |> min(32_767)
  end

  @spec normalize_special_target(term()) :: term()
  defp normalize_special_target(target) when is_binary(target) do
    normalize_bare_special_target(target)
  end

  @spec normalize_bare_special_target(term()) :: term()
  defp normalize_bare_special_target(target) when is_binary(target) do
    case target do
      "Clear" -> "Pebble.Ui.clear"
      "Pixel" -> "Pebble.Ui.pixel"
      "Line" -> "Pebble.Ui.line"
      "RectOp" -> "Pebble.Ui.rect"
      "FillRect" -> "Pebble.Ui.fillRect"
      "Circle" -> "Pebble.Ui.circle"
      "FillCircle" -> "Pebble.Ui.fillCircle"
      "TextInt" -> "Pebble.Ui.textInt"
      "TextLabel" -> "Pebble.Ui.textLabel"
      "Text" -> "Pebble.Ui.text"
      "StrokeWidth" -> "Pebble.Ui.strokeWidth"
      "Antialiased" -> "Pebble.Ui.antialiased"
      "StrokeColor" -> "Pebble.Ui.strokeColor"
      "FillColor" -> "Pebble.Ui.fillColor"
      "TextColor" -> "Pebble.Ui.textColor"
      "CompositingMode" -> "Pebble.Ui.compositingMode"
      "Group" -> "Pebble.Ui.group"
      "PathFilled" -> "Pebble.Ui.pathFilled"
      "PathOutline" -> "Pebble.Ui.pathOutline"
      "PathOutlineOpen" -> "Pebble.Ui.pathOutlineOpen"
      "RoundRect" -> "Pebble.Ui.roundRect"
      "Arc" -> "Pebble.Ui.arc"
      "FillRadial" -> "Pebble.Ui.fillRadial"
      "BitmapInRect" -> "Pebble.Ui.drawBitmapInRect"
      "RotatedBitmap" -> "Pebble.Ui.drawRotatedBitmap"
      other -> other
    end
  end

  @spec http_request_constructor_expr(term(), term(), term()) :: term()
  defp http_request_constructor_expr(method_ctor, url, to_msg) do
    method = %{op: :constructor_call, target: "Pebble.Http.#{method_ctor}", args: []}

    req =
      %{
        op: :record_literal,
        fields: [
          {"method", method},
          {"url", url},
          {"headers", %{op: :list_literal, items: []}},
          {"body", %{op: :constructor_call, target: "Nothing", args: []}},
          {"timeout", %{op: :constructor_call, target: "Nothing", args: []}}
        ]
      }

    %{op: :constructor_call, target: "Pebble.Http.Request", args: [req, to_msg]}
  end

  @spec subscription_batch_expr([map()]) :: map()
  defp subscription_batch_expr([%{op: :list_literal, items: items}]) do
    mask =
      Enum.reduce(items, 0, fn item, acc ->
        Bitwise.bor(acc, subscription_item_mask(item))
      end)

    %{op: :int_literal, value: mask}
  end

  defp subscription_batch_expr(_), do: %{op: :unsupported}

  @spec subscription_item_mask(map()) :: non_neg_integer()
  defp subscription_item_mask(%{op: :int_literal, value: value}) when is_integer(value), do: value

  defp subscription_item_mask(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    case special_value_from_target(target, args) do
      %{op: :int_literal, value: value} when is_integer(value) ->
        value

      _ ->
        subscription_item_mask(%{op: :qualified_call, target: target})
    end
  end

  defp subscription_item_mask(%{op: :qualified_call, target: target}) when is_binary(target) do
    case normalize_special_target(target) do
      "Pebble.Events.onTick" -> 1
      "Pebble.Events.onSecondChange" -> 1
      "Pebble.Frame.every" -> 8192
      "Pebble.Frame.atFps" -> 8192
      "Pebble.Events.onHourChange" -> 1024
      "Pebble.Events.onMinuteChange" -> 2048
      "Pebble.Button.on" -> 16384
      "Pebble.Button.onPress" -> 16384
      "Pebble.Button.onRelease" -> 16384
      "Pebble.Button.onLongPress" -> 16384
      "Pebble.Accel.onTap" -> 16
      "Pebble.Accel.onData" -> 32768
      "Pebble.System.onBatteryChange" -> 32
      "Pebble.System.onConnectionChange" -> 64
      "Pebble.Health.onEvent" -> 2_147_483_648
      "Elm.Kernel.PebbleWatch.onBatteryChange" -> 32
      "Elm.Kernel.PebbleWatch.onConnectionChange" -> 64
      "Elm.Kernel.PebbleWatch.onHealthEvent" -> 2_147_483_648
      "Elm.Kernel.PebbleWatch.onFrame" -> 8192
      "Elm.Kernel.PebbleWatch.onButtonUp" -> 2
      "Elm.Kernel.PebbleWatch.onButtonSelect" -> 4
      "Elm.Kernel.PebbleWatch.onButtonDown" -> 8
      "Elm.Kernel.PebbleWatch.onButtonLongUp" -> 128
      "Elm.Kernel.PebbleWatch.onButtonLongSelect" -> 256
      "Elm.Kernel.PebbleWatch.onButtonLongDown" -> 512
      "Elm.Kernel.PebbleWatch.onButtonRaw" -> 16384
      "Elm.Kernel.PebbleWatch.onAccelTap" -> 16
      "Elm.Kernel.PebbleWatch.onAccelData" -> 32768
      "Companion.Watch.onPhoneToWatch" -> 4096
      "Elm.Kernel.PebbleWatch.onHourChange" -> 1024
      "Elm.Kernel.PebbleWatch.onMinuteChange" -> 2048
      "Elm.Kernel.PebbleWatch.onSecondChange" -> 1
      "Elm.Kernel.Time.every" -> 1
      _ -> 0
    end
  end

  defp subscription_item_mask(_), do: 0

  @spec encoded_cmd_expr(non_neg_integer(), [map()], non_neg_integer()) :: map()
  defp encoded_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
      %{op: :tuple2, left: %{op: :int_literal, value: kind}, right: tuple_chain(payload)}
    else
      %{op: :unsupported}
    end
  end

  @spec encoded_text_cmd_expr(non_neg_integer(), [map()]) :: map()
  defp encoded_text_cmd_expr(kind, [font_id, x, y, w, h, value]) do
    payload = [font_id, x, y, w, h, value]
    %{op: :tuple2, left: %{op: :int_literal, value: kind}, right: tuple_chain(payload)}
  end

  defp encoded_text_cmd_expr(_kind, _args), do: %{op: :unsupported}

  @spec constructor_tag_expr(map()) :: map()
  defp constructor_tag_expr(%{op: :int_literal, value: value}) when is_integer(value) do
    %{op: :int_literal, value: value}
  end

  defp constructor_tag_expr(%{op: :var, name: name}) when is_binary(name) do
    %{op: :int_literal, value: constructor_tag(name)}
  end

  defp constructor_tag_expr(%{op: :qualified_ref, target: target}) when is_binary(target) do
    %{op: :int_literal, value: constructor_tag(target)}
  end

  defp constructor_tag_expr(%{op: :qualified_var, target: target}) when is_binary(target) do
    %{op: :int_literal, value: constructor_tag(target)}
  end

  defp constructor_tag_expr(%{op: :constructor_call, target: target, args: []})
       when is_binary(target) do
    %{op: :int_literal, value: constructor_tag(target)}
  end

  defp constructor_tag_expr(%{op: :qualified_call, target: target, args: []})
       when is_binary(target) do
    %{op: :int_literal, value: constructor_tag(target)}
  end

  defp constructor_tag_expr(_), do: %{op: :int_literal, value: 0}

  @spec constructor_tag(String.t()) :: non_neg_integer()
  defp constructor_tag(name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    Map.get_lazy(tags, name, fn ->
      name
      |> String.split(".")
      |> List.last()
      |> then(&Map.get(tags, &1, 0))
    end)
  end

  @spec field_access_expr(map(), String.t()) :: map()
  defp field_access_expr(arg_expr, field) when is_map(arg_expr) and is_binary(field) do
    %{op: :field_access, arg: arg_expr, field: field}
  end

  @spec tuple_chain([map()]) :: map()
  defp tuple_chain([single]), do: single

  defp tuple_chain([head | rest]) do
    %{op: :tuple2, left: head, right: tuple_chain(rest)}
  end

  @spec tagged_value_expr(non_neg_integer(), map()) :: map()
  defp tagged_value_expr(tag, value_expr) do
    %{op: :tuple2, left: %{op: :int_literal, value: tag}, right: value_expr}
  end

  @spec path_expr(map(), map(), map(), map()) :: map()
  defp path_expr(points, offset_x, offset_y, rotation) do
    %{
      op: :tuple2,
      left: points,
      right: %{
        op: :tuple2,
        left: offset_x,
        right: %{
          op: :tuple2,
          left: offset_y,
          right: rotation
        }
      }
    }
  end

  @spec pattern_condition(String.t(), map()) :: String.t()
  defp pattern_condition(_subject_ref, %{kind: :wildcard}), do: "1"
  defp pattern_condition(_subject_ref, %{kind: :var}), do: "1"

  defp pattern_condition(subject_ref, pattern)
       when is_map(pattern) and not is_binary(subject_ref),
       do: pattern_condition(pattern_subject_ref(subject_ref), pattern)

  defp pattern_condition(subject_ref, %{kind: :int, value: value}) when is_integer(value) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == #{value}"
  end

  defp pattern_condition(subject_ref, %{kind: :tuple, elements: [left, right]}) do
    left_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->first"
    right_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && (#{pattern_condition(left_ref, left)}) && (#{pattern_condition(right_ref, right)})"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, name: "Ok", arg_pattern: arg_pattern}) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 1#{arg_cond}"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, name: "Err", arg_pattern: arg_pattern}) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 0#{arg_cond}"
  end

  defp pattern_condition(subject_ref, %{
         kind: :constructor,
         name: "Just",
         arg_pattern: arg_pattern
       }) do
    maybe_value_ref = "((ElmcMaybe *)#{subject_ref}->payload)->value"
    tuple_value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    maybe_arg_cond =
      if arg_pattern, do: " && (#{pattern_condition(maybe_value_ref, arg_pattern)})", else: ""

    tuple_arg_cond =
      if arg_pattern, do: " && (#{pattern_condition(tuple_value_ref, arg_pattern)})", else: ""

    maybe_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)#{subject_ref}->payload)->is_just == 1#{maybe_arg_cond}"

    tuple_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && #{subject_ref}->payload != NULL && elmc_as_int(((ElmcTuple2 *)#{subject_ref}->payload)->first) == 1#{tuple_arg_cond}"

    "((#{maybe_cond}) || (#{tuple_cond}))"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, name: "Nothing"}) do
    maybe_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)#{subject_ref}->payload)->is_just == 0"

    int_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == 0"

    "((#{maybe_cond}) || (#{int_cond}))"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, name: "[]"}) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload == NULL"
  end

  defp pattern_condition(subject_ref, %{
         kind: :constructor,
         name: "::",
         arg_pattern: %{kind: :tuple, elements: [head_pattern, tail_pattern]}
       }) do
    head_ref = "((ElmcCons *)#{subject_ref}->payload)->head"
    tail_ref = "((ElmcCons *)#{subject_ref}->payload)->tail"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload != NULL && (#{pattern_condition(head_ref, head_pattern)}) && (#{pattern_condition(tail_ref, tail_pattern)})"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, name: "::"}) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload != NULL"
  end

  defp pattern_condition(_subject_ref, %{kind: :record}) do
    "1"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, tag: tag, arg_pattern: arg_pattern})
       when is_integer(tag) and is_map(arg_pattern) do
    value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    tagged_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag} && (#{pattern_condition(value_ref, arg_pattern)}))"

    "(#{subject_ref}) && #{tagged_match}"
  end

  defp pattern_condition(subject_ref, %{kind: :constructor, tag: tag}) when is_integer(tag) do
    int_match = "((#{subject_ref})->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == #{tag})"

    tuple_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag})"

    "(#{subject_ref}) && (#{int_match} || #{tuple_match})"
  end

  defp pattern_condition(_subject_ref, _pattern), do: "0"

  @spec bind_pattern(map(), map(), term()) :: map()
  defp bind_pattern(env, %{kind: :wildcard}, _subject_ref), do: env

  defp bind_pattern(env, %{kind: :var, name: bind}, subject_ref) do
    Map.put(env, bind, pattern_subject_ref(subject_ref))
  end

  defp bind_pattern(env, %{kind: :tuple, elements: [left, right]}, subject_ref) do
    subject_ref = pattern_subject_ref(subject_ref)

    env
    |> bind_pattern(left, "((ElmcTuple2 *)#{subject_ref}->payload)->first")
    |> bind_pattern(right, "((ElmcTuple2 *)#{subject_ref}->payload)->second")
  end

  defp bind_pattern(
         env,
         %{kind: :constructor, name: "Ok", bind: bind, arg_pattern: arg},
         subject_ref
       ) do
    subject_ref = pattern_subject_ref(subject_ref)
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  defp bind_pattern(
         env,
         %{kind: :constructor, name: "Err", bind: bind, arg_pattern: arg},
         subject_ref
       ) do
    subject_ref = pattern_subject_ref(subject_ref)
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  defp bind_pattern(
         env,
         %{kind: :constructor, name: "Just", bind: bind, arg_pattern: arg},
         subject_ref
       ) do
    subject_ref = pattern_subject_ref(subject_ref)

    value_ref =
      "((#{subject_ref}->tag == ELMC_TAG_MAYBE) ? ((ElmcMaybe *)#{subject_ref}->payload)->value : ((ElmcTuple2 *)#{subject_ref}->payload)->second)"

    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  defp bind_pattern(
         env,
         %{
           kind: :constructor,
           name: "::",
           bind: bind,
           arg_pattern: %{kind: :tuple, elements: [head, tail]}
         },
         subject_ref
       ) do
    subject_ref = pattern_subject_ref(subject_ref)
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    env
    |> bind_pattern(head, "((ElmcCons *)#{subject_ref}->payload)->head")
    |> bind_pattern(tail, "((ElmcCons *)#{subject_ref}->payload)->tail")
  end

  defp bind_pattern(env, %{kind: :record, fields: fields, bind: bind}, subject_ref)
       when is_list(fields) do
    subject_ref = pattern_subject_ref(subject_ref)
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    Enum.reduce(fields, env, fn field, acc ->
      case field do
        "value" ->
          Map.put(acc, field, "((ElmcTuple2 *)#{subject_ref}->payload)->first")

        "temperature" ->
          Map.put(acc, field, "((ElmcTuple2 *)#{subject_ref}->payload)->second")

        name when is_binary(name) ->
          Map.put(acc, name, subject_ref)

        _ ->
          acc
      end
    end)
  end

  defp bind_pattern(
         env,
         %{kind: :constructor, tag: tag, bind: bind, arg_pattern: arg},
         subject_ref
       )
       when is_integer(tag) do
    subject_ref = pattern_subject_ref(subject_ref)
    value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"
    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  defp bind_pattern(env, _pattern, _subject_ref), do: env

  defp put_record_shape(env, _name, nil), do: env

  defp put_record_shape(env, name, fields) when is_binary(name) and is_list(fields) do
    shapes = Map.get(env, :__record_shapes__, %{})
    Map.put(env, :__record_shapes__, Map.put(shapes, name, fields))
  end

  defp put_record_shape(env, _name, _fields), do: env

  defp put_boxed_int_binding(env, name, true) when is_binary(name) or is_atom(name) do
    boxed_ints = Map.get(env, :__boxed_int_bindings__, MapSet.new())
    Map.put(env, :__boxed_int_bindings__, MapSet.put(boxed_ints, binding_key(name)))
  end

  defp put_boxed_int_binding(env, name, _is_int) when is_binary(name) or is_atom(name) do
    boxed_ints =
      env
      |> Map.get(:__boxed_int_bindings__, MapSet.new())
      |> MapSet.delete(binding_key(name))

    Map.put(env, :__boxed_int_bindings__, boxed_ints)
  end

  defp put_boxed_int_binding(env, _name, _is_int), do: env

  defp boxed_int_binding?(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__boxed_int_bindings__, MapSet.new())
    |> MapSet.member?(binding_key(name))
  end

  defp boxed_int_binding?(_env, _name), do: false

  defp put_boxed_string_binding(env, name, true) when is_binary(name) or is_atom(name) do
    boxed_strings = Map.get(env, :__boxed_string_bindings__, MapSet.new())
    Map.put(env, :__boxed_string_bindings__, MapSet.put(boxed_strings, binding_key(name)))
  end

  defp put_boxed_string_binding(env, name, _is_string) when is_binary(name) or is_atom(name) do
    boxed_strings =
      env
      |> Map.get(:__boxed_string_bindings__, MapSet.new())
      |> MapSet.delete(binding_key(name))

    Map.put(env, :__boxed_string_bindings__, boxed_strings)
  end

  defp put_boxed_string_binding(env, _name, _is_string), do: env

  defp boxed_string_binding?(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__boxed_string_bindings__, MapSet.new())
    |> MapSet.member?(binding_key(name))
  end

  defp boxed_string_binding?(_env, _name), do: false

  defp put_native_int_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_ints = Map.get(env, :__native_int_bindings__, %{})
    Map.put(env, :__native_int_bindings__, Map.put(native_ints, binding_key(name), ref))
  end

  defp put_native_int_binding(env, _name, _ref), do: env

  defp remove_native_int_binding(env, name) when is_binary(name) or is_atom(name) do
    native_ints =
      env
      |> Map.get(:__native_int_bindings__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__native_int_bindings__, native_ints)
  end

  defp remove_native_int_binding(env, _name), do: env

  defp native_int_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_int_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  defp native_int_binding(_env, _name), do: nil

  defp native_int_binding?(env, name) when is_binary(name) or is_atom(name),
    do: is_binary(native_int_binding(env, name))

  defp native_int_binding?(_env, _name), do: false

  defp put_native_float_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_floats = Map.get(env, :__native_float_bindings__, %{})
    Map.put(env, :__native_float_bindings__, Map.put(native_floats, binding_key(name), ref))
  end

  defp put_native_float_binding(env, _name, _ref), do: env

  defp remove_native_float_binding(env, name) when is_binary(name) or is_atom(name) do
    native_floats =
      env
      |> Map.get(:__native_float_bindings__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__native_float_bindings__, native_floats)
  end

  defp remove_native_float_binding(env, _name), do: env

  defp native_float_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_float_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  defp native_float_binding(_env, _name), do: nil

  defp put_pebble_angle_binding(env, name, expr)
       when (is_binary(name) or is_atom(name)) and is_map(expr) do
    bindings = Map.get(env, :__pebble_angle_bindings__, %{})
    Map.put(env, :__pebble_angle_bindings__, Map.put(bindings, binding_key(name), expr))
  end

  defp put_pebble_angle_binding(env, _name, _expr), do: env

  defp pebble_angle_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__pebble_angle_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  defp pebble_angle_binding(_env, _name), do: nil

  defp put_native_bool_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_bools = Map.get(env, :__native_bool_bindings__, %{})
    Map.put(env, :__native_bool_bindings__, Map.put(native_bools, binding_key(name), ref))
  end

  defp put_native_bool_binding(env, _name, _ref), do: env

  defp remove_native_bool_binding(env, name) when is_binary(name) or is_atom(name) do
    native_bools =
      env
      |> Map.get(:__native_bool_bindings__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__native_bool_bindings__, native_bools)
  end

  defp remove_native_bool_binding(env, _name), do: env

  defp native_bool_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_bool_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  defp native_bool_binding(_env, _name), do: nil

  defp put_native_string_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_strings = Map.get(env, :__native_string_bindings__, %{})
    Map.put(env, :__native_string_bindings__, Map.put(native_strings, binding_key(name), ref))
  end

  defp put_native_string_binding(env, _name, _ref), do: env

  defp native_string_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_string_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  defp native_string_binding(_env, _name), do: nil

  defp function_let_classification(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__function_analysis__, %{})
    |> Map.get(name, :boxed)
  end

  defp function_let_classification(_env, _name), do: :boxed

  @spec pattern_subject_ref(term()) :: String.t()
  defp pattern_subject_ref(subject_ref) when is_binary(subject_ref), do: subject_ref
  defp pattern_subject_ref(%{op: :var, name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"op" => :var, "name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(subject_ref), do: inspect(subject_ref)

  defp record_shape_for_var(env, name) when is_binary(name) do
    env
    |> Map.get(:__record_shapes__, %{})
    |> Map.get(name)
  end

  defp record_shape(%{op: :record_literal, fields: fields}, _env) when is_list(fields) do
    fields
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp record_shape(%{op: :record_update, base: base}, env), do: record_shape(base, env)

  defp record_shape(%{op: :var, name: name}, env) do
    record_shape_for_var(env, name) ||
      record_shape_for_function_return({Map.get(env, :__module__, "Main"), name}, env, 0)
  end

  defp record_shape(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    record_shape_for_function_return(
      {Map.get(env, :__module__, "Main"), name},
      env,
      length(args || [])
    )
  end

  defp record_shape(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    normalized = normalize_special_target(target)

    case special_value_from_target(normalized, args || []) do
      nil ->
        normalized
        |> split_qualified_function_target()
        |> record_shape_for_function_return(env, length(args || []))

      rewritten ->
        record_shape(rewritten, env)
    end
  end

  defp record_shape(
         %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default, _maybe]},
         env
       ) do
    record_shape(default, env)
  end

  defp record_shape(_expr, _env), do: nil

  defp record_shape_for_function_return(nil, _env, _arg_count), do: nil

  defp record_shape_for_function_return(target_key, env, arg_count) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target_key) do
      %{type: type} ->
        if length(function_arg_types(type)) == arg_count do
          record_shape_for_type(function_return_type(type), env)
        end

      _ ->
        nil
    end
  end

  defp record_shape_for_type(type, env) when is_binary(type) do
    type_name = normalize_type_name(type)
    current_module = Map.get(env, :__module__, "Main")

    alias_shapes =
      Map.get(env, :__record_alias_shapes__) || Process.get(:elmc_record_alias_shapes, %{})

    cond do
      Map.has_key?(alias_shapes, {current_module, type_name}) ->
        Map.get(alias_shapes, {current_module, type_name})

      String.contains?(type_name, ".") ->
        case split_qualified_type_name(type_name) do
          nil -> nil
          target_key -> Map.get(alias_shapes, target_key)
        end

      true ->
        nil
    end
  end

  defp record_shape_for_type(_type, _env), do: nil

  defp split_qualified_type_name(type_name) when is_binary(type_name) do
    case String.split(type_name, ".") do
      [_single] ->
        nil

      parts ->
        {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}
    end
  end

  defp record_get_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get(#{source}, \"#{escape_c_string(field)}\")"

      index ->
        "elmc_record_get_index(#{source}, #{index} /* #{escape_c_comment(field)} */)"
    end
  end

  defp record_get_expr(source, field, _fields) do
    "elmc_record_get(#{source}, \"#{escape_c_string(field)}\")"
  end

  defp record_get_int_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_int(#{source}, \"#{escape_c_string(field)}\")"

      index ->
        "ELMC_RECORD_GET_INDEX_INT(#{source}, #{index} /* #{escape_c_comment(field)} */)"
    end
  end

  defp record_get_int_expr(source, field, _fields) do
    "elmc_record_get_int(#{source}, \"#{escape_c_string(field)}\")"
  end

  defp record_get_maybe_int_expr(source, field, fields, default_ref) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_maybe_int(#{source}, \"#{escape_c_string(field)}\", #{default_ref})"

      index ->
        "elmc_record_get_index_maybe_int(#{source}, #{index} /* #{escape_c_comment(field)} */, #{default_ref})"
    end
  end

  defp record_get_maybe_int_expr(source, field, _fields, default_ref) do
    "elmc_record_get_maybe_int(#{source}, \"#{escape_c_string(field)}\", #{default_ref})"
  end

  defp record_get_bool_expr(source, field, fields) when is_list(fields) do
    case Enum.find_index(fields, &(&1 == field)) do
      nil ->
        "elmc_record_get_bool(#{source}, \"#{escape_c_string(field)}\")"

      index ->
        "elmc_record_get_index_bool(#{source}, #{index} /* #{escape_c_comment(field)} */)"
    end
  end

  defp record_get_bool_expr(source, field, _fields) do
    "elmc_record_get_bool(#{source}, \"#{escape_c_string(field)}\")"
  end

  defp unary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: function, args: [%{op: :var, name: "__x"}]}
    }
  end

  defp binary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [%{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
      }
    }
  end

  defp bound_binary_runtime_lambda(function, first) do
    %{
      op: :lambda,
      args: ["__b"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, %{op: :var, name: "__b"}]
      }
    }
  end

  defp ternary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__a", "__b", "__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [
          %{op: :var, name: "__a"},
          %{op: :var, name: "__b"},
          %{op: :var, name: "__c"}
        ]
      }
    }
  end

  defp bound_ternary_runtime_lambda(function, first) do
    %{
      op: :lambda,
      args: ["__b", "__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, %{op: :var, name: "__b"}, %{op: :var, name: "__c"}]
      }
    }
  end

  defp bound_ternary_runtime_lambda(function, first, second) do
    %{
      op: :lambda,
      args: ["__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, second, %{op: :var, name: "__c"}]
      }
    }
  end

  @spec compile_builtin_operator_call(term(), term(), term(), term()) :: term()
  defp compile_builtin_operator_call("e", [], env, counter),
    do: compile_expr(%{op: :float_literal, value: 2.718281828459045}, env, counter)

  defp compile_builtin_operator_call("pi", [], env, counter),
    do: compile_expr(%{op: :float_literal, value: 3.141592653589793}, env, counter)

  defp compile_builtin_operator_call("LT", [], env, counter),
    do: compile_expr(%{op: :int_literal, value: -1}, env, counter)

  defp compile_builtin_operator_call("EQ", [], env, counter),
    do: compile_expr(%{op: :int_literal, value: 0}, env, counter)

  defp compile_builtin_operator_call("GT", [], env, counter),
    do: compile_expr(%{op: :int_literal, value: 1}, env, counter)

  defp compile_builtin_operator_call("__add__", [left, right], env, counter),
    do: compile_int_binop(left, right, "+", env, counter)

  defp compile_builtin_operator_call("__add__", args, env, counter) when length(args) in [0, 1],
    do: compile_curried_binary_builtin("__add__", args, env, counter)

  defp compile_builtin_operator_call("__sub__", [left, right], env, counter),
    do: compile_int_binop(left, right, "-", env, counter)

  defp compile_builtin_operator_call("__sub__", args, env, counter) when length(args) in [0, 1],
    do: compile_curried_binary_builtin("__sub__", args, env, counter)

  defp compile_builtin_operator_call("__mul__", [left, right], env, counter),
    do: compile_int_binop(left, right, "*", env, counter)

  defp compile_builtin_operator_call("__mul__", args, env, counter) when length(args) in [0, 1],
    do: compile_curried_binary_builtin("__mul__", args, env, counter)

  defp compile_builtin_operator_call("__pow__", [base, exponent], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_pow", args: [base, exponent]},
        env,
        counter
      )

  defp compile_builtin_operator_call("__pow__", args, env, counter) when length(args) in [0, 1],
    do: compile_curried_binary_builtin("__pow__", args, env, counter)

  defp compile_builtin_operator_call("__fdiv__", [left, right], env, counter),
    do: compile_float_div(left, right, env, counter)

  defp compile_builtin_operator_call("__fdiv__", args, env, counter) when length(args) in [0, 1],
    do: compile_curried_binary_builtin("__fdiv__", args, env, counter)

  defp compile_builtin_operator_call("__idiv__", [left, right], env, counter),
    do: compile_int_idiv(left, right, env, counter)

  defp compile_builtin_operator_call("__idiv__", args, env, counter) when length(args) in [0, 1],
    do: compile_curried_binary_builtin("__idiv__", args, env, counter)

  defp compile_builtin_operator_call("__append__", [left, right], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]},
        env,
        counter
      )

  defp compile_builtin_operator_call("__append__", args, env, counter)
       when length(args) in [0, 1],
       do: compile_curried_binary_builtin("__append__", args, env, counter)

  defp compile_builtin_operator_call(name, [left, right], env, counter)
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"],
       do: compile_compare_operator(left, right, name, env, counter)

  defp compile_builtin_operator_call(name, args, env, counter)
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] and
              length(args) in [0, 1],
       do: compile_curried_binary_builtin(name, args, env, counter)

  defp compile_builtin_operator_call("modBy", [base, value], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
        env,
        counter
      )

  defp compile_builtin_operator_call("remainderBy", [base, value], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
        env,
        counter
      )

  defp compile_builtin_operator_call("round", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_round", args: [x]}, env, counter)

  defp compile_builtin_operator_call("floor", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_floor", args: [x]}, env, counter)

  defp compile_builtin_operator_call("ceiling", [x], env, counter),
    do:
      compile_expr(%{op: :runtime_call, function: "elmc_basics_ceiling", args: [x]}, env, counter)

  defp compile_builtin_operator_call("truncate", [x], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_truncate", args: [x]},
        env,
        counter
      )

  defp compile_builtin_operator_call("toFloat", [x], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_to_float", args: [x]},
        env,
        counter
      )

  defp compile_builtin_operator_call("sqrt", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_sqrt", args: [x]}, env, counter)

  defp compile_builtin_operator_call("logBase", [base, x], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_log_base", args: [base, x]},
        env,
        counter
      )

  defp compile_builtin_operator_call("sin", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_sin", args: [x]}, env, counter)

  defp compile_builtin_operator_call("cos", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_cos", args: [x]}, env, counter)

  defp compile_builtin_operator_call("tan", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_tan", args: [x]}, env, counter)

  defp compile_builtin_operator_call("acos", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_acos", args: [x]}, env, counter)

  defp compile_builtin_operator_call("asin", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_asin", args: [x]}, env, counter)

  defp compile_builtin_operator_call("atan", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_atan", args: [x]}, env, counter)

  defp compile_builtin_operator_call("atan2", [y, x], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_atan2", args: [y, x]},
        env,
        counter
      )

  defp compile_builtin_operator_call("degrees", [x], env, counter),
    do:
      compile_expr(%{op: :runtime_call, function: "elmc_basics_degrees", args: [x]}, env, counter)

  defp compile_builtin_operator_call("radians", [x], env, counter),
    do:
      compile_expr(%{op: :runtime_call, function: "elmc_basics_radians", args: [x]}, env, counter)

  defp compile_builtin_operator_call("turns", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_turns", args: [x]}, env, counter)

  defp compile_builtin_operator_call("fromPolar", [polar], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_from_polar", args: [polar]},
        env,
        counter
      )

  defp compile_builtin_operator_call("toPolar", [point], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_to_polar", args: [point]},
        env,
        counter
      )

  defp compile_builtin_operator_call("isNaN", [x], env, counter),
    do:
      compile_expr(%{op: :runtime_call, function: "elmc_basics_is_nan", args: [x]}, env, counter)

  defp compile_builtin_operator_call("isInfinite", [x], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_is_infinite", args: [x]},
        env,
        counter
      )

  defp compile_builtin_operator_call("abs", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_abs", args: [x]}, env, counter)

  defp compile_builtin_operator_call("negate", [x], env, counter),
    do:
      compile_expr(%{op: :runtime_call, function: "elmc_basics_negate", args: [x]}, env, counter)

  defp compile_builtin_operator_call("not", [x], env, counter),
    do: compile_expr(%{op: :runtime_call, function: "elmc_basics_not", args: [x]}, env, counter)

  defp compile_builtin_operator_call("xor", [a, b], env, counter),
    do:
      compile_expr(%{op: :runtime_call, function: "elmc_basics_xor", args: [a, b]}, env, counter)

  defp compile_builtin_operator_call("compare", [a, b], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_compare", args: [a, b]},
        env,
        counter
      )

  defp compile_builtin_operator_call("max", [left, right], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_max", args: [left, right]},
        env,
        counter
      )

  defp compile_builtin_operator_call("min", [left, right], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_min", args: [left, right]},
        env,
        counter
      )

  defp compile_builtin_operator_call("clamp", [low, high, value], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_clamp", args: [low, high, value]},
        env,
        counter
      )

  defp compile_builtin_operator_call(_name, _args, _env, _counter), do: nil

  @spec compile_curried_binary_builtin(String.t(), [term()], term(), term()) :: term()
  defp compile_curried_binary_builtin(name, [], env, counter) do
    compile_expr(
      %{
        op: :lambda,
        args: ["__left", "__right"],
        body: %{
          op: :call,
          name: name,
          args: [%{op: :var, name: "__left"}, %{op: :var, name: "__right"}]
        }
      },
      env,
      counter
    )
  end

  defp compile_curried_binary_builtin(name, [left], env, counter) do
    compile_expr(
      %{
        op: :lambda,
        args: ["__right"],
        body: %{op: :call, name: name, args: [left, %{op: :var, name: "__right"}]}
      },
      env,
      counter
    )
  end

  @spec compile_int_binop(term(), term(), term(), term(), term()) :: term()
  defp compile_int_binop(
         %{op: :int_literal, value: left},
         %{op: :int_literal, value: right},
         operator,
         _env,
         counter
       )
       when operator in ["+", "-", "*"] do
    value =
      case operator do
        "+" -> left + right
        "-" -> left - right
        "*" -> left * right
      end

    compile_expr(%{op: :int_literal, value: value}, %{}, counter)
  end

  defp compile_int_binop(left, right, operator, env, counter) do
    cond do
      native_int_expr?(left, env) and native_int_expr?(right, env) ->
        {left_code, left_var, counter} = compile_native_int_expr(left, env, counter)
        {right_code, right_var, counter} = compile_native_int_expr(right, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        code = """
        #{left_code}
          #{right_code}
          ElmcValue *#{out} = elmc_new_int(#{left_var} #{operator} #{right_var});
        """

        {code, out, next}

      native_float_expr?(left, env) and native_float_expr?(right, env) ->
        compile_native_float_boxed(
          %{op: :call, name: float_operator_name(operator), args: [left, right]},
          env,
          counter
        )

      true ->
        {left_code, left_var, counter} = compile_expr(left, env, counter)
        {right_code, right_var, counter} = compile_expr(right, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        code = """
        #{left_code}
          #{right_code}
          ElmcValue *#{out} =
              ((#{left_var} && #{left_var}->tag == ELMC_TAG_FLOAT) || (#{right_var} && #{right_var}->tag == ELMC_TAG_FLOAT))
                  ? elmc_new_float(elmc_as_float(#{left_var}) #{operator} elmc_as_float(#{right_var}))
                  : elmc_new_int(elmc_as_int(#{left_var}) #{operator} elmc_as_int(#{right_var}));
          elmc_release(#{left_var});
          elmc_release(#{right_var});
        """

        {code, out, next}
    end
  end

  @spec compile_int_idiv(term(), term(), term(), term()) :: term()
  defp compile_int_idiv(left, right, env, counter) do
    {left_code, left_var, counter} = compile_native_int_expr(left, env, counter)

    {code, out, counter} =
      case static_nonzero_int_value(right) do
        value when is_integer(value) ->
          next = counter + 1
          out = "tmp_#{next}"

          """
          #{left_code}
            ElmcValue *#{out} = elmc_new_int(#{left_var} / #{value});
          """
          |> then(&{&1, out, next})

        nil ->
          {right_code, right_var, counter} = compile_native_int_expr(right, env, counter)
          next = counter + 1
          out = "tmp_#{next}"

          """
          #{left_code}
            #{right_code}
            const elmc_int_t __den_#{next} = #{right_var};
            ElmcValue *#{out} = elmc_new_int(__den_#{next} == 0 ? 0 : (#{left_var} / __den_#{next}));
          """
          |> then(&{&1, out, next})
      end

    {code, out, counter}
  end

  defp compile_native_int_boxed(expr, env, counter) do
    {code, value_ref, counter} = compile_native_int_expr(expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {
      """
      #{code}
        ElmcValue *#{out} = elmc_new_int(#{value_ref});
      """,
      out,
      next
    }
  end

  defp compile_native_int_expr(%{op: :int_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  defp compile_native_int_expr(%{op: :char_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  defp compile_native_int_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    if native_int_expr?(then_expr, env) and native_int_expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
      {then_code, then_ref, counter} = compile_native_int_expr(then_expr, env, counter)
      {else_code, else_ref, counter} = compile_native_int_expr(else_expr, env, counter)
      next = counter + 1
      out = "native_if_#{next}"

      code = """
      #{cond_code}
        elmc_int_t #{out};
        if (#{cond_ref}) {
      #{indent(then_code, 4)}
          #{out} = #{then_ref};
        } else {
      #{indent(else_code, 4)}
          #{out} = #{else_ref};
        }
      """

      {code, out, next}
    else
      compile_native_int_fallback(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      )
    end
  end

  defp compile_native_int_expr(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, source} when is_binary(source) ->
        getter = record_get_int_expr(source, field, record_shape_for_var(env, arg))

        before_probe =
          env |> battery_alert_field_probe(arg, field, :before) |> agent_probe_region()

        after_probe = env |> battery_alert_field_probe(arg, field, :after) |> agent_probe_region()

        if before_probe == "" and after_probe == "" do
          {"", getter, counter}
        else
          next = counter + 1
          out = "native_field_probe_#{next}"

          code = """
          #{before_probe}
            const elmc_int_t #{out} = #{getter};
          #{after_probe}
          """

          {code, out, next}
        end

      :error ->
        compile_native_int_fallback(%{op: :field_access, arg: arg, field: field}, env, counter)
    end
  end

  defp compile_native_int_expr(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         env,
         counter
       ) do
    compile_native_int_expr(%{op: :field_access, arg: name, field: field}, env, counter)
  end

  defp compile_native_int_expr(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    case inline_record_field_expr(arg_expr, field, env) do
      nil ->
        {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
        next = counter + 1
        out = "native_field_#{next}"
        getter = record_get_int_expr(arg_var, field, record_shape(arg_expr, env))

        before_probe =
          env |> battery_alert_field_probe(nil, field, :before) |> agent_probe_region()

        after_probe = env |> battery_alert_field_probe(nil, field, :after) |> agent_probe_region()

        code = """
        #{arg_code}
        #{before_probe}
          const elmc_int_t #{out} = #{getter};
        #{after_probe}
          elmc_release(#{arg_var});
        """

        {code, out, next}

      field_expr ->
        compile_native_int_expr(field_expr, env, counter)
    end
  end

  defp compile_native_int_expr(%{op: :var, name: name} = expr, env, counter) do
    case native_int_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            if boxed_int_binding?(env, name) do
              {"", "elmc_as_int(#{source})", counter}
            else
              {"", "(#{source} ? elmc_as_int(#{source}) : 0)", counter}
            end

          _ ->
            compile_native_int_fallback(expr, env, counter)
        end
    end
  end

  defp compile_native_int_expr(%{op: :add_const, var: name, value: value}, env, counter) do
    compile_native_int_expr(
      %{
        op: :call,
        name: "__add__",
        args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
      },
      env,
      counter
    )
  end

  defp compile_native_int_expr(%{op: :sub_const, var: name, value: value}, env, counter) do
    compile_native_int_expr(
      %{
        op: :call,
        name: "__sub__",
        args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
      },
      env,
      counter
    )
  end

  defp compile_native_int_expr(%{op: :add_vars, left: left, right: right}, env, counter) do
    compile_native_int_expr(
      %{op: :call, name: "__add__", args: [%{op: :var, name: left}, %{op: :var, name: right}]},
      env,
      counter
    )
  end

  defp compile_native_int_expr(%{op: :call, name: name, args: [left, right]}, env, counter)
       when name in ["__add__", "__sub__", "__mul__"] do
    op = %{"__add__" => "+", "__sub__" => "-", "__mul__" => "*"}[name]
    {left_code, left_ref, counter} = compile_native_int_expr(left, env, counter)
    {right_code, right_ref, counter} = compile_native_int_expr(right, env, counter)
    {left_code <> right_code, "(#{left_ref} #{op} #{right_ref})", counter}
  end

  defp compile_native_int_expr(%{op: :call, name: "__idiv__", args: [left, right]}, env, counter) do
    {left_code, left_ref, counter} = compile_native_int_expr(left, env, counter)

    case static_nonzero_int_value(right) do
      value when is_integer(value) ->
        {left_code, "(#{left_ref} / #{value})", counter}

      nil ->
        {right_code, right_ref, counter} = compile_native_int_expr(right, env, counter)
        next = counter + 1
        denom = "native_den_#{next}"

        code = """
        #{left_code}#{right_code}
          const elmc_int_t #{denom} = #{right_ref};
        """

        {code, "(#{denom} == 0 ? 0 : (#{left_ref} / #{denom}))", next}
    end
  end

  defp compile_native_int_expr(%{op: :call, name: name, args: [left, right]}, env, counter)
       when name in ["min", "max"] do
    {left_code, left_ref, counter} = compile_native_int_expr(left, env, counter)
    {right_code, right_ref, counter} = compile_native_int_expr(right, env, counter)
    next = counter + 1
    left_var = "native_#{name}_left_#{next}"
    right_var = "native_#{name}_right_#{next}"
    out = "native_#{name}_#{next}"
    cmp_op = if name == "min", do: "<=", else: ">="

    code = """
    #{left_code}
    #{right_code}
      const elmc_int_t #{left_var} = #{left_ref};
      const elmc_int_t #{right_var} = #{right_ref};
      const elmc_int_t #{out} = (#{left_var} #{cmp_op} #{right_var}) ? #{left_var} : #{right_var};
    """

    {code, out, next}
  end

  defp compile_native_int_expr(%{op: :call, name: name, args: [value]}, env, counter)
       when name in ["abs", "negate"] do
    {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
    next = counter + 1
    value_var = "native_#{name}_arg_#{next}"
    out = "native_#{name}_#{next}"

    expr =
      case name do
        "abs" -> "(#{value_var} < 0 ? -#{value_var} : #{value_var})"
        "negate" -> "(-#{value_var})"
      end

    code = """
    #{value_code}
      const elmc_int_t #{value_var} = #{value_ref};
      const elmc_int_t #{out} = #{expr};
    """

    {code, out, next}
  end

  defp compile_native_int_expr(%{op: :call, name: "modBy", args: [base, value]}, env, counter) do
    case static_nonzero_int_value(base) do
      base_value when is_integer(base_value) ->
        {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
        next = counter + 1
        out = "native_mod_#{next}"
        correction = abs(base_value)

        code = """
        #{value_code}
          elmc_int_t #{out} = #{value_ref} % #{base_value};
          if (#{out} < 0) #{out} += #{correction};
        """

        {code, out, next}

      nil ->
        {base_code, base_ref, counter} = compile_native_int_expr(base, env, counter)
        {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
        next = counter + 1
        base_var = "native_mod_base_#{next}"
        out = "native_mod_#{next}"

        code = """
        #{base_code}#{value_code}
          const elmc_int_t #{base_var} = #{base_ref};
          elmc_int_t #{out} = 0;
          if (#{base_var} != 0) {
            #{out} = #{value_ref} % #{base_var};
            if (#{out} < 0) #{out} += (#{base_var} < 0 ? -#{base_var} : #{base_var});
          }
        """

        {code, out, next}
    end
  end

  defp compile_native_int_expr(
         %{op: :call, name: "remainderBy", args: [base, value]},
         env,
         counter
       ) do
    {base_code, base_ref, counter} = compile_native_int_expr(base, env, counter)
    {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
    next = counter + 1
    base_var = "native_rem_base_#{next}"

    code = """
    #{base_code}#{value_code}
      const elmc_int_t #{base_var} = #{base_ref};
    """

    {code, "(#{base_var} == 0 ? 0 : (#{value_ref} % #{base_var}))", next}
  end

  defp compile_native_int_expr(%{op: :call, name: name, args: args} = expr, env, counter)
       when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")

    case compile_native_int_inline_function({module_name, name}, args, env, counter) do
      {:ok, code, value_ref, counter} -> {code, value_ref, counter}
      :error -> compile_native_int_fallback(expr, env, counter)
    end
  end

  defp compile_native_int_expr(
         %{op: :qualified_call, target: target, args: args} = expr,
         env,
         counter
       ) do
    case special_value_from_target(target, args) do
      %{op: :int_literal, value: value} ->
        {"", "#{value}", counter}

      %{op: :char_literal, value: value} ->
        {"", "#{value}", counter}

      nil ->
        case qualified_builtin_operator_name(target) do
          builtin
          when builtin in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] ->
            compile_native_int_expr(%{op: :call, name: builtin, args: args}, env, counter)

          _ ->
            case split_qualified_function_target(normalize_special_target(target)) do
              nil ->
                compile_native_int_fallback(expr, env, counter)

              target_key ->
                case compile_native_int_inline_function(target_key, args, env, counter) do
                  {:ok, code, value_ref, counter} -> {code, value_ref, counter}
                  :error -> compile_native_int_fallback(expr, env, counter)
                end
            end
        end

      rewritten ->
        compile_native_int_expr(rewritten, env, counter)
    end
  end

  defp compile_native_int_expr(
         %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
         env,
         counter
       ),
       do: compile_native_int_expr(%{op: :call, name: "modBy", args: [base, value]}, env, counter)

  defp compile_native_int_expr(
         %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
         env,
         counter
       ),
       do:
         compile_native_int_expr(
           %{op: :call, name: "remainderBy", args: [base, value]},
           env,
           counter
         )

  defp compile_native_int_expr(
         %{op: :runtime_call, function: function, args: [left, right]},
         env,
         counter
       )
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    compile_native_int_expr(
      %{op: :call, name: native_min_max_name(function), args: [left, right]},
      env,
      counter
    )
  end

  defp compile_native_int_expr(
         %{op: :runtime_call, function: function, args: [value]},
         env,
         counter
       )
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    compile_native_int_expr(
      %{op: :call, name: native_unary_int_name(function), args: [value]},
      env,
      counter
    )
  end

  defp compile_native_int_expr(
         %{op: :runtime_call, function: function, args: [value]},
         env,
         counter
       )
       when function in [
              "elmc_basics_round",
              "elmc_basics_floor",
              "elmc_basics_ceiling",
              "elmc_basics_truncate"
            ] do
    case function == "elmc_basics_round" and compile_pebble_trig_round(value, env, counter) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      _ ->
        compile_native_float_to_int_expr(function, value, env, counter)
    end
  end

  defp compile_native_int_expr(
         %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, maybe]},
         env,
         counter
       ) do
    {default_code, default_ref, counter} = compile_native_int_expr(default_val, env, counter)

    {maybe_code, maybe_ref, release_maybe, counter} =
      case maybe do
        %{op: :field_access, arg: arg, field: field} when is_binary(arg) ->
          case Map.fetch(env, arg) do
            {:ok, source} when is_binary(source) ->
              getter =
                record_get_maybe_int_expr(
                  source,
                  field,
                  record_shape_for_var(env, arg),
                  default_ref
                )

              {"", getter, false, counter}

            :error ->
              {code, var, counter} = compile_expr(maybe, env, counter)
              {code, "elmc_maybe_with_default_int(#{default_ref}, #{var})", var, counter}
          end

        %{op: :field_access, arg: %{op: :var, name: name}, field: field} when is_binary(name) ->
          case Map.fetch(env, name) do
            {:ok, source} when is_binary(source) ->
              getter =
                record_get_maybe_int_expr(
                  source,
                  field,
                  record_shape_for_var(env, name),
                  default_ref
                )

              {"", getter, false, counter}

            :error ->
              {code, var, counter} = compile_expr(maybe, env, counter)
              {code, "elmc_maybe_with_default_int(#{default_ref}, #{var})", var, counter}
          end

        _ ->
          {code, var, counter} = compile_expr(maybe, env, counter)
          {code, "elmc_maybe_with_default_int(#{default_ref}, #{var})", var, counter}
      end

    next = counter + 1
    out = "native_maybe_default_#{next}"

    release_code =
      if is_binary(release_maybe), do: "\n  elmc_release(#{release_maybe});", else: ""

    code = """
    #{default_code}
    #{maybe_code}
      const elmc_int_t #{out} = #{maybe_ref};#{release_code}
    """

    {code, out, next}
  end

  defp compile_native_int_expr(expr, env, counter),
    do: compile_native_int_fallback(expr, env, counter)

  defp compile_native_float_to_int_expr(function, value, env, counter) do
    if native_float_expr?(value, env) do
      {value_code, value_ref, counter} = compile_native_float_expr(value, env, counter)
      next = counter + 1
      value_var = "native_float_arg_#{next}"
      out = "native_float_to_int_#{next}"

      expr =
        case function do
          "elmc_basics_round" ->
            "(elmc_int_t)(#{value_var} + (#{value_var} >= 0 ? 0.5 : -0.5))"

          "elmc_basics_floor" ->
            "((elmc_int_t)#{value_var} > #{value_var} ? (elmc_int_t)#{value_var} - 1 : (elmc_int_t)#{value_var})"

          "elmc_basics_ceiling" ->
            "((elmc_int_t)#{value_var} < #{value_var} ? (elmc_int_t)#{value_var} + 1 : (elmc_int_t)#{value_var})"

          "elmc_basics_truncate" ->
            "(elmc_int_t)#{value_var}"
        end

      code = """
      #{value_code}
        const double #{value_var} = #{value_ref};
        const elmc_int_t #{out} = #{expr};
      """

      {code, out, next}
    else
      compile_native_int_fallback(
        %{op: :runtime_call, function: function, args: [value]},
        env,
        counter
      )
    end
  end

  defp compile_pebble_trig_round(
         %{op: :call, name: "__mul__", args: [left, right]},
         env,
         counter
       ) do
    cond do
      trig = pebble_bound_trig_expr(left, env) ->
        compile_pebble_trig_round_expr(trig, right, env, counter)

      trig = pebble_bound_trig_expr(right, env) ->
        compile_pebble_trig_round_expr(trig, left, env, counter)

      true ->
        :error
    end
  end

  defp compile_pebble_trig_round(_expr, _env, _counter), do: :error

  defp compile_pebble_trig_round_expr(
         {trig_function, angle_expr},
         radius_float_expr,
         env,
         counter
       ) do
    with {:ok, radius_expr} <- to_float_arg(radius_float_expr),
         {:ok, angle_source_expr} <- pebble_angle_source(angle_expr) do
      {angle_code, angle_ref, counter} = compile_native_int_expr(angle_source_expr, env, counter)
      {radius_code, radius_ref, counter} = compile_native_int_expr(radius_expr, env, counter)
      next = counter + 1
      trig_var = "native_trig_#{next}"
      prod_var = "native_trig_prod_#{next}"
      out = "native_trig_round_#{next}"
      c_trig = if trig_function == :sin, do: "sin_lookup", else: "cos_lookup"

      double_trig =
        if trig_function == :sin,
          do: "generated_trig_sin_double",
          else: "generated_trig_cos_double"

      code = """
      #{angle_code}
      #{radius_code}
      #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
        const int32_t #{trig_var} = #{c_trig}((int32_t)#{angle_ref});
        const int32_t #{prod_var} = #{trig_var} * (int32_t)#{radius_ref};
        const elmc_int_t #{out} = (#{prod_var} + (#{prod_var} >= 0 ? (TRIG_MAX_RATIO / 2) : -(TRIG_MAX_RATIO / 2))) / TRIG_MAX_RATIO;
      #else
        const double native_trig_theta_#{next} = ((((double)#{angle_ref} * (double)2) * 3.141592653589793) / (double)65536);
        const double native_trig_arg_#{next} = #{double_trig}(native_trig_theta_#{next}) * (double)#{radius_ref};
        const elmc_int_t #{out} = (elmc_int_t)(native_trig_arg_#{next} + (native_trig_arg_#{next} >= 0 ? 0.5 : -0.5));
      #endif
      """

      {:ok, code, out, next}
    else
      _ -> :error
    end
  end

  defp pebble_bound_trig_expr(
         %{op: :qualified_call, target: target, args: [%{op: :var, name: name}]},
         env
       )
       when target in ["Basics.sin", "sin", "Basics.cos", "cos"] do
    case pebble_angle_binding(env, name) do
      nil -> nil
      angle_expr -> {if(target in ["Basics.sin", "sin"], do: :sin, else: :cos), angle_expr}
    end
  end

  defp pebble_bound_trig_expr(
         %{op: :runtime_call, function: function, args: [%{op: :var, name: name}]},
         env
       )
       when function in ["elmc_basics_sin", "elmc_basics_cos"] do
    case pebble_angle_binding(env, name) do
      nil -> nil
      angle_expr -> {if(function == "elmc_basics_sin", do: :sin, else: :cos), angle_expr}
    end
  end

  defp pebble_bound_trig_expr(_expr, _env), do: nil

  defp pebble_bound_trig_round_expr?(%{op: :call, name: "__mul__", args: [left, right]}, env) do
    (pebble_bound_trig_expr(left, env) && match?({:ok, _}, to_float_arg(right))) ||
      (pebble_bound_trig_expr(right, env) && match?({:ok, _}, to_float_arg(left)))
  end

  defp pebble_bound_trig_round_expr?(_expr, _env), do: false

  defp to_float_arg(%{op: :qualified_call, target: target, args: [value]})
       when target in ["Basics.toFloat", "toFloat"],
       do: {:ok, value}

  defp to_float_arg(%{op: :runtime_call, function: "elmc_basics_to_float", args: [value]}),
    do: {:ok, value}

  defp to_float_arg(_expr), do: :error

  defp pebble_angle_source(%{
         op: :call,
         name: "__fdiv__",
         args: [numerator, %{op: :int_literal, value: 65_536}]
       }),
       do: pebble_angle_numerator_source(numerator)

  defp pebble_angle_source(_expr), do: :error

  defp pebble_angle_numerator_source(%{op: :call, name: "__mul__", args: [left, right]}) do
    cond do
      pi_expr?(left) -> double_to_float_source(right)
      pi_expr?(right) -> double_to_float_source(left)
      true -> :error
    end
  end

  defp pebble_angle_numerator_source(_expr), do: :error

  defp double_to_float_source(%{
         op: :call,
         name: "__mul__",
         args: [left, %{op: :int_literal, value: 2}]
       }),
       do: to_float_arg(left)

  defp double_to_float_source(%{
         op: :call,
         name: "__mul__",
         args: [%{op: :int_literal, value: 2}, right]
       }),
       do: to_float_arg(right)

  defp double_to_float_source(_expr), do: :error

  defp compile_native_int_inline_function(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})
    inline_stack = Map.get(env, :__native_int_inline_stack__, MapSet.new())

    with %{args: arg_names, expr: body} when is_list(arg_names) <- Map.get(decl_map, target_key),
         true <- length(arg_names) == length(args),
         false <- MapSet.member?(inline_stack, target_key),
         substituted <- substitute_expr(body, Map.new(Enum.zip(arg_names, args))),
         true <- native_int_expr?(substituted, env) do
      env =
        Map.put(
          env,
          :__native_int_inline_stack__,
          MapSet.put(inline_stack, target_key)
        )

      {code, value_ref, counter} = compile_native_int_expr(substituted, env, counter)
      code = code <> "  // inlined #{format_function_target(target_key)}\n"
      {:ok, code, value_ref, counter}
    else
      _ -> :error
    end
  end

  defp format_function_target({module_name, function_name}), do: "#{module_name}.#{function_name}"
  defp format_function_target(other), do: inspect(other)

  defp native_min_max_name("elmc_basics_min"), do: "min"
  defp native_min_max_name("elmc_basics_max"), do: "max"

  defp native_unary_int_name("elmc_basics_abs"), do: "abs"
  defp native_unary_int_name("elmc_basics_negate"), do: "negate"

  defp float_operator_name("+"), do: "__add__"
  defp float_operator_name("-"), do: "__sub__"
  defp float_operator_name("*"), do: "__mul__"

  defp compile_native_int_fallback(expr, env, counter) do
    {code, var, counter} = compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_i_#{next}"

    {
      """
      #{code}
        const elmc_int_t #{out} = elmc_as_int(#{var});
        elmc_release(#{var});
      """,
      out,
      next
    }
  end

  defp compile_native_float_boxed(expr, env, counter) do
    {code, value_ref, counter} = compile_native_float_expr(expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {
      """
      #{code}
        ElmcValue *#{out} = elmc_new_float(#{value_ref});
      """,
      out,
      next
    }
  end

  defp compile_native_float_expr(%{op: :float_literal, value: value}, _env, counter) do
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {"", float_val, counter}
  end

  defp compile_native_float_expr(%{op: op, value: value}, _env, counter)
       when op in [:int_literal, :char_literal] do
    {"", "(double)#{value}", counter}
  end

  defp compile_native_float_expr(%{op: :var, name: name} = expr, env, counter) do
    case native_float_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case native_int_binding(env, name) do
          native_ref when is_binary(native_ref) ->
            {"", "(double)#{native_ref}", counter}

          nil ->
            compile_native_float_fallback(expr, env, counter)
        end
    end
  end

  defp compile_native_float_expr(%{op: :call, name: name, args: [left, right]}, env, counter)
       when name in ["__add__", "__sub__", "__mul__", "__fdiv__"] do
    op = %{"__add__" => "+", "__sub__" => "-", "__mul__" => "*", "__fdiv__" => "/"}[name]
    {left_code, left_ref, counter} = compile_native_float_expr(left, env, counter)
    {right_code, right_ref, counter} = compile_native_float_expr(right, env, counter)
    {left_code <> right_code, "(#{left_ref} #{op} #{right_ref})", counter}
  end

  defp compile_native_float_expr(
         %{op: :runtime_call, function: "elmc_basics_to_float", args: [value]},
         env,
         counter
       ) do
    {value_code, value_ref, counter} = compile_native_int_expr(value, env, counter)
    {value_code, "(double)#{value_ref}", counter}
  end

  defp compile_native_float_expr(
         %{op: :runtime_call, function: function, args: [value]},
         env,
         counter
       )
       when function in [
              "elmc_basics_sin",
              "elmc_basics_cos",
              "elmc_basics_tan",
              "elmc_basics_sqrt"
            ] do
    {value_code, value_ref, counter} = compile_native_float_expr(value, env, counter)

    native_function =
      %{
        "elmc_basics_sin" => "elmc_basics_sin_double",
        "elmc_basics_cos" => "elmc_basics_cos_double",
        "elmc_basics_tan" => "elmc_basics_tan_double",
        "elmc_basics_sqrt" => "elmc_basics_sqrt_double"
      }
      |> Map.fetch!(function)

    {value_code, "#{native_function}(#{value_ref})", counter}
  end

  defp compile_native_float_expr(
         %{op: :runtime_call, function: "elmc_basics_abs", args: [value]},
         env,
         counter
       ) do
    {value_code, value_ref, counter} = compile_native_float_expr(value, env, counter)
    {value_code, "(#{value_ref} < 0 ? -#{value_ref} : #{value_ref})", counter}
  end

  defp compile_native_float_expr(
         %{op: :runtime_call, function: "elmc_basics_negate", args: [value]},
         env,
         counter
       ) do
    {value_code, value_ref, counter} = compile_native_float_expr(value, env, counter)
    {value_code, "(-#{value_ref})", counter}
  end

  defp compile_native_float_expr(
         %{op: :qualified_call, target: target, args: args} = expr,
         env,
         counter
       ) do
    case special_value_from_target(target, args) do
      nil ->
        case qualified_builtin_operator_name(target) do
          builtin when builtin in ["__add__", "__sub__", "__mul__", "__fdiv__"] ->
            compile_native_float_expr(%{op: :call, name: builtin, args: args}, env, counter)

          _ ->
            compile_native_float_fallback(expr, env, counter)
        end

      rewritten ->
        compile_native_float_expr(rewritten, env, counter)
    end
  end

  defp compile_native_float_expr(expr, env, counter),
    do: compile_native_float_fallback(expr, env, counter)

  defp compile_native_float_fallback(expr, env, counter) do
    {code, var, counter} = compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_f_#{next}"

    {
      """
      #{code}
        const double #{out} = elmc_as_float(#{var});
        elmc_release(#{var});
      """,
      out,
      next
    }
  end

  defp compile_native_bool_expr(%{op: :var, name: name} = expr, env, counter) do
    case native_bool_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            {"", "elmc_as_bool(#{source})", counter}

          _ ->
            compile_native_bool_fallback(expr, env, counter)
        end
    end
  end

  defp compile_native_bool_expr(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, source} when is_binary(source) ->
        getter = record_get_bool_expr(source, field, record_shape_for_var(env, arg))

        before_probe =
          env |> battery_alert_field_probe(arg, field, :before) |> agent_probe_region()

        after_probe = env |> battery_alert_field_probe(arg, field, :after) |> agent_probe_region()

        if before_probe == "" and after_probe == "" do
          {"", getter, counter}
        else
          next = counter + 1
          out = "native_bool_field_probe_#{next}"

          code = """
          #{before_probe}
            const elmc_int_t #{out} = #{getter};
          #{after_probe}
          """

          {code, out, next}
        end

      :error ->
        compile_native_bool_fallback(%{op: :field_access, arg: arg, field: field}, env, counter)
    end
  end

  defp compile_native_bool_expr(
         %{op: :field_access, arg: %{op: :var, name: name}, field: field},
         env,
         counter
       ) do
    compile_native_bool_expr(%{op: :field_access, arg: name, field: field}, env, counter)
  end

  defp compile_native_bool_expr(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    case inline_record_field_expr(arg_expr, field, env) do
      nil ->
        {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
        next = counter + 1
        out = "native_bool_field_#{next}"
        getter = record_get_bool_expr(arg_var, field, record_shape(arg_expr, env))

        before_probe =
          env |> battery_alert_field_probe(nil, field, :before) |> agent_probe_region()

        after_probe = env |> battery_alert_field_probe(nil, field, :after) |> agent_probe_region()

        code = """
        #{arg_code}
        #{before_probe}
          const elmc_int_t #{out} = #{getter};
        #{after_probe}
          elmc_release(#{arg_var});
        """

        {code, out, next}

      field_expr ->
        compile_native_bool_expr(field_expr, env, counter)
    end
  end

  defp compile_native_bool_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    if native_bool_expr?(then_expr, env) and native_bool_expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = compile_native_bool_expr(cond_expr, env, counter)
      {then_code, then_ref, counter} = compile_native_bool_expr(then_expr, env, counter)
      {else_code, else_ref, counter} = compile_native_bool_expr(else_expr, env, counter)
      next = counter + 1
      out = "native_bool_if_#{next}"

      code = """
      #{cond_code}
        elmc_int_t #{out} = 0;
        if (#{cond_ref}) {
      #{indent(then_code, 4)}
          #{out} = #{then_ref};
        } else {
      #{indent(else_code, 4)}
          #{out} = #{else_ref};
        }
      """

      {code, out, next}
    else
      compile_native_bool_fallback(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      )
    end
  end

  defp compile_native_bool_expr(
         %{op: :compare, kind: kind, left: left, right: right},
         env,
         counter
       ) do
    operator =
      case kind do
        :eq -> "__eq__"
        :neq -> "__neq__"
        :gt -> "__gt__"
        :gte -> "__gte__"
        :lt -> "__lt__"
        :lte -> "__lte__"
        _ -> "__eq__"
      end

    compile_native_bool_compare(left, right, operator, env, counter)
  end

  defp compile_native_bool_expr(%{op: :call, name: name, args: [left, right]}, env, counter)
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] do
    compile_native_bool_compare(left, right, name, env, counter)
  end

  defp compile_native_bool_expr(
         %{op: :qualified_call, target: target, args: args} = expr,
         env,
         counter
       ) do
    case special_value_from_target(target, args) do
      nil ->
        case qualified_builtin_operator_name(target) do
          builtin
          when builtin in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] ->
            compile_native_bool_expr(%{op: :call, name: builtin, args: args}, env, counter)

          _ ->
            compile_native_bool_fallback(expr, env, counter)
        end

      rewritten ->
        compile_native_bool_expr(rewritten, env, counter)
    end
  end

  defp compile_native_bool_expr(expr, env, counter),
    do: compile_native_bool_fallback(expr, env, counter)

  defp compile_native_bool_compare(left, right, operator, env, counter) do
    if native_int_compare_safe?(operator, left, right, env) do
      {left_code, left_ref, counter} = compile_native_int_expr(left, env, counter)
      {right_code, right_ref, counter} = compile_native_int_expr(right, env, counter)

      comparison =
        case operator do
          "__eq__" -> "=="
          "__neq__" -> "!="
          "__lt__" -> "<"
          "__lte__" -> "<="
          "__gt__" -> ">"
          "__gte__" -> ">="
        end

      {left_code <> right_code, "(#{left_ref} #{comparison} #{right_ref})", counter}
    else
      {left_code, left_var, counter} = compile_expr(left, env, counter)
      {right_code, right_var, counter} = compile_expr(right, env, counter)
      next = counter + 1
      out = "native_cmp_#{next}"

      code =
        case operator do
          "__eq__" ->
            """
            #{left_code}
              #{right_code}
              const elmc_int_t #{out} = elmc_value_equal(#{left_var}, #{right_var});
              elmc_release(#{left_var});
              elmc_release(#{right_var});
            """

          "__neq__" ->
            """
            #{left_code}
              #{right_code}
              const elmc_int_t #{out} = !elmc_value_equal(#{left_var}, #{right_var});
              elmc_release(#{left_var});
              elmc_release(#{right_var});
            """

          _ ->
            cmp_var = "__cmp_bool_#{next}"

            comparison =
              case operator do
                "__lt__" -> "<"
                "__lte__" -> "<="
                "__gt__" -> ">"
                "__gte__" -> ">="
              end

            """
            #{left_code}
              #{right_code}
              ElmcValue *#{cmp_var} = elmc_basics_compare(#{left_var}, #{right_var});
              const elmc_int_t #{out} = elmc_as_int(#{cmp_var}) #{comparison} 0;
              elmc_release(#{cmp_var});
              elmc_release(#{left_var});
              elmc_release(#{right_var});
            """
        end

      {code, out, next}
    end
  end

  defp compile_native_bool_fallback(expr, env, counter) do
    {code, var, counter} = compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_b_#{next}"

    {
      """
      #{code}
        const elmc_int_t #{out} = #{native_bool_value_expr(expr, env, var)};
        elmc_release(#{var});
      """,
      out,
      next
    }
  end

  defp native_bool_value_expr(expr, env, var) do
    if typed_bool_expr?(expr, env), do: "elmc_as_bool(#{var})", else: "elmc_as_int(#{var}) != 0"
  end

  @spec compile_float_div(term(), term(), term(), term()) :: term()
  defp compile_float_div(left, right, env, counter) do
    if native_float_expr?(left, env) and native_float_expr?(right, env) do
      compile_native_float_boxed(
        %{op: :call, name: "__fdiv__", args: [left, right]},
        env,
        counter
      )
    else
      {left_code, left_var, counter} = compile_expr(left, env, counter)
      {right_code, right_var, counter} = compile_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{left_code}
        #{right_code}
        const double __denf_#{next} = elmc_as_float(#{right_var});
        const double __numf_#{next} = elmc_as_float(#{left_var});
        ElmcValue *#{out} = elmc_new_float(__numf_#{next} / __denf_#{next});
        elmc_release(#{left_var});
        elmc_release(#{right_var});
      """

      {code, out, next}
    end
  end

  @spec compile_compare_operator(term(), term(), String.t(), term(), term()) :: term()
  defp compile_compare_operator(left, right, operator, env, counter) do
    if native_int_compare_safe?(operator, left, right, env) do
      compile_int_compare_operator(left, right, operator, env, counter)
    else
      {left_code, left_var, counter} = compile_expr(left, env, counter)
      {right_code, right_var, counter} = compile_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code =
        case operator do
          "__eq__" ->
            """
            #{left_code}
              #{right_code}
              ElmcValue *#{out} = elmc_new_bool(elmc_value_equal(#{left_var}, #{right_var}));
              elmc_release(#{left_var});
              elmc_release(#{right_var});
            """

          "__neq__" ->
            """
            #{left_code}
              #{right_code}
              ElmcValue *#{out} = elmc_new_bool(!elmc_value_equal(#{left_var}, #{right_var}));
              elmc_release(#{left_var});
              elmc_release(#{right_var});
            """

          _ ->
            comparison =
              case operator do
                "__lt__" -> "<"
                "__lte__" -> "<="
                "__gt__" -> ">"
                "__gte__" -> ">="
              end

            """
            #{left_code}
              #{right_code}
              ElmcValue *__cmp_#{next} = elmc_basics_compare(#{left_var}, #{right_var});
              ElmcValue *#{out} = elmc_new_bool(elmc_as_int(__cmp_#{next}) #{comparison} 0);
              elmc_release(__cmp_#{next});
              elmc_release(#{left_var});
              elmc_release(#{right_var});
            """
        end

      {code, out, next}
    end
  end

  defp native_int_compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] do
    native_int_expr?(left, env) and native_int_expr?(right, env)
  end

  defp native_int_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: boxed_int_binding?(env, name) or is_binary(native_int_binding(env, name))

  defp native_int_expr?(%{op: :field_access}, _env), do: true

  defp native_int_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: native_int_expr?(then_expr, env) and native_int_expr?(else_expr, env)

  defp native_int_expr?(%{op: :call, name: name, args: [left, right]}, env)
       when name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] do
    native_int_expr?(left, env) and native_int_expr?(right, env)
  end

  defp native_int_expr?(%{op: :call, name: name, args: [value]}, env)
       when name in ["abs", "negate"] do
    native_int_expr?(value, env)
  end

  defp native_int_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")

    native_int_inline_function_expr?({module_name, name}, args, env) or
      typed_int_expr?(%{op: :call, name: name, args: args}, env)
  end

  defp native_int_expr?(
         %{op: :runtime_call, function: function, args: [left, right]},
         env
       )
       when function in [
              "elmc_basics_min",
              "elmc_basics_max",
              "elmc_basics_mod_by",
              "elmc_basics_remainder_by"
            ] do
    native_int_expr?(left, env) and native_int_expr?(right, env)
  end

  defp native_int_expr?(
         %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, _maybe]},
         env
       ) do
    native_int_expr?(default_val, env)
  end

  defp native_int_expr?(%{op: :runtime_call, function: function, args: [value]}, env)
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    native_int_expr?(value, env)
  end

  defp native_int_expr?(%{op: :runtime_call, function: function, args: [value]}, env)
       when function in [
              "elmc_basics_round",
              "elmc_basics_floor",
              "elmc_basics_ceiling",
              "elmc_basics_truncate"
            ] do
    (function == "elmc_basics_round" and pebble_bound_trig_round_expr?(value, env)) or
      native_float_expr?(value, env)
  end

  defp native_int_expr?(%{op: :qualified_call, target: target, args: [value]}, env)
       when target in ["Basics.round", "round"] do
    pebble_bound_trig_round_expr?(value, env) or
      native_int_expr?(%{op: :runtime_call, function: "elmc_basics_round", args: [value]}, env)
  end

  defp native_int_expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case special_value_from_target(target, args) do
      %{op: op} when op in [:int_literal, :char_literal] ->
        true

      nil ->
        cond do
          qualified_builtin_operator_name(target) in [
            "__add__",
            "__sub__",
            "__mul__",
            "__idiv__",
            "modBy",
            "remainderBy"
          ] and
              length(args) == 2 ->
            Enum.all?(args, &native_int_expr?(&1, env))

          qualified_builtin_operator_name(target) in ["abs", "negate"] and length(args) == 1 ->
            Enum.all?(args, &native_int_expr?(&1, env))

          target_key = split_qualified_function_target(normalize_special_target(target)) ->
            native_int_inline_function_expr?(target_key, args, env) or
              typed_int_expr?(%{op: :qualified_call, target: target, args: args}, env)

          true ->
            false
        end

      expr ->
        native_int_expr?(expr, env)
    end
  end

  defp native_int_expr?(expr, _env), do: int_expr?(expr)

  defp typed_int_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    typed_function_return?({module_name, name}, env, length(args || []), "Int")
  end

  defp typed_int_expr?(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    target
    |> normalize_special_target()
    |> split_qualified_function_target()
    |> typed_function_return?(env, length(args || []), "Int")
  end

  defp typed_int_expr?(_expr, _env), do: false

  defp native_int_inline_function_expr?(target_key, args, env) do
    decl_map = Map.get(env, :__program_decls__, %{})
    inline_stack = Map.get(env, :__native_int_inline_stack__, MapSet.new())

    with %{args: arg_names, expr: body} when is_list(arg_names) <- Map.get(decl_map, target_key),
         true <- length(arg_names) == length(args),
         false <- MapSet.member?(inline_stack, target_key),
         substituted <- substitute_expr(body, Map.new(Enum.zip(arg_names, args))) do
      env =
        Map.put(
          env,
          :__native_int_inline_stack__,
          MapSet.put(inline_stack, target_key)
        )

      native_int_expr?(substituted, env)
    else
      _ -> false
    end
  end

  defp native_float_expr?(%{op: :float_literal}, _env), do: true

  defp native_float_expr?(%{op: op}, _env) when op in [:int_literal, :char_literal], do: true

  defp native_float_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: is_binary(native_float_binding(env, name)) or is_binary(native_int_binding(env, name))

  defp native_float_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: native_float_expr?(then_expr, env) and native_float_expr?(else_expr, env)

  defp native_float_expr?(%{op: :call, name: name, args: [left, right]}, env)
       when name in ["__add__", "__sub__", "__mul__", "__fdiv__"] do
    native_float_expr?(left, env) and native_float_expr?(right, env)
  end

  defp native_float_expr?(
         %{op: :runtime_call, function: "elmc_basics_to_float", args: [value]},
         env
       ) do
    native_int_expr?(value, env)
  end

  defp native_float_expr?(%{op: :runtime_call, function: function, args: [value]}, env)
       when function in [
              "elmc_basics_sin",
              "elmc_basics_cos",
              "elmc_basics_tan",
              "elmc_basics_sqrt",
              "elmc_basics_abs",
              "elmc_basics_negate"
            ] do
    native_float_expr?(value, env)
  end

  defp native_float_expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case special_value_from_target(target, args) do
      %{op: op} when op in [:float_literal, :int_literal, :char_literal] ->
        true

      nil ->
        qualified_builtin_operator_name(target) in ["__add__", "__sub__", "__mul__", "__fdiv__"] and
          length(args) == 2 and
          Enum.all?(args, &native_float_expr?(&1, env))

      expr ->
        native_float_expr?(expr, env)
    end
  end

  defp native_float_expr?(_expr, _env), do: false

  defp native_bool_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do:
      is_binary(native_bool_binding(env, name)) or
        match?({:ok, source} when is_binary(source), Map.fetch(env, name)) or
        typed_bool_expr?(%{op: :var, name: name}, env)

  defp native_bool_expr?(%{op: :field_access}, _env), do: true

  defp native_bool_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: native_bool_expr?(then_expr, env) and native_bool_expr?(else_expr, env)

  defp native_bool_expr?(expr, env), do: bool_expr?(expr) or typed_bool_expr?(expr, env)

  defp bool_expr?(%{op: :compare}), do: true

  defp bool_expr?(%{op: :call, name: name, args: args})
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] and
              length(args) == 2,
       do: true

  defp bool_expr?(%{op: :qualified_call, target: target, args: args}) do
    case special_value_from_target(target, args) do
      nil ->
        qualified_builtin_operator_name(target) in [
          "__eq__",
          "__neq__",
          "__lt__",
          "__lte__",
          "__gt__",
          "__gte__"
        ] and length(args) == 2

      expr ->
        bool_expr?(expr)
    end
  end

  defp bool_expr?(_expr), do: false

  defp static_nonzero_int_value(%{op: op, value: value})
       when op in [:int_literal, :char_literal] and is_integer(value) and value != 0,
       do: value

  defp static_nonzero_int_value(_expr), do: nil

  defp int_expr?(%{op: op})
       when op in [:int_literal, :char_literal, :add_const, :sub_const, :add_vars],
       do: true

  defp int_expr?(%{op: :call, name: name, args: args})
       when name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] and
              length(args) == 2,
       do: Enum.all?(args, &int_expr?/1)

  defp int_expr?(%{op: :call, name: name, args: args})
       when name in ["abs", "negate"] and length(args) == 1,
       do: Enum.all?(args, &int_expr?/1)

  defp int_expr?(%{op: :runtime_call, function: function, args: args})
       when function in ["elmc_basics_mod_by", "elmc_basics_remainder_by"] and length(args) == 2,
       do: Enum.all?(args, &int_expr?/1)

  defp int_expr?(%{op: :runtime_call, function: function, args: args})
       when function in ["elmc_basics_abs", "elmc_basics_negate"] and length(args) == 1,
       do: Enum.all?(args, &int_expr?/1)

  defp int_expr?(%{op: :qualified_call, target: target, args: args}) do
    case special_value_from_target(target, args) do
      %{op: op} when op in [:int_literal, :char_literal] ->
        true

      nil ->
        (qualified_builtin_operator_name(target) in [
           "__add__",
           "__sub__",
           "__mul__",
           "__idiv__",
           "modBy",
           "remainderBy"
         ] and length(args) == 2 and Enum.all?(args, &int_expr?/1)) or
          (qualified_builtin_operator_name(target) in ["abs", "negate"] and length(args) == 1 and
             Enum.all?(args, &int_expr?/1))

      expr ->
        int_expr?(expr)
    end
  end

  defp int_expr?(_expr), do: false

  defp compile_int_compare_operator(
         %{op: :int_literal, value: left},
         %{op: :int_literal, value: right},
         operator,
         _env,
         counter
       ) do
    result =
      case operator do
        "__eq__" -> left == right
        "__neq__" -> left != right
        "__lt__" -> left < right
        "__lte__" -> left <= right
        "__gt__" -> left > right
        "__gte__" -> left >= right
      end

    next = counter + 1
    out = "tmp_#{next}"
    {"ElmcValue *#{out} = elmc_new_bool(#{if(result, do: 1, else: 0)});", out, next}
  end

  defp compile_int_compare_operator(left, right, operator, env, counter) do
    {left_code, left_var, counter} = compile_native_int_expr(left, env, counter)
    {right_code, right_var, counter} = compile_native_int_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    comparison =
      case operator do
        "__eq__" -> "=="
        "__neq__" -> "!="
        "__lt__" -> "<"
        "__lte__" -> "<="
        "__gt__" -> ">"
        "__gte__" -> ">="
      end

    code = """
    #{left_code}
      #{right_code}
      ElmcValue *#{out} = elmc_new_bool(#{left_var} #{comparison} #{right_var});
    """

    {code, out, next}
  end

  @spec compile_cross_module_call(String.t(), [map()], map(), non_neg_integer()) ::
          {String.t(), String.t(), non_neg_integer()}
  defp compile_cross_module_call(target, args, env, counter) do
    case split_qualified_function_target(target) do
      {module_name, name} -> compile_function_call(module_name, name, args, env, counter)
      nil -> compile_function_call(target, "", args, env, counter)
    end
  end

  @spec qualified_builtin_operator_name(String.t()) :: String.t() | nil
  defp qualified_builtin_operator_name(target) when is_binary(target) do
    normalized = normalize_special_target(target)

    case String.split(normalized, ".") do
      ["Basics", name]
      when name in [
             "__add__",
             "__sub__",
             "__mul__",
             "__pow__",
             "__fdiv__",
             "__idiv__",
             "__append__",
             "__eq__",
             "__neq__",
             "__lt__",
             "__lte__",
             "__gt__",
             "__gte__",
             "modBy",
             "remainderBy",
             "round",
             "floor",
             "ceiling",
             "truncate",
             "toFloat",
             "abs",
             "negate",
             "not",
             "xor",
             "compare",
             "max",
             "min",
             "clamp"
           ] ->
        name

      _ ->
        nil
    end
  end

  @spec used_vars(map() | nil) :: MapSet.t()
  defp used_vars(nil), do: MapSet.new()

  defp used_vars(%{op: :var, name: name}), do: MapSet.new([name])
  defp used_vars(%{op: :float_literal}), do: MapSet.new()
  defp used_vars(%{op: :field_access, arg: arg}) when is_binary(arg), do: MapSet.new([arg])
  defp used_vars(%{op: :field_access, arg: arg}) when is_map(arg), do: used_vars(arg)
  defp used_vars(%{op: :compose_left, f: f, g: g}), do: MapSet.new([f, g])
  defp used_vars(%{op: :compose_right, f: f, g: g}), do: MapSet.new([f, g])
  defp used_vars(%{op: :add_const, var: name}), do: MapSet.new([name])
  defp used_vars(%{op: :sub_const, var: name}), do: MapSet.new([name])
  defp used_vars(%{op: :add_vars, left: left, right: right}), do: MapSet.new([left, right])
  defp used_vars(%{op: :tuple_second, arg: arg}), do: MapSet.new([arg])
  defp used_vars(%{op: :tuple_first, arg: arg}), do: MapSet.new([arg])
  defp used_vars(%{op: :string_length, arg: arg}), do: MapSet.new([arg])
  defp used_vars(%{op: :char_from_code, arg: arg}), do: MapSet.new([arg])
  defp used_vars(%{op: :tuple_second_expr, arg: arg}), do: used_vars(arg)
  defp used_vars(%{op: :tuple_first_expr, arg: arg}), do: used_vars(arg)
  defp used_vars(%{op: :string_length_expr, arg: arg}), do: used_vars(arg)
  defp used_vars(%{op: :char_from_code_expr, arg: arg}), do: used_vars(arg)

  defp used_vars(%{op: :runtime_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  defp used_vars(%{op: :qualified_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  defp used_vars(%{op: :constructor_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  defp used_vars(%{op: :list_literal, items: items}) do
    Enum.reduce(items, MapSet.new(), fn item, acc -> MapSet.union(acc, used_vars(item)) end)
  end

  defp used_vars(%{op: :call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  defp used_vars(%{op: :field_call, args: args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, used_vars(arg)) end)
  end

  defp used_vars(%{op: :lambda, body: body}) do
    used_vars(body)
  end

  defp used_vars(%{op: :record_literal, fields: fields}) do
    Enum.reduce(fields, MapSet.new(), fn
      %{expr: expr}, acc -> MapSet.union(acc, used_vars(expr))
      _other, acc -> acc
    end)
  end

  defp used_vars(%{op: :record_update, base: base, fields: fields}) do
    Enum.reduce(fields, used_vars(base), fn
      %{expr: expr}, acc -> MapSet.union(acc, used_vars(expr))
      _other, acc -> acc
    end)
  end

  defp used_vars(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}) do
    MapSet.union(used_vars(value_expr), used_vars(in_expr))
  end

  defp used_vars(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}) do
    used_vars(cond_expr)
    |> MapSet.union(used_vars(then_expr))
    |> MapSet.union(used_vars(else_expr))
  end

  defp used_vars(%{op: :compare, left: left, right: right}) do
    MapSet.union(used_vars(left), used_vars(right))
  end

  defp used_vars(%{op: :tuple2, left: left, right: right}) do
    MapSet.union(used_vars(left), used_vars(right))
  end

  defp used_vars(%{op: :case, subject: subject, branches: branches}) do
    branch_vars =
      branches
      |> Enum.map(&used_vars(&1.expr))
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    MapSet.put(branch_vars, subject)
  end

  defp used_vars(_), do: MapSet.new()

  @spec write_per_module_headers(ElmEx.IR.t(), String.t()) :: :ok | {:error, term()}
  defp write_per_module_headers(ir, c_dir) do
    Enum.reduce_while(ir.modules, :ok, fn mod, :ok ->
      safe_name = mod.name |> String.replace(".", "_")
      filename = "elmc_#{safe_name}.h"
      content = per_module_header(ir, mod)

      case File.write(Path.join(c_dir, filename), content) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec write_per_module_sources(ElmEx.IR.t(), String.t()) :: :ok | {:error, term()}
  defp write_per_module_sources(ir, c_dir) do
    Enum.reduce_while(ir.modules, :ok, fn mod, :ok ->
      safe_name = mod.name |> String.replace(".", "_")
      filename = "elmc_#{safe_name}.c"
      content = per_module_source(ir, mod)

      case File.write(Path.join(c_dir, filename), content) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec per_module_header(ElmEx.IR.t(), ElmEx.IR.Module.t()) :: String.t()
  defp per_module_header(_ir, mod) do
    safe_name = mod.name |> String.replace(".", "_") |> String.upcase()

    function_decls =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl ->
        c_name = module_fn_name(mod.name, decl.name)
        "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"
      end)
      |> Enum.join("\n")

    """
    #ifndef ELMC_#{safe_name}_H
    #define ELMC_#{safe_name}_H

    #include "../runtime/elmc_runtime.h"

    #{function_decls}

    #endif
    """
  end

  @spec per_module_source(ElmEx.IR.t(), ElmEx.IR.Module.t()) :: String.t()
  defp per_module_source(_ir, mod) do
    safe_name = mod.name |> String.replace(".", "_")

    function_defs =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl ->
        c_name = module_fn_name(mod.name, decl.name)

        """
        ElmcValue *#{c_name}(ElmcValue ** const args, const int argc) {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          #{emit_body(decl, mod.name)}
        }
        """
      end)
      |> Enum.join("\n")

    """
    #include "elmc_#{safe_name}.h"
    #include "elmc_generated.h"

    #{pebble_debug_probe_prelude()}

    #{function_defs}
    """
  end

  @spec link_manifest(ElmEx.IR.t()) :: String.t()
  defp link_manifest(ir) do
    modules =
      ir.modules
      |> Enum.map(fn mod ->
        safe_name = mod.name |> String.replace(".", "_")

        functions =
          mod.declarations
          |> Enum.filter(&(&1.kind == :function))
          |> Enum.map(fn decl ->
            %{
              "name" => decl.name,
              "c_symbol" => module_fn_name(mod.name, decl.name),
              "arity" => length(decl.args || [])
            }
          end)

        %{
          "module" => mod.name,
          "header" => "c/elmc_#{safe_name}.h",
          "source" => "c/elmc_#{safe_name}.c",
          "functions" => functions,
          "imports" => mod.imports || []
        }
      end)

    Jason.encode!(%{"modules" => modules, "version" => "1.0"}, pretty: true)
  end

  @spec module_fn_name(String.t(), String.t()) :: String.t()
  defp module_fn_name(module_name, function_name) do
    safe_module = module_name |> String.replace(".", "_")
    "elmc_fn_#{safe_module}_#{function_name}"
  end

  @spec qualified_to_c_name(String.t()) :: String.t()
  defp qualified_to_c_name(target) when is_binary(target) do
    # "Module.Name.function" -> "elmc_fn_Module_Name_function"
    parts = String.split(target, ".")

    case parts do
      [single] ->
        "elmc_fn_Main_#{single}"

      _ ->
        module_parts = Enum.slice(parts, 0..-2//1)
        func = List.last(parts)
        module_name = Enum.join(module_parts, "_")
        "elmc_fn_#{module_name}_#{func}"
    end
  end

  @spec indent(String.t(), non_neg_integer()) :: String.t()
  defp indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.trim(line) == "", do: line, else: pad <> line
    end)
  end

  @spec escape_c_string(String.t()) :: String.t()
  defp escape_c_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape_c_comment(value) do
    value
    |> to_string()
    |> String.replace("*/", "* /")
    |> String.replace("\n", " ")
    |> String.replace("\r", " ")
  end

  defp safe_c_suffix(value) when is_binary(value) do
    String.replace(value, ~r/[^A-Za-z0-9_]/, "_")
  end

  defp safe_c_suffix(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> safe_c_suffix()
  end

  defp safe_c_suffix(_value), do: "value"
end
