defmodule Elmc.RuntimeStdlibGapsTest do
  use ExUnit.Case

  alias Elmc.Test.RcTrackHarness

  @tag :runtime_c
  test "list sort uses official comparable order for strings" do
    run_harness(
      """
      int main(void) {
        ElmcValue *list = elmc_list_nil();
        ElmcValue *c = elmc_harness_new_string("c");
        list = elmc_harness_list_cons(c, list);
        ElmcValue *a = elmc_harness_new_string("a");
        list = elmc_harness_list_cons(a, list);
        ElmcValue *b = elmc_harness_new_string("b");
        list = elmc_harness_list_cons(b, list);

        ElmcValue *sorted = NULL;
        if (elmc_list_sort(&sorted, list) != RC_SUCCESS) return 1;
        ElmcValue *cursor = sorted;
        printf("%s", (const char *)((ElmcCons *)cursor->payload)->head->payload);
        cursor = ((ElmcCons *)cursor->payload)->tail;
        printf(" %s", (const char *)((ElmcCons *)cursor->payload)->head->payload);
        cursor = ((ElmcCons *)cursor->payload)->tail;
        printf(" %s\\n", (const char *)((ElmcCons *)cursor->payload)->head->payload);

        elmc_release(sorted);
        elmc_release(list);
        return 0;
      }
      """,
      "a b c"
    )
  end

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
        ElmcValue *n3 = elmc_harness_new_int(3);
        list = elmc_harness_list_cons(n3, list);
        ElmcValue *n1 = elmc_harness_new_int(1);
        list = elmc_harness_list_cons(n1, list);
        ElmcValue *n2 = elmc_harness_new_int(2);
        list = elmc_harness_list_cons(n2, list);

        ElmcValue *f = elmc_harness_closure_new(by_identity, 1);
        ElmcValue *sorted = NULL;
        if (elmc_list_sort_by(&sorted, f, list) != RC_SUCCESS) return 1;
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
      static RC compare_ints(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 2) return elmc_new_int(out, 0);
        return elmc_basics_compare(out, args[0], args[1]);
      }

      int main(void) {
        ElmcValue *list = elmc_list_nil();
        ElmcValue *n3 = elmc_harness_new_int(3);
        list = elmc_harness_list_cons(n3, list);
        ElmcValue *n1 = elmc_harness_new_int(1);
        list = elmc_harness_list_cons(n1, list);
        ElmcValue *n2 = elmc_harness_new_int(2);
        list = elmc_harness_list_cons(n2, list);

        ElmcValue *f = elmc_harness_closure_new_rc(compare_ints, 2, 0, NULL);
        ElmcValue *sorted = NULL;
        if (elmc_list_sort_with(&sorted, f, list) != RC_SUCCESS) return 1;
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
  test "list sum and product keep official number type for floats" do
    run_harness(
      """
      int main(void) {
        ElmcValue *list = elmc_list_nil();
        ElmcValue *b = elmc_harness_new_float(2.5);
        list = elmc_harness_list_cons(b, list);
        ElmcValue *a = elmc_harness_new_float(1.5);
        list = elmc_harness_list_cons(a, list);
        ElmcValue *sum = NULL;
        if (elmc_list_sum(&sum, list) != RC_SUCCESS) return 1;
        ElmcValue *prod_list = elmc_list_nil();
        ElmcValue *d = elmc_harness_new_float(3.0);
        prod_list = elmc_harness_list_cons(d, prod_list);
        ElmcValue *c = elmc_harness_new_float(2.0);
        prod_list = elmc_harness_list_cons(c, prod_list);
        ElmcValue *prod = NULL;
        if (elmc_list_product(&prod, prod_list) != RC_SUCCESS) return 1;
        ElmcValue *empty = elmc_list_nil();
        ElmcValue *empty_sum = NULL;
        if (elmc_list_sum_float(&empty_sum, empty) != RC_SUCCESS) return 1;
        ElmcValue *empty_prod = NULL;
        if (elmc_list_product_float(&empty_prod, empty) != RC_SUCCESS) return 1;
        printf("%.1f %.1f %.1f %.1f\\n", elmc_as_float(sum), elmc_as_float(prod), elmc_as_float(empty_sum), elmc_as_float(empty_prod));
        elmc_release(empty_prod);
        elmc_release(empty_sum);
        elmc_release(empty);
        elmc_release(prod);
        elmc_release(prod_list);
        elmc_release(sum);
        elmc_release(list);
        return 0;
      }
      """,
      "4.0 6.0 0.0 1.0"
    )
  end

  @tag :runtime_c
  test "debug toString prefixes Set Dict and Array like official elm/core" do
    run_harness(
      """
      int main(void) {
        ElmcValue *list = elmc_list_nil();
        ElmcValue *two = elmc_harness_new_int(2);
        list = elmc_harness_list_cons(two, list);
        ElmcValue *one = elmc_harness_new_int(1);
        list = elmc_harness_list_cons(one, list);
        ElmcValue *set_text = NULL;
        ElmcValue *dict_text = NULL;
        ElmcValue *array_text = NULL;
        if (elmc_debug_set_to_string(&set_text, list) != RC_SUCCESS) return 1;
        if (elmc_debug_dict_to_string(&dict_text, list) != RC_SUCCESS) return 1;
        if (elmc_debug_array_to_string(&array_text, list) != RC_SUCCESS) return 1;
        printf("%s|%s|%s\\n",
          (const char *)set_text->payload,
          (const char *)dict_text->payload,
          (const char *)array_text->payload);
        elmc_release(array_text);
        elmc_release(dict_text);
        elmc_release(set_text);
        elmc_release(list);
        return 0;
      }
      """,
      "Set.fromList [1,2]|Dict.fromList [1,2]|Array.fromList [1,2]"
    )
  end

  @tag :runtime_c
  test "debug toString distinguishes official #3 from a nested pair" do
    run_harness(
      """
      int main(void) {
        ElmcValue *one = elmc_harness_new_int(1);
        ElmcValue *two = elmc_harness_new_int(2);
        ElmcValue *three = elmc_harness_new_int(3);
        ElmcValue *inner = elmc_harness_tuple2_take(two, three);
        ElmcValue *nested_pair = elmc_harness_tuple2_take(one, inner);
        ElmcValue *triple = NULL;
        ElmcValue *text3 = NULL;
        ElmcValue *textn = NULL;
        if (elmc_tuple3(&triple, one, two, three) != RC_SUCCESS) return 1;
        if (elmc_debug_to_string(&text3, triple) != RC_SUCCESS) return 2;
        if (elmc_debug_to_string(&textn, nested_pair) != RC_SUCCESS) return 3;
        if (elmc_value_equal(triple, nested_pair)) return 4;
        printf("%s|%s\\n", (const char *)text3->payload, (const char *)textn->payload);
        elmc_release(text3);
        elmc_release(textn);
        elmc_release(triple);
        elmc_release(nested_pair);
        return 0;
      }
      """,
      "(1,2,3)|(1,(2,3))"
    )
  end

  @tag :runtime_c
  test "compare and list sort walk official #3 as a, then b, then c" do
    run_harness(
      """
      int main(void) {
        ElmcValue *one = elmc_harness_new_int(1);
        ElmcValue *two = elmc_harness_new_int(2);
        ElmcValue *three = elmc_harness_new_int(3);
        ElmcValue *four = elmc_harness_new_int(4);
        ElmcValue *zero = elmc_harness_new_int(0);
        ElmcValue *nine = elmc_harness_new_int(9);
        ElmcValue *t123 = NULL;
        ElmcValue *t124 = NULL;
        ElmcValue *t200 = NULL;
        ElmcValue *t190 = NULL;
        ElmcValue *ord_lt = NULL;
        ElmcValue *ord_eq = NULL;
        ElmcValue *ord_gt = NULL;
        ElmcValue *list = elmc_list_nil();
        ElmcValue *sorted = NULL;
        if (elmc_tuple3(&t123, one, two, three) != RC_SUCCESS) return 1;
        if (elmc_tuple3(&t124, one, two, four) != RC_SUCCESS) return 2;
        if (elmc_tuple3(&t200, two, zero, zero) != RC_SUCCESS) return 3;
        if (elmc_tuple3(&t190, one, nine, zero) != RC_SUCCESS) return 4;
        if (elmc_basics_compare(&ord_lt, t123, t124) != RC_SUCCESS) return 5;
        if (elmc_basics_compare(&ord_eq, t123, t123) != RC_SUCCESS) return 6;
        if (elmc_basics_compare(&ord_gt, t200, t123) != RC_SUCCESS) return 7;
        list = elmc_harness_list_cons(t200, list);
        list = elmc_harness_list_cons(t190, list);
        list = elmc_harness_list_cons(t123, list);
        if (elmc_list_sort(&sorted, list) != RC_SUCCESS) return 8;
        ElmcValue *cursor = sorted;
        ElmcValue *h0 = ((ElmcCons *)cursor->payload)->head;
        cursor = ((ElmcCons *)cursor->payload)->tail;
        ElmcValue *h1 = ((ElmcCons *)cursor->payload)->head;
        cursor = ((ElmcCons *)cursor->payload)->tail;
        ElmcValue *h2 = ((ElmcCons *)cursor->payload)->head;
        printf("%lld|%lld|%lld|%d|%d|%d\\n",
          (long long)elmc_as_int(ord_lt),
          (long long)elmc_as_int(ord_eq),
          (long long)elmc_as_int(ord_gt),
          elmc_value_equal(h0, t123) ? 1 : 0,
          elmc_value_equal(h1, t190) ? 1 : 0,
          elmc_value_equal(h2, t200) ? 1 : 0);
        elmc_release(sorted);
        elmc_release(list);
        elmc_release(ord_lt);
        elmc_release(ord_eq);
        elmc_release(ord_gt);
        elmc_release(t123);
        elmc_release(t124);
        elmc_release(t200);
        elmc_release(t190);
        return 0;
      }
      """,
      "-1|0|1|1|1|1"
    )
  end

  @tag :runtime_c
  test "debug toString escapes vertical tab in Char like official elm/core" do
    run_harness(
      """
      int main(void) {
        ElmcValue *ch = NULL;
        if (elmc_new_char(&ch, 0x0B) != RC_SUCCESS) return 1;
        ElmcValue *text = NULL;
        if (elmc_debug_to_string(&text, ch) != RC_SUCCESS) return 1;
        printf("%s\\n", (const char *)text->payload);
        elmc_release(text);
        elmc_release(ch);
        return 0;
      }
      """,
      "'\\v'"
    )
  end

  @tag :runtime_c
  test "string reverse repeat trim and words match official elm/core" do
    run_harness(
      """
      int main(void) {
        ElmcValue *stressed = elmc_harness_new_string("stressed");
        ElmcValue *ha = elmc_harness_new_string("ha");
        ElmcValue *nbsp = elmc_harness_new_string("\\302\\240x\\302\\240");
        ElmcValue *words_in = elmc_harness_new_string("a\\302\\240b");
        ElmcValue *zero = elmc_harness_new_int(0);
        ElmcValue *neg = elmc_harness_new_int(-1);
        ElmcValue *three = elmc_harness_new_int(3);
        ElmcValue *rev = NULL;
        ElmcValue *rep = NULL;
        ElmcValue *rep0 = NULL;
        ElmcValue *repn = NULL;
        ElmcValue *trimmed = NULL;
        ElmcValue *words = NULL;
        if (elmc_string_reverse(&rev, stressed) != RC_SUCCESS) return 1;
        if (elmc_string_repeat(&rep, three, ha) != RC_SUCCESS) return 1;
        if (elmc_string_repeat(&rep0, zero, ha) != RC_SUCCESS) return 1;
        if (elmc_string_repeat(&repn, neg, ha) != RC_SUCCESS) return 1;
        if (elmc_string_trim(&trimmed, nbsp) != RC_SUCCESS) return 1;
        if (elmc_string_words(&words, words_in) != RC_SUCCESS) return 1;
        ElmcValue *w0 = ((ElmcCons *)words->payload)->head;
        ElmcValue *w1 = ((ElmcCons *)((ElmcCons *)words->payload)->tail->payload)->head;
        printf("%s|%s|%s|%s|%s|%s|%s\\n",
          (const char *)rev->payload,
          (const char *)rep->payload,
          (const char *)rep0->payload,
          (const char *)repn->payload,
          (const char *)trimmed->payload,
          (const char *)w0->payload,
          (const char *)w1->payload);
        elmc_release(words);
        elmc_release(trimmed);
        elmc_release(repn);
        elmc_release(rep0);
        elmc_release(rep);
        elmc_release(rev);
        elmc_release(three);
        elmc_release(neg);
        elmc_release(zero);
        elmc_release(words_in);
        elmc_release(nbsp);
        elmc_release(ha);
        elmc_release(stressed);
        return 0;
      }
      """,
      "desserts|hahaha|||x|a|b"
    )
  end

  @tag :runtime_c
  test "char toLocaleUpper matches official elm/core on ASCII" do
    run_harness(
      """
      int main(void) {
        ElmcValue *a = NULL;
        ElmcValue *z = NULL;
        ElmcValue *up = NULL;
        ElmcValue *lo = NULL;
        if (elmc_new_char(&a, (elmc_int_t)'a') != RC_SUCCESS) return 1;
        if (elmc_new_char(&z, (elmc_int_t)'Z') != RC_SUCCESS) return 1;
        if (elmc_char_to_locale_upper(&up, a) != RC_SUCCESS) return 1;
        if (elmc_char_to_locale_lower(&lo, z) != RC_SUCCESS) return 1;
        printf("%lld %lld\\n", (long long)elmc_as_int(up), (long long)elmc_as_int(lo));
        elmc_release(lo);
        elmc_release(up);
        elmc_release(z);
        elmc_release(a);
        return 0;
      }
      """,
      "65 122"
    )
  end

  @tag :runtime_c
  test "string map and filter match official elm/core" do
    run_harness(
      """
      static RC slash_to_dot(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 1 || !args[0]) return RC_ERR_INVALID_ARG;
        elmc_int_t c = elmc_as_int(args[0]);
        if (c == '/') return elmc_new_char(out, (elmc_int_t)'.');
        *out = elmc_retain(args[0]);
        return RC_SUCCESS;
      }

      static RC keep_digit(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 1 || !args[0]) return RC_ERR_INVALID_ARG;
        elmc_int_t c = elmc_as_int(args[0]);
        int digit = c >= '0' && c <= '9';
        return elmc_new_bool(out, digit);
      }

      int main(void) {
        ElmcValue *src = elmc_harness_new_string("a/b/c");
        ElmcValue *digits = elmc_harness_new_string("R2-D2");
        ElmcValue *map_f = elmc_harness_closure_new_rc(slash_to_dot, 1, 0, NULL);
        ElmcValue *filter_f = elmc_harness_closure_new_rc(keep_digit, 1, 0, NULL);
        ElmcValue *mapped = NULL;
        ElmcValue *filtered = NULL;
        if (elmc_string_map(&mapped, map_f, src) != RC_SUCCESS) return 1;
        if (elmc_string_filter(&filtered, filter_f, digits) != RC_SUCCESS) return 1;
        printf("%s|%s\\n", (const char *)mapped->payload, (const char *)filtered->payload);
        elmc_release(filtered);
        elmc_release(mapped);
        elmc_release(filter_f);
        elmc_release(map_f);
        elmc_release(digits);
        elmc_release(src);
        return 0;
      }
      """,
      "a.b.c|22"
    )
  end

  @tag :runtime_c
  test "string fromFloat matches official number + ''" do
    run_harness(
      """
      int main(void) {
        ElmcValue *half = elmc_harness_new_float(0.5);
        ElmcValue *whole = elmc_harness_new_float(123.0);
        ElmcValue *frac = elmc_harness_new_float(3.9);
        ElmcValue *s0 = NULL;
        ElmcValue *s1 = NULL;
        ElmcValue *s2 = NULL;
        if (elmc_string_from_float(&s0, half) != RC_SUCCESS) return 1;
        if (elmc_string_from_float(&s1, whole) != RC_SUCCESS) return 1;
        if (elmc_string_from_float(&s2, frac) != RC_SUCCESS) return 1;
        printf("%s %s %s\\n",
          (const char *)s0->payload,
          (const char *)s1->payload,
          (const char *)s2->payload);
        elmc_release(s0);
        elmc_release(s1);
        elmc_release(s2);
        elmc_release(half);
        elmc_release(whole);
        elmc_release(frac);
        return 0;
      }
      """,
      "0.5 123 3.9"
    )
  end

  @tag :runtime_c
  test "string words and lines match official elm/core" do
    run_harness(
      """
      static void print_string_list(ElmcValue *list) {
        int first = 1;
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          const char *text =
            (node->head && node->head->tag == ELMC_TAG_STRING && node->head->payload)
              ? (const char *)node->head->payload
              : "";
          printf("%s%s", first ? "" : ",", text);
          first = 0;
          cursor = node->tail;
        }
      }

      int main(void) {
        ElmcValue *words_src = elmc_harness_new_string("How are \\t you? \\n Good?");
        ElmcValue *empty = elmc_harness_new_string("");
        ElmcValue *lines_src = elmc_harness_new_string("a\\r\\nb\\nc");
        ElmcValue *words = NULL;
        ElmcValue *empty_words = NULL;
        ElmcValue *lines = NULL;
        if (elmc_string_words(&words, words_src) != RC_SUCCESS) return 1;
        if (elmc_string_words(&empty_words, empty) != RC_SUCCESS) return 1;
        if (elmc_string_lines(&lines, lines_src) != RC_SUCCESS) return 1;
        print_string_list(words);
        printf("|");
        print_string_list(empty_words);
        printf("|");
        print_string_list(lines);
        printf("\\n");
        elmc_release(words);
        elmc_release(empty_words);
        elmc_release(lines);
        elmc_release(words_src);
        elmc_release(empty);
        elmc_release(lines_src);
        return 0;
      }
      """,
      "How,are,you?,Good?||a,b,c"
    )
  end

  @tag :runtime_c
  test "string length indexes pad and case match official BMP" do
    run_harness(
      """
      int main(void) {
        ElmcValue *word = elmc_harness_new_string("éclair");
        ElmcValue *len = NULL;
        if (elmc_string_length_val(&len, word) != RC_SUCCESS) return 1;
        ElmcValue *needle = elmc_harness_new_string("c");
        ElmcValue *ixs = NULL;
        if (elmc_string_indexes(&ixs, needle, word) != RC_SUCCESS) return 1;
        ElmcValue *upper = NULL;
        if (elmc_string_to_upper(&upper, word) != RC_SUCCESS) return 1;
        ElmcValue *sigma = elmc_harness_new_string("Σ");
        ElmcValue *lower = NULL;
        if (elmc_string_to_lower(&lower, sigma) != RC_SUCCESS) return 1;
        ElmcValue *sharp = elmc_harness_new_string("ß");
        ElmcValue *sharp_up = NULL;
        if (elmc_string_to_upper(&sharp_up, sharp) != RC_SUCCESS) return 1;
        ElmcValue *locale_up = NULL;
        if (elmc_string_to_locale_upper(&locale_up, word) != RC_SUCCESS) return 1;
        ElmcValue *locale_lo = NULL;
        if (elmc_string_to_locale_lower(&locale_lo, sigma) != RC_SUCCESS) return 1;
        ElmcValue *ech = NULL;
        if (elmc_new_char(&ech, 0x00E9) != RC_SUCCESS) return 1;
        ElmcValue *from_ch = NULL;
        if (elmc_string_from_char(&from_ch, ech) != RC_SUCCESS) return 1;
        ElmcValue *one = elmc_harness_new_string("é");
        ElmcValue *n5 = elmc_harness_new_int(5);
        ElmcValue *dot = NULL;
        if (elmc_new_char(&dot, (elmc_int_t)'.') != RC_SUCCESS) return 1;
        ElmcValue *padded = NULL;
        if (elmc_string_pad(&padded, n5, dot, one) != RC_SUCCESS) return 1;
        printf("%lld %lld %s %s %s %s %s %s %s\\n",
          (long long)elmc_as_int(len),
          (long long)elmc_as_int(((ElmcCons *)ixs->payload)->head),
          (const char *)upper->payload,
          (const char *)lower->payload,
          (const char *)sharp_up->payload,
          (const char *)from_ch->payload,
          (const char *)padded->payload,
          (const char *)locale_up->payload,
          (const char *)locale_lo->payload);
        elmc_release(locale_lo);
        elmc_release(locale_up);
        elmc_release(padded);
        elmc_release(dot);
        elmc_release(n5);
        elmc_release(one);
        elmc_release(from_ch);
        elmc_release(ech);
        elmc_release(sharp_up);
        elmc_release(sharp);
        elmc_release(lower);
        elmc_release(sigma);
        elmc_release(upper);
        elmc_release(ixs);
        elmc_release(needle);
        elmc_release(len);
        elmc_release(word);
        return 0;
      }
      """,
      "6 1 ÉCLAIR σ SS é ..é.. ÉCLAIR σ"
    )
  end

  @tag :runtime_c
  test "string and char case map Latin Extended-A and Cyrillic like JS" do
    run_harness(
      """
      int main(void) {
        ElmcValue *word = elmc_harness_new_string("čaša");
        ElmcValue *upper = NULL;
        if (elmc_string_to_upper(&upper, word) != RC_SUCCESS) return 1;
        ElmcValue *lower = NULL;
        if (elmc_string_to_lower(&lower, upper) != RC_SUCCESS) return 1;
        ElmcValue *sh = NULL;
        if (elmc_new_char(&sh, 0x0161) != RC_SUCCESS) return 1;
        ElmcValue *sh_up = NULL;
        if (elmc_char_to_upper(&sh_up, sh) != RC_SUCCESS) return 1;
        ElmcValue *sh_lo = NULL;
        if (elmc_char_to_lower(&sh_lo, sh_up) != RC_SUCCESS) return 1;
        ElmcValue *ya = NULL;
        if (elmc_new_char(&ya, 0x044F) != RC_SUCCESS) return 1;
        ElmcValue *ya_up = NULL;
        if (elmc_char_to_upper(&ya_up, ya) != RC_SUCCESS) return 1;
        ElmcValue *idot = elmc_harness_new_string("\\xC4\\xB0");
        ElmcValue *idot_lo = NULL;
        if (elmc_string_to_lower(&idot_lo, idot) != RC_SUCCESS) return 1;
        const char *idot_text =
          (idot_lo && idot_lo->tag == ELMC_TAG_STRING && idot_lo->payload)
            ? (const char *)idot_lo->payload
            : "";
        int idot_ok =
          idot_text[0] == 'i' &&
          (unsigned char)idot_text[1] == 0xCC &&
          (unsigned char)idot_text[2] == 0x87 &&
          idot_text[3] == '\\0';
        printf("%s %s %lld %lld %lld %d\\n",
          (const char *)upper->payload,
          (const char *)lower->payload,
          (long long)elmc_as_int(sh_up),
          (long long)elmc_as_int(sh_lo),
          (long long)elmc_as_int(ya_up),
          idot_ok);
        elmc_release(idot_lo);
        elmc_release(idot);
        elmc_release(ya_up);
        elmc_release(ya);
        elmc_release(sh_lo);
        elmc_release(sh_up);
        elmc_release(sh);
        elmc_release(lower);
        elmc_release(upper);
        elmc_release(word);
        return 0;
      }
      """,
      "ČAŠA čaša 352 353 1071 1"
    )
  end

  @tag :runtime_c
  test "string replace is official join after split" do
    run_harness(
      """
      static void print_string_list(ElmcValue *list) {
        int first = 1;
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          const char *text =
            (node->head && node->head->tag == ELMC_TAG_STRING && node->head->payload)
              ? (const char *)node->head->payload
              : "";
          printf("%s%s", first ? "" : ",", text);
          first = 0;
          cursor = node->tail;
        }
      }

      int main(void) {
        ElmcValue *s = elmc_harness_new_string("a-b-a");
        ElmcValue *dash = elmc_harness_new_string("-");
        ElmcValue *plus = elmc_harness_new_string("+");
        ElmcValue *out = NULL;
        if (elmc_string_replace(&out, dash, plus, s) != RC_SUCCESS) return 1;
        ElmcValue *word = elmc_harness_new_string("éclair");
        ElmcValue *empty = elmc_harness_new_string("");
        ElmcValue *sep = elmc_harness_new_string("-");
        ElmcValue *empty_rep = NULL;
        if (elmc_string_replace(&empty_rep, empty, sep, word) != RC_SUCCESS) return 1;
        ElmcValue *parts = NULL;
        if (elmc_string_split(&parts, empty, word) != RC_SUCCESS) return 1;
        ElmcValue *trail = elmc_harness_new_string("home/evan/Desktop/");
        ElmcValue *slash = elmc_harness_new_string("/");
        ElmcValue *trail_parts = NULL;
        if (elmc_string_split(&trail_parts, slash, trail) != RC_SUCCESS) return 1;
        printf("%s|%s|", (const char *)out->payload, (const char *)empty_rep->payload);
        print_string_list(parts);
        printf("|");
        print_string_list(trail_parts);
        printf("\\n");
        elmc_release(trail_parts);
        elmc_release(slash);
        elmc_release(trail);
        elmc_release(parts);
        elmc_release(empty_rep);
        elmc_release(sep);
        elmc_release(empty);
        elmc_release(word);
        elmc_release(out);
        elmc_release(plus);
        elmc_release(dash);
        elmc_release(s);
        return 0;
      }
      """,
      "a+b+a|é-c-l-a-i-r|é,c,l,a,i,r|home,evan,Desktop,"
    )
  end

  @tag :runtime_c
  test "dict get with default uses comparable keys for strings" do
    run_harness(
      """
      int main(void) {
        ElmcValue *empty = elmc_list_nil();
        ElmcValue *key = elmc_harness_new_string("name");
        ElmcValue *val = elmc_harness_new_int(42);
        ElmcValue *dict = NULL;
        if (elmc_dict_insert(&dict, key, val, empty) != RC_SUCCESS) return 1;
        elmc_release(val);
        ElmcValue *lookup_key = elmc_harness_new_string("name");
        elmc_int_t found = elmc_dict_get_with_default_int_value(0, lookup_key, dict);
        ElmcValue *other = elmc_harness_new_string("other");
        elmc_int_t missing = elmc_dict_get_with_default_int_value(7, other, dict);
        printf("%lld %lld\\n", (long long)found, (long long)missing);
        elmc_release(other);
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
        ElmcValue *key = elmc_harness_new_string("name");
        ElmcValue *val = elmc_harness_new_int(42);
        ElmcValue *dict = NULL;
        if (elmc_dict_insert(&dict, key, val, empty) != RC_SUCCESS) return 1;
        elmc_release(val);
        ElmcValue *lookup_key = elmc_harness_new_string("name");
        ElmcValue *found = NULL;
        if (elmc_dict_get(&found, lookup_key, dict) != RC_SUCCESS) return 1;
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
      static ElmcValue *dict_insert_ret(ElmcValue *key, ElmcValue *val, ElmcValue *dict) {
        ElmcValue *out = NULL;
        if (elmc_dict_insert(&out, key, val, dict) != RC_SUCCESS) return NULL;
        return out;
      }

      static ElmcValue *left_only(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 3) return args[2] ? elmc_retain(args[2]) : elmc_int_zero();
        return dict_insert_ret(args[0], args[1], args[2]);
      }

      static ElmcValue *both(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 4) return args[3] ? elmc_retain(args[3]) : elmc_int_zero();
        ElmcValue *sum = NULL;
        if (elmc_new_int(&sum, elmc_as_int(args[1]) + elmc_as_int(args[2])) != RC_SUCCESS) return NULL;
        ElmcValue *out = dict_insert_ret(args[0], sum, args[3]);
        elmc_release(sum);
        return out;
      }

      static ElmcValue *right_only(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures; (void)capture_count;
        if (argc < 3) return args[2] ? elmc_retain(args[2]) : elmc_int_zero();
        return dict_insert_ret(args[0], args[1], args[2]);
      }

      static ElmcValue *pair(const char *key, elmc_int_t value) {
        ElmcValue *k = NULL;
        ElmcValue *v = NULL;
        ElmcValue *pair = NULL;
        if (elmc_new_string(&k, key) != RC_SUCCESS) return NULL;
        if (elmc_new_int(&v, value) != RC_SUCCESS) { elmc_release(k); return NULL; }
        if (elmc_tuple2_take(&pair, k, v) != RC_SUCCESS) {
          elmc_release(k);
          elmc_release(v);
          return NULL;
        }
        return pair;
      }

      static ElmcValue *dict_from_pairs(ElmcValue *first, ElmcValue *second) {
        ElmcValue *list = elmc_list_nil();
        ElmcValue *cell = NULL;
        if (elmc_list_cons(&cell, second, list) != RC_SUCCESS) return NULL;
        elmc_release(second);
        ElmcValue *out_list = NULL;
        if (elmc_list_cons(&out_list, first, cell) != RC_SUCCESS) {
          elmc_release(cell);
          return NULL;
        }
        elmc_release(first);
        elmc_release(cell);
        ElmcValue *dict = NULL;
        if (elmc_dict_from_list(&dict, out_list) != RC_SUCCESS) {
          elmc_release(out_list);
          return NULL;
        }
        elmc_release(out_list);
        return dict;
      }

      int main(void) {
        ElmcValue *a = dict_from_pairs(pair("x", 1), pair("z", 3));
        ElmcValue *b = dict_from_pairs(pair("y", 10), pair("z", 30));
        if (!a || !b) return 1;

        ElmcValue *lf = elmc_harness_closure_new(left_only, 3);
        ElmcValue *bf = elmc_harness_closure_new(both, 4);
        ElmcValue *rf = elmc_harness_closure_new(right_only, 3);
        ElmcValue *empty = elmc_list_nil();

        ElmcValue *merged = NULL;
        if (elmc_dict_merge(&merged, lf, bf, rf, a, b, empty) != RC_SUCCESS) return 1;
        ElmcValue *kx = elmc_harness_new_string("x");
        ElmcValue *ky = elmc_harness_new_string("y");
        ElmcValue *kz = elmc_harness_new_string("z");
        ElmcValue *mx = NULL;
        ElmcValue *my = NULL;
        ElmcValue *mz = NULL;
        if (elmc_dict_get(&mx, kx, merged) != RC_SUCCESS) return 1;
        if (elmc_dict_get(&my, ky, merged) != RC_SUCCESS) return 1;
        if (elmc_dict_get(&mz, kz, merged) != RC_SUCCESS) return 1;
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
        elmc_release(empty);
        return 0;
      }
      """,
      "1 10 33"
    )
  end

  @tag :runtime_c
  test "array slice translates negative indexes like official elm/core" do
    run_harness(
      """
      int main(void) {
        const elmc_int_t items[] = {0, 1, 2, 3, 4};
        ElmcValue *arr = elmc_harness_list_from_int_array(items, 5);
        ElmcValue *st = elmc_harness_new_int(2);
        ElmcValue *en = elmc_harness_new_int(-1);
        ElmcValue *sliced = NULL;
        if (elmc_array_slice(&sliced, st, en, arr) != RC_SUCCESS) return 1;
        ElmcValue *i0 = elmc_harness_new_int(0);
        ElmcValue *i1 = elmc_harness_new_int(1);
        ElmcValue *a = NULL;
        ElmcValue *b = NULL;
        if (elmc_array_get(&a, i0, sliced) != RC_SUCCESS) return 1;
        if (elmc_array_get(&b, i1, sliced) != RC_SUCCESS) return 1;
        printf("%lld %lld\\n",
          (long long)elmc_as_int(elmc_maybe_or_tuple_just_payload_borrow(a)),
          (long long)elmc_as_int(elmc_maybe_or_tuple_just_payload_borrow(b)));
        elmc_release(b);
        elmc_release(a);
        elmc_release(i1);
        elmc_release(i0);
        elmc_release(sliced);
        elmc_release(en);
        elmc_release(st);
        elmc_release(arr);
        return 0;
      }
      """,
      "2 3"
    )
  end

  @tag :runtime_c
  test "toPolar uses official atan2 y x" do
    run_harness(
      """
      #include <math.h>
      int main(void) {
        ElmcValue *x = elmc_harness_new_float(3.0);
        ElmcValue *y = elmc_harness_new_float(4.0);
        ElmcValue *point = elmc_harness_tuple2_take(x, y);
        ElmcValue *polar = NULL;
        if (elmc_basics_to_polar(&polar, point) != RC_SUCCESS) return 1;
        ElmcTuple2 *pair = (ElmcTuple2 *)polar->payload;
        int ok =
          fabs(elmc_as_float(pair->first) - 5.0) < 0.001 &&
          fabs(elmc_as_float(pair->second) - atan2(4.0, 3.0)) < 0.001;
        printf("%d\\n", ok);
        elmc_release(polar);
        elmc_release(point);
        return 0;
      }
      """,
      "1"
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

      #{RcTrackHarness.harness_prelude()}

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
        RcTrackHarness.runtime_link_stub(),
        harness_path,
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out
    assert String.trim(run_out) == expected_output
  end
end
