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
          Elmc.Test.RcTrackHarness.runtime_link_stub(),
          "json_runtime_harness.c",
          "-lm",
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
      return elmc_new_int_take(argc > 0 ? elmc_as_int(args[0]) + 1 : 0);
    }

    static ElmcValue *sum2(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 2) return elmc_new_int_take(0);
      return elmc_new_int_take(elmc_as_int(args[0]) + elmc_as_int(args[1]));
    }

    static ElmcValue *sum3(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 3) return elmc_new_int_take(0);
      return elmc_new_int_take(elmc_as_int(args[0]) + elmc_as_int(args[1]) + elmc_as_int(args[2]));
    }

    static ElmcValue *sum6(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 6) return elmc_new_int_take(0);
      return elmc_new_int_take(elmc_as_int(args[0]) + elmc_as_int(args[1]) + elmc_as_int(args[2]) +
                          elmc_as_int(args[3]) + elmc_as_int(args[4]) + elmc_as_int(args[5]));
    }

    static ElmcValue *sum7(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 7) return elmc_new_int_take(0);
      return elmc_new_int_take(elmc_as_int(args[0]) + elmc_as_int(args[1]) + elmc_as_int(args[2]) +
                          elmc_as_int(args[3]) + elmc_as_int(args[4]) + elmc_as_int(args[5]) +
                          elmc_as_int(args[6]));
    }

    static ElmcValue *identity(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 1 || !args[0]) return elmc_int_zero();
      return elmc_retain(args[0]);
    }

    static ElmcValue *encode_int_value(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)captures;
      (void)capture_count;
      if (argc < 1 || !args[0]) return elmc_new_string_take("0");
      return elmc_json_encode_int(args[0]);
    }

    static ElmcValue *name_decoder(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
      (void)args;
      (void)argc;
      (void)captures;
      (void)capture_count;
      ElmcValue *field = elmc_new_string_take("name");
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
      return elmc_new_string_take(text);
    }

    static ElmcValue *decode(ElmcValue *decoder, const char *raw) {
      ElmcValue *input = json_text(raw);
      ElmcValue *result = elmc_json_decode_string(decoder, input);
      elmc_release(input);
      return result;
    }

    int main(void) {
      ElmcValue *screen = elmc_new_string_take("screen");
      ElmcValue *width = elmc_new_string_take("width");
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

      ElmcValue *tag = elmc_new_string_take("message_tag");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *tag_decoder = elmc_json_decode_field(tag, int_decoder);
      ElmcValue *r2 = decode(tag_decoder, "{\\"message_tag\\":12,\\"value\\":21}");
      if (result_int(r2) != 12) return 2;
      elmc_release(r2);
      elmc_release(tag_decoder);
      elmc_release(int_decoder);
      elmc_release(tag);

      ElmcValue *idx = elmc_new_int_take(1);
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *index_decoder = elmc_json_decode_index(idx, int_decoder);
      ElmcValue *r3 = decode(index_decoder, "[4,5,6]");
      if (result_int(r3) != 5) return 3;
      elmc_release(r3);
      elmc_release(index_decoder);
      elmc_release(int_decoder);
      elmc_release(idx);

      ElmcValue *missing = elmc_new_string_take("missing");
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
      decoders = elmc_list_cons_take(string_decoder, decoders);
      decoders = elmc_list_cons_take(int_decoder, decoders);
      ElmcValue *one_of = elmc_json_decode_one_of(decoders);
      ElmcValue *r5 = decode(one_of, "7");
      if (result_int(r5) != 7) return 5;
      elmc_release(r5);
      elmc_release(one_of);
      elmc_release(decoders);

      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *inc_closure = elmc_closure_new_take(inc, 0, 0, NULL);
      ElmcValue *map_decoder = elmc_json_decode_map(inc_closure, int_decoder);
      ElmcValue *r6 = decode(map_decoder, "9");
      if (result_int(r6) != 10) return 6;
      elmc_release(r6);
      elmc_release(map_decoder);
      elmc_release(inc_closure);
      elmc_release(int_decoder);

      ElmcValue *field_a = elmc_new_string_take("a");
      ElmcValue *field_b = elmc_new_string_take("b");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *a_decoder = elmc_json_decode_field(field_a, int_decoder);
      ElmcValue *b_decoder = elmc_json_decode_field(field_b, int_decoder);
      ElmcValue *sum_closure = elmc_closure_new_take(sum2, 0, 0, NULL);
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

      field_a = elmc_new_string_take("a");
      field_b = elmc_new_string_take("b");
      ElmcValue *field_c = elmc_new_string_take("c");
      int_decoder = elmc_json_decode_int_decoder();
      a_decoder = elmc_json_decode_field(field_a, int_decoder);
      b_decoder = elmc_json_decode_field(field_b, int_decoder);
      ElmcValue *c_decoder = elmc_json_decode_field(field_c, int_decoder);
      ElmcValue *sum3_closure = elmc_closure_new_take(sum3, 0, 0, NULL);
      ElmcValue *map3_decoder = elmc_json_decode_map3(sum3_closure, a_decoder, b_decoder, c_decoder);
      ElmcValue *r7b = decode(map3_decoder, "{\\"a\\":1,\\"b\\":2,\\"c\\":3}");
      if (result_int(r7b) != 6) return 15;
      elmc_release(r7b);
      elmc_release(map3_decoder);
      elmc_release(sum3_closure);
      elmc_release(c_decoder);
      elmc_release(a_decoder);
      elmc_release(b_decoder);
      elmc_release(int_decoder);
      elmc_release(field_a);
      elmc_release(field_b);
      elmc_release(field_c);

      ElmcValue *kind = elmc_new_string_take("kind");
      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *kind_decoder = elmc_json_decode_field(kind, int_decoder);
      ElmcValue *name_closure = elmc_closure_new_take(name_decoder, 0, 0, NULL);
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

      ElmcValue *payload = elmc_new_string_take("payload");
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

      ElmcValue *raw = elmc_new_string_take("{\\"ok\\":true}");
      ElmcValue *encoded = elmc_json_encode_string(elmc_new_string_take("a\\\\nb"));
      if (!encoded || encoded->tag != ELMC_TAG_STRING || strcmp((const char *)encoded->payload, "\\"a\\\\\\\\nb\\"") != 0) return 13;
      elmc_release(encoded);

      ElmcValue *key = elmc_new_string_take("nested");
      ElmcValue *pair = elmc_tuple2_take_value(key, raw);
      ElmcValue *pairs = elmc_list_cons_take(pair, elmc_list_nil());
      ElmcValue *object = elmc_json_encode_object(pairs);
      if (!object || object->tag != ELMC_TAG_STRING || strcmp((const char *)object->payload, "{\\"nested\\":{\\"ok\\":true}}") != 0) return 14;
      elmc_release(object);
      elmc_release(pairs);

      ElmcValue *field_d;
      ElmcValue *field_e;
      ElmcValue *field_f;
      ElmcValue *d_decoder;
      ElmcValue *e_decoder;
      ElmcValue *f_decoder;
      field_a = elmc_new_string_take("a");
      field_b = elmc_new_string_take("b");
      field_c = elmc_new_string_take("c");
      field_d = elmc_new_string_take("d");
      field_e = elmc_new_string_take("e");
      field_f = elmc_new_string_take("f");
      int_decoder = elmc_json_decode_int_decoder();
      a_decoder = elmc_json_decode_field(field_a, int_decoder);
      b_decoder = elmc_json_decode_field(field_b, int_decoder);
      c_decoder = elmc_json_decode_field(field_c, int_decoder);
      d_decoder = elmc_json_decode_field(field_d, int_decoder);
      e_decoder = elmc_json_decode_field(field_e, int_decoder);
      f_decoder = elmc_json_decode_field(field_f, int_decoder);
      ElmcValue *sum6_closure = elmc_closure_new_take(sum6, 0, 0, NULL);
      ElmcValue *map6_decoder = elmc_json_decode_map6(sum6_closure, a_decoder, b_decoder, c_decoder, d_decoder, e_decoder, f_decoder);
      ElmcValue *r15 = decode(map6_decoder, "{\\"a\\":1,\\"b\\":2,\\"c\\":3,\\"d\\":4,\\"e\\":5,\\"f\\":6}");
      if (result_int(r15) != 21) return 16;
      elmc_release(r15);
      elmc_release(map6_decoder);
      elmc_release(sum6_closure);
      elmc_release(f_decoder);
      elmc_release(e_decoder);
      elmc_release(d_decoder);
      elmc_release(c_decoder);
      elmc_release(b_decoder);
      elmc_release(a_decoder);
      elmc_release(int_decoder);
      elmc_release(field_f);
      elmc_release(field_e);
      elmc_release(field_d);
      elmc_release(field_c);
      elmc_release(field_b);
      elmc_release(field_a);

      int_decoder = elmc_json_decode_int_decoder();
      ElmcValue *kvp_decoder = elmc_json_decode_key_value_pairs(int_decoder);
      ElmcValue *r16 = decode(kvp_decoder, "{\\"one\\":1,\\"two\\":2}");
      if (!r16 || r16->tag != ELMC_TAG_RESULT || !r16->payload || !((ElmcResult *)r16->payload)->is_ok) return 17;
      ElmcValue *kvp_list = ((ElmcResult *)r16->payload)->value;
      if (!kvp_list || kvp_list->tag != ELMC_TAG_LIST) return 17;
      elmc_release(r16);
      elmc_release(kvp_decoder);
      elmc_release(int_decoder);

      {
        ElmcValue *fa = elmc_new_string_take("a");
        ElmcValue *fb = elmc_new_string_take("b");
        ElmcValue *fc = elmc_new_string_take("c");
        ElmcValue *fd = elmc_new_string_take("d");
        ElmcValue *fe = elmc_new_string_take("e");
        ElmcValue *ff = elmc_new_string_take("f");
        ElmcValue *fg = elmc_new_string_take("g");
        ElmcValue *int_dec = elmc_json_decode_int_decoder();
        ElmcValue *da = elmc_json_decode_field(fa, int_dec);
        ElmcValue *db = elmc_json_decode_field(fb, int_dec);
        ElmcValue *dc = elmc_json_decode_field(fc, int_dec);
        ElmcValue *dd = elmc_json_decode_field(fd, int_dec);
        ElmcValue *de = elmc_json_decode_field(fe, int_dec);
        ElmcValue *df = elmc_json_decode_field(ff, int_dec);
        ElmcValue *dg = elmc_json_decode_field(fg, int_dec);
        ElmcValue *sum7_closure = elmc_closure_new_take(sum7, 0, 0, NULL);
        ElmcValue *map7_decoder = elmc_json_decode_map7(sum7_closure, da, db, dc, dd, de, df, dg);
        ElmcValue *r17 = decode(map7_decoder, "{\\"a\\":1,\\"b\\":2,\\"c\\":3,\\"d\\":4,\\"e\\":5,\\"f\\":6,\\"g\\":7}");
        if (result_int(r17) != 28) return 18;
        elmc_release(r17);
        elmc_release(map7_decoder);
        elmc_release(sum7_closure);
        elmc_release(dg);
        elmc_release(df);
        elmc_release(de);
        elmc_release(dd);
        elmc_release(dc);
        elmc_release(db);
        elmc_release(da);
        elmc_release(int_dec);
        elmc_release(fg);
        elmc_release(ff);
        elmc_release(fe);
        elmc_release(fd);
        elmc_release(fc);
        elmc_release(fb);
        elmc_release(fa);
      }

      ElmcValue *dict_key = elmc_new_string_take("x");
      ElmcValue *dict_val = elmc_new_int_take(9);
      ElmcValue *dict_pair = elmc_tuple2_take_value(dict_key, dict_val);
      ElmcValue *dict_list = elmc_list_cons_take(dict_pair, elmc_list_nil());
      ElmcValue *id_closure = elmc_closure_new_take(identity, 0, 0, NULL);
      ElmcValue *encode_int_closure = elmc_closure_new_take(encode_int_value, 0, 0, NULL);
      ElmcValue *encoded_dict = elmc_json_encode_dict(id_closure, encode_int_closure, dict_list);
      if (!encoded_dict || encoded_dict->tag != ELMC_TAG_STRING || strcmp((const char *)encoded_dict->payload, "{\\"x\\":9}") != 0) return 19;
      elmc_release(encoded_dict);
      elmc_release(encode_int_closure);
      elmc_release(id_closure);
      elmc_release(dict_list);

      printf("json-runtime-ok\\n");
      return 0;
    }
    """
  end
end
