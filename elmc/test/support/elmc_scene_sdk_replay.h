#ifndef ELMC_SCENE_SDK_REPLAY_H
#define ELMC_SCENE_SDK_REPLAY_H

#include "elmc_pebble.h"
#include "pebble_sdk_spy.h"

typedef struct {
  int scene_cmds;
  int scene_text;
  int scene_fill_rect;
  int scene_fill_circle;
  int scene_circle;
  int scene_fill_radial;
  int scene_text_origin;
  int sdk_text;
  int sdk_fill_rect;
  int sdk_fill_circle;
  int sdk_circle;
} ElmcSceneSdkReplayStats;

int elmc_scene_replay_to_sdk(const ElmcPebbleApp *app, ElmcSceneSdkReplayStats *stats);

#endif
