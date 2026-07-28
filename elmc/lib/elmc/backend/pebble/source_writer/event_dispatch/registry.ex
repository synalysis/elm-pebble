defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.Registry do
  @moduledoc """
  Mask → payload-shape registry for Pebble subscription event dispatch.

  Msg constructor tags come from call-site `:pebble_sub` params (worker slot
  layout); dispatch only reads `elmc_pebble_sub_tag` / button-raw tables — no
  constructor name guessing.
  """

  @type payload ::
          :dispatch_int
          | {:tag_value, keyword()}
          | {:tag_bool, keyword()}
          | {:record_int_fields, keyword()}

  @type entry :: %{
          fn: String.t(),
          params: [{String.t(), String.t()}],
          mask: String.t(),
          payload: payload(),
          watchface_guard: boolean(),
          custom?: boolean(),
          body: String.t() | nil
        }

  @spec entries() :: [entry()]
  def entries do
    clock_entries() ++
      platform_entries() ++
      motion_entries() ++
      input_entries() ++
      services_entries() ++
      app_message_entries() ++
      cmd_callback_stub_entries()
  end

  @spec helpers() :: [String.t()]
  def helpers do
    ["elmc_pebble_is_subscribed", "elmc_pebble_sub_tag", "elmc_pebble_button_event"]
  end

  defp clock_entries do
    for {fn_suffix, param} <- [
          {"hour", "hour"},
          {"minute", "minute"},
          {"day", "day"},
          {"month", "month"},
          {"year", "year"}
        ] do
      mask_entry("elmc_pebble_dispatch_#{fn_suffix}", [{"int", param}], clock_mask(fn_suffix),
        tag_value: param
      )
    end
  end

  defp platform_entries do
    [
      mask_entry(
        "elmc_pebble_dispatch_animation_finished",
        [{"int", "animation_id"}],
        "ELMC_PEBBLE_SUB_ANIMATION_FINISHED",
        tag_value: "animation_id"
      )
    ]
  end

  defp motion_entries do
    [
      %{
        fn: "elmc_pebble_dispatch_frame",
        params: [
          {"ElmcPebbleApp *", "app"},
          {"int64_t", "dt_ms"},
          {"int64_t", "elapsed_ms"},
          {"int64_t", "frame"}
        ],
        mask: "ELMC_PEBBLE_SUB_FRAME",
        payload:
          {:record_int_fields,
           fields: [
             {"dtMs", "dt_ms"},
             {"elapsedMs", "elapsed_ms"},
             {"frame", "frame"}
           ]},
        watchface_guard: true,
        custom?: false,
        body: nil
      }
    ]
  end

  defp input_entries do
    [
      %{
        fn: "elmc_pebble_dispatch_button",
        params: [{"ElmcPebbleApp *", "app"}, {"int32_t", "button_id"}],
        mask: nil,
        payload: :dispatch_int,
        watchface_guard: true,
        custom?: true,
        body: button_body()
      },
      %{
        fn: "elmc_pebble_dispatch_button_raw",
        params: [
          {"ElmcPebbleApp *", "app"},
          {"int32_t", "button_id"},
          {"int32_t", "pressed"}
        ],
        mask: "ELMC_PEBBLE_SUB_BUTTON_RAW",
        payload: :dispatch_int,
        watchface_guard: true,
        custom?: true,
        body: button_raw_body()
      },
      %{
        fn: "elmc_pebble_dispatch_accel_tap",
        params: [
          {"ElmcPebbleApp *", "app"},
          {"int32_t", "axis"},
          {"int32_t", "direction"}
        ],
        mask: "ELMC_PEBBLE_SUB_ACCEL_TAP",
        payload: :dispatch_int,
        watchface_guard: true,
        custom?: true,
        body: accel_tap_body()
      },
      mask_entry(
        "elmc_pebble_dispatch_accel_data",
        [{"int32_t", "x"}, {"int32_t", "y"}, {"int32_t", "z"}],
        "ELMC_PEBBLE_SUB_ACCEL_DATA",
        watchface_guard: true,
        record_int_fields: [
          {"x", "x"},
          {"y", "y"},
          {"z", "z"}
        ]
      )
    ]
  end

  defp services_entries do
    [
      mask_entry(
        "elmc_pebble_dispatch_battery",
        [{"int", "level"}],
        "ELMC_PEBBLE_SUB_BATTERY",
        tag_value: "level",
        clamp: {0, 100}
      ),
      mask_entry(
        "elmc_pebble_dispatch_connection",
        [{"int", "connected"}],
        "ELMC_PEBBLE_SUB_CONNECTION",
        tag_bool: "connected"
      ),
      mask_entry(
        "elmc_pebble_dispatch_health",
        [{"int", "event"}],
        "ELMC_PEBBLE_SUB_HEALTH",
        tag_value: "event",
        clamp: {0, 2},
        default_on_clamp: 0
      ),
      mask_entry(
        "elmc_pebble_dispatch_app_focus",
        [{"int", "in_focus"}],
        "ELMC_PEBBLE_SUB_APP_FOCUS",
        tag_value_expr: "in_focus ? 0 : 1"
      ),
      mask_entry(
        "elmc_pebble_dispatch_backlight",
        [{"int", "is_on"}],
        "ELMC_PEBBLE_SUB_BACKLIGHT",
        tag_value_expr: "is_on ? 0 : 1"
      ),
      mask_entry(
        "elmc_pebble_dispatch_screen_change",
        [
          {"int", "width"},
          {"int", "height"},
          {"int", "shape"},
          {"int", "color_mode"}
        ],
        "ELMC_PEBBLE_SUB_SCREEN_CHANGE",
        record_int_fields: [
          {"width", "width"},
          {"height", "height"},
          {"shape", "shape"},
          {"colorMode", "color_mode"}
        ]
      ),
      mask_entry(
        "elmc_pebble_dispatch_speaker_finished",
        [{"int", "reason"}],
        "ELMC_PEBBLE_SUB_SPEAKER_FINISHED",
        tag_value: "reason",
        clamp: {0, 3},
        default_on_clamp: 0
      ),
      mask_entry(
        "elmc_pebble_dispatch_dictation_status",
        [{"int", "status"}],
        "ELMC_PEBBLE_SUB_DICTATION",
        tag_value: "status",
        clamp: {0, 2}
      ),
      %{
        fn: "elmc_pebble_dispatch_dictation_result",
        params: [
          {"ElmcPebbleApp *", "app"},
          {"int", "is_ok"},
          {"int", "error_code"},
          {"const char *", "text"}
        ],
        mask: "ELMC_PEBBLE_SUB_DICTATION",
        payload: :dispatch_int,
        watchface_guard: false,
        custom?: true,
        body: dictation_result_body()
      },
      mask_entry(
        "elmc_pebble_dispatch_unobstructed_will_change",
        [{"int", "x"}, {"int", "y"}, {"int", "w"}, {"int", "h"}],
        "ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA",
        record_int_fields: [
          {"x", "x"},
          {"y", "y"},
          {"w", "w"},
          {"h", "h"}
        ]
      ),
      mask_entry(
        "elmc_pebble_dispatch_unobstructed_changing",
        [{"int", "progress"}],
        "ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA",
        tag_value: "progress",
        clamp: {0, 255}
      ),
      mask_entry(
        "elmc_pebble_dispatch_unobstructed_did_change",
        [],
        "ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA",
        dispatch_int: true
      )
    ]
  end

  defp mask_entry(fn_name, params, mask, opts) when is_list(opts) do
    watchface_guard = Keyword.get(opts, :watchface_guard, false)

    payload =
      cond do
        Keyword.get(opts, :dispatch_int) ->
          :dispatch_int

        fields = Keyword.get(opts, :record_int_fields) ->
          {:record_int_fields, fields: fields}

        param = Keyword.get(opts, :tag_bool) ->
          {:tag_bool, param: param}

        expr = Keyword.get(opts, :tag_value_expr) ->
          {:tag_value, expr: expr}

        param = Keyword.get(opts, :tag_value) ->
          clamp = Keyword.get(opts, :clamp)
          default = Keyword.get(opts, :default_on_clamp)

          kw = [param: param]
          kw = if clamp, do: Keyword.put(kw, :clamp, clamp), else: kw
          kw = if default != nil, do: Keyword.put(kw, :default_on_clamp, default), else: kw
          {:tag_value, kw}

        true ->
          raise ArgumentError, "mask_entry #{fn_name} needs a payload option"
      end

    %{
      fn: fn_name,
      params: [{"ElmcPebbleApp *", "app"} | params],
      mask: mask,
      payload: payload,
      watchface_guard: watchface_guard,
      custom?: false,
      body: nil
    }
  end

  defp clock_mask("hour"), do: "ELMC_PEBBLE_SUB_HOUR"
  defp clock_mask("minute"), do: "ELMC_PEBBLE_SUB_MINUTE"
  defp clock_mask("day"), do: "ELMC_PEBBLE_SUB_DAY"
  defp clock_mask("month"), do: "ELMC_PEBBLE_SUB_MONTH"
  defp clock_mask("year"), do: "ELMC_PEBBLE_SUB_YEAR"

  defp button_body do
    """
    if (!app || !app->initialized) return -1;
    if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
    int64_t required = 0;
    if (button_id == ELMC_PEBBLE_BUTTON_UP) {
      required = ELMC_PEBBLE_SUB_BUTTON_UP;
    } else if (button_id == ELMC_PEBBLE_BUTTON_SELECT) {
      required = ELMC_PEBBLE_SUB_BUTTON_SELECT;
    } else if (button_id == ELMC_PEBBLE_BUTTON_DOWN) {
      required = ELMC_PEBBLE_SUB_BUTTON_DOWN;
    } else {
      return -3;
    }
    if (!elmc_pebble_is_subscribed(app, required)) return -8;
    elmc_int_t tag = elmc_worker_sub_msg_tag(&app->worker, required);
    if (tag <= 0) return -6;
    return elmc_pebble_dispatch_int(app, tag);
    """
  end

  defp button_raw_body do
    """
    if (!app || !app->initialized) return -1;
    if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
    if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BUTTON_RAW)) return -8;
    elmc_int_t event = elmc_pebble_button_event(pressed);
    elmc_int_t tag = elmc_worker_button_raw_msg_tag(&app->worker, button_id, event);
    if (tag <= 0) return 1;
    return elmc_pebble_dispatch_int(app, tag);
    """
  end

  defp accel_tap_body do
    """
    (void)axis;
    (void)direction;
    if (!app || !app->initialized) return -1;
    if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
    if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_TAP)) return -8;
    elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ACCEL_TAP);
    if (tag <= 0) return -6;
    return elmc_pebble_dispatch_int(app, tag);
    """
  end

  defp dictation_result_body do
    """
    if (!app || !app->initialized) return -1;
    if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DICTATION)) return -8;
    elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DICTATION);
    if (tag <= 0) return -6;

    ElmcValue *result_payload = NULL;
    if (is_ok) {
      ElmcValue *ok_value = elmc_new_string_take(text ? text : "");
      if (elmc_result_ok(&result_payload, ok_value) != RC_SUCCESS) return -2;
      elmc_release(ok_value);
    } else {
      ElmcValue *error_value = NULL;
      if (error_code == 3) {
        error_value =
            elmc_tuple2_take_value(elmc_new_int_take(3), elmc_new_string_take(text ? text : ""));
      } else {
        error_value = elmc_new_int_take(error_code);
      }
      if (!error_value) return -2;
      if (elmc_result_err(&result_payload, error_value) != RC_SUCCESS) return -2;
      elmc_release(error_value);
    }
    if (!result_payload) return -2;

    int rc = elmc_pebble_dispatch_tag_payload(app, tag, result_payload);
    elmc_release(result_payload);
    return rc;
    """
  end

  defp app_message_entries do
    [
      %{
        fn: "elmc_pebble_dispatch_appmessage",
        params: [
          {"ElmcPebbleApp *", "app"},
          {"int32_t", "key"},
          {"int32_t", "value"}
        ],
        mask: "ELMC_PEBBLE_SUB_APPMESSAGE",
        payload: :dispatch_int,
        watchface_guard: false,
        custom?: true,
        body: """
        int64_t tag = 0;
        int rc = elmc_pebble_msg_from_appmessage(key, value, &tag);
        if (rc != 0) return rc;
        return elmc_pebble_dispatch_int(app, tag);
        """
      }
    ]
  end

  defp cmd_callback_stub_entries do
    [
      %{
        fn: "elmc_pebble_dispatch_storage_string",
        params: [{"ElmcPebbleApp *", "app"}, {"const char *", "value"}],
        mask: nil,
        payload: :dispatch_int,
        watchface_guard: false,
        custom?: true,
        body: """
        (void)value;
        if (!app || !app->initialized) return -1;
        /* Storage string dispatch requires the Msg tag encoded in the cmd (cmd.p1). */
        return -6;
        """
      },
      %{
        fn: "elmc_pebble_dispatch_random_int",
        params: [{"ElmcPebbleApp *", "app"}, {"int32_t", "value"}],
        mask: nil,
        payload: :dispatch_int,
        watchface_guard: false,
        custom?: true,
        body: """
        (void)value;
        if (!app || !app->initialized) return -1;
        /* Random.generate must encode the callback tag in the cmd (cmd.p0). */
        return -6;
        """
      }
    ]
  end

  @spec tick_body(boolean()) :: String.t()
  def tick_body(tick_has_payload?) do
    payload_line = Elmc.Backend.Pebble.MsgCodegen.tick_dispatch_line(tick_has_payload?)

    """
    if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_TICK)) return -8;
    elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_TICK);
    if (tag <= 0) return -6;
    #{payload_line}
    return elmc_pebble_dispatch_int(app, tag);
    """
  end

  @spec app_message_decode_body(String.t(), String.t()) :: String.t()
  def app_message_decode_body(value_decode_cases, key_decode_cases) do
    """
    int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag) {
      if (!out_tag) return -1;

      if (key == 0) {
        switch (value) {
    #{value_decode_cases}
          default: return -3;
        }
      }

      if (value == 0) return -4;
      switch (key) {
    #{key_decode_cases}
        default: return -3;
      }
    }
    """
  end

  @spec compass_body() :: String.t()
  def compass_body do
    """
    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_compass_heading");
      if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -1);
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_COMPASS)) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -8);
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_COMPASS);
      if (tag <= 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -6);

      RC Rc = RC_SUCCESS;
      const char *names[] = {"degrees", "isValid"};
      ElmcValue *values[2];
      ElmcValue *record = NULL;
      ElmcValue *tag_value = NULL;
      ElmcValue *msg = NULL;
      CATCH_BEGIN
        CHECK_RC_TO(Rc, elmc_new_float(&values[0], degrees));
        CHECK_RC_TO(Rc, elmc_new_bool(&values[1], is_valid ? 1 : 0));
        CHECK_RC_TO(Rc, elmc_record_new_take(&record, 2, names, values));
        CHECK_RC_TO(Rc, elmc_new_int(&tag_value, tag));
        CHECK_RC_TO(Rc, elmc_tuple2_take(&msg, tag_value, record));
      CATCH_END
      elmc_release(tag_value);
      elmc_release(record);
      if (Rc != RC_SUCCESS) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -2);
      elmc_pebble_prepare_dispatch(app);
      int dispatch_rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", elmc_pebble_finish_dispatch(app, dispatch_rc));
    }
    """
  end

  @spec host_api_body() :: String.t()
  def host_api_body do
    """
    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd) {
      if (!app || !app->initialized || !out_cmd) return -1;
      ElmcValue *cmd = elmc_worker_take_cmd(&app->worker);
      if (!cmd) return -2;
      int rc = elmc_cmd_from_value(cmd, out_cmd);
      elmc_release(cmd);
      return rc;
    }

    static int elmc_pebble_cmd_queue_index(ElmcValue *queue, int target, ElmcPebbleCmd *out_cmd) {
      if (!out_cmd || target < 0) return -1;
      int index = 0;
      ElmcValue *cursor = queue;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcPebbleCmd cmd = {0};
        if (node->head && elmc_cmd_from_value(node->head, &cmd) == 0 &&
            cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          if (index == target) {
            *out_cmd = cmd;
            return 0;
          }
          index += 1;
        }
        cursor = node->tail;
      }
      if (cursor && cursor->tag != ELMC_TAG_LIST) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_cmd_from_value(cursor, &cmd) == 0 && cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          if (index == target) {
            *out_cmd = cmd;
            return 0;
          }
        }
      }
      return -2;
    }

    static int elmc_pebble_cmd_queue_count_value(ElmcValue *queue) {
      int count = 0;
      ElmcValue *cursor = queue;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcPebbleCmd cmd = {0};
        if (node->head && elmc_cmd_from_value(node->head, &cmd) == 0 &&
            cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          count += 1;
        }
        cursor = node->tail;
      }
      if (cursor && cursor->tag != ELMC_TAG_LIST) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_cmd_from_value(cursor, &cmd) == 0 && cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          count += 1;
        }
      }
      return count;
    }

    int elmc_pebble_pending_cmd_count(ElmcPebbleApp *app) {
      if (!app || !app->initialized) return 0;
      ElmcValue *queue = elmc_worker_pending_cmds_borrow(&app->worker);
      if (!queue) return 0;
      int count = elmc_pebble_cmd_queue_count_value(queue);
      elmc_release(queue);
      return count;
    }

    int elmc_pebble_last_dispatch_cmd_count(ElmcPebbleApp *app) {
      if (!app || !app->initialized) return 0;
      return elmc_worker_last_dispatch_cmd_count(&app->worker);
    }

    int elmc_pebble_last_dispatch_cmd_at(ElmcPebbleApp *app, int index, ElmcPebbleCmd *out_cmd) {
      if (!app || !app->initialized || !out_cmd) return -1;
      ElmcWorkerDispatchCmd snap = {0};
      if (elmc_worker_last_dispatch_cmd_at(&app->worker, index, &snap) != 0) return -2;
      out_cmd->kind = snap.kind;
      out_cmd->p0 = snap.p0;
      out_cmd->p1 = snap.p1;
      out_cmd->p2 = snap.p2;
      out_cmd->p3 = snap.p3;
      out_cmd->p4 = snap.p4;
      out_cmd->p5 = snap.p5;
      strncpy(out_cmd->text, snap.text, sizeof(out_cmd->text) - 1);
      out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
      return 0;
    }

    int elmc_pebble_pending_cmd_at(ElmcPebbleApp *app, int index, ElmcPebbleCmd *out_cmd) {
      if (!app || !app->initialized || !out_cmd) return -1;
      ElmcValue *queue = elmc_worker_pending_cmds_borrow(&app->worker);
      if (!queue) return -2;
      int rc = elmc_pebble_cmd_queue_index(queue, index, out_cmd);
      elmc_release(queue);
      return rc;
    }

    static int elmc_pebble_view_commands_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe);
    static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end);

    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd) {
      int count = elmc_pebble_view_commands(app, out_cmd, 1);
      if (count < 0) return count;
      if (count == 0) return -7;
      return 0;
    }

    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds) {
      return elmc_pebble_view_commands_impl(app, out_cmds, max_cmds, 0, 1);
    }

    int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
      int count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0, NULL);
      if (count < max_cmds) {
        elmc_pebble_clear_view_cache(app);
      }
      return count;
    }
    """
  end

  @spec helper_body(String.t()) :: String.t() | nil
  def helper_body("elmc_pebble_is_subscribed") do
    """
    static int elmc_pebble_is_subscribed(ElmcPebbleApp *app, int64_t flag) {
      if (!app || !app->initialized) return 0;
      int64_t active = elmc_worker_subscriptions(&app->worker);
      return (active & flag) != 0;
    }
    """
  end

  def helper_body("elmc_pebble_sub_tag") do
    """
    static elmc_int_t elmc_pebble_sub_tag(ElmcPebbleApp *app, int64_t flag) {
      return elmc_worker_sub_msg_tag(&app->worker, flag);
    }
    """
  end

  def helper_body("elmc_pebble_button_event") do
    """
    static elmc_int_t elmc_pebble_button_event(int32_t pressed) {
      return pressed ? ELMC_BUTTON_EVENT_PRESSED : ELMC_BUTTON_EVENT_RELEASED;
    }
    """
  end

  def helper_body(_), do: nil
end
