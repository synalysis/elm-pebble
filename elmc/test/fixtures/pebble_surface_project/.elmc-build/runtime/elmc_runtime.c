#include "elmc_runtime.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_PLATFORM 1
#endif
#ifdef ELMC_PEBBLE_PLATFORM
#include <pebble.h>
#endif

static uint64_t ELMC_ALLOCATED = 0;
static uint64_t ELMC_RELEASED = 0;

#define ELMC_PROCESS_MAX_SLOTS 16
#define ELMC_RC_IMMORTAL UINT32_MAX
static elmc_int_t ELMC_INT_ZERO_PAYLOAD = 0;
ElmcValue ELMC_INT_ZERO = { ELMC_RC_IMMORTAL, ELMC_TAG_INT, &ELMC_INT_ZERO_PAYLOAD, 0 };
static char ELMC_EMPTY_STRING_PAYLOAD[] = "";
static ElmcValue ELMC_EMPTY_STRING = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, ELMC_EMPTY_STRING_PAYLOAD, 0 };
static int ELMC_ALLOC_FAILURE_LOGGED = 0;

typedef struct {
  int active;
  int64_t pid;
  ElmcValue *task;
#ifdef ELMC_PEBBLE_PLATFORM
  AppTimer *timer;
#else
  void *timer;
#endif
} ElmcProcessSlot;

static void elmc_log_alloc_failed_once(const char *context, size_t size) {
  if (ELMC_ALLOC_FAILURE_LOGGED) return;
  ELMC_ALLOC_FAILURE_LOGGED = 1;
#ifdef ELMC_PEBBLE_PLATFORM
  APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC allocation failed in %s (%lu bytes)", context ? context : "unknown", (unsigned long)size);
#else
  fprintf(stderr, "ELMC allocation failed in %s (%lu bytes)\n", context ? context : "unknown", (unsigned long)size);
#endif
}

static void *elmc_malloc(size_t size, const char *context) {
  void *ptr = malloc(size);
  if (!ptr) elmc_log_alloc_failed_once(context, size);
  return ptr;
}

static ElmcValue *elmc_alloc(ElmcTag tag, void *payload) {
  ElmcValue *value = (ElmcValue *)elmc_malloc(sizeof(ElmcValue), __func__);
  if (!value) return NULL;
  value->rc = 1;
  value->tag = tag;
  value->payload = payload;
  value->scalar = 0;
  ELMC_ALLOCATED += 1;
  return value;
}

static ElmcValue *elmc_alloc_scalar(ElmcTag tag, elmc_int_t scalar) {
  ElmcValue *value = elmc_alloc(tag, NULL);
  if (value) value->scalar = scalar;
  return value;
}

static ElmcValue *elmc_list_reverse_copy(ElmcValue *list) {
  ElmcValue *out = elmc_list_nil();
  ElmcValue *cursor = list;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *next = elmc_list_cons(node->head, out);
    elmc_release(out);
    out = next;
    cursor = node->tail;
  }
  return out;
}

ElmcValue *elmc_new_int(elmc_int_t value) {
  if (value == 0) return &ELMC_INT_ZERO;
  return elmc_alloc_scalar(ELMC_TAG_INT, value);
}

ElmcValue *elmc_new_bool(int value) {
  return elmc_alloc_scalar(ELMC_TAG_BOOL, value != 0);
}

ElmcValue *elmc_new_string(const char *value) {
  if (!value || value[0] == '\0') return &ELMC_EMPTY_STRING;
  size_t len = strlen(value);
  char *ptr = (char *)elmc_malloc(len + 1, __func__);
  if (!ptr) return &ELMC_EMPTY_STRING;
  memcpy(ptr, value, len + 1);
  ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, ptr);
  if (!out) {
    free(ptr);
    return &ELMC_EMPTY_STRING;
  }
  return out;
}

ElmcValue *elmc_list_nil(void) {
  return elmc_alloc(ELMC_TAG_LIST, NULL);
}

ElmcValue *elmc_list_cons(ElmcValue *head, ElmcValue *tail) {
  ElmcCons *node = (ElmcCons *)elmc_malloc(sizeof(ElmcCons), __func__);
  if (!node) return NULL;
  node->head = elmc_retain(head);
  node->tail = elmc_retain(tail);
  return elmc_alloc(ELMC_TAG_LIST, node);
}

static ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail) {
  ElmcCons *node = (ElmcCons *)elmc_malloc(sizeof(ElmcCons), __func__);
  if (!node) {
    elmc_release(head);
    elmc_release(tail);
    return NULL;
  }
  node->head = head;
  node->tail = tail;
  return elmc_alloc(ELMC_TAG_LIST, node);
}

ElmcValue *elmc_list_from_values_take(ElmcValue **items, int count) {
  ElmcValue *out = elmc_list_nil();
  if (!items || count <= 0) return out;
  for (int i = count - 1; i >= 0; i--) {
    out = elmc_list_cons_take(items[i], out);
  }
  return out;
}

ElmcValue *elmc_maybe_nothing(void) {
  ElmcMaybe *maybe = (ElmcMaybe *)elmc_malloc(sizeof(ElmcMaybe), __func__);
  if (!maybe) return NULL;
  maybe->is_just = 0;
  maybe->value = NULL;
  return elmc_alloc(ELMC_TAG_MAYBE, maybe);
}

ElmcValue *elmc_maybe_just(ElmcValue *value) {
  ElmcMaybe *maybe = (ElmcMaybe *)elmc_malloc(sizeof(ElmcMaybe), __func__);
  if (!maybe) return NULL;
  maybe->is_just = 1;
  maybe->value = elmc_retain(value);
  return elmc_alloc(ELMC_TAG_MAYBE, maybe);
}

ElmcValue *elmc_tuple2(ElmcValue *first, ElmcValue *second) {
  ElmcTuple2 *tuple = (ElmcTuple2 *)elmc_malloc(sizeof(ElmcTuple2), __func__);
  if (!tuple) return NULL;
  tuple->first = elmc_retain(first);
  tuple->second = elmc_retain(second);
  return elmc_alloc(ELMC_TAG_TUPLE2, tuple);
}

ElmcValue *elmc_tuple2_take(ElmcValue *first, ElmcValue *second) {
  ElmcTuple2 *tuple = (ElmcTuple2 *)elmc_malloc(sizeof(ElmcTuple2), __func__);
  if (!tuple) {
    elmc_release(first);
    elmc_release(second);
    return NULL;
  }
  tuple->first = first;
  tuple->second = second;
  return elmc_alloc(ELMC_TAG_TUPLE2, tuple);
}

ElmcValue *elmc_tuple2_ints(elmc_int_t first, elmc_int_t second) {
  return elmc_tuple2_take(elmc_new_int(first), elmc_new_int(second));
}

elmc_int_t elmc_as_int(ElmcValue *value) {
  if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL)) return 0;
  return value->scalar;
}

ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode) {
  int64_t mode = 0; /* 0 = interaction, 1 = disable, 2 = enable */

  if (maybe_mode) {
    if (maybe_mode->tag == ELMC_TAG_MAYBE && maybe_mode->payload != NULL) {
      ElmcMaybe *maybe = (ElmcMaybe *)maybe_mode->payload;
      if (maybe->is_just && maybe->value) {
        mode = elmc_as_int(maybe->value) != 0 ? 2 : 1;
      }
    } else if (maybe_mode->tag == ELMC_TAG_TUPLE2 && maybe_mode->payload != NULL) {
      ElmcTuple2 *tuple = (ElmcTuple2 *)maybe_mode->payload;
      int64_t ctor_tag = tuple->first ? elmc_as_int(tuple->first) : 0;
      if (ctor_tag == 1 && tuple->second) {
        mode = elmc_as_int(tuple->second) != 0 ? 2 : 1;
      }
    }
  }

  ElmcValue *kind = elmc_new_int(6);
  ElmcValue *p0 = elmc_new_int(mode);
  ElmcValue *p1 = elmc_int_zero();
  ElmcValue *p2 = elmc_int_zero();
  ElmcValue *p3 = elmc_int_zero();
  ElmcValue *p4 = elmc_int_zero();
  ElmcValue *p5 = elmc_int_zero();
  ElmcValue *tail0 = elmc_tuple2(p4, p5);
  ElmcValue *tail1 = elmc_tuple2(p3, tail0);
  ElmcValue *tail2 = elmc_tuple2(p2, tail1);
  ElmcValue *tail3 = elmc_tuple2(p1, tail2);
  ElmcValue *tail4 = elmc_tuple2(p0, tail3);
  ElmcValue *command = elmc_tuple2(kind, tail4);

  elmc_release(kind);
  elmc_release(p0);
  elmc_release(p1);
  elmc_release(p2);
  elmc_release(p3);
  elmc_release(p4);
  elmc_release(p5);
  elmc_release(tail0);
  elmc_release(tail1);
  elmc_release(tail2);
  elmc_release(tail3);
  elmc_release(tail4);
  return command;
}

ElmcValue *elmc_new_float(double value) {
  double *ptr = (double *)elmc_malloc(sizeof(double), __func__);
  if (!ptr) return NULL;
  *ptr = value;
  return elmc_alloc(ELMC_TAG_FLOAT, ptr);
}

double elmc_as_float(ElmcValue *value) {
  if (!value) return 0.0;
  if (value->tag == ELMC_TAG_FLOAT) return *((double *)value->payload);
  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) return (double)elmc_as_int(value);
  return 0.0;
}

ElmcValue *elmc_record_new(int field_count, const char **field_names, ElmcValue **field_values) {
  ElmcRecord *record = (ElmcRecord *)elmc_malloc(sizeof(ElmcRecord), __func__);
  if (!record) return NULL;
  record->field_count = field_count;
  record->field_names = (const char **)elmc_malloc(sizeof(const char *) * field_count, __func__);
  record->field_values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * field_count, __func__);
  if (!record->field_names || !record->field_values) {
    free(record->field_names);
    free(record->field_values);
    free(record);
    return NULL;
  }
  for (int i = 0; i < field_count; i++) {
    size_t len = strlen(field_names[i]);
    char *name_copy = (char *)elmc_malloc(len + 1, __func__);
    if (name_copy) { memcpy(name_copy, field_names[i], len + 1); }
    record->field_names[i] = name_copy;
    record->field_values[i] = elmc_retain(field_values[i]);
  }
  return elmc_alloc(ELMC_TAG_RECORD, record);
}

ElmcValue *elmc_record_new_take(int field_count, const char **field_names, ElmcValue **field_values) {
  ElmcRecord *record = (ElmcRecord *)elmc_malloc(sizeof(ElmcRecord), __func__);
  if (!record) return NULL;
  record->field_count = field_count;
  record->field_names = (const char **)elmc_malloc(sizeof(const char *) * field_count, __func__);
  record->field_values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * field_count, __func__);
  if (!record->field_names || !record->field_values) {
    free(record->field_names);
    free(record->field_values);
    free(record);
    for (int i = 0; i < field_count; i++) {
      elmc_release(field_values[i]);
    }
    return NULL;
  }
  for (int i = 0; i < field_count; i++) {
    size_t len = strlen(field_names[i]);
    char *name_copy = (char *)elmc_malloc(len + 1, __func__);
    if (name_copy) { memcpy(name_copy, field_names[i], len + 1); }
    record->field_names[i] = name_copy;
    record->field_values[i] = field_values[i];
  }
  return elmc_alloc(ELMC_TAG_RECORD, record);
}

ElmcValue *elmc_record_new_ints(int field_count, const char **field_names, const elmc_int_t *field_values) {
  ElmcValue *values[field_count];
  for (int i = 0; i < field_count; i++) {
    values[i] = elmc_new_int(field_values[i]);
  }
  return elmc_record_new_take(field_count, field_names, values);
}

ElmcValue *elmc_record_get_index(ElmcValue *record, int index) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  if (index >= 0 && index < rec->field_count) return elmc_retain(rec->field_values[index]);
  return elmc_int_zero();
}

ElmcValue *elmc_closure_new(ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures) {
  ElmcClosure *clo = (ElmcClosure *)elmc_malloc(sizeof(ElmcClosure), __func__);
  if (!clo) return NULL;
  clo->fn = fn;
  clo->arity = arity;
  clo->capture_count = capture_count;
  clo->captures = NULL;
  if (capture_count > 0) {
    clo->captures = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * capture_count, __func__);
    if (!clo->captures) { free(clo); return NULL; }
    for (int i = 0; i < capture_count; i++) {
      clo->captures[i] = elmc_retain(captures[i]);
    }
  }
  return elmc_alloc(ELMC_TAG_CLOSURE, clo);
}

ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc) {
  if (!closure || closure->tag != ELMC_TAG_CLOSURE || !closure->payload) return elmc_int_zero();
  ElmcClosure *clo = (ElmcClosure *)closure->payload;
  int consumed = argc;
  if (clo->arity > 0 && argc > clo->arity) {
    consumed = clo->arity;
  }
  ElmcValue *result = clo->fn(args, consumed, clo->captures, clo->capture_count);
  if (consumed < argc) {
    ElmcValue *next = elmc_closure_call(result, args + consumed, argc - consumed);
    elmc_release(result);
    return next;
  }
  return result;
}

ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc) {
  if (!value) return elmc_int_zero();
  if (value->tag == ELMC_TAG_CLOSURE) {
    return elmc_closure_call(value, args, argc);
  }
  if (argc == 1 && args && args[0] && args[0]->tag == ELMC_TAG_CLOSURE) {
    ElmcValue *access_args[1] = { value };
    return elmc_closure_call(args[0], access_args, 1);
  }
  return elmc_retain(value);
}

ElmcValue *elmc_list_append(ElmcValue *a, ElmcValue *b) {
  ElmcValue *rev_a = elmc_list_reverse_copy(a);
  ElmcValue *out = elmc_retain(b);
  ElmcValue *cursor = rev_a;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *next = elmc_list_cons(node->head, out);
    elmc_release(out);
    out = next;
    cursor = node->tail;
  }
  elmc_release(rev_a);
  return out;
}

ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe) {
  if (!maybe) return elmc_retain(default_val);
  if (maybe->tag == ELMC_TAG_MAYBE) {
    ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
    if (m && m->is_just && m->value) return elmc_retain(m->value);
    return elmc_retain(default_val);
  }
  if (maybe->tag == ELMC_TAG_TUPLE2 && maybe->payload) {
    ElmcTuple2 *pair = (ElmcTuple2 *)maybe->payload;
    if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) {
      return elmc_retain(pair->second);
    }
  }
  return elmc_retain(default_val);
}

elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe) {
  if (!maybe) return default_val;
  if (maybe->tag == ELMC_TAG_MAYBE) {
    ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
    if (m && m->is_just && m->value) return elmc_as_int(m->value);
    return default_val;
  }
  if (maybe->tag == ELMC_TAG_TUPLE2 && maybe->payload) {
    ElmcTuple2 *pair = (ElmcTuple2 *)maybe->payload;
    if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) {
      return elmc_as_int(pair->second);
    }
  }
  return default_val;
}

ElmcValue *elmc_string_to_int(ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();
  const char *str = (const char *)s->payload;
  if (!str || *str == '\0') return elmc_maybe_nothing();
  int sign = 1;
  size_t idx = 0;
  if (str[idx] == '+' || str[idx] == '-') {
    if (str[idx] == '-') sign = -1;
    idx++;
  }
  if (str[idx] == '\0') return elmc_maybe_nothing();

  uint64_t acc = 0;
  int saw_digit = 0;
  for (; str[idx] != '\0'; idx++) {
    char ch = str[idx];
    if (ch < '0' || ch > '9') return elmc_maybe_nothing();
    saw_digit = 1;
    uint64_t digit = (uint64_t)(ch - '0');
    if (acc > 922337203685477580ULL || (acc == 922337203685477580ULL && digit > 7ULL + (sign < 0 ? 1ULL : 0ULL))) {
      return elmc_maybe_nothing();
    }
    acc = (acc * 10ULL) + digit;
  }
  if (!saw_digit) return elmc_maybe_nothing();

  int64_t parsed = 0;
  if (sign < 0) {
    if (acc == 9223372036854775808ULL) {
      parsed = INT64_MIN;
    } else {
      parsed = -(int64_t)acc;
    }
  } else {
    parsed = (int64_t)acc;
  }

  ElmcValue *v = elmc_new_int(parsed);
  ElmcValue *out = elmc_maybe_just(v);
  elmc_release(v);
  return out;
}

ElmcValue *elmc_string_to_float(ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();

  const char *p = (const char *)s->payload;
  int sign = 1;
  if (*p == '+' || *p == '-') {
    if (*p == '-') sign = -1;
    p++;
  }

  int saw_digit = 0;
  double whole = 0.0;
  while (*p >= '0' && *p <= '9') {
    saw_digit = 1;
    whole = whole * 10.0 + (double)(*p - '0');
    p++;
  }

  double frac = 0.0;
  double place = 0.1;
  if (*p == '.') {
    p++;
    while (*p >= '0' && *p <= '9') {
      saw_digit = 1;
      frac += (double)(*p - '0') * place;
      place *= 0.1;
      p++;
    }
  }

  if (!saw_digit || *p != '\0') return elmc_maybe_nothing();

  double val = (double)sign * (whole + frac);
  ElmcValue *v = elmc_new_float(val);
  ElmcValue *out = elmc_maybe_just(v);
  elmc_release(v);
  return out;
}

ElmcValue *elmc_string_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
  const char *src = (const char *)s->payload;
  int64_t len = (int64_t)strlen(src);
  int64_t st = elmc_as_int(start);
  int64_t en = elmc_as_int(end_idx);
  if (st < 0) st = len + st;
  if (en < 0) en = len + en;
  if (st < 0) st = 0;
  if (en < 0) en = 0;
  if (st > len) st = len;
  if (en > len) en = len;
  if (en <= st) return &ELMC_EMPTY_STRING;
  size_t new_len = (size_t)(en - st);
  char *buf = (char *)elmc_malloc(new_len + 1, __func__);
  if (!buf) return &ELMC_EMPTY_STRING;
  memcpy(buf, src + st, new_len);
  buf[new_len] = '\0';
  ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
  if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
  return out;
}

ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s) {
  ElmcValue *zero = elmc_int_zero();
  ElmcValue *out = elmc_string_slice(zero, n, s);
  elmc_release(zero);
  return out;
}

ElmcValue *elmc_basics_floor(ElmcValue *x) {
  double v = elmc_as_float(x);
  int64_t i = (int64_t)v;
  if ((double)i > v) i--;
  return elmc_new_int(i);
}

ElmcValue *elmc_retain(ElmcValue *value) {
  if (!value) return NULL;
  if (value->rc == ELMC_RC_IMMORTAL) return value;
  value->rc += 1;
  return value;
}

void elmc_release(ElmcValue *value) {
  if (!value) return;
  if (value->rc == ELMC_RC_IMMORTAL) return;
  if (value->rc == 0) return;
  value->rc -= 1;
  if (value->rc > 0) return;
  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
    /* Scalar values live inline in ElmcValue, not in heap payloads. */
  } else if (value->tag == ELMC_TAG_LIST && value->payload != NULL) {
    ElmcCons *node = (ElmcCons *)value->payload;
    elmc_release(node->head);
    elmc_release(node->tail);
  } else if (value->tag == ELMC_TAG_MAYBE && value->payload != NULL) {
    ElmcMaybe *maybe = (ElmcMaybe *)value->payload;
    if (maybe->value) elmc_release(maybe->value);
  } else if (value->tag == ELMC_TAG_RESULT && value->payload != NULL) {
    ElmcResult *result = (ElmcResult *)value->payload;
    if (result->value) elmc_release(result->value);
  } else if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (tuple->first) elmc_release(tuple->first);
    if (tuple->second) elmc_release(tuple->second);
  } else if (value->tag == ELMC_TAG_RECORD && value->payload != NULL) {
    ElmcRecord *rec = (ElmcRecord *)value->payload;
    for (int i = 0; i < rec->field_count; i++) {
      if (rec->field_values[i]) elmc_release(rec->field_values[i]);
      free((void *)rec->field_names[i]);
    }
    free(rec->field_names);
    free(rec->field_values);
  } else if (value->tag == ELMC_TAG_CLOSURE && value->payload != NULL) {
    ElmcClosure *clo = (ElmcClosure *)value->payload;
    for (int i = 0; i < clo->capture_count; i++) {
      if (clo->captures[i]) elmc_release(clo->captures[i]);
    }
    free(clo->captures);
  }
  if (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL) {
    free(value->payload);
  }
  free(value);
  ELMC_RELEASED += 1;
}
