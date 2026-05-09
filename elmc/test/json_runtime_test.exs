defmodule Elmc.JsonRuntimeTest do
  use ExUnit.Case

  test "compact JSON runtime decodes and encodes supported shapes" do
    cc = System.find_executable("cc") || System.find_executable("gcc")
    if is_nil(cc), do: flunk("no C compiler available for JSON runtime test")

    out_dir = Path.expand("tmp/json_runtime", __DIR__)
    runtime_dir = Path.join(out_dir, "runtime")
    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir)

    harness_path = Path.join(out_dir, "json_runtime_harness.c")
    binary_path = Path.join(out_dir, "json_runtime_harness")
    File.write!(harness_path, json_runtime_harness_source())

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "runtime/elmc_runtime.c",
          "json_runtime_harness.c",
          "-o",
          "json_runtime_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
    assert run_out =~ "json-runtime-ok"
  end

  defp json_runtime_harness_source do
    """
    #include "elmc_runtime.h"
    #include <stdio.h>
    #include <string.h>

    static ElmcValue *inc(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      return elmc_new_int(argc > 0 ? elmc_as_int(args[0]) + 1 : 0);
    }

    static ElmcValue *sum2(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 2) return elmc_new_int(0);
      return elmc_new_int(elmc_as_int(args[0]) + elmc_as_int(args[1]));
    }

    static ElmcValue *name_decoder(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)args;
      (void)argc;
      (void)captures;
      (void)capture_count;
      ElmcValue *field = elmc_new_string("name");
      ElmcValue *string_decoder = elmc_json_decode_string_decoder();
      ElmcValue *decoder = elmc_json_decode_field(field, string_decoder);
      elmc_release(field);
      elmc_release(string_decoder);
      return decoder;
    }

    static int result_int(ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return -999;
      ElmcResult *res = (ElmcResult *)result->payload;
      if (!res->is_ok || !res->value) return -998;
      return (int)elmc_as_int(res->value);
    }

    static const char *result_string(ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return NULL;
      ElmcResult *res = (ElmcResult *)result->payload;
      if (!res->is_ok || !res->value || res->value->tag != ELMC_TAG_STRING) return NULL;
      return (const char *)res->value->payload;
    }

    static int result_is_err(ElmcValue *result) {
      return result && result->tag == ELMC_TAG_RESULT && result->payload &&
             !((ElmcResult *)result->payload)->is_ok;
    }

    static int result_is_nothing(ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return 0;
      ElmcResult *res = (ElmcResult *)result->payload;
      if (!res->is_ok || !res->value || res->value->tag != ELMC_TAG_MAYBE || !res->value->payload) return 0;
      return ((ElmcMaybe *)res->value->payload)->is_just == 0;
    }

    static ElmcValue *json_text(const char *text) {
      return elmc_new_string(text);
    }

    static ElmcValue *decode(ElmcValue *decoder, const char *raw) {
      ElmcValue *input = json_text(raw);
      ElmcValue *result = elmc_json_decode_string(decoder, input);
      elmc_release(input);
      return result;
    }

    int main(void) {
      ElmcValue *screen = elmc_new_string("screen");
      ElmcValue *width = elmc_new_string("width");
      ElmcValue *int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *width_decoder = elmc_json_decode_field(width, int_decoder);
      ElmcValue *screen_width_decoder = elmc_json_decode_field(screen, width_decoder);
      ElmcValue *r1 = decode(screen_width_decoder, "{\\"screen\\":{\\"width\\":144,\\"is_color\\":true},\\"watch_profile_id\\":\\"basalt\\"}");
      if (result_int(r1) != 144) return 1;
      elmc_release(r1);
      elmc_release(screen_width_decoder);
      elmc_release(width_decoder);
      elmc_release(int_decoder);
      elmc_release(width);
      elmc_release(screen);

      ElmcValue *tag = elmc_new_string("message_tag");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *tag_decoder = elmc_json_decode_field(tag, int_decoder);
      ElmcValue *r2 = decode(tag_decoder, "{\\"message_tag\\":12,\\"value\\":21}");
      if (result_int(r2) != 12) return 2;
      elmc_release(r2);
      elmc_release(tag_decoder);
      elmc_release(int_decoder);
      elmc_release(tag);

      ElmcValue *idx = elmc_new_int(1);
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *index_decoder = elmc_json_decode_index(idx, int_decoder);
      ElmcValue *r3 = decode(index_decoder, "[4,5,6]");
      if (result_int(r3) != 5) return 3;
      elmc_release(r3);
      elmc_release(index_decoder);
      elmc_release(int_decoder);
      elmc_release(idx);

      ElmcValue *missing = elmc_new_string("missing");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *missing_decoder = elmc_json_decode_field(missing, int_decoder);
      ElmcValue *maybe_decoder = elmc_json_decode_maybe(missing_decoder);
      ElmcValue *r4 = decode(maybe_decoder, "{\\"present\\":1}");
      if (!result_is_nothing(r4)) return 4;
      elmc_release(r4);
      elmc_release(maybe_decoder);
      elmc_release(missing_decoder);
      elmc_release(int_decoder);
      elmc_release(missing);

      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *string_decoder = elmc_json_decode_string_decoder();
      ElmcValue *decoders = elmc_list_nil();
      ElmcValue *tmp = elmc_list_cons(string_decoder, decoders);
      elmc_release(decoders);
      decoders = elmc_list_cons(int_decoder, tmp);
      elmc_release(tmp);
      ElmcValue *one_of = elmc_json_decode_one_of(decoders);
      ElmcValue *r5 = decode(one_of, "7");
      if (result_int(r5) != 7) return 5;
      elmc_release(r5);
      elmc_release(one_of);
      elmc_release(decoders);
      elmc_release(string_decoder);
      elmc_release(int_decoder);

      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *inc_closure = elmc_closure_new(inc, 0, NULL);
      ElmcValue *map_decoder = elmc_json_decode_map(inc_closure, int_decoder);
      ElmcValue *r6 = decode(map_decoder, "9");
      if (result_int(r6) != 10) return 6;
      elmc_release(r6);
      elmc_release(map_decoder);
      elmc_release(inc_closure);
      elmc_release(int_decoder);

      ElmcValue *field_a = elmc_new_string("a");
      ElmcValue *field_b = elmc_new_string("b");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *a_decoder = elmc_json_decode_field(field_a, int_decoder);
      ElmcValue *b_decoder = elmc_json_decode_field(field_b, int_decoder);
      ElmcValue *sum_closure = elmc_closure_new(sum2, 0, NULL);
      ElmcValue *map2_decoder = elmc_json_decode_map2(sum_closure, a_decoder, b_decoder);
      ElmcValue *r7 = decode(map2_decoder, "{\\"a\\":2,\\"b\\":5}");
      if (result_int(r7) != 7) return 7;
      elmc_release(r7);
      elmc_release(map2_decoder);
      elmc_release(sum_closure);
      elmc_release(a_decoder);
      elmc_release(b_decoder);
      elmc_release(int_decoder);
      elmc_release(field_a);
      elmc_release(field_b);

      ElmcValue *kind = elmc_new_string("kind");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *kind_decoder = elmc_json_decode_field(kind, int_decoder);
      ElmcValue *name_closure = elmc_closure_new(name_decoder, 0, NULL);
      ElmcValue *and_then_decoder = elmc_json_decode_and_then(name_closure, kind_decoder);
      ElmcValue *r8 = decode(and_then_decoder, "{\\"kind\\":1,\\"name\\":\\"demo\\"}");
      const char *name = result_string(r8);
      if (!name || strcmp(name, "demo") != 0) return 8;
      elmc_release(r8);
      elmc_release(and_then_decoder);
      elmc_release(name_closure);
      elmc_release(kind_decoder);
      elmc_release(int_decoder);
      elmc_release(kind);

      ElmcValue *payload = elmc_new_string("payload");
      ElmcValue *value_decoder = elmc_json_decode_value_decoder();
      ElmcValue *payload_decoder = elmc_json_decode_field(payload, value_decoder);
      ElmcValue *r9 = decode(payload_decoder, "{\\"payload\\":{\\"x\\":[1,true,null]}}");
      const char *payload_text = result_string(r9);
      if (!payload_text || strcmp(payload_text, "{\\"x\\":[1,true,null]}") != 0) return 9;
      elmc_release(r9);
      elmc_release(payload_decoder);
      elmc_release(value_decoder);
      elmc_release(payload);

      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *r10 = decode(int_decoder, "1 trailing");
      if (!result_is_err(r10)) return 10;
      elmc_release(r10);
      ElmcValue *r11 = decode(int_decoder, "[1,]");
      if (!result_is_err(r11)) return 11;
      elmc_release(r11);
      ElmcValue *r12 = decode(int_decoder, "1.5");
      if (!result_is_err(r12)) return 12;
      elmc_release(r12);
      elmc_release(int_decoder);

      ElmcValue *raw = elmc_new_string("{\\"ok\\":true}");
      ElmcValue *encoded = elmc_json_encode_string(elmc_new_string("a\\\\nb"));
      if (!encoded || encoded->tag != ELMC_TAG_STRING || strcmp((const char *)encoded->payload, "\\"a\\\\\\\\nb\\"") != 0) return 13;
      elmc_release(encoded);

      ElmcValue *key = elmc_new_string("nested");
      ElmcValue *pair = elmc_tuple2(key, raw);
      ElmcValue *pairs = elmc_list_nil();
      ElmcValue *pairs2 = elmc_list_cons(pair, pairs);
      ElmcValue *object = elmc_json_encode_object(pairs2);
      if (!object || object->tag != ELMC_TAG_STRING || strcmp((const char *)object->payload, "{\\"nested\\":{\\"ok\\":true}}") != 0) return 14;
      elmc_release(object);
      elmc_release(pairs2);
      elmc_release(pairs);
      elmc_release(pair);
      elmc_release(key);
      elmc_release(raw);

      printf("json-runtime-ok\\n");
      return 0;
    }
    """
  end
end
