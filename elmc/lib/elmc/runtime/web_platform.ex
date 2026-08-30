defmodule Elmc.Runtime.WebPlatform do
  @moduledoc false

  @doc "RC declarations for web/platform helpers (host provides real WASM imports)."
  def runtime_header_declarations do
    """
    RC elmc_string_chop_end(ElmcValue **out, ElmcValue *str, ElmcValue *suffix);
    RC elmc_string_chop_start(ElmcValue **out, ElmcValue *str, ElmcValue *prefix);
    RC elmc_string_chop_forward_slashes(ElmcValue **out, ElmcValue *str);
    RC elmc_url_percent_encode(ElmcValue **out, ElmcValue *segment);
    RC elmc_url_percent_decode(ElmcValue **out, ElmcValue *segment);
    RC elmc_url_from_string(ElmcValue **out, ElmcValue *url);
    RC elmc_url_to_string(ElmcValue **out, ElmcValue *url);
    RC elmc_url_builder_absolute(ElmcValue **out, ElmcValue *path, ElmcValue *query);
    RC elmc_url_builder_relative(ElmcValue **out, ElmcValue *path, ElmcValue *query);
    RC elmc_url_builder_cross_origin(ElmcValue **out, ElmcValue *pre, ElmcValue *path, ElmcValue *query);
    RC elmc_url_builder_custom(ElmcValue **out, ElmcValue *root, ElmcValue *path, ElmcValue *query, ElmcValue *frag);
    RC elmc_url_builder_query_string(ElmcValue **out, ElmcValue *key, ElmcValue *value);
    RC elmc_url_builder_query_int(ElmcValue **out, ElmcValue *key, ElmcValue *value);
    RC elmc_url_builder_to_query(ElmcValue **out, ElmcValue *params);
    RC elmc_http_empty_body(ElmcValue **out, ElmcValue *req);
    RC elmc_http_pair(ElmcValue **out, ElmcValue *key, ElmcValue *value);
    RC elmc_http_file_body(ElmcValue **out, ElmcValue *file);
    RC elmc_http_multipart_body(ElmcValue **out, ElmcValue *parts);
    RC elmc_http_bytes_part(ElmcValue **out, ElmcValue *key, ElmcValue *mime, ElmcValue *bytes);
    RC elmc_http_to_form_data(ElmcValue **out, ElmcValue *parts);
    RC elmc_http_bytes_to_blob(ElmcValue **out, ElmcValue *mime, ElmcValue *bytes);
    RC elmc_http_to_data_view(ElmcValue **out, ElmcValue *body);
    RC elmc_http_expect(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder, ElmcValue *req);
    RC elmc_http_map_expect(ElmcValue **out, ElmcValue *func, ElmcValue *expect);
    RC elmc_http_expect_string(ElmcValue **out, ElmcValue *to_msg);
    RC elmc_http_expect_json(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder);
    RC elmc_http_expect_bytes(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder);
    RC elmc_http_expect_whatever(ElmcValue **out, ElmcValue *to_msg);
    RC elmc_http_expect_string_response(ElmcValue **out, ElmcValue *to_msg, ElmcValue *to_result);
    RC elmc_http_expect_bytes_response(ElmcValue **out, ElmcValue *to_msg, ElmcValue *to_result);
    RC elmc_http_command(ElmcValue **out, ElmcValue *req);
    RC elmc_http_risky_command(ElmcValue **out, ElmcValue *req);
    RC elmc_http_task(ElmcValue **out, ElmcValue *req);
    RC elmc_http_risky_task(ElmcValue **out, ElmcValue *req);
    RC elmc_http_string_resolver(ElmcValue **out, ElmcValue *to_result);
    RC elmc_http_bytes_resolver(ElmcValue **out, ElmcValue *to_result);
    RC elmc_http_cancel(ElmcValue **out, ElmcValue *tracker);
    RC elmc_http_fraction_sent(ElmcValue **out, ElmcValue *progress);
    RC elmc_http_fraction_received(ElmcValue **out, ElmcValue *progress);
    RC elmc_backend_task_http_get_json(ElmcValue **out, ElmcValue *url, ElmcValue *expect);
    RC elmc_backend_task_http_get(ElmcValue **out, ElmcValue *url, ElmcValue *expect);
    RC elmc_backend_task_http_get_with_options(ElmcValue **out, ElmcValue *url, ElmcValue *options, ElmcValue *expect);
    RC elmc_backend_task_http_expect_json(ElmcValue **out, ElmcValue *decoder);
    RC elmc_backend_task_http_expect_string(ElmcValue **out);
    RC elmc_backend_task_http_expect_whatever(ElmcValue **out);
    RC elmc_backend_task_http_expect_bytes(ElmcValue **out);
    RC elmc_backend_task_http_with_metadata(ElmcValue **out, ElmcValue *expect);
    RC elmc_backend_task_http_empty_body(ElmcValue **out);
    RC elmc_backend_task_http_string_body(ElmcValue **out, ElmcValue *body);
    RC elmc_backend_task_http_json_body(ElmcValue **out, ElmcValue *value);
    RC elmc_backend_task_http_bytes_body(ElmcValue **out, ElmcValue *bytes);
    RC elmc_bytes_encode_sequence(ElmcValue **out, ElmcValue *list);
    RC elmc_backend_task_http_request(ElmcValue **out, ElmcValue *req);
    RC elmc_backend_task_http_post(ElmcValue **out, ElmcValue *url, ElmcValue *body, ElmcValue *expect);
    RC elmc_file_download_task(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content);
    RC elmc_file_select(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept);
    RC elmc_file_download(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content);
    RC elmc_file_download_url(ElmcValue **out, ElmcValue *href);
    RC elmc_file_select_files(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept);
    RC elmc_file_name(ElmcValue **out, ElmcValue *file);
    RC elmc_file_mime(ElmcValue **out, ElmcValue *file);
    RC elmc_file_size(ElmcValue **out, ElmcValue *file);
    RC elmc_file_last_modified(ElmcValue **out, ElmcValue *file);
    RC elmc_file_to_string(ElmcValue **out, ElmcValue *file);
    RC elmc_file_to_bytes(ElmcValue **out, ElmcValue *file);
    RC elmc_file_to_url(ElmcValue **out, ElmcValue *file);
    RC elmc_file_decoder(ElmcValue **out);
    RC elmc_random_generate(ElmcValue **out, ElmcValue *to_msg, ElmcValue *generator);
    RC elmc_regex_from_string(ElmcValue **out, ElmcValue *pattern);
    RC elmc_regex_from_string_with(ElmcValue **out, ElmcValue *options, ElmcValue *pattern);
    RC elmc_regex_find(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
    RC elmc_regex_find_at_most(ElmcValue **out, ElmcValue *n, ElmcValue *regex, ElmcValue *str);
    RC elmc_regex_contains(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
    RC elmc_regex_replace(ElmcValue **out, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str);
    RC elmc_regex_replace_at_most(ElmcValue **out, ElmcValue *n, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str);
    RC elmc_regex_split(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
    RC elmc_regex_split_at_most(ElmcValue **out, ElmcValue *n, ElmcValue *regex, ElmcValue *str);
    RC elmc_time_here(ElmcValue **out);
    RC elmc_time_get_zone_name(ElmcValue **out);
    RC elmc_time_utc(ElmcValue **out);
    RC elmc_time_custom_zone(ElmcValue **out, ElmcValue *offset, ElmcValue *eras);
    RC elmc_time_to_hour(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_minute(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_second(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_millis(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_year(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_day(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_month(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_time_to_weekday(ElmcValue **out, ElmcValue *zone, ElmcValue *posix);
    RC elmc_browser_get_viewport(ElmcValue **out);
    RC elmc_browser_get_viewport_of(ElmcValue **out, ElmcValue *id);
    RC elmc_browser_set_viewport(ElmcValue **out, ElmcValue *x, ElmcValue *y);
    RC elmc_browser_set_viewport_of(ElmcValue **out, ElmcValue *id, ElmcValue *x, ElmcValue *y);
    RC elmc_browser_get_element(ElmcValue **out, ElmcValue *id);
    RC elmc_browser_dom_focus(ElmcValue **out, ElmcValue *id);
    RC elmc_browser_dom_blur(ElmcValue **out, ElmcValue *id);
    """
  end

  def runtime_source_impl do
    """
    static const char *elmc_web_cstr(ElmcValue *value) {
      if (value && value->tag == ELMC_TAG_STRING && value->payload) {
        return (const char *)value->payload;
      }
      return "";
    }

    static int elmc_web_ends_with(const char *str, const char *suffix) {
      size_t sl = strlen(str);
      size_t su = strlen(suffix);
      if (su == 0 || su > sl) return 0;
      return memcmp(str + (sl - su), suffix, su) == 0;
    }

    static int elmc_web_starts_with(const char *str, const char *prefix) {
      size_t pl = strlen(prefix);
      return pl == 0 || strncmp(str, prefix, pl) == 0;
    }

    RC elmc_string_chop_end(ElmcValue **out, ElmcValue *str, ElmcValue *suffix) {
      const char *s = elmc_web_cstr(str);
      const char *suf = elmc_web_cstr(suffix);
      if (suf[0] && elmc_web_ends_with(s, suf)) {
        size_t keep = strlen(s) - strlen(suf);
        char *buf = (char *)elmc_malloc(keep + 1, __func__);
        if (!buf) return RC_ERR_OUT_OF_MEMORY;
        memcpy(buf, s, keep);
        buf[keep] = '\\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        if (!allocated) {
          elmc_free(buf);
          return RC_ERR_OUT_OF_MEMORY;
        }
        *out = allocated;
        return RC_SUCCESS;
      }
      *out = str ? elmc_retain(str) : NULL;
      if (!*out) return elmc_new_string(out, "");
      return RC_SUCCESS;
    }

    RC elmc_string_chop_start(ElmcValue **out, ElmcValue *str, ElmcValue *prefix) {
      const char *s = elmc_web_cstr(str);
      const char *pre = elmc_web_cstr(prefix);
      if (pre[0] && elmc_web_starts_with(s, pre)) {
        return elmc_new_string(out, s + strlen(pre));
      }
      *out = str ? elmc_retain(str) : NULL;
      if (!*out) return elmc_new_string(out, "");
      return RC_SUCCESS;
    }

    RC elmc_string_chop_forward_slashes(ElmcValue **out, ElmcValue *str) {
      const char *s = elmc_web_cstr(str);
      size_t len = strlen(s);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      for (size_t i = 0; i < len; i++) {
        char c = s[i] == '\\\\' ? '/' : s[i];
        if (c == '/' && j > 0 && buf[j - 1] == '/') continue;
        buf[j++] = c;
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }

    static int elmc_url_is_unreserved(unsigned char c) {
      return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
             c == '-' || c == '_' || c == '.' || c == '~';
    }

    RC elmc_url_percent_encode(ElmcValue **out, ElmcValue *segment) {
      const char *s = elmc_web_cstr(segment);
      size_t len = strlen(s);
      char *buf = (char *)elmc_malloc(len * 3 + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      static const char *hex = "0123456789ABCDEF";
      for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        if (elmc_url_is_unreserved(c)) {
          buf[j++] = (char)c;
        } else {
          buf[j++] = '%';
          buf[j++] = hex[c >> 4];
          buf[j++] = hex[c & 15];
        }
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }

    static int elmc_url_hex_value(char c) {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'A' && c <= 'F') return c - 'A' + 10;
      if (c >= 'a' && c <= 'f') return c - 'a' + 10;
      return -1;
    }

    RC elmc_url_percent_decode(ElmcValue **out, ElmcValue *segment) {
      /* Official elm/url: String -> Maybe String. decodeURIComponent: no '+'
         → space, and an incomplete or non-hex '%' escape is Nothing. */
      const char *s = elmc_web_cstr(segment);
      size_t len = strlen(s);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      for (size_t i = 0; i < len; i++) {
        if (s[i] == '%') {
          if (i + 2 >= len) {
            elmc_free(buf);
            *out = elmc_maybe_nothing();
            return RC_SUCCESS;
          }
          int hi = elmc_url_hex_value(s[i + 1]);
          int lo = elmc_url_hex_value(s[i + 2]);
          if (hi < 0 || lo < 0) {
            elmc_free(buf);
            *out = elmc_maybe_nothing();
            return RC_SUCCESS;
          }
          buf[j++] = (char)((hi << 4) | lo);
          i += 2;
          continue;
        }
        buf[j++] = s[i];
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      return elmc_maybe_just_own(out, allocated);
    }

    static size_t elmc_url_list_join_len(ElmcValue *list, const char *sep) {
      size_t n = 0, seplen = strlen(sep), count = 0;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        n += strlen(elmc_web_cstr(node->head));
        count += 1;
        cursor = node->tail;
      }
      if (count > 1) n += seplen * (count - 1);
      return n;
    }
    static void elmc_url_list_join_into(char *buf, ElmcValue *list, const char *sep) {
      size_t j = 0;
      int first = 1;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        const char *s = elmc_web_cstr(node->head);
        if (!first) {
          size_t sl = strlen(sep);
          memcpy(buf + j, sep, sl);
          j += sl;
        }
        first = 0;
        size_t n = strlen(s);
        memcpy(buf + j, s, n);
        j += n;
        cursor = node->tail;
      }
      buf[j] = '\\0';
    }
    static int elmc_url_query_pair(ElmcValue *param, const char **key, const char **val) {
      if (!param || !key || !val) return 0;
      if (param->tag == ELMC_TAG_TUPLE2 && param->payload) {
        ElmcTuple2 *t = (ElmcTuple2 *)param->payload;
        if (t->first && t->first->tag == ELMC_TAG_INT && t->second &&
            t->second->tag == ELMC_TAG_TUPLE2 && t->second->payload) {
          ElmcTuple2 *inner = (ElmcTuple2 *)t->second->payload;
          *key = elmc_web_cstr(inner->first);
          *val = elmc_web_cstr(inner->second);
          return 1;
        }
        *key = elmc_web_cstr(t->first);
        *val = elmc_web_cstr(t->second);
        return 1;
      }
      if (param->tag == ELMC_TAG_RECORD && param->payload) {
        ElmcRecord *rec = (ElmcRecord *)param->payload;
        if (rec->field_count >= 2) {
          *key = elmc_web_cstr(rec->field_values[0]);
          *val = elmc_web_cstr(rec->field_values[1]);
          return 1;
        }
      }
      return 0;
    }
    static RC elmc_url_to_query_into(ElmcValue **out, ElmcValue *params) {
      size_t n = 0, count = 0;
      ElmcValue *cursor = params;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        const char *k = "";
        const char *v = "";
        if (elmc_url_query_pair(node->head, &k, &v)) {
          n += strlen(k) + 1 + strlen(v);
          count += 1;
        }
        cursor = node->tail;
      }
      if (count == 0) return elmc_new_string(out, "");
      n += 1 + (count - 1);
      char *buf = (char *)elmc_malloc(n + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      buf[j++] = '?';
      int first = 1;
      cursor = params;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        const char *k = "";
        const char *v = "";
        if (elmc_url_query_pair(node->head, &k, &v)) {
          if (!first) buf[j++] = '&';
          first = 0;
          size_t kn = strlen(k), vn = strlen(v);
          memcpy(buf + j, k, kn);
          j += kn;
          buf[j++] = '=';
          memcpy(buf + j, v, vn);
          j += vn;
        }
        cursor = node->tail;
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }
    static RC elmc_url_build(ElmcValue **out, const char *prefix, ElmcValue *path, ElmcValue *query) {
      ElmcValue *qstr = NULL;
      RC rc = elmc_url_to_query_into(&qstr, query);
      if (rc != RC_SUCCESS) return rc;
      const char *qs = elmc_web_cstr(qstr);
      size_t plen = strlen(prefix);
      size_t path_len = elmc_url_list_join_len(path, "/");
      size_t qlen = strlen(qs);
      char *buf = (char *)elmc_malloc(plen + path_len + qlen + 1, __func__);
      if (!buf) {
        elmc_release(qstr);
        return RC_ERR_OUT_OF_MEMORY;
      }
      memcpy(buf, prefix, plen);
      elmc_url_list_join_into(buf + plen, path, "/");
      memcpy(buf + plen + path_len, qs, qlen + 1);
      elmc_release(qstr);
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }
    RC elmc_url_from_string(ElmcValue **out, ElmcValue *url) {
      const char *s = elmc_web_cstr(url);
      /* Official elm/url: only http:// and https://, then the same chomp. */
      int https = 0;
      const char *p = NULL;
      if (s && strncmp(s, "https://", 8) == 0) {
        https = 1;
        p = s + 8;
      } else if (s && strncmp(s, "http://", 7) == 0) {
        p = s + 7;
      } else {
        *out = elmc_maybe_nothing();
        return RC_SUCCESS;
      }
      if (!p[0]) {
        *out = elmc_maybe_nothing();
        return RC_SUCCESS;
      }
      const char *host_end = p;
      while (*host_end && *host_end != ':' && *host_end != '/' && *host_end != '?' && *host_end != '#')
        host_end++;
      char host[256];
      size_t host_len = (size_t)(host_end - p);
      if (host_len >= sizeof(host)) host_len = sizeof(host) - 1;
      memcpy(host, p, host_len);
      host[host_len] = '\\0';
      if (host_len == 0 || strchr(host, '@')) {
        *out = elmc_maybe_nothing();
        return RC_SUCCESS;
      }
      ElmcValue *port_m = elmc_maybe_nothing();
      if (*host_end == ':') {
        host_end++;
        if (*host_end < '0' || *host_end > '9') {
          *out = elmc_maybe_nothing();
          return RC_SUCCESS;
        }
        elmc_int_t port = 0;
        while (*host_end >= '0' && *host_end <= '9') {
          port = port * 10 + (*host_end - '0');
          host_end++;
        }
        if (*host_end && *host_end != '/' && *host_end != '?' && *host_end != '#') {
          *out = elmc_maybe_nothing();
          return RC_SUCCESS;
        }
        ElmcValue *pv = NULL;
        RC rc = elmc_new_int(&pv, port);
        if (rc != RC_SUCCESS) return rc;
        rc = elmc_maybe_just(&port_m, pv);
        elmc_release(pv);
        if (rc != RC_SUCCESS) return rc;
      }
      const char *path_end = host_end;
      while (*path_end && *path_end != '?' && *path_end != '#') path_end++;
      char path[512];
      if (path_end == host_end) {
        memcpy(path, "/", 2);
      } else {
        size_t n = (size_t)(path_end - host_end);
        if (n >= sizeof(path)) n = sizeof(path) - 1;
        memcpy(path, host_end, n);
        path[n] = '\\0';
      }
      ElmcValue *query_m = elmc_maybe_nothing();
      const char *frag = NULL;
      if (*path_end == '?') {
        const char *q = path_end + 1;
        const char *qe = q;
        while (*qe && *qe != '#') qe++;
        if (*qe == '#') frag = qe + 1;
        char qb[512];
        size_t n = (size_t)(qe - q);
        if (n >= sizeof(qb)) n = sizeof(qb) - 1;
        memcpy(qb, q, n);
        qb[n] = '\\0';
        ElmcValue *qv = NULL;
        RC rc = elmc_new_string(&qv, qb);
        if (rc != RC_SUCCESS) return rc;
        rc = elmc_maybe_just(&query_m, qv);
        elmc_release(qv);
        if (rc != RC_SUCCESS) return rc;
      } else if (*path_end == '#') {
        frag = path_end + 1;
      }
      ElmcValue *frag_m = elmc_maybe_nothing();
      if (frag && frag[0]) {
        ElmcValue *fv = NULL;
        RC rc = elmc_new_string(&fv, frag);
        if (rc != RC_SUCCESS) return rc;
        rc = elmc_maybe_just(&frag_m, fv);
        elmc_release(fv);
        if (rc != RC_SUCCESS) return rc;
      }
      ElmcValue *fields[6] = {0};
      RC rc = elmc_new_int(&fields[0], https ? 2 : 1);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_new_string(&fields[1], host);
      if (rc != RC_SUCCESS) return rc;
      fields[2] = port_m;
      rc = elmc_new_string(&fields[3], path);
      if (rc != RC_SUCCESS) return rc;
      fields[4] = query_m;
      fields[5] = frag_m;
      ElmcValue *rec = NULL;
      rc = elmc_record_new_values_take(&rec, 6, fields);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_maybe_just(out, rec);
      elmc_release(rec);
      return rc;
    }
    RC elmc_url_to_string(ElmcValue **out, ElmcValue *url) {
      if (url && url->tag == ELMC_TAG_STRING) {
        *out = elmc_retain(url);
        return RC_SUCCESS;
      }
      ElmcValue *proto = ELMC_RECORD_GET_INDEX(url, 0);
      ElmcValue *host = ELMC_RECORD_GET_INDEX(url, 1);
      ElmcValue *port_m = ELMC_RECORD_GET_INDEX(url, 2);
      ElmcValue *path = ELMC_RECORD_GET_INDEX(url, 3);
      ElmcValue *query_m = ELMC_RECORD_GET_INDEX(url, 4);
      ElmcValue *frag_m = ELMC_RECORD_GET_INDEX(url, 5);
      const char *scheme = elmc_as_int(proto) == 2 ? "https://" : "http://";
      const char *host_s = elmc_web_cstr(host);
      const char *path_s = elmc_web_cstr(path);
      char port_s[32] = "";
      ElmcValue *port_v = elmc_maybe_just_payload(port_m);
      if (port_v) snprintf(port_s, sizeof(port_s), ":%lld", (long long)elmc_as_int(port_v));
      const char *query_s = elmc_maybe_just_payload(query_m) ? elmc_web_cstr(elmc_maybe_just_payload(query_m)) : NULL;
      const char *frag_s = elmc_maybe_just_payload(frag_m) ? elmc_web_cstr(elmc_maybe_just_payload(frag_m)) : NULL;
      size_t n = strlen(scheme) + strlen(host_s) + strlen(port_s) + strlen(path_s) +
                 (query_s ? 1 + strlen(query_s) : 0) + (frag_s ? 1 + strlen(frag_s) : 0);
      char *buf = (char *)elmc_malloc(n + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      snprintf(buf, n + 1, "%s%s%s%s%s%s%s%s", scheme, host_s, port_s, path_s,
               query_s ? "?" : "", query_s ? query_s : "", frag_s ? "#" : "", frag_s ? frag_s : "");
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }
    RC elmc_url_builder_absolute(ElmcValue **out, ElmcValue *path, ElmcValue *query) {
      return elmc_url_build(out, "/", path, query);
    }
    RC elmc_url_builder_relative(ElmcValue **out, ElmcValue *path, ElmcValue *query) {
      return elmc_url_build(out, "", path, query);
    }
    RC elmc_url_builder_cross_origin(ElmcValue **out, ElmcValue *pre, ElmcValue *path, ElmcValue *query) {
      const char *pre_s = elmc_web_cstr(pre);
      size_t plen = strlen(pre_s);
      char *prefix = (char *)elmc_malloc(plen + 2, __func__);
      if (!prefix) return RC_ERR_OUT_OF_MEMORY;
      memcpy(prefix, pre_s, plen);
      prefix[plen] = '/';
      prefix[plen + 1] = '\\0';
      RC rc = elmc_url_build(out, prefix, path, query);
      elmc_free(prefix);
      return rc;
    }
    RC elmc_url_builder_custom(ElmcValue **out, ElmcValue *root, ElmcValue *path, ElmcValue *query, ElmcValue *frag) {
      char cross_buf[512];
      const char *prefix = "/";
      if (root && root->tag == ELMC_TAG_INT && elmc_as_int(root) == 1) {
        prefix = "";
      } else if (root && root->tag == ELMC_TAG_TUPLE2 && root->payload) {
        const char *pre = elmc_web_cstr(((ElmcTuple2 *)root->payload)->second);
        snprintf(cross_buf, sizeof(cross_buf), "%s/", pre);
        prefix = cross_buf;
      }
      ElmcValue *built = NULL;
      RC rc = elmc_url_build(&built, prefix, path, query);
      if (rc != RC_SUCCESS) return rc;
      ElmcValue *frag_v = elmc_maybe_just_payload(frag);
      if (!frag_v) {
        *out = built;
        return RC_SUCCESS;
      }
      const char *base = elmc_web_cstr(built);
      const char *fs = elmc_web_cstr(frag_v);
      size_t n = strlen(base) + 1 + strlen(fs);
      char *buf = (char *)elmc_malloc(n + 1, __func__);
      if (!buf) {
        elmc_release(built);
        return RC_ERR_OUT_OF_MEMORY;
      }
      snprintf(buf, n + 1, "%s#%s", base, fs);
      elmc_release(built);
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }
    RC elmc_url_builder_query_string(ElmcValue **out, ElmcValue *key, ElmcValue *value) {
      ElmcValue *ek = NULL;
      ElmcValue *ev = NULL;
      RC rc = elmc_url_percent_encode(&ek, key);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_url_percent_encode(&ev, value);
      if (rc != RC_SUCCESS) {
        elmc_release(ek);
        return rc;
      }
      rc = elmc_tuple2_take(out, ek, ev);
      if (rc != RC_SUCCESS) {
        elmc_release(ek);
        elmc_release(ev);
      }
      return rc;
    }
    RC elmc_url_builder_query_int(ElmcValue **out, ElmcValue *key, ElmcValue *value) {
      ElmcValue *ek = NULL;
      ElmcValue *ev = NULL;
      RC rc = elmc_url_percent_encode(&ek, key);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_string_from_native_int(&ev, elmc_as_int(value));
      if (rc != RC_SUCCESS) {
        elmc_release(ek);
        return rc;
      }
      rc = elmc_tuple2_take(out, ek, ev);
      if (rc != RC_SUCCESS) {
        elmc_release(ek);
        elmc_release(ev);
      }
      return rc;
    }
    RC elmc_url_builder_to_query(ElmcValue **out, ElmcValue *params) {
      return elmc_url_to_query_into(out, params);
    }

    static RC elmc_web_unsupported(ElmcValue **out) {
      *out = NULL;
      return RC_ERR_UNSUPPORTED;
    }

    RC elmc_http_empty_body(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_pair(ElmcValue **out, ElmcValue *key, ElmcValue *value) {
      (void)key;
      (void)value;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_file_body(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_multipart_body(ElmcValue **out, ElmcValue *parts) {
      (void)parts;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_bytes_part(ElmcValue **out, ElmcValue *key, ElmcValue *mime, ElmcValue *bytes) {
      (void)key;
      (void)mime;
      (void)bytes;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_to_form_data(ElmcValue **out, ElmcValue *parts) {
      (void)parts;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_bytes_to_blob(ElmcValue **out, ElmcValue *mime, ElmcValue *bytes) {
      (void)mime;
      (void)bytes;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_to_data_view(ElmcValue **out, ElmcValue *body) {
      (void)body;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder, ElmcValue *req) {
      (void)to_msg;
      (void)decoder;
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_map_expect(ElmcValue **out, ElmcValue *func, ElmcValue *expect) {
      (void)func;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect_string(ElmcValue **out, ElmcValue *to_msg) {
      (void)to_msg;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect_json(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder) {
      (void)to_msg;
      (void)decoder;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect_bytes(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder) {
      (void)to_msg;
      (void)decoder;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect_whatever(ElmcValue **out, ElmcValue *to_msg) {
      (void)to_msg;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect_string_response(ElmcValue **out, ElmcValue *to_msg, ElmcValue *to_result) {
      (void)to_msg;
      (void)to_result;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect_bytes_response(ElmcValue **out, ElmcValue *to_msg, ElmcValue *to_result) {
      (void)to_msg;
      (void)to_result;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_command(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_risky_command(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_task(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_risky_task(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_string_resolver(ElmcValue **out, ElmcValue *to_result) {
      (void)to_result;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_bytes_resolver(ElmcValue **out, ElmcValue *to_result) {
      (void)to_result;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_cancel(ElmcValue **out, ElmcValue *tracker) {
      (void)tracker;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_fraction_sent(ElmcValue **out, ElmcValue *progress) {
      (void)progress;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_fraction_received(ElmcValue **out, ElmcValue *progress) {
      (void)progress;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_get_json(ElmcValue **out, ElmcValue *url, ElmcValue *expect) {
      (void)url;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_get(ElmcValue **out, ElmcValue *url, ElmcValue *expect) {
      (void)url;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_get_with_options(ElmcValue **out, ElmcValue *url, ElmcValue *options, ElmcValue *expect) {
      (void)url;
      (void)options;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_expect_json(ElmcValue **out, ElmcValue *decoder) {
      (void)decoder;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_expect_string(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_expect_whatever(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_expect_bytes(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_with_metadata(ElmcValue **out, ElmcValue *expect) {
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_empty_body(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_string_body(ElmcValue **out, ElmcValue *body) {
      (void)body;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_json_body(ElmcValue **out, ElmcValue *value) {
      (void)value;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_bytes_body(ElmcValue **out, ElmcValue *bytes) {
      (void)bytes;
      return elmc_web_unsupported(out);
    }
    RC elmc_bytes_encode_sequence(ElmcValue **out, ElmcValue *list) {
      (void)list;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_request(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_post(ElmcValue **out, ElmcValue *url, ElmcValue *body, ElmcValue *expect) {
      (void)url;
      (void)body;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_download_task(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content) {
      (void)name;
      (void)mime;
      (void)content;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_select(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept) {
      (void)to_msg;
      (void)accept;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_download(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content) {
      (void)name;
      (void)mime;
      (void)content;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_download_url(ElmcValue **out, ElmcValue *href) {
      (void)href;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_select_files(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept) {
      (void)to_msg;
      (void)accept;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_name(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_mime(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_size(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_last_modified(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_to_string(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_to_bytes(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_to_url(ElmcValue **out, ElmcValue *file) {
      (void)file;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_decoder(ElmcValue **out) {
      return elmc_web_unsupported(out);
    }
    RC elmc_random_generate(ElmcValue **out, ElmcValue *to_msg, ElmcValue *generator) {
      (void)to_msg;
      (void)generator;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_from_string(ElmcValue **out, ElmcValue *pattern) {
      (void)pattern;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_find(ElmcValue **out, ElmcValue *regex, ElmcValue *str) {
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_contains(ElmcValue **out, ElmcValue *regex, ElmcValue *str) {
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_replace(ElmcValue **out, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str) {
      (void)regex;
      (void)replacement;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_from_string_with(ElmcValue **out, ElmcValue *options, ElmcValue *pattern) {
      (void)options;
      (void)pattern;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_find_at_most(ElmcValue **out, ElmcValue *n, ElmcValue *regex, ElmcValue *str) {
      (void)n;
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_replace_at_most(ElmcValue **out, ElmcValue *n, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str) {
      (void)n;
      (void)regex;
      (void)replacement;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_split(ElmcValue **out, ElmcValue *regex, ElmcValue *str) {
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_split_at_most(ElmcValue **out, ElmcValue *n, ElmcValue *regex, ElmcValue *str) {
      (void)n;
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    static elmc_int_t elmc_time_floored_div(elmc_int_t n, elmc_int_t d) {
      if (d == 0) return 0;
      elmc_int_t q = n / d;
      elmc_int_t r = n % d;
      if (r != 0 && ((n < 0) != (d < 0))) q -= 1;
      return q;
    }
    static elmc_int_t elmc_time_mod_by(elmc_int_t m, elmc_int_t n) {
      if (m == 0) return 0;
      return n - m * elmc_time_floored_div(n, m);
    }
    static elmc_int_t elmc_time_zone_offset_min(ElmcValue *zone) {
      if (!zone) return 0;
      if (zone->tag == ELMC_TAG_INT) return elmc_as_int(zone);
      if (zone->tag == ELMC_TAG_TUPLE2 && zone->payload) {
        return elmc_as_int(((ElmcTuple2 *)zone->payload)->first);
      }
      if (zone->tag == ELMC_TAG_RECORD && zone->payload) {
        ElmcRecord *rec = (ElmcRecord *)zone->payload;
        if (rec->field_count >= 1 && rec->field_values[0] &&
            rec->field_values[0]->tag == ELMC_TAG_INT) {
          return elmc_as_int(rec->field_values[0]);
        }
        if (rec->field_count >= 2) return elmc_as_int(rec->field_values[1]);
      }
      return elmc_as_int(zone);
    }
    static ElmcValue *elmc_time_zone_eras(ElmcValue *zone) {
      if (!zone) return NULL;
      if (zone->tag == ELMC_TAG_TUPLE2 && zone->payload) {
        return ((ElmcTuple2 *)zone->payload)->second;
      }
      if (zone->tag == ELMC_TAG_RECORD && zone->payload) {
        ElmcRecord *rec = (ElmcRecord *)zone->payload;
        if (rec->field_count >= 2 && rec->field_values[0] &&
            rec->field_values[0]->tag == ELMC_TAG_INT) {
          return rec->field_values[1];
        }
      }
      return NULL;
    }
    static elmc_int_t elmc_time_era_start(ElmcValue *era) {
      if (era && era->tag == ELMC_TAG_RECORD && era->payload) {
        ElmcRecord *rec = (ElmcRecord *)era->payload;
        if (rec->field_count >= 2) return elmc_as_int(rec->field_values[1]);
      }
      if (era && era->tag == ELMC_TAG_TUPLE2 && era->payload) {
        return elmc_as_int(((ElmcTuple2 *)era->payload)->second);
      }
      return 0;
    }
    static elmc_int_t elmc_time_era_offset(ElmcValue *era) {
      if (era && era->tag == ELMC_TAG_RECORD && era->payload) {
        ElmcRecord *rec = (ElmcRecord *)era->payload;
        if (rec->field_count >= 1) return elmc_as_int(rec->field_values[0]);
      }
      if (era && era->tag == ELMC_TAG_TUPLE2 && era->payload) {
        return elmc_as_int(((ElmcTuple2 *)era->payload)->first);
      }
      return 0;
    }
    static elmc_int_t elmc_time_adjusted_minutes(ElmcValue *zone, ElmcValue *posix) {
      elmc_int_t posix_minutes = elmc_time_floored_div(elmc_as_int(posix), 60000);
      ElmcValue *cursor = elmc_time_zone_eras(zone);
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (elmc_time_era_start(node->head) < posix_minutes) {
          return posix_minutes + elmc_time_era_offset(node->head);
        }
        cursor = node->tail;
      }
      return posix_minutes + elmc_time_zone_offset_min(zone);
    }
    static void elmc_time_civil(elmc_int_t minutes, elmc_int_t *year, elmc_int_t *month, elmc_int_t *day) {
      elmc_int_t raw_day = elmc_time_floored_div(minutes, 60 * 24) + 719468;
      elmc_int_t era = elmc_time_floored_div(raw_day >= 0 ? raw_day : raw_day - 146096, 146097);
      elmc_int_t day_of_era = raw_day - era * 146097;
      elmc_int_t year_of_era = elmc_time_floored_div(
          day_of_era - elmc_time_floored_div(day_of_era, 1460) +
              elmc_time_floored_div(day_of_era, 36524) - elmc_time_floored_div(day_of_era, 146096),
          365);
      elmc_int_t y = year_of_era + era * 400;
      elmc_int_t day_of_year =
          day_of_era - (365 * year_of_era + elmc_time_floored_div(year_of_era, 4) -
                        elmc_time_floored_div(year_of_era, 100));
      elmc_int_t mp = elmc_time_floored_div(5 * day_of_year + 2, 153);
      elmc_int_t m = mp + (mp < 10 ? 3 : -9);
      *day = day_of_year - elmc_time_floored_div(153 * mp + 2, 5) + 1;
      *month = m;
      *year = y + (m <= 2 ? 1 : 0);
    }
    RC elmc_time_utc(ElmcValue **out) {
      ElmcValue *fields[2] = {0};
      RC rc = elmc_new_int(&fields[0], 0);
      if (rc != RC_SUCCESS) return rc;
      fields[1] = elmc_list_nil();
      return elmc_record_new_values_take(out, 2, fields);
    }
    RC elmc_time_custom_zone(ElmcValue **out, ElmcValue *offset, ElmcValue *eras) {
      ElmcValue *fields[2];
      fields[0] = offset ? elmc_retain(offset) : elmc_int_zero();
      fields[1] = eras ? elmc_retain(eras) : elmc_list_nil();
      return elmc_record_new_values_take(out, 2, fields);
    }
    RC elmc_time_here(ElmcValue **out) {
      ElmcValue *zone = NULL;
      RC rc = elmc_new_int(&zone, 0);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_task_succeed(out, zone);
      elmc_release(zone);
      return rc;
    }
    RC elmc_time_get_zone_name(ElmcValue **out) {
      ElmcValue *offset = NULL;
      RC rc = elmc_new_int(&offset, 0);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_task_succeed(out, offset);
      elmc_release(offset);
      return rc;
    }
    RC elmc_time_to_hour(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      return elmc_new_int(out, elmc_time_mod_by(24, elmc_time_floored_div(elmc_time_adjusted_minutes(zone, posix), 60)));
    }
    RC elmc_time_to_minute(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      return elmc_new_int(out, elmc_time_mod_by(60, elmc_time_adjusted_minutes(zone, posix)));
    }
    RC elmc_time_to_second(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      (void)zone;
      return elmc_new_int(out, elmc_time_mod_by(60, elmc_time_floored_div(elmc_as_int(posix), 1000)));
    }
    RC elmc_time_to_millis(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      (void)zone;
      return elmc_new_int(out, elmc_time_mod_by(1000, elmc_as_int(posix)));
    }
    RC elmc_time_to_year(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      elmc_int_t y = 0, m = 0, d = 0;
      elmc_time_civil(elmc_time_adjusted_minutes(zone, posix), &y, &m, &d);
      return elmc_new_int(out, y);
    }
    RC elmc_time_to_day(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      elmc_int_t y = 0, m = 0, d = 0;
      elmc_time_civil(elmc_time_adjusted_minutes(zone, posix), &y, &m, &d);
      return elmc_new_int(out, d);
    }
    RC elmc_time_to_month(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      elmc_int_t y = 0, m = 0, d = 0;
      elmc_time_civil(elmc_time_adjusted_minutes(zone, posix), &y, &m, &d);
      if (m < 1) m = 1;
      if (m > 12) m = 12;
      return elmc_new_int(out, m - 1);
    }
    RC elmc_time_to_weekday(ElmcValue **out, ElmcValue *zone, ElmcValue *posix) {
      elmc_int_t adj = elmc_time_adjusted_minutes(zone, posix);
      elmc_int_t idx = elmc_time_mod_by(7, elmc_time_floored_div(adj, 60 * 24));
      static const elmc_int_t from_epoch[7] = {3, 4, 5, 6, 0, 1, 2};
      return elmc_new_int(out, from_epoch[idx]);
    }
    RC elmc_browser_get_viewport(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_browser_get_viewport_of(ElmcValue **out, ElmcValue *id) {
      (void)id;
      return elmc_web_unsupported(out);
    }
    RC elmc_browser_set_viewport(ElmcValue **out, ElmcValue *x, ElmcValue *y) {
      (void)x;
      (void)y;
      return elmc_web_unsupported(out);
    }
    RC elmc_browser_set_viewport_of(ElmcValue **out, ElmcValue *id, ElmcValue *x, ElmcValue *y) {
      (void)id;
      (void)x;
      (void)y;
      return elmc_web_unsupported(out);
    }
    RC elmc_browser_get_element(ElmcValue **out, ElmcValue *id) {
      (void)id;
      return elmc_web_unsupported(out);
    }
    RC elmc_browser_dom_focus(ElmcValue **out, ElmcValue *id) {
      (void)id;
      return elmc_web_unsupported(out);
    }
    RC elmc_browser_dom_blur(ElmcValue **out, ElmcValue *id) {
      (void)id;
      return elmc_web_unsupported(out);
    }
    """
  end
end
