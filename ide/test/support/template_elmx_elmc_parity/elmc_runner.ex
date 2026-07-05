defmodule Ide.Test.TemplateElmxElmcParity.ElmcRunner do
  @moduledoc false

  alias Ide.ProjectTemplates
  alias Ide.Test.TemplateElmxElmcParity.ElmcHostHarness
  alias Ide.Test.TemplateElmxElmcParity.ElmcRunner.PayloadCodegen
  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan
  alias Ide.WatchModels

  @trig_stubs_dir Path.expand(__DIR__)
  @trig_stubs_h Path.join(@trig_stubs_dir, "pebble_trig_host_stubs.h")
  @trig_stubs_c Path.join(@trig_stubs_dir, "pebble_trig_host_stubs.c")

  @compile_opts [
    direct_render_only: true,
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: true,
    strip_dead_code: true,
    prod: false
  ]

  @spec run!(ExecutionPlan.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def run!(plan, opts \\ []) do
    if is_nil(System.find_executable("cc")) do
      {:error, :cc_not_available}
    else
      do_run!(plan, opts)
    end
  end

  defp do_run!(plan, opts) do
    keep_out_dir? = Keyword.get(opts, :keep_out_dir, false)

    with {:ok, out_dir, tags} <- resolve_compile(plan, opts),
         {:ok, steps} <- run_harness!(plan, out_dir, tags) do
      if not keep_out_dir?, do: File.rm_rf!(out_dir)
      {:ok, steps}
    else
      err ->
        if not keep_out_dir? do
          case Keyword.get(opts, :prepared) do
            %{elmc: %{out_dir: out_dir}} -> File.rm_rf!(out_dir)
            _ -> :ok
          end
        end

        err
    end
  end

  @doc false
  @spec run_harness!(ExecutionPlan.t(), String.t(), map()) :: {:ok, [map()]} | {:error, term()}
  def run_harness!(plan, out_dir, tags) do
    with harness_path <- write_harness!(out_dir, plan, tags),
         {:ok, output} <-
           ElmcHostHarness.run_capture(
             out_dir,
             harness_path,
             "template_parity_harness",
             sources: harness_sources(out_dir, harness_path),
             extra_flags: ["-include", @trig_stubs_h, "-I", @trig_stubs_dir]
           ) do
      parse_output(output)
    end
  end

  defp resolve_compile(plan, opts) do
    case Keyword.get(opts, :prepared) do
      %{elmc: %{out_dir: out_dir, tags: tags}} ->
        {:ok, out_dir, tags}

      _ ->
        project_dir = Keyword.fetch!(opts, :project_dir)
        out_dir = Keyword.get(opts, :out_dir, default_out_dir(plan.template_key))
        File.rm_rf!(out_dir)

        compile_opts =
          @compile_opts
          |> Keyword.merge(entry_module: "Main")
          |> Keyword.merge(Keyword.take(opts, [:direct_render_only, :strip_dead_code]))

        header_path = Path.join(out_dir, "c/elmc_pebble.h")

        with :ok <- ElmcHostHarness.compile!(project_dir, out_dir, compile_opts),
             {:ok, tags} <- parse_msg_tags(header_path) do
          {:ok, out_dir, tags}
        end
    end
  end

  @spec parse_msg_tags(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_msg_tags(header_path) when is_binary(header_path) do
    source = File.read!(header_path)

    tags =
      ~r/ELMC_PEBBLE_MSG_([A-Z0-9_]+)\s*=\s*(\d+)/
      |> Regex.scan(source)
      |> Map.new(fn [_, name, _value] ->
        key = String.replace(name, "_", "")
        {key, "ELMC_PEBBLE_MSG_#{name}"}
      end)

    {:ok, tags}
  end

  defp write_harness!(out_dir, plan, tags) do
    harness_path = Path.join(out_dir, "c/template_parity_harness.c")
    File.write!(harness_path, harness_source(plan, tags))
    harness_path
  end

  defp harness_sources(out_dir, harness_path) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_worker.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      @trig_stubs_c,
      harness_path
    ]
  end

  defp harness_source(plan, tags) do
    profile = Map.get(WatchModels.profiles_map(), plan.watch_profile_id, %{})
    screen = Map.get(profile, "screen") || %{}
    width = Map.get(screen, "width") || 144
    height = Map.get(screen, "height") || 168
    shape = if Map.get(profile, "shape") == "round", do: 1, else: 0
    color_mode = if Map.get(profile, "color_mode") == "Color", do: 2, else: 1

    run_mode =
      if ProjectTemplates.target_type_for_template(plan.template_key) == "watchface" do
        "ELMC_PEBBLE_MODE_WATCHFACE"
      else
        "ELMC_PEBBLE_MODE_APP"
      end

    step_blocks =
      plan.steps
      |> Enum.map(fn step -> step_c(step, tags) end)
      |> Enum.join("\n\n")

    """
    #include <stdio.h>
    #include <string.h>
    #include "elmc_pebble.h"

    static ElmcValue *harness_int(elmc_int_t v) {
      ElmcValue *out = NULL;
      if (elmc_new_int(&out, v) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_bool(int v) {
      ElmcValue *out = NULL;
      if (elmc_new_bool(&out, v ? 1 : 0) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_string(const char *s) {
      ElmcValue *out = NULL;
      if (elmc_new_string(&out, s) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_tuple2_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      if (elmc_tuple2_take(&out, a, b) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_maybe_just(ElmcValue *v) {
      return harness_tuple2_take(harness_int(1), v);
    }

    static ElmcValue *harness_maybe_nothing(void) {
      return harness_int(0);
    }

    static ElmcValue *harness_result_ok(ElmcValue *v) {
      return harness_tuple2_take(harness_int(0), v);
    }

    static ElmcValue *harness_result_err(ElmcValue *v) {
      return harness_tuple2_take(harness_int(1), v);
    }

    static ElmcValue *harness_unit(void) {
      return harness_tuple2_take(harness_int(0), harness_int(0));
    }

    static ElmcValue *harness_int_list(const elmc_int_t *values, int count) {
      ElmcValue *list = elmc_list_nil();
      int i = count - 1;
      while (i >= 0) {
        ElmcValue *next = NULL;
        if (elmc_list_cons(&next, harness_int(values[i]), list) != RC_SUCCESS) {
          elmc_release(list);
          return NULL;
        }
        list = next;
        i -= 1;
      }
      return list;
    }

    static ElmcValue *make_record_1(ElmcValue *a) {
      ElmcValue *items[1] = {a};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 1, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_2(ElmcValue *a, ElmcValue *b) {
      ElmcValue *items[2] = {a, b};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 2, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_3(ElmcValue *a, ElmcValue *b, ElmcValue *c) {
      ElmcValue *items[3] = {a, b, c};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 3, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_4(ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d) {
      ElmcValue *items[4] = {a, b, c, d};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 4, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_5(ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e) {
      ElmcValue *items[5] = {a, b, c, d, e};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 5, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_6(ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e, ElmcValue *f) {
      ElmcValue *items[6] = {a, b, c, d, e, f};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 6, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_7(ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e, ElmcValue *f, ElmcValue *g) {
      ElmcValue *items[7] = {a, b, c, d, e, f, g};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 7, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *make_record_8(ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e, ElmcValue *f, ElmcValue *g, ElmcValue *h) {
      ElmcValue *items[8] = {a, b, c, d, e, f, g, h};
      ElmcValue *out = NULL;
      if (elmc_record_new_values(&out, 8, items) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *launch_context(void) {
      ElmcValue *screen_fields[4] = {
          harness_int(#{width}), harness_int(#{height}), harness_int(#{shape}), harness_int(#{color_mode})};
      ElmcValue *screen = make_record_4(screen_fields[0], screen_fields[1], screen_fields[2], screen_fields[3]);
      for (int i = 0; i < 4; i++) elmc_release(screen_fields[i]);

      ElmcValue *ctx_fields[7] = {
          harness_int(2),
          harness_string("LaunchUser"),
          harness_string(#{inspect(plan.watch_profile_id)}),
          screen,
          harness_bool(1),
          harness_bool(0),
          harness_bool(1)
      };
      ElmcValue *ctx = make_record_7(
          ctx_fields[0], ctx_fields[1], ctx_fields[2], ctx_fields[3],
          ctx_fields[4], ctx_fields[5], ctx_fields[6]);
      for (int i = 0; i < 7; i++) {
        if (i != 3) elmc_release(ctx_fields[i]);
      }
      elmc_release(screen);
      return ctx;
    }

    static void json_escape_write(FILE *out, const char *text) {
      if (!text) {
        fputs("null", out);
        return;
      }
      fputc('"', out);
      for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (*p == '\\\\' || *p == '"') fputc('\\\\', out);
        fputc(*p, out);
      }
      fputc('"', out);
    }

    static void emit_view_ops(FILE *out, ElmcPebbleApp *app) {
      ElmcPebbleDrawCmd cmds[128] = {0};
      int count = elmc_pebble_view_commands(app, cmds, 128);
      fputs("[", out);
      for (int i = 0; i < count; i++) {
        if (i > 0) fputs(",", out);
        fputs("{\\"kind\\":", out);
        fprintf(out, "%d", (int)cmds[i].kind);
        fputs(",\\"p0\\":", out);
        fprintf(out, "%d", (int)cmds[i].p0);
        fputs(",\\"p1\\":", out);
        fprintf(out, "%d", (int)cmds[i].p1);
        fputs(",\\"p2\\":", out);
        fprintf(out, "%d", (int)cmds[i].p2);
        fputs(",\\"p3\\":", out);
        fprintf(out, "%d", (int)cmds[i].p3);
        fputs(",\\"text\\":", out);
        if (cmds[i].kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
            cmds[i].text[0] == '\\0' && cmds[i].p3 == 0) {
          json_escape_write(out, "Waiting for companion app");
        } else {
          json_escape_write(out, cmds[i].text);
        }
        fputc('}', out);
      }
      fputs("]", out);
    }

    static void emit_commands_range(FILE *out, ElmcPebbleApp *app, int start, int end) {
      fputs("[", out);
      int emitted = 0;
      for (int i = start; i < end; i++) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_pending_cmd_at(app, i, &cmd) != 0) continue;
        if (emitted > 0) fputs(",", out);
        emitted += 1;
        fputs("{\\"kind\\":", out);
        fprintf(out, "%lld", (long long)cmd.kind);
        fputs(",\\"p0\\":", out);
        fprintf(out, "%lld", (long long)cmd.p0);
        fputc('}', out);
      }
      fputs("]", out);
    }

    static void emit_last_dispatch_commands(FILE *out, ElmcPebbleApp *app) {
      int count = elmc_pebble_last_dispatch_cmd_count(app);
      fputs("[", out);
      int emitted = 0;
      for (int i = 0; i < count; i++) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_last_dispatch_cmd_at(app, i, &cmd) != 0) continue;
        if (emitted > 0) fputs(",", out);
        emitted += 1;
        fputs("{\\"kind\\":", out);
        fprintf(out, "%lld", (long long)cmd.kind);
        fputs(",\\"p0\\":", out);
        fprintf(out, "%lld", (long long)cmd.p0);
        fputc('}', out);
      }
      fputs("]", out);
    }

    static void emit_step_with_last_dispatch(
        ElmcPebbleApp *app,
        const char *step_id,
        const char *op,
        const char *message,
        int ok,
        const char *error) {
      ElmcValue *model = elmc_worker_model(&app->worker);
      ElmcValue *model_text = model ? elmc_debug_to_string(model) : NULL;
      const char *model_cstr =
          (model_text && model_text->tag == ELMC_TAG_STRING && model_text->payload)
              ? (const char *)model_text->payload
              : "";

      printf("{\\"step_id\\":");
      json_escape_write(stdout, step_id);
      printf(",\\"op\\":");
      json_escape_write(stdout, op);
      printf(",\\"message\\":");
      json_escape_write(stdout, message);
      printf(",\\"backend\\":\\"elmc\\",\\"error\\":");
      json_escape_write(stdout, error);
      printf(",\\"model\\":");
      json_escape_write(stdout, model_cstr);
      printf(",\\"view_output\\":");
      emit_view_ops(stdout, app);
      printf(",\\"render_tree\\":{},\\"active_subscriptions\\":[");
      fprintf(stdout, "%lld", (long long)elmc_pebble_active_subscriptions(app));
      printf("],\\"commands\\":");
      emit_last_dispatch_commands(stdout, app);
      printf("}\\n");

      elmc_release(model_text);
      elmc_release(model);
      (void)ok;
    }

    static void emit_step(
        ElmcPebbleApp *app,
        const char *step_id,
        const char *op,
        const char *message,
        int ok,
        const char *error) {
      ElmcValue *model = elmc_worker_model(&app->worker);
      ElmcValue *model_text = model ? elmc_debug_to_string(model) : NULL;
      const char *model_cstr =
          (model_text && model_text->tag == ELMC_TAG_STRING && model_text->payload)
              ? (const char *)model_text->payload
              : "";

      printf("{\\"step_id\\":");
      json_escape_write(stdout, step_id);
      printf(",\\"op\\":");
      json_escape_write(stdout, op);
      printf(",\\"message\\":");
      json_escape_write(stdout, message);
      printf(",\\"backend\\":\\"elmc\\",\\"error\\":");
      json_escape_write(stdout, error);
      printf(",\\"model\\":");
      json_escape_write(stdout, model_cstr);
      printf(",\\"view_output\\":");
      emit_view_ops(stdout, app);
      printf(",\\"render_tree\\":{},\\"active_subscriptions\\":[");
      fprintf(stdout, "%lld", (long long)elmc_pebble_active_subscriptions(app));
      printf("],\\"commands\\":[]}\\n");

      elmc_release(model_text);
      elmc_release(model);
      (void)ok;
    }

    static void emit_step_all_pending(
        ElmcPebbleApp *app,
        const char *step_id,
        const char *op,
        const char *message,
        int ok,
        const char *error) {
      int count = elmc_pebble_pending_cmd_count(app);
      ElmcValue *model = elmc_worker_model(&app->worker);
      ElmcValue *model_text = model ? elmc_debug_to_string(model) : NULL;
      const char *model_cstr =
          (model_text && model_text->tag == ELMC_TAG_STRING && model_text->payload)
              ? (const char *)model_text->payload
              : "";

      printf("{\\"step_id\\":");
      json_escape_write(stdout, step_id);
      printf(",\\"op\\":");
      json_escape_write(stdout, op);
      printf(",\\"message\\":");
      json_escape_write(stdout, message);
      printf(",\\"backend\\":\\"elmc\\",\\"error\\":");
      json_escape_write(stdout, error);
      printf(",\\"model\\":");
      json_escape_write(stdout, model_cstr);
      printf(",\\"view_output\\":");
      emit_view_ops(stdout, app);
      printf(",\\"render_tree\\":{},\\"active_subscriptions\\":[");
      fprintf(stdout, "%lld", (long long)elmc_pebble_active_subscriptions(app));
      printf("],\\"commands\\":");
      emit_commands_range(stdout, app, 0, count);
      printf("}\\n");

      elmc_release(model_text);
      elmc_release(model);
      (void)ok;
    }

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, #{run_mode}) != 0) return 2;
      elmc_release(flags);

    #{step_blocks}

      elmc_pebble_deinit(&app);
      return 0;
    }
    """
  end

  defp step_c(%{op: :init, id: id}, _tags) do
    """
    emit_step_all_pending(&app, #{inspect(id)}, "init", "", 1, NULL);
    """
  end

  defp step_c(%{op: :view, id: id}, _tags) do
    """
    emit_step(&app, #{inspect(id)}, "view", "", 1, NULL);
    """
  end

  defp step_c(%{op: :subscriptions, id: id}, _tags) do
    """
    emit_step(&app, #{inspect(id)}, "subscriptions", "", 1, NULL);
    """
  end

  defp step_c(%{op: :update, id: id, message: message} = step, tags) do
    {dispatch, err} = PayloadCodegen.dispatch_expr(message, Map.get(step, :message_value), tags)

    if err do
      """
      emit_step(&app, #{inspect(id)}, "update", #{inspect(to_string(message || ""))}, 0, #{inspect(err)});
      """
    else
      """
      if (#{dispatch} != 0) {
        emit_step(&app, #{inspect(id)}, "update", #{inspect(to_string(message || ""))}, 0, "dispatch_failed");
      } else {
        emit_step_with_last_dispatch(&app, #{inspect(id)}, "update", #{inspect(to_string(message || ""))}, 1, NULL);
      }
      """
    end
  end

  defp parse_output(output) when is_binary(output) do
    steps =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.starts_with?(&1, "{"))
      |> Enum.map(&Jason.decode!/1)

    {:ok, steps}
  rescue
    error -> {:error, {:invalid_harness_json, error, output}}
  end

  defp default_out_dir(template_key) do
    Path.join(
      System.tmp_dir!(),
      "ide-template-parity-elmc-#{template_key}-#{System.unique_integer([:positive])}"
    )
  end
end
