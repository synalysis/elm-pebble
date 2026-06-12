defmodule Elmc.RuntimeStdlibGapsTest do
  use ExUnit.Case

  @tag :runtime_c
  test "list sortBy sorts by mapped keys" do
    run_harness(
      """
      static ElmcValue *by_identity(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 1 || !args[0]) return elmc_int_zero();
        return elmc_retain(args[0]);
      }

      int main(void) {
        ElmcValue *list = elmc_list_nil();
        list = elmc_list_cons_take(elmc_new_int_take(3), list);
        list = elmc_list_cons_take(elmc_new_int_take(1), list);
        list = elmc_list_cons_take(elmc_new_int_take(2), list);

        ElmcValue *cap[1] = { NULL };
        ElmcValue *f = elmc_closure_new_take(by_identity, 1, 0, cap);
        ElmcValue *sorted = elmc_list_sort_by_take(f, list);

        ElmcValue *cursor = sorted;
        printf("%lld", (long long)elmc_as_int(((ElmcCons *)cursor->payload)->head));
        cursor = ((ElmcCons *)cursor->payload)->tail;
        printf(" %lld", (long long)elmc_as_int(((ElmcCons *)cursor->payload)->head));
        cursor = ((ElmcCons *)cursor->payload)->tail;
        printf(" %lld\\n", (long long)elmc_as_int(((ElmcCons *)cursor->payload)->head));

        elmc_release(sorted);
        elmc_release(f);
        elmc_release(list);
        return 0;
      }
      """,
      "1 2 3"
    )
  end

  @tag :runtime_c
  test "list sortWith orders by comparison function" do
    run_harness(
      """
      static ElmcValue *compare_ints(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 2) return elmc_int_zero();
        return elmc_basics_compare(args[0], args[1]);
      }

      int main(void) {
        ElmcValue *list = elmc_list_nil();
        list = elmc_list_cons_take(elmc_new_int_take(3), list);
        list = elmc_list_cons_take(elmc_new_int_take(1), list);
        list = elmc_list_cons_take(elmc_new_int_take(2), list);

        ElmcValue *cap[1] = { NULL };
        ElmcValue *f = elmc_closure_new_take(compare_ints, 2, 0, cap);
        ElmcValue *sorted = elmc_list_sort_with_take(f, list);

        ElmcValue *cursor = sorted;
        printf("%lld", (long long)elmc_as_int(((ElmcCons *)cursor->payload)->head));
        cursor = ((ElmcCons *)cursor->payload)->tail;
        printf(" %lld", (long long)elmc_as_int(((ElmcCons *)cursor->payload)->head));
        cursor = ((ElmcCons *)cursor->payload)->tail;
        printf(" %lld\\n", (long long)elmc_as_int(((ElmcCons *)cursor->payload)->head));

        elmc_release(sorted);
        elmc_release(f);
        elmc_release(list);
        return 0;
      }
      """,
      "1 2 3"
    )
  end

  @tag :runtime_c
  test "string replace substitutes all occurrences" do
    run_harness(
      """
      int main(void) {
        ElmcValue *s = elmc_new_string_take("a-b-a");
        ElmcValue *out = elmc_string_replace_take(elmc_new_string_take("-"), elmc_new_string_take("+"), s);
        printf("%s\\n", (const char *)out->payload);
        elmc_release(out);
        elmc_release(s);
        return 0;
      }
      """,
      "a+b+a"
    )
  end

  @tag :runtime_c
  test "dict get with default uses comparable keys for strings" do
    run_harness(
      """
      int main(void) {
        ElmcValue *empty = elmc_list_nil();
        ElmcValue *key = elmc_new_string_take("name");
        ElmcValue *dict = elmc_dict_insert_take(key, elmc_new_int_take(42), empty);
        ElmcValue *lookup_key = elmc_new_string_take("name");
        elmc_int_t found = elmc_dict_get_with_default_int_value(0, lookup_key, dict);
        elmc_int_t missing = elmc_dict_get_with_default_int_value(7, elmc_new_string_take("other"), dict);
        printf("%lld %lld\\n", (long long)found, (long long)missing);
        elmc_release(lookup_key);
        elmc_release(key);
        elmc_release(dict);
        elmc_release(empty);
        return (found == 42 && missing == 7) ? 0 : 1;
      }
      """,
      "42 7"
    )
  end

  @tag :runtime_c
  test "dict insert and get use comparable keys for strings" do
    run_harness(
      """
      int main(void) {
        ElmcValue *empty = elmc_list_nil();
        ElmcValue *key = elmc_new_string_take("name");
        ElmcValue *dict = elmc_dict_insert_take(key, elmc_new_int_take(42), empty);
        ElmcValue *lookup_key = elmc_new_string_take("name");
        ElmcValue *found = elmc_dict_get_take(lookup_key, dict);
        int ok = found && found->tag == ELMC_TAG_MAYBE && found->payload &&
                 ((ElmcMaybe *)found->payload)->is_just &&
                 elmc_as_int(((ElmcMaybe *)found->payload)->value) == 42;
        printf("%d\\n", ok);
        elmc_release(found);
        elmc_release(lookup_key);
        elmc_release(key);
        elmc_release(dict);
        elmc_release(empty);
        return ok ? 0 : 1;
      }
      """,
      "1"
    )
  end

  @tag :runtime_c
  test "dict merge applies left, both, and right resolvers" do
    run_harness(
      """
      static ElmcValue *left_only(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 3) return args[2];
        return elmc_dict_insert_take(args[0], args[1], args[2]);
      }

      static ElmcValue *both(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 4) return args[3];
        ElmcValue *sum = elmc_new_int_take(elmc_as_int(args[1]) + elmc_as_int(args[2]));
        ElmcValue *out = elmc_dict_insert_take(args[0], sum, args[3]);
        elmc_release(sum);
        return out;
      }

      static ElmcValue *right_only(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 3) return args[2];
        return elmc_dict_insert_take(args[0], args[1], args[2]);
      }

      int main(void) {
        ElmcValue *a = elmc_dict_from_list_take(elmc_list_cons_take(
          elmc_tuple2_take_value(elmc_new_string_take("x"), elmc_new_int_take(1)),
          elmc_list_cons_take(elmc_tuple2_take_value(elmc_new_string_take("z"), elmc_new_int_take(3)), elmc_list_nil())
        ));
        ElmcValue *b = elmc_dict_from_list_take(elmc_list_cons_take(
          elmc_tuple2_take_value(elmc_new_string_take("y"), elmc_new_int_take(10)),
          elmc_list_cons_take(elmc_tuple2_take_value(elmc_new_string_take("z"), elmc_new_int_take(30)), elmc_list_nil())
        ));

        ElmcValue *cap[1] = { NULL };
        ElmcValue *lf = elmc_closure_new_take(left_only, 3, 0, cap);
        ElmcValue *bf = elmc_closure_new_take(both, 4, 0, cap);
        ElmcValue *rf = elmc_closure_new_take(right_only, 3, 0, cap);
        ElmcValue *empty = elmc_list_nil();

        ElmcValue *merged = elmc_dict_merge_take(lf, bf, rf, a, b, empty);
        ElmcValue *kx = elmc_new_string_take("x");
        ElmcValue *ky = elmc_new_string_take("y");
        ElmcValue *kz = elmc_new_string_take("z");
        ElmcValue *mx = elmc_dict_get_take(kx, merged);
        ElmcValue *my = elmc_dict_get_take(ky, merged);
        ElmcValue *mz = elmc_dict_get_take(kz, merged);
        printf("%lld %lld %lld\\n",
          (long long)elmc_as_int(((ElmcMaybe *)mx->payload)->value),
          (long long)elmc_as_int(((ElmcMaybe *)my->payload)->value),
          (long long)elmc_as_int(((ElmcMaybe *)mz->payload)->value));
        elmc_release(mx);
        elmc_release(my);
        elmc_release(mz);
        elmc_release(kx);
        elmc_release(ky);
        elmc_release(kz);
        elmc_release(merged);
        elmc_release(lf);
        elmc_release(bf);
        elmc_release(rf);
        elmc_release(a);
        elmc_release(b);
        return 0;
      }
      """,
      "1 10 33"
    )
  end

  defp run_harness(body, expected_output) do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime C test")

    out_dir = Path.expand("tmp/runtime_stdlib_gaps", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    File.rm_rf!(out_dir)
    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    harness_path = Path.join(out_dir, "harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_runtime.h"
      #include <stdio.h>

      #{body}
      """
    )

    binary_path = Path.join(out_dir, "harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{runtime_dir}",
        Path.join(runtime_dir, "elmc_runtime.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
    assert String.trim(run_out) == expected_output
  end
end
