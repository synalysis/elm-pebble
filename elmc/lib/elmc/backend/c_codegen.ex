defmodule Elmc.Backend.CCodegen do
  @moduledoc """
  Writes C source files from lowered IR.
  """

  alias ElmEx.IR
  @vendored_cjson_c Path.expand("../../../vendor/cjson/cJSON.c", __DIR__)
  @vendored_cjson_h Path.expand("../../../vendor/cjson/cJSON.h", __DIR__)

  @spec write_project(IR.t(), String.t(), map()) :: :ok | {:error, term()}
  def write_project(%IR{} = ir, out_dir, _opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), header(ir)),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), source(ir)),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), host_harness()),
         :ok <- write_vendored_cjson(out_dir),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), makefile()) do
      :ok
    end
  end

  @spec write_project_multi(IR.t(), String.t(), map()) :: :ok | {:error, term()}
  def write_project_multi(%IR{} = ir, out_dir, _opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- write_per_module_headers(ir, c_dir),
         :ok <- write_per_module_sources(ir, c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), header(ir)),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), source(ir)),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), host_harness()),
         :ok <- write_vendored_cjson(out_dir),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), makefile()),
         :ok <- File.write(Path.join(out_dir, "link_manifest.json"), link_manifest(ir)) do
      :ok
    end
  end

  @spec header(ElmEx.IR.t()) :: String.t()
  defp header(ir) do
    function_decls =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl ->
          c_name = module_fn_name(mod.name, decl.name)
          "ElmcValue *#{c_name}(ElmcValue **args, int argc);"
        end)
      end)
      |> Enum.join("\n")

    """
    #ifndef ELMC_GENERATED_H
    #define ELMC_GENERATED_H

    #include "../runtime/elmc_runtime.h"
    #include "../ports/elmc_ports.h"

    #{function_decls}

    #endif
    """
  end

  @spec source(ElmEx.IR.t()) :: String.t()
  defp source(ir) do
    # Initialize lambda collection for hoisting to file scope
    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_lambda_counter, 0)

    function_defs =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl ->
          c_name = module_fn_name(mod.name, decl.name)

          """
          ElmcValue *#{c_name}(ElmcValue **args, int argc) {
            /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
            #{emit_body(decl, mod.name)}
          }
          """
        end)
      end)
      |> Enum.join("\n")

    lambda_defs =
      Process.get(:elmc_lambdas, [])
      |> Enum.reverse()
      |> Enum.join("\n")

    Process.delete(:elmc_lambdas)
    Process.delete(:elmc_lambda_counter)

    """
    #include "elmc_generated.h"

    #{lambda_defs}

    #{function_defs}
    """
  end

  @spec cmake() :: String.t()
  defp cmake do
    """
    cmake_minimum_required(VERSION 3.20)
    project(elmc_generated C)

    set(CJSON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cjson")

    add_library(cjson STATIC "${CJSON_DIR}/cJSON.c")
    target_include_directories(cjson PUBLIC "${CJSON_DIR}")

    add_library(elmc_runtime runtime/elmc_runtime.c)
    add_library(elmc_ports ports/elmc_ports.c)
    add_library(elmc_generated c/elmc_generated.c)
    add_library(elmc_worker c/elmc_worker.c)
    add_library(elmc_pebble c/elmc_pebble.c)
    target_include_directories(elmc_runtime PUBLIC runtime "${CJSON_DIR}")
    target_compile_definitions(elmc_runtime PUBLIC ELMC_USE_CJSON=1)
    target_link_libraries(elmc_runtime PUBLIC cjson)
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
    CJSON_DIR := cjson
    CFLAGS ?= -std=c11 -Wall -Wextra -Iruntime -Iports -Ic -I$(CJSON_DIR) -DELMC_USE_CJSON=1
    SOURCES := runtime/elmc_runtime.c ports/elmc_ports.c c/elmc_generated.c c/elmc_worker.c c/elmc_pebble.c c/host_harness.c $(CJSON_DIR)/cJSON.c

    all: elmc_host

    elmc_host: $(SOURCES)
    \t$(CC) $(CFLAGS) $(SOURCES) -o elmc_host

    clean:
    \trm -f elmc_host
    """
  end

  @spec write_vendored_cjson(String.t()) :: :ok | {:error, term()}
  defp write_vendored_cjson(out_dir) do
    cjson_out_dir = Path.join(out_dir, "cjson")

    with :ok <- File.mkdir_p(cjson_out_dir),
         :ok <- File.cp(@vendored_cjson_c, Path.join(cjson_out_dir, "cJSON.c")),
         :ok <- File.cp(@vendored_cjson_h, Path.join(cjson_out_dir, "cJSON.h")) do
      :ok
    end
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

  @spec emit_body(ElmEx.IR.Declaration.t(), String.t()) :: String.t()
  defp emit_body(%{expr: nil}, _module_name) do
    "(void)args; (void)argc; return elmc_new_int(0);"
  end

  defp emit_body(decl, module_name) do
    arg_names = decl.args || []

    arg_bindings =
      arg_names
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        "ElmcValue *#{arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)
      |> Enum.join("\n  ")

    # Always cast bound args to void; this keeps generated C warning-clean even
    # when special lowering paths bypass an argument that appeared in source AST.
    unused_casts =
      arg_names
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    env =
      arg_names
      |> Enum.reduce(%{__module__: module_name}, fn arg, acc ->
        Map.put(acc, arg, arg)
      end)

    {code, result_var, _counter} =
      compile_expr(decl.expr || %{op: :int_literal, value: 0}, env, 0)

    """
    (void)args;
      (void)argc;
    #{arg_bindings}
      #{unused_casts}
      #{code}
      return #{result_var};
    """
  end

  @spec compile_expr(map() | nil, map(), non_neg_integer()) ::
          {String.t(), String.t(), non_neg_integer()}
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

    case Map.fetch(env, name) do
      {:ok, source} ->
        {"ElmcValue *#{var} = #{source} ? elmc_retain(#{source}) : elmc_new_int(0);", var, next}

      :error ->
        # Not a local variable – must be a same-module top-level declaration.
        module_name = Map.get(env, :__module__, "Main")
        safe_module = String.replace(module_name, ".", "_")
        c_name = "elmc_fn_#{safe_module}_#{name}"
        {"ElmcValue *#{var} = #{c_name}(NULL, 0);", var, next}
    end
  end

  defp compile_expr(%{op: :add_const, var: name, value: value}, env, counter) do
    source = Map.get(env, name, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{source}) + #{value});", var, next}
  end

  defp compile_expr(%{op: :add_vars, left: left, right: right}, env, counter) do
    left_ref = Map.get(env, left, left)
    right_ref = Map.get(env, right, right)
    next = counter + 1
    var = "tmp_#{next}"

    {"ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{left_ref}) + elmc_as_int(#{right_ref}));",
     var, next}
  end

  defp compile_expr(%{op: :sub_const, var: name, value: value}, env, counter) do
    source = Map.get(env, name, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{source}) - #{value});", var, next}
  end

  defp compile_expr(%{op: :tuple2, left: left, right: right}, env, counter) do
    {left_code, left_var, counter} = compile_expr(left, env, counter)
    {right_code, right_var, counter} = compile_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    code = """
    #{left_code}
      #{right_code}
      ElmcValue *#{out} = elmc_tuple2(#{left_var}, #{right_var});
      elmc_release(#{left_var});
      elmc_release(#{right_var});
    """

    {code, out, next}
  end

  defp compile_expr(%{op: :list_literal, items: items}, env, counter) do
    next = counter + 1
    base = "tmp_#{next}"

    {code, out, final_counter} =
      Enum.reduce(
        Enum.reverse(items),
        {"ElmcValue *#{base} = elmc_list_nil();", base, next},
        fn item, {acc_code, acc_list, c} ->
          {item_code, item_var, c1} = compile_expr(item, env, c)
          c2 = c1 + 1
          new_list = "tmp_#{c2}"

          step = """
          #{item_code}
            ElmcValue *#{new_list} = elmc_list_cons(#{item_var}, #{acc_list});
            elmc_release(#{item_var});
            elmc_release(#{acc_list});
          """

          {acc_code <> "\n  " <> step, new_list, c2}
        end
      )

    {code, out, final_counter}
  end

  defp compile_expr(%{op: :tuple_second, arg: arg}, env, counter) do
    source = Map.get(env, arg, arg)
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

  defp compile_expr(%{op: :tuple_first, arg: arg}, env, counter) do
    source = Map.get(env, arg, arg)
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

        {code, out, next}

      expr ->
        compile_expr(expr, env, counter)
    end
  end

  defp compile_expr(%{op: :call, name: name, args: args}, env, counter) do
    case compile_builtin_operator_call(name, args, env, counter) do
      nil ->
        {arg_code, arg_vars, counter} =
          Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
            {code, var, c2} = compile_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
          end)

        module_name = Map.get(env, :__module__, "Main")
        c_name = module_fn_name(module_name, name)
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

        {code, out, next}

      result ->
        result
    end
  end

  defp compile_expr(%{op: :runtime_call, function: function, args: args}, env, counter) do
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
    """

    {code, out, next}
  end

  defp compile_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
         env,
         counter
       ) do
    {value_code, value_var, counter} = compile_expr(value_expr, env, counter)
    {body_code, body_var, counter} = compile_expr(in_expr, Map.put(env, name, value_var), counter)

    code = """
    #{value_code}
      #{body_code}
      elmc_release(#{value_var});
    """

    {code, body_var, counter}
  end

  defp compile_expr(
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         env,
         counter
       ) do
    {cond_code, cond_var, counter} = compile_expr(cond_expr, env, counter)
    {then_code, then_var, counter} = compile_expr(then_expr, env, counter)
    {else_code, else_var, counter} = compile_expr(else_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    code = """
    #{cond_code}
      ElmcValue *#{out} = elmc_new_int(0);
      if (elmc_as_int(#{cond_var}) != 0) {
    #{indent(then_code, 4)}
          elmc_release(#{out});
          #{out} = #{then_var};
      } else {
    #{indent(else_code, 4)}
          elmc_release(#{out});
          #{out} = #{else_var};
      }
      elmc_release(#{cond_var});
    """

    {code, out, next}
  end

  defp compile_expr(%{op: :compare, kind: kind, left: left, right: right}, env, counter) do
    {left_code, left_var, counter} = compile_expr(left, env, counter)
    {right_code, right_var, counter} = compile_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    operator =
      case kind do
        :eq -> "=="
        :gt -> ">"
        :lt -> "<"
        _ -> "=="
      end

    code = """
    #{left_code}
      #{right_code}
      ElmcValue *#{out} = elmc_new_bool(elmc_as_int(#{left_var}) #{operator} elmc_as_int(#{right_var}));
      elmc_release(#{left_var});
      elmc_release(#{right_var});
    """

    {code, out, next}
  end

  defp compile_expr(%{op: :case, subject: subject, branches: branches}, env, counter) do
    subject_ref = Map.get(env, subject, subject)
    next = counter + 1
    out = "tmp_#{next}"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        branch_env = bind_pattern(env, branch.pattern, subject_ref)
        {expr_code, expr_var, c2} = compile_expr(branch.expr, branch_env, c)
        cond_code = pattern_condition(subject_ref, branch.pattern)

        snippet = """
        #{if acc == "", do: "if", else: "else if"} (#{cond_code}) {
        #{indent(expr_code, 4)}
            elmc_release(#{out});
            #{out} = #{expr_var};
        }
        """

        {acc <> snippet, c2}
      end)

    code = """
    ElmcValue *#{out} = elmc_new_int(0);
      #{branch_code}
    """

    {code, out, final_counter}
  end

  defp compile_expr(%{op: :float_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {"ElmcValue *#{var} = elmc_new_float(#{float_val});", var, next}
  end

  defp compile_expr(%{op: :record_literal, fields: fields}, env, counter) do
    sorted_fields = Enum.sort_by(fields, & &1.name)

    {field_code, field_vars, counter} =
      Enum.reduce(sorted_fields, {"", [], counter}, fn field, {code_acc, vars_acc, c} ->
        {code, var, c2} = compile_expr(field.expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [{field.name, var}], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    field_count = length(sorted_fields)

    names_array =
      sorted_fields |> Enum.map(fn f -> "\"#{escape_c_string(f.name)}\"" end) |> Enum.join(", ")

    values_array = field_vars |> Enum.map(fn {_name, var} -> var end) |> Enum.join(", ")

    releases =
      field_vars
      |> Enum.map_join("\n  ", fn {_name, var} -> "elmc_release(#{var});" end)

    code = """
    #{field_code}
      const char *rec_names_#{next}[#{max(field_count, 1)}] = { #{names_array} };
      ElmcValue *rec_values_#{next}[#{max(field_count, 1)}] = { #{values_array} };
      ElmcValue *#{out} = elmc_record_new(#{field_count}, rec_names_#{next}, rec_values_#{next});
      #{releases}
    """

    {code, out, next}
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

        {"ElmcValue *#{var} = elmc_record_get(#{source}, \"#{escape_c_string(field)}\");", var,
         next}

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

  defp compile_expr(%{op: :field_access, arg: arg_expr, field: field}, env, counter)
       when is_map(arg_expr) do
    {arg_code, arg_var, counter} = compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = elmc_record_get(#{arg_var}, "#{escape_c_string(field)}");
      elmc_release(#{arg_var});
    """

    {code, var, next}
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

    # Generate a globally unique closure function name (hoisted to file scope)
    lambda_id = Process.get(:elmc_lambda_counter, 0) + 1
    Process.put(:elmc_lambda_counter, lambda_id)
    next = counter + 1
    closure_fn_name = "elmc_lambda_#{lambda_id}"
    lambda_arg_names = lambda_args || []

    # Build arg bindings for the closure function body
    arg_bindings =
      lambda_arg_names
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        "ElmcValue *#{arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)
      |> Enum.join("\n  ")

    # Build capture bindings
    capture_bindings =
      free_vars
      |> Enum.with_index()
      |> Enum.map(fn {var_name, index} ->
        "ElmcValue *#{var_name} = (capture_count > #{index}) ? captures[#{index}] : NULL;"
      end)
      |> Enum.join("\n  ")

    # Build the body in a clean environment with just args and captures as names
    # Propagate __module__ context so intra-module calls resolve correctly
    body_env =
      (lambda_arg_names ++ free_vars)
      |> Map.new(fn name -> {name, name} end)
      |> Map.put(:__module__, Map.get(env, :__module__, "Main"))

    {body_code, body_var, _body_counter} = compile_expr(body, body_env, 0)

    # Hoist the closure function to file scope via process dictionary
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
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{capture_count}, cap_#{next});
    """

    {code, out, next}
  end

  defp compile_expr(%{op: :unsupported}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(0);", var, next}
  end

  defp compile_expr(_expr, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(0);", var, next}
  end

  @spec special_value_from_target(String.t(), [map()]) :: map() | nil
  defp special_value_from_target("Pebble.Ui.clear", args), do: encoded_cmd_expr(2, args, 1)

  defp special_value_from_target("Pebble.Ui.pixel", [pos, color]),
    do: encoded_cmd_expr(3, [field_access_expr(pos, "x"), field_access_expr(pos, "y"), color], 3)

  defp special_value_from_target("Pebble.Ui.pixel", args), do: encoded_cmd_expr(3, args, 3)

  defp special_value_from_target("Pebble.Ui.line", [start_pos, end_pos, color]),
    do:
      encoded_cmd_expr(
        4,
        [
          field_access_expr(start_pos, "x"),
          field_access_expr(start_pos, "y"),
          field_access_expr(end_pos, "x"),
          field_access_expr(end_pos, "y"),
          color
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.line", args), do: encoded_cmd_expr(4, args, 5)

  defp special_value_from_target("Pebble.Ui.rect", [bounds, color]),
    do:
      encoded_cmd_expr(
        5,
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.rect", args), do: encoded_cmd_expr(5, args, 5)

  defp special_value_from_target("Pebble.Ui.fillRect", [bounds, color]),
    do:
      encoded_cmd_expr(
        6,
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  defp special_value_from_target("Pebble.Ui.fillRect", args), do: encoded_cmd_expr(6, args, 5)

  defp special_value_from_target("Pebble.Ui.circle", [center, radius, color]),
    do:
      encoded_cmd_expr(
        7,
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        4
      )

  defp special_value_from_target("Pebble.Ui.circle", args), do: encoded_cmd_expr(7, args, 4)

  defp special_value_from_target("Pebble.Ui.fillCircle", [center, radius, color]),
    do:
      encoded_cmd_expr(
        8,
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        4
      )

  defp special_value_from_target("Pebble.Ui.fillCircle", args), do: encoded_cmd_expr(8, args, 4)

  defp special_value_from_target("Pebble.Ui.textInt", [font_id, pos, value]),
    do:
      encoded_cmd_expr(
        27,
        [font_id, field_access_expr(pos, "x"), field_access_expr(pos, "y"), value],
        4
      )

  defp special_value_from_target("Pebble.Ui.textLabel", [font_id, pos, label]),
    do:
      encoded_cmd_expr(
        28,
        [font_id, field_access_expr(pos, "x"), field_access_expr(pos, "y"), label],
        4
      )

  defp special_value_from_target("Pebble.Ui.text", [font_id, bounds, value]),
    do:
      encoded_text_cmd_expr(
        29,
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

  defp special_value_from_target("Pebble.Ui.Color.black", []),
    do: %{op: :int_literal, value: 0xC0}

  defp special_value_from_target("Pebble.Ui.Color.white", []),
    do: %{op: :int_literal, value: 0xFF}

  defp special_value_from_target("Pebble.Ui.Color.red", []), do: %{op: :int_literal, value: 0xF0}

  defp special_value_from_target("Pebble.Ui.Color.chromeYellow", []),
    do: %{op: :int_literal, value: 0xF8}

  defp special_value_from_target("Pebble.Ui.Color.green", []),
    do: %{op: :int_literal, value: 0xCC}

  defp special_value_from_target("Pebble.Ui.Color.blue", []),
    do: %{op: :int_literal, value: 0xC3}

  defp special_value_from_target("Pebble.Time.Monday", []), do: %{op: :int_literal, value: 0}
  defp special_value_from_target("Pebble.Time.Tuesday", []), do: %{op: :int_literal, value: 1}
  defp special_value_from_target("Pebble.Time.Wednesday", []), do: %{op: :int_literal, value: 2}
  defp special_value_from_target("Pebble.Time.Thursday", []), do: %{op: :int_literal, value: 3}
  defp special_value_from_target("Pebble.Time.Friday", []), do: %{op: :int_literal, value: 4}
  defp special_value_from_target("Pebble.Time.Saturday", []), do: %{op: :int_literal, value: 5}
  defp special_value_from_target("Pebble.Time.Sunday", []), do: %{op: :int_literal, value: 6}

  defp special_value_from_target("PushContext", args), do: encoded_cmd_expr(10, args, 0)
  defp special_value_from_target("PopContext", args), do: encoded_cmd_expr(11, args, 0)

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
    do: %{op: :tuple2, left: %{op: :int_literal, value: 19}, right: context}

  defp special_value_from_target("Pebble.Ui.path", [points, offset_x, offset_y, rotation]),
    do: path_expr(points, offset_x, offset_y, rotation)

  defp special_value_from_target("Pebble.Ui.pathFilled", [path]),
    do: %{op: :tuple2, left: %{op: :int_literal, value: 20}, right: path}

  defp special_value_from_target("Pebble.Ui.pathOutline", [path]),
    do: %{op: :tuple2, left: %{op: :int_literal, value: 21}, right: path}

  defp special_value_from_target("Pebble.Ui.pathOutlineOpen", [path]),
    do: %{op: :tuple2, left: %{op: :int_literal, value: 22}, right: path}

  defp special_value_from_target("Pebble.Ui.roundRect", [bounds, radius, color]),
    do:
      encoded_cmd_expr(
        17,
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

  defp special_value_from_target("Pebble.Ui.roundRect", args), do: encoded_cmd_expr(17, args, 6)

  defp special_value_from_target("Pebble.Ui.arc", [bounds, start_angle, end_angle]),
    do:
      encoded_cmd_expr(
        18,
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

  defp special_value_from_target("Pebble.Ui.arc", args), do: encoded_cmd_expr(18, args, 6)

  defp special_value_from_target("Pebble.Ui.fillRadial", [bounds, start_angle, end_angle]),
    do:
      encoded_cmd_expr(
        23,
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

  defp special_value_from_target("Pebble.Ui.fillRadial", args), do: encoded_cmd_expr(23, args, 6)

  defp special_value_from_target("Pebble.Ui.drawBitmapInRect", [bitmap, bounds]),
    do:
      encoded_cmd_expr(
        25,
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
    do: encoded_cmd_expr(25, args, 5)

  defp special_value_from_target("Pebble.Ui.drawRotatedBitmap", args),
    do: encoded_cmd_expr(26, args, 6)

  defp special_value_from_target("Pebble.Ui.windowStack", [windows]),
    do: %{op: :tuple2, left: %{op: :int_literal, value: 1000}, right: windows}

  defp special_value_from_target("Pebble.Ui.window", [window_id, layers]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: 1001},
      right: %{op: :tuple2, left: window_id, right: layers}
    }

  defp special_value_from_target("Pebble.Ui.canvasLayer", [layer_id, ops]),
    do: %{
      op: :tuple2,
      left: %{op: :int_literal, value: 1002},
      right: %{op: :tuple2, left: layer_id, right: ops}
    }

  defp special_value_from_target("Pebble.Cmd.none", _args), do: %{op: :int_literal, value: 0}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.none", _args),
    do: %{op: :int_literal, value: 0}

  defp special_value_from_target("Pebble.Cmd.timerAfter", args), do: encoded_cmd_expr(1, args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.timerAfter", args),
    do: encoded_cmd_expr(1, args, 1)

  defp special_value_from_target("Pebble.Cmd.storageWriteInt", args),
    do: encoded_cmd_expr(2, args, 2)

  defp special_value_from_target("Pebble.Storage.writeInt", args),
    do: encoded_cmd_expr(2, args, 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteInt", args),
    do: encoded_cmd_expr(2, args, 2)

  defp special_value_from_target("Pebble.Cmd.storageReadInt", [key, _to_msg]),
    do: encoded_cmd_expr(3, [key], 1)

  defp special_value_from_target("Pebble.Storage.readInt", [key, _to_msg]),
    do: encoded_cmd_expr(3, [key], 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageReadInt", [key, _to_msg]),
    do: encoded_cmd_expr(3, [key], 1)

  defp special_value_from_target("Pebble.Cmd.storageDelete", args),
    do: encoded_cmd_expr(4, args, 1)

  defp special_value_from_target("Pebble.Storage.delete", args),
    do: encoded_cmd_expr(4, args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.storageDelete", args),
    do: encoded_cmd_expr(4, args, 1)

  defp special_value_from_target("Pebble.Internal.Companion.companionSend", args),
    do: encoded_cmd_expr(5, args, 2)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.companionSend", args),
    do: encoded_cmd_expr(5, args, 2)

  defp special_value_from_target("Pebble.Cmd.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  defp special_value_from_target("Pebble.Cmd.getCurrentTimeString", [_to_msg]),
    do: %{op: :int_literal, value: 7}

  defp special_value_from_target("Pebble.Time.currentTimeString", [_to_msg]),
    do: %{op: :int_literal, value: 7}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentTimeString", [_to_msg]),
    do: %{op: :int_literal, value: 7}

  defp special_value_from_target("Pebble.Cmd.getCurrentDateTime", [_to_msg]),
    do: %{op: :int_literal, value: 23}

  defp special_value_from_target("Pebble.Time.currentDateTime", [_to_msg]),
    do: %{op: :int_literal, value: 23}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentDateTime", [_to_msg]),
    do: %{op: :int_literal, value: 23}

  defp special_value_from_target("Pebble.System.batteryLevel", [_to_msg]),
    do: %{op: :int_literal, value: 24}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getBatteryLevel", [_to_msg]),
    do: %{op: :int_literal, value: 24}

  defp special_value_from_target("Pebble.System.connectionStatus", [_to_msg]),
    do: %{op: :int_literal, value: 25}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getConnectionStatus", [_to_msg]),
    do: %{op: :int_literal, value: 25}

  defp special_value_from_target("Pebble.Cmd.getClockStyle24h", [_to_msg]),
    do: %{op: :int_literal, value: 8}

  defp special_value_from_target("Pebble.Time.clockStyle24h", [_to_msg]),
    do: %{op: :int_literal, value: 8}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getClockStyle24h", [_to_msg]),
    do: %{op: :int_literal, value: 8}

  defp special_value_from_target("Pebble.Cmd.getTimezoneIsSet", [_to_msg]),
    do: %{op: :int_literal, value: 9}

  defp special_value_from_target("Pebble.Time.timezoneIsSet", [_to_msg]),
    do: %{op: :int_literal, value: 9}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getTimezoneIsSet", [_to_msg]),
    do: %{op: :int_literal, value: 9}

  defp special_value_from_target("Pebble.Cmd.getTimezone", [_to_msg]),
    do: %{op: :int_literal, value: 10}

  defp special_value_from_target("Pebble.Time.timezone", [_to_msg]),
    do: %{op: :int_literal, value: 10}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getTimezone", [_to_msg]),
    do: %{op: :int_literal, value: 10}

  defp special_value_from_target("Pebble.Cmd.getWatchModel", [_to_msg]),
    do: %{op: :int_literal, value: 11}

  defp special_value_from_target("Pebble.WatchInfo.getModel", [_to_msg]),
    do: %{op: :int_literal, value: 11}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getWatchModel", [_to_msg]),
    do: %{op: :int_literal, value: 11}

  defp special_value_from_target("Pebble.Cmd.getFirmwareVersion", [_to_msg]),
    do: %{op: :int_literal, value: 12}

  defp special_value_from_target("Pebble.WatchInfo.getFirmwareVersion", [_to_msg]),
    do: %{op: :int_literal, value: 12}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getFirmwareVersion", [_to_msg]),
    do: %{op: :int_literal, value: 12}

  defp special_value_from_target("Pebble.WatchInfo.getColor", [_to_msg]),
    do: %{op: :int_literal, value: 17}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.getColor", [_to_msg]),
    do: %{op: :int_literal, value: 17}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.wakeupScheduleAfterSeconds", args),
    do: encoded_cmd_expr(18, args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.wakeupCancel", args),
    do: encoded_cmd_expr(19, args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.logInfoCode", args),
    do: encoded_cmd_expr(20, args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.logWarnCode", args),
    do: encoded_cmd_expr(21, args, 1)

  defp special_value_from_target("Elm.Kernel.PebbleWatch.logErrorCode", args),
    do: encoded_cmd_expr(22, args, 1)

  defp special_value_from_target("Pebble.Cmd.vibesCancel", _args),
    do: %{op: :int_literal, value: 13}

  defp special_value_from_target("Pebble.Vibes.cancel", _args),
    do: %{op: :int_literal, value: 13}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesCancel", _args),
    do: %{op: :int_literal, value: 13}

  defp special_value_from_target("Pebble.Cmd.vibesShortPulse", _args),
    do: %{op: :int_literal, value: 14}

  defp special_value_from_target("Pebble.Vibes.shortPulse", _args),
    do: %{op: :int_literal, value: 14}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesShortPulse", _args),
    do: %{op: :int_literal, value: 14}

  defp special_value_from_target("Pebble.Cmd.vibesLongPulse", _args),
    do: %{op: :int_literal, value: 15}

  defp special_value_from_target("Pebble.Vibes.longPulse", _args),
    do: %{op: :int_literal, value: 15}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesLongPulse", _args),
    do: %{op: :int_literal, value: 15}

  defp special_value_from_target("Pebble.Cmd.vibesDoublePulse", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Pebble.Vibes.doublePulse", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.vibesDoublePulse", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Pebble.Events.onTick", _args), do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onTick", _args),
    do: %{op: :int_literal, value: 1}

  defp special_value_from_target("Pebble.Events.onHourChange", _args),
    do: %{op: :int_literal, value: 1024}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onHourChange", _args),
    do: %{op: :int_literal, value: 1024}

  defp special_value_from_target("Pebble.Events.onMinuteChange", _args),
    do: %{op: :int_literal, value: 2048}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onMinuteChange", _args),
    do: %{op: :int_literal, value: 2048}

  defp special_value_from_target("Pebble.Events.onButtonUp", _args),
    do: %{op: :int_literal, value: 2}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonUp", _args),
    do: %{op: :int_literal, value: 2}

  defp special_value_from_target("Pebble.Events.onButtonSelect", _args),
    do: %{op: :int_literal, value: 4}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonSelect", _args),
    do: %{op: :int_literal, value: 4}

  defp special_value_from_target("Pebble.Events.onButtonDown", _args),
    do: %{op: :int_literal, value: 8}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonDown", _args),
    do: %{op: :int_literal, value: 8}

  defp special_value_from_target("Pebble.Events.onButtonLongUp", _args),
    do: %{op: :int_literal, value: 128}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongUp", _args),
    do: %{op: :int_literal, value: 128}

  defp special_value_from_target("Pebble.Events.onButtonLongSelect", _args),
    do: %{op: :int_literal, value: 256}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongSelect", _args),
    do: %{op: :int_literal, value: 256}

  defp special_value_from_target("Pebble.Events.onButtonLongDown", _args),
    do: %{op: :int_literal, value: 512}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongDown", _args),
    do: %{op: :int_literal, value: 512}

  defp special_value_from_target("Pebble.Events.onAccelTap", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onAccelTap", _args),
    do: %{op: :int_literal, value: 16}

  defp special_value_from_target("Pebble.System.onBatteryChange", _args),
    do: %{op: :int_literal, value: 32}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onBatteryChange", _args),
    do: %{op: :int_literal, value: 32}

  defp special_value_from_target("Pebble.System.onConnectionChange", _args),
    do: %{op: :int_literal, value: 64}

  defp special_value_from_target("Elm.Kernel.PebbleWatch.onConnectionChange", _args),
    do: %{op: :int_literal, value: 64}

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

  defp special_value_from_target("Basics.round", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_round", args: [x]}

  defp special_value_from_target("Basics.floor", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_floor", args: [x]}

  defp special_value_from_target("Basics.ceiling", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_ceiling", args: [x]}

  defp special_value_from_target("Basics.truncate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_truncate", args: [x]}

  defp special_value_from_target("Basics.remainderBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]}

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

      true ->
        nil
    end
  end

  defp special_value_from_target(target, args) when is_binary(target) and is_list(args) do
    normalized = normalize_special_target(target)
    if normalized == target, do: nil, else: special_value_from_target(normalized, args)
  end

  defp special_value_from_target(_, _), do: nil

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
      "Rect" -> "Pebble.Ui.rect"
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
        acc + subscription_item_mask(item)
      end)

    %{op: :int_literal, value: mask}
  end

  defp subscription_batch_expr(_), do: %{op: :unsupported}

  @spec subscription_item_mask(map()) :: non_neg_integer()
  defp subscription_item_mask(%{op: :int_literal, value: value}) when is_integer(value), do: value

  defp subscription_item_mask(%{op: :qualified_call, target: target}) when is_binary(target) do
    case normalize_special_target(target) do
      "Pebble.Events.onTick" -> 1
      "Pebble.Events.onHourChange" -> 1024
      "Pebble.Events.onMinuteChange" -> 2048
      "Pebble.Events.onButtonUp" -> 2
      "Pebble.Events.onButtonSelect" -> 4
      "Pebble.Events.onButtonDown" -> 8
      "Pebble.Events.onButtonLongUp" -> 128
      "Pebble.Events.onButtonLongSelect" -> 256
      "Pebble.Events.onButtonLongDown" -> 512
      "Pebble.Events.onAccelTap" -> 16
      "Pebble.System.onBatteryChange" -> 32
      "Pebble.System.onConnectionChange" -> 64
      "Elm.Kernel.PebbleWatch.onBatteryChange" -> 32
      "Elm.Kernel.PebbleWatch.onConnectionChange" -> 64
      "Companion.Watch.onPhoneToWatch" -> 4096
      "Elm.Kernel.PebbleWatch.onHourChange" -> 1024
      "Elm.Kernel.PebbleWatch.onMinuteChange" -> 2048
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

  @spec pattern_subject_ref(term()) :: String.t()
  defp pattern_subject_ref(subject_ref) when is_binary(subject_ref), do: subject_ref
  defp pattern_subject_ref(%{op: :var, name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"op" => :var, "name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(subject_ref), do: inspect(subject_ref)

  @spec compile_builtin_operator_call(term(), term(), term(), term()) :: term()
  defp compile_builtin_operator_call("__add__", [left, right], env, counter),
    do: compile_int_binop(left, right, "+", env, counter)

  defp compile_builtin_operator_call("__sub__", [left, right], env, counter),
    do: compile_int_binop(left, right, "-", env, counter)

  defp compile_builtin_operator_call("__mul__", [left, right], env, counter),
    do: compile_int_binop(left, right, "*", env, counter)

  defp compile_builtin_operator_call("__pow__", [base, exponent], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_basics_pow", args: [base, exponent]},
        env,
        counter
      )

  defp compile_builtin_operator_call("__fdiv__", [left, right], env, counter),
    do: compile_float_div(left, right, env, counter)

  defp compile_builtin_operator_call("__idiv__", [left, right], env, counter),
    do: compile_int_idiv(left, right, env, counter)

  defp compile_builtin_operator_call("__append__", [left, right], env, counter),
    do:
      compile_expr(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]},
        env,
        counter
      )

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

  @spec compile_int_binop(term(), term(), term(), term(), term()) :: term()
  defp compile_int_binop(left, right, operator, env, counter) do
    {left_code, left_var, counter} = compile_expr(left, env, counter)
    {right_code, right_var, counter} = compile_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    code = """
    #{left_code}
      #{right_code}
      ElmcValue *#{out} = elmc_new_int(elmc_as_int(#{left_var}) #{operator} elmc_as_int(#{right_var}));
      elmc_release(#{left_var});
      elmc_release(#{right_var});
    """

    {code, out, next}
  end

  @spec compile_int_idiv(term(), term(), term(), term()) :: term()
  defp compile_int_idiv(left, right, env, counter) do
    {left_code, left_var, counter} = compile_expr(left, env, counter)
    {right_code, right_var, counter} = compile_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    code = """
    #{left_code}
      #{right_code}
      int64_t __den_#{next} = elmc_as_int(#{right_var});
      ElmcValue *#{out} = elmc_new_int(__den_#{next} == 0 ? 0 : (elmc_as_int(#{left_var}) / __den_#{next}));
      elmc_release(#{left_var});
      elmc_release(#{right_var});
    """

    {code, out, next}
  end

  @spec compile_float_div(term(), term(), term(), term()) :: term()
  defp compile_float_div(left, right, env, counter) do
    {left_code, left_var, counter} = compile_expr(left, env, counter)
    {right_code, right_var, counter} = compile_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    code = """
    #{left_code}
      #{right_code}
      double __denf_#{next} = elmc_as_float(#{right_var});
      double __numf_#{next} = elmc_as_float(#{left_var});
      ElmcValue *#{out} = elmc_new_float(__numf_#{next} / __denf_#{next});
      elmc_release(#{left_var});
      elmc_release(#{right_var});
    """

    {code, out, next}
  end

  @spec compile_cross_module_call(String.t(), [map()], map(), non_neg_integer()) ::
          {String.t(), String.t(), non_neg_integer()}
  defp compile_cross_module_call(target, args, env, counter) do
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

    {code, out, next}
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
        "ElmcValue *#{c_name}(ElmcValue **args, int argc);"
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
        ElmcValue *#{c_name}(ElmcValue **args, int argc) {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          #{emit_body(decl, mod.name)}
        }
        """
      end)
      |> Enum.join("\n")

    """
    #include "elmc_#{safe_name}.h"
    #include "elmc_generated.h"

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
end
