defmodule Elmc.YesViewRcBalanceTest do
  @moduledoc """
  Regression: watchface_yes init/drain/view/deinit must RC-balance.

  Covers list_cursor_map retain fix (drawOuterScale boxed path) and direct-render
  filter+map loops that reuse an owned TickSpec slot (drawDial_commands_append).
  """

  use ExUnit.Case, async: false

  @moduletag :slow
  @moduletag :rc_track

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  test "watchface_yes first view is RC-balanced after init/drain" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc missing")

    out_dir = Path.join(System.tmp_dir!(), "yes-view-rc-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)
    assert {:ok, _} = TemplateCompile.compile_watch_template("watchface_yes", Keyword.put(@compile_opts, :out_dir, out_dir))

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated =~ ~r/owned\[\d+\] = list_map_cursor_head_\d+;/
    refute generated =~ ~r/owned\[\d+\] = elmc_retain\(list_map_cursor_head_\d+\);/
    # Maybe.withDefault must not drop Just-payload retain before the alias check
    # (frees model.sun → default 3/9 dial → double-free on next ProvideSun).
    refute generated =~
             ~r/elmc_release\(owned\[\d+\]\);\s*\n\s*if \(owned\[\d+\] == owned\[\d+\]\)/

    harness_path = Path.join(out_dir, "c/yes_view_rc_balance_harness.c")
    File.write!(harness_path, harness_c())
    RcTrackHarness.write_trig_stubs!(out_dir)

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        "yes_view_rc_balance",
        sources:
          RcTrackHarness.pebble_harness_sources(out_dir, harness_path, [
            Path.join(out_dir, "c/pebble_trig_host_stubs.c")
          ]),
        extra_flags: ["-include", Path.join(out_dir, "c/pebble_trig_host_stubs.h")],
        rc_track: true,
        alloc_track: false
      )

    assert out =~ "rc_ok yes view balance"
    refute out =~ "rc leak"
  end

  defp harness_c do
    """
    #include <stdio.h>
    #include <string.h>
    #include "elmc_pebble.h"

    static ElmcValue *hi(elmc_int_t v) {
      ElmcValue *o = NULL;
      if (elmc_new_int(&o, v) != RC_SUCCESS) return NULL;
      return o;
    }
    static ElmcValue *hs(const char *s) {
      ElmcValue *o = NULL;
      if (elmc_new_string(&o, s) != RC_SUCCESS) return NULL;
      return o;
    }
    static ElmcValue *current_datetime(void) {
      ElmcValue *fields[8] = {hi(2026),hi(7),hi(1),hi(3),hi(10),hi(30),hi(0),hi(0)};
      ElmcValue *rec = NULL;
      if (elmc_record_new_values(&rec, 8, fields) != RC_SUCCESS) return NULL;
      for (int i=0;i<8;i++) elmc_release(fields[i]);
      return rec;
    }
    static ElmcValue *launch_context(void) {
      ElmcValue *sw=hi(144), *sh=hi(168), *ss=hi(1), *sc=hi(2);
      ElmcValue *sv[] = {sw,sh,ss,sc};
      ElmcValue *screen=NULL;
      if (elmc_record_new_values(&screen,4,sv)!=RC_SUCCESS) return NULL;
      for(int i=0;i<4;i++) elmc_release(sv[i]);
      ElmcValue *reason=hi(2), *wm=hs(""), *wp=hs("emery");
      ElmcValue *hm=hi(0), *hc=hi(0), *hh=hi(1);
      ElmcValue *cv[] = {reason,wm,wp,screen,hm,hc,hh};
      ElmcValue *ctx=NULL;
      if (elmc_record_new_values(&ctx,7,cv)!=RC_SUCCESS) return NULL;
      for(int i=0;i<7;i++) if(i!=3) elmc_release(cv[i]);
      elmc_release(screen);
      return ctx;
    }
    static int drain(ElmcPebbleApp *app) {
      for (int round=0; round<8; round++) {
        int progressed=0;
        for (int j=0;j<32;j++) {
          ElmcPebbleCmd cmd={0};
          if (elmc_pebble_take_cmd(app,&cmd)!=0) return 10;
          if (cmd.kind==ELMC_PEBBLE_CMD_NONE) return 0;
          progressed=1;
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME
          if (cmd.kind==ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME) {
            ElmcValue *dt=current_datetime();
            if(!dt) return 11;
            if (elmc_pebble_dispatch_tag_payload(app, cmd.p0, dt)!=0) {
              elmc_release(dt);
              return 12;
            }
            elmc_release(dt);
            continue;
          }
    #endif
          /* Companion send / battery / etc. — consume without host reply. */
        }
        if(!progressed) break;
      }
      return 0;
    }
    int main(void) {
      elmc_rc_track_reset();
      ElmcPebbleApp app={0};
      ElmcValue *flags=launch_context();
      if(!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE)!=0) return 2;
      elmc_release(flags);
      int dr=drain(&app);
      if(dr) return dr;

      ElmcPebbleDrawCmd cmds[64]={0};
      int n = elmc_pebble_view_commands(&app, cmds, 64);
      if (n < 1) {
        fprintf(stderr, "view failed n=%d\\n", n);
        return 24;
      }

      elmc_pebble_deinit(&app);
      if (!elmc_rc_track_check_balanced()) {
        fprintf(stderr, "rc leak yes view balance\\n");
        elmc_rc_track_dump_live(stderr);
        return 5;
      }
      printf("rc_ok yes view balance\\n");
      return 0;
    }
    """
  end
end
