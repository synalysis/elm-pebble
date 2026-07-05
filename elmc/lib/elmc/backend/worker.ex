defmodule Elmc.Backend.Worker do
  @moduledoc """
  Generates a minimal C worker adapter for Elm-like init/update loops.
  """

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.Subscriptions
  alias Elmc.Types

  @fallback_sub_tag_slots 32
  @fallback_button_raw_subs 16

  @spec write_worker_adapter(IR.t(), String.t(), String.t()) :: :ok | {:error, Types.file_error()}
  def write_worker_adapter(%IR{} = ir, out_dir, entry_module) do
    c_dir = Path.join(out_dir, "c")
    analysis = subscription_analysis(ir, entry_module)

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_worker.h"), worker_header(analysis)),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_worker.c"),
             ir |> worker_source(entry_module, analysis) |> CSource.format()
           ) do
      :ok
    end
  end

  @spec subscription_analysis(IR.t(), String.t()) :: Subscriptions.worker_subscription_layout()
  def subscription_analysis(%IR{} = ir, entry_module) do
    case subscriptions_expr(ir, entry_module) do
      nil ->
        %{
          tag_masks: [],
          button_raw_count: 0,
          compact: true,
          has_frame: false,
          model_dependent?: false,
          slot_map: %{},
          frame_slot: nil,
          sub_tag_slots: 1,
          button_raw_subs: 1
        }

      expr ->
        decl = subscriptions_decl(ir, entry_module)

        expr
        |> Subscriptions.analyze_subscription_masks()
        |> Map.put(:model_dependent?, Subscriptions.model_dependent?(decl))
        |> build_slot_layout()
    end
  end

  defp subscriptions_decl(%IR{} = ir, entry_module) do
    ir.modules
    |> Enum.find_value(fn mod ->
      if mod.name == entry_module do
        mod.declarations
        |> Enum.find_value(fn
          %{kind: :function, name: "subscriptions"} = decl -> decl
          _ -> nil
        end)
      end
    end)
  end

  defp subscriptions_expr(%IR{} = ir, entry_module) do
    case subscriptions_decl(ir, entry_module) do
      %{expr: expr} when not is_nil(expr) -> expr
      %{body: body} when not is_nil(body) -> body
      _ -> nil
    end
  end

  defp build_slot_layout(%{compact: false} = analysis) do
    Map.merge(analysis, %{
      slot_map: %{},
      frame_slot: nil,
      sub_tag_slots: @fallback_sub_tag_slots,
      button_raw_subs: max(analysis.button_raw_count, @fallback_button_raw_subs)
    })
  end

  defp build_slot_layout(%{tag_masks: tag_masks, has_frame: has_frame} = analysis) do
    {slot_map, next_index} =
      Enum.map_reduce(tag_masks, 0, fn mask, index ->
        name = slot_define_name(mask)
        {{mask, {name, index}}, index + 1}
      end)
      |> then(fn {pairs, next_index} -> {Map.new(pairs), next_index} end)

    frame_slot = if has_frame, do: next_index, else: nil
    button_raw_subs = max(analysis.button_raw_count, 1)

    # Raw-button-only apps with three or more presses fault on Basalt/QEMU init unless
    # the compact worker layout also reserves a frame tag slot (see game-2048).
    needs_frame_slot? =
      has_frame or
        (analysis.button_raw_count >= 3 and tag_masks == [])
    frame_slot = if needs_frame_slot?, do: frame_slot || next_index, else: frame_slot
    sub_tag_slots = next_index + if(needs_frame_slot?, do: 1, else: 0) |> max(1)

    Map.merge(analysis, %{
      slot_map: slot_map,
      frame_slot: frame_slot,
      sub_tag_slots: sub_tag_slots,
      button_raw_subs: button_raw_subs
    })
  end

  defp sub_tag_slot_fn(%{compact: false}) do
    """
    static int elmc_sub_tag_slot(int64_t mask) {
      if (mask == 0) return -1;
      if ((mask & (1LL << 13)) != 0) return 13;
      if ((mask & (mask - 1)) != 0) return -1;
      int bit = 0;
      while (bit < 32 && (mask & (1LL << bit)) == 0) bit++;
      return bit < 32 ? bit : -1;
    }
    """
  end

  defp sub_tag_slot_fn(%{compact: true} = analysis) do
    frame_guard =
      if is_integer(analysis.frame_slot) do
        "  if ((mask & (1LL << 13)) != 0) return ELMC_WORKER_SLOT_FRAME;\n"
      else
        ""
      end

    switch_cases =
      analysis.slot_map
      |> Enum.map(fn {mask, {name, _index}} ->
        "    case #{mask_case_label(mask)}: return #{name};"
      end)
      |> Enum.join("\n")

    switch_body =
      if switch_cases == "" do
        "  (void)mask;\n  return -1;"
      else
        """
        switch (mask) {
        #{switch_cases}
          default: return -1;
        }
        """
      end

    """
    static int elmc_sub_tag_slot(int64_t mask) {
      if (mask == 0) return -1;
    #{frame_guard}#{switch_body}
    }
    """
  end

  defp mask_case_label(mask) when is_binary(mask) do
    Map.get(Emit.subscription_mask_literals(), mask, mask)
  end

  defp slot_define_name(mask) when is_binary(mask) do
    mask
    |> String.replace_prefix("ELMC_SUBSCRIPTION_", "ELMC_WORKER_SLOT_")
    |> String.replace(~r/[^A-Z0-9_]/, "_")
    |> String.trim("_")
  end

  @spec worker_header(map()) :: String.t()
  defp worker_header(analysis) do
    slot_defines = worker_slot_defines(analysis)

    """
    #ifndef ELMC_WORKER_H
    #define ELMC_WORKER_H

    #include "elmc_generated.h"

    #define ELMC_WORKER_MAX_BUTTON_RAW_SUBS #{analysis.button_raw_subs}
    #define ELMC_WORKER_SUB_TAG_SLOTS #{analysis.sub_tag_slots}
    #{slot_defines}

    typedef struct {
      elmc_int_t button_id;
      elmc_int_t event;
      elmc_int_t msg_tag;
    } ElmcButtonRawSub;

    typedef struct {
      ElmcValue *model;
      ElmcValue *pending_cmd;
      ElmcValue *last_dispatch_cmd;
      int64_t subscriptions;
      elmc_int_t sub_msg_tags[ELMC_WORKER_SUB_TAG_SLOTS];
      ElmcButtonRawSub button_raw_subs[ELMC_WORKER_MAX_BUTTON_RAW_SUBS];
      int button_raw_sub_count;
      int dispatch_needs_render;
    } ElmcWorkerState;

    int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags);
    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg);
    int elmc_worker_dispatch_needs_render(ElmcWorkerState *state);
    ElmcValue *elmc_worker_model(ElmcWorkerState *state);
    ElmcValue *elmc_worker_pending_cmds_borrow(ElmcWorkerState *state);
    ElmcValue *elmc_worker_last_dispatch_cmd_borrow(ElmcWorkerState *state);
    ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
    int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
    elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag);
    elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event);
    elmc_int_t elmc_worker_last_fail_code(void);
    elmc_int_t elmc_worker_last_fail_line(void);
    void elmc_worker_deinit(ElmcWorkerState *state);

    #endif
    """
  end

  defp worker_slot_defines(%{compact: false}), do: ""

  defp worker_slot_defines(%{slot_map: slot_map, frame_slot: frame_slot}) do
    lines =
      Enum.map(slot_map, fn {_mask, {name, index}} ->
        "#define #{name} #{index}"
      end)

    frame_line =
      if is_integer(frame_slot) do
        ["#define ELMC_WORKER_SLOT_FRAME #{frame_slot}"]
      else
        []
      end

    (lines ++ frame_line)
    |> Enum.sort()
    |> Enum.join("\n")
    |> case do
      "" -> ""
      defines -> defines <> "\n"
    end
  end

  @spec worker_source(ElmEx.IR.t(), String.t(), map()) :: String.t()
  defp worker_source(ir, entry_module, analysis) do
    module =
      Enum.find(ir.modules, fn mod ->
        mod.name == entry_module
      end)

    declarations = if module, do: module.declarations, else: []
    has_init = Enum.any?(declarations, &(&1.kind == :function and &1.name == "init"))
    has_update = Enum.any?(declarations, &(&1.kind == :function and &1.name == "update"))

    has_subscriptions =
      Enum.any?(declarations, &(&1.kind == :function and &1.name == "subscriptions"))

    safe_module = entry_module |> String.replace(".", "_")

    init_call =
      if has_init do
        """
        ElmcValue *args[] = { flags };
          ElmcValue *result = NULL;
          RC init_rc = elmc_fn_#{safe_module}_init(&result, args, 1);
          if (init_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker init", init_rc);
            elmc_release(result);
            return -2;
          }
        """
      else
        """
        (void)flags;
          ElmcValue *result = elmc_int_zero();
        """
      end

    init_missing_guard = if has_init, do: "", else: "  return -3;\n"

    update_call =
      if has_update do
        """
        ElmcValue *args[] = { msg, state->model };
          ElmcValue *result = NULL;
          RC update_rc = elmc_fn_#{safe_module}_update(&result, args, 2);
          if (update_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker update", update_rc);
            elmc_release(result);
            return -2;
          }
        """
      else
        """
        (void)msg;
          ElmcValue *result = elmc_int_zero();
        """
      end

    update_missing_guard = if has_update, do: "", else: "  return -4;\n"

    subscriptions_call =
      if has_subscriptions do
        """
        ElmcValue *args[] = { state->model };
          ElmcValue *result = NULL;
          RC sub_rc = elmc_fn_#{safe_module}_subscriptions(&result, args, 1);
          if (sub_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker subscriptions", sub_rc);
            elmc_release(result);
            return 0;
          }
        """
      else
        """
        ElmcValue *result = elmc_int_zero();
        """
      end

    dispatch_subscriptions_refresh =
      if has_subscriptions and Map.get(analysis, :model_dependent?, true) do
        "  if (state->dispatch_needs_render) {\n    state->subscriptions = compute_subscriptions(state);\n  }\n"
      else
        ""
      end

    """
    #include "elmc_worker.h"
    #if defined(__has_include)
    #if __has_include("../../elmc_emulator_build_flags.h")
    #include "../../elmc_emulator_build_flags.h"
    #elif __has_include("elmc_emulator_build_flags.h")
    #include "elmc_emulator_build_flags.h"
    #endif
    #endif

    #if defined(ELMC_PEBBLE_PLATFORM)
    #include <pebble.h>
    #define ELMC_WORKER_LOG_RC_FAIL(site, rc) \\
      do { \\
        ELMC_RC_LOG_FAIL((rc), (site), "failed"); \\
        APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC %s RC %u line %u", (site), (unsigned)(rc), (unsigned)elmc_last_fail_line); \\
      } while (0)
    #else
    #define ELMC_WORKER_LOG_RC_FAIL(site, rc) ELMC_RC_LOG_FAIL((rc), (site), "failed")
    #endif

    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
    static void elmc_worker_heap_log(const char *label) {
      APP_LOG(
        APP_LOG_LEVEL_INFO,
        "ELMC heap %s used=%lu free=%lu",
        label ? label : "?",
        (unsigned long)heap_bytes_used(),
        (unsigned long)heap_bytes_free());
    }
    #else
    #define elmc_worker_heap_log(label) do { (void)(label); } while (0)
    #endif

    /* Transfer ownership from (model, cmd) tuple without retaining or double-freeing. */
    static ElmcValue *extract_model_take(ElmcValue *value) {
      if (!value) return elmc_int_zero();
      if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_retain(value);
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      if (!pair->first) return elmc_int_zero();
      ElmcValue *model = pair->first;
      pair->first = NULL;
      return model;
    }

    static ElmcValue *extract_cmd_take(ElmcValue *value) {
      if (!value) return elmc_int_zero();
      if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_int_zero();
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      if (!pair->second) return elmc_int_zero();
      ElmcValue *cmd = pair->second;
      pair->second = NULL;
      return cmd;
    }

    static int elmc_cmd_is_none(ElmcValue *value) {
      return !value || ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0);
    }

    static ElmcValue *elmc_cmd_none(void) {
      return elmc_int_zero();
    }

    static RC elmc_cmd_queue_cons_take(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        *out = elmc_list_cons_take(head, tail);
      CATCH_END;
      return rc;
    }

    static RC elmc_cmd_queue_push_back_take(ElmcValue **out, ElmcValue *queue, ElmcValue *cmd) {
      RC rc = RC_SUCCESS;
      ElmcValue *cell = NULL;
      ElmcValue *head_cell = NULL;
      CATCH_BEGIN
        if (!cmd || elmc_cmd_is_none(cmd)) {
          elmc_release(cmd);
          cmd = NULL;
          *out = queue ? queue : elmc_cmd_none();
          queue = NULL;
        } else {
          rc = elmc_cmd_queue_cons_take(&cell, cmd, elmc_list_nil());
          cmd = NULL;
          CHECK_RC(rc);
          if (!cell || elmc_cmd_is_none(cell)) {
            *out = queue ? queue : elmc_cmd_none();
            queue = NULL;
            cell = NULL;
          } else if (!queue || elmc_cmd_is_none(queue)) {
            elmc_release(queue);
            queue = NULL;
            *out = cell;
            cell = NULL;
      } else if (queue->tag == ELMC_TAG_CMD) {
        rc = elmc_cmd_queue_cons_take(&head_cell, queue, cell);
        queue = NULL;
        cell = NULL;
        CHECK_RC(rc);
            *out = head_cell ? head_cell : elmc_cmd_none();
            head_cell = NULL;
          } else if (queue->tag != ELMC_TAG_LIST) {
            elmc_release(cell);
            cell = NULL;
            *out = queue;
            queue = NULL;
          } else {
            ElmcValue **tail = &queue;
            ElmcValue *cursor = queue;
            while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
              ElmcCons *node = (ElmcCons *)cursor->payload;
              tail = &node->tail;
              cursor = node->tail;
            }
            *tail = cell;
            cell = NULL;
            *out = queue;
            queue = NULL;
          }
        }
      CATCH_END;
      elmc_release(cmd);
      elmc_release(queue);
      elmc_release(cell);
      elmc_release(head_cell);
      return rc;
    }

    static RC elmc_cmd_queue_concat_take(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
      RC rc = RC_SUCCESS;
      ElmcValue *tail_cell = NULL;
      ElmcValue *pair = NULL;
      CATCH_BEGIN
        if (!left || elmc_cmd_is_none(left)) {
          elmc_release(left);
          left = NULL;
          *out = right ? right : elmc_cmd_none();
          right = NULL;
        } else if (!right || elmc_cmd_is_none(right)) {
          elmc_release(right);
          right = NULL;
          *out = left;
          left = NULL;
        } else if (left->tag == ELMC_TAG_CMD) {
          if (right->tag == ELMC_TAG_CMD) {
            rc = elmc_cmd_queue_cons_take(&tail_cell, right, elmc_list_nil());
            right = NULL;
            CHECK_RC(rc);
        rc = elmc_cmd_queue_cons_take(&pair, left, tail_cell ? tail_cell : elmc_list_nil());
        left = NULL;
        tail_cell = NULL;
        CHECK_RC(rc);
            *out = pair;
            pair = NULL;
          } else if (right->tag == ELMC_TAG_LIST) {
            rc = elmc_cmd_queue_cons_take(&pair, left, right);
            left = NULL;
            right = NULL;
            CHECK_RC(rc);
            *out = pair;
            pair = NULL;
          } else {
            elmc_release(right);
            right = NULL;
            *out = left;
            left = NULL;
          }
        } else if (right->tag == ELMC_TAG_CMD) {
          rc = elmc_cmd_queue_push_back_take(out, left, right);
          left = NULL;
          right = NULL;
          CHECK_RC(rc);
        } else if (right->tag != ELMC_TAG_LIST) {
          elmc_release(right);
          right = NULL;
          *out = left;
          left = NULL;
        } else if (left->tag != ELMC_TAG_LIST) {
          elmc_release(left);
          left = NULL;
          *out = right;
          right = NULL;
        } else {
          ElmcValue **tail = &left;
          ElmcValue *cursor = left;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            tail = &node->tail;
            cursor = node->tail;
          }
          *tail = right;
          right = NULL;
          *out = left;
          left = NULL;
        }
      CATCH_END;
      elmc_release(left);
      elmc_release(right);
      elmc_release(tail_cell);
      elmc_release(pair);
      return rc;
    }

    static RC elmc_cmd_queue_push_entry(ElmcValue **out, ElmcValue *flat, ElmcValue *entry) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        if (!entry) {
          *out = flat ? flat : elmc_cmd_none();
          flat = NULL;
        } else if (elmc_cmd_is_none(entry)) {
          elmc_release(entry);
          entry = NULL;
          *out = flat ? flat : elmc_cmd_none();
          flat = NULL;
        } else if (entry->tag == ELMC_TAG_LIST) {
          ElmcValue *cursor = entry;
          ElmcValue *current_flat = flat;
          flat = NULL;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            ElmcValue *head = node->head;
            node->head = NULL;
            rc = elmc_cmd_queue_push_entry(&current_flat, current_flat, head);
            CHECK_RC(rc);
            ElmcValue *next = node->tail;
            node->tail = NULL;
            ElmcValue *cursor_cell = cursor;
            cursor = next;
            elmc_release(cursor_cell);
          }
          /* List spine cells were released in the loop; do not release entry again. */
          entry = NULL;
          *out = current_flat;
        } else {
          rc = elmc_cmd_queue_push_back_take(out, flat, entry);
          flat = NULL;
          entry = NULL;
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(flat);
      elmc_release(entry);
      return rc;
    }

    static RC elmc_cmd_queue_normalize(ElmcValue **out, ElmcValue *cmd) {
      RC rc = RC_SUCCESS;
      ElmcValue *flat = NULL;
      ElmcValue *materialized = NULL;
      CATCH_BEGIN
        if (!cmd || elmc_cmd_is_none(cmd)) {
          elmc_release(cmd);
          cmd = NULL;
          *out = elmc_cmd_none();
        } else {
          materialized = cmd;
          cmd = NULL;
          if (!materialized || elmc_cmd_is_none(materialized)) {
            elmc_release(materialized);
            materialized = NULL;
            *out = elmc_cmd_none();
          } else if (materialized->tag != ELMC_TAG_LIST) {
            flat = elmc_cmd_none();
            rc = elmc_cmd_queue_push_back_take(&flat, flat, materialized);
            materialized = NULL;
            CHECK_RC(rc);
            *out = flat;
            flat = NULL;
          } else {
            flat = elmc_cmd_none();
            rc = elmc_cmd_queue_push_entry(&flat, flat, materialized);
            CHECK_RC(rc);
            materialized = NULL;
            *out = flat;
            flat = NULL;
          }
        }
      CATCH_END;
      elmc_release(cmd);
      elmc_release(materialized);
      elmc_release(flat);
      return rc;
    }

    #{sub_tag_slot_fn(analysis)}

    static void elmc_worker_clear_sub_tags(ElmcWorkerState *state) {
      if (!state) return;
      for (int i = 0; i < ELMC_WORKER_SUB_TAG_SLOTS; i++) state->sub_msg_tags[i] = 0;
      state->button_raw_sub_count = 0;
    }

    static int elmc_worker_mask_is_button_raw(int64_t mask) {
      return (mask & (1LL << 14)) != 0;
    }

    static void elmc_worker_apply_sub(ElmcWorkerState *state, ElmcValue *sub) {
      if (!state || !sub) return;

      if (sub->tag == ELMC_TAG_SUB && sub->payload != NULL) {
        ElmcSubPayload *payload = (ElmcSubPayload *)sub->payload;
        state->subscriptions |= payload->mask;
        if (elmc_worker_mask_is_button_raw(payload->mask) && payload->arity >= 3) {
          if (state->button_raw_sub_count < ELMC_WORKER_MAX_BUTTON_RAW_SUBS) {
            ElmcButtonRawSub *entry = &state->button_raw_subs[state->button_raw_sub_count++];
            entry->button_id = payload->p0;
            entry->event = payload->p1;
            entry->msg_tag = payload->p2;
          }
          return;
        }
        if (payload->arity > 0) {
          int slot = elmc_sub_tag_slot(payload->mask);
          if (slot >= 0 && slot < ELMC_WORKER_SUB_TAG_SLOTS) state->sub_msg_tags[slot] = payload->p0;
        }
        return;
      }

      if (sub->tag == ELMC_TAG_LIST && sub->payload != NULL) {
        ElmcValue *cursor = sub;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *cons = (ElmcCons *)cursor->payload;
          if (cons->head) elmc_worker_apply_sub(state, cons->head);
          cursor = cons->tail;
        }
      }
    }

    static int64_t compute_subscriptions(ElmcWorkerState *state) {
      if (!state || !state->model) return 0;
    #{subscriptions_call}
      elmc_worker_clear_sub_tags(state);
      state->subscriptions = 0;
      if (result) elmc_worker_apply_sub(state, result);
      elmc_release(result);
      return state->subscriptions;
    }

    elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag) {
      if (!state || flag == 0) return 0;
      int slot = elmc_sub_tag_slot(flag);
      if (slot < 0 || slot >= ELMC_WORKER_SUB_TAG_SLOTS) return 0;
      return state->sub_msg_tags[slot];
    }

    elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event) {
      if (!state) return 0;
      for (int i = 0; i < state->button_raw_sub_count; i++) {
        ElmcButtonRawSub *entry = &state->button_raw_subs[i];
        if (entry->button_id == button_id && entry->event == event) return entry->msg_tag;
      }
      return 0;
    }

    int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags) {
      if (!state) return -1;
      state->subscriptions = 0;
      elmc_worker_clear_sub_tags(state);
      elmc_worker_heap_log("init:start");
    #{init_missing_guard}#{init_call}
      ElmcValue *next_model = extract_model_take(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
      state->model = next_model;
      state->dispatch_needs_render = 1;
      {
        ElmcValue *pending = NULL;
        ElmcValue *raw_cmd = extract_cmd_take(result);
        RC pending_rc = elmc_cmd_queue_normalize(&pending, raw_cmd);
        if (pending_rc != RC_SUCCESS) {
          ELMC_WORKER_LOG_RC_FAIL("worker init pending cmd", pending_rc);
          elmc_release(result);
          return -2;
        }
        if (state->last_dispatch_cmd) {
          elmc_release(state->last_dispatch_cmd);
          state->last_dispatch_cmd = NULL;
        }
        state->last_dispatch_cmd =
            (pending && !elmc_cmd_is_none(pending)) ? elmc_retain(pending) : elmc_cmd_none();
        state->pending_cmd = pending;
      }
      elmc_release(result);
      state->subscriptions = compute_subscriptions(state);
      elmc_worker_heap_log("init:end");
      return 0;
    }

    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {
      if (!state || !state->model) return -1;
      state->dispatch_needs_render = 0;
      elmc_worker_heap_log("update:start");
      ElmcValue *prev_model = state->model;
    #{update_missing_guard}#{update_call}
      ElmcValue *next_model = extract_model_take(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
      if (next_model != prev_model) {
        elmc_release(state->model);
      } else if (next_model->rc > 1) {
        elmc_release(next_model);
      }
      state->model = next_model;
      state->dispatch_needs_render = 1;
      {
        ElmcValue *next_cmd = NULL;
        ElmcValue *raw_cmd = extract_cmd_take(result);
        RC next_rc = elmc_cmd_queue_normalize(&next_cmd, raw_cmd);
        if (next_rc != RC_SUCCESS) {
          ELMC_WORKER_LOG_RC_FAIL("worker update pending cmd", next_rc);
          elmc_release(result);
          return -2;
        }
        if (state->last_dispatch_cmd) {
          elmc_release(state->last_dispatch_cmd);
          state->last_dispatch_cmd = NULL;
        }
        state->last_dispatch_cmd =
            (next_cmd && !elmc_cmd_is_none(next_cmd)) ? elmc_retain(next_cmd) : elmc_cmd_none();
        if (!elmc_cmd_is_none(next_cmd)) {
          state->dispatch_needs_render = 1;
        }
        ElmcValue *merged = NULL;
        RC merge_rc = elmc_cmd_queue_concat_take(&merged, state->pending_cmd, next_cmd);
        if (merge_rc != RC_SUCCESS) {
          elmc_release(next_cmd);
          ELMC_WORKER_LOG_RC_FAIL("worker update cmd concat", merge_rc);
          elmc_release(result);
          return -2;
        }
        state->pending_cmd = merged;
      }
      elmc_release(result);
    #{dispatch_subscriptions_refresh}  elmc_worker_heap_log("update:end");
      return 0;
    }

    int elmc_worker_dispatch_needs_render(ElmcWorkerState *state) {
      if (!state) return 0;
      return state->dispatch_needs_render;
    }

    ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
      if (!state || !state->model) return NULL;
      return elmc_retain(state->model);
    }

    ElmcValue *elmc_worker_pending_cmds_borrow(ElmcWorkerState *state) {
      if (!state || !state->pending_cmd) return elmc_cmd_none();
      return elmc_retain(state->pending_cmd);
    }

    ElmcValue *elmc_worker_last_dispatch_cmd_borrow(ElmcWorkerState *state) {
      if (!state || !state->last_dispatch_cmd) return elmc_cmd_none();
      return elmc_retain(state->last_dispatch_cmd);
    }

    ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state) {
      if (!state) return NULL;
      if (!state->pending_cmd) {
        return elmc_cmd_none();
      }

      while (state->pending_cmd && state->pending_cmd->tag == ELMC_TAG_LIST) {
        if (state->pending_cmd->payload == NULL) {
          elmc_release(state->pending_cmd);
          state->pending_cmd = elmc_cmd_none();
          return elmc_cmd_none();
        }

        ElmcCons *node = (ElmcCons *)state->pending_cmd->payload;
        ElmcValue *head = node->head;
        ElmcValue *rest = node->tail;
        /* Transfer ownership: detach before release (list release walks the spine). */
        node->head = NULL;
        node->tail = NULL;
        elmc_release(state->pending_cmd);
        state->pending_cmd = rest ? rest : elmc_cmd_none();

        if (elmc_cmd_is_none(head)) {
          elmc_release(head);
          continue;
        }

        return head;
      }

      if (elmc_cmd_is_none(state->pending_cmd)) {
        ElmcValue *none = elmc_cmd_none();
        elmc_release(state->pending_cmd);
        state->pending_cmd = none;
        return none;
      }

      ElmcValue *cmd = state->pending_cmd;
      state->pending_cmd = elmc_cmd_none();
      return cmd;
    }

    int64_t elmc_worker_subscriptions(ElmcWorkerState *state) {
      if (!state) return 0;
      return state->subscriptions;
    }

    elmc_int_t elmc_worker_last_fail_code(void) {
      return (elmc_int_t)elmc_rc_fail_code();
    }

    elmc_int_t elmc_worker_last_fail_line(void) {
      return (elmc_int_t)elmc_last_fail_line;
    }

    void elmc_worker_deinit(ElmcWorkerState *state) {
      if (!state) return;
      if (state->model) {
        elmc_release(state->model);
        state->model = NULL;
      }
      if (state->pending_cmd) {
        elmc_release(state->pending_cmd);
        state->pending_cmd = NULL;
      }
      if (state->last_dispatch_cmd) {
        elmc_release(state->last_dispatch_cmd);
        state->last_dispatch_cmd = NULL;
      }
      state->subscriptions = 0;
    }
    """
  end
end
