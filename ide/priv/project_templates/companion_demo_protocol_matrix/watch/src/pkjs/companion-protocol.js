var constants = {
  KEY_MESSAGE_TAG: 10,
  KEY_SEND_COLOR_FIELD1: 11,
  KEY_SEND_MEASURE_FIELD1_TAG: 12,
  KEY_SEND_MEASURE_FIELD1_VALUE: 13,
  KEY_SEND_POINT_FIELD1_X: 14,
  KEY_SEND_POINT_FIELD1_Y: 15,
  KEY_SEND_COUNTS_FIELD1_COUNT: 16,
  KEY_SEND_COUNTS_FIELD1_0: 17,
  KEY_SEND_COUNTS_FIELD1_1: 18,
  KEY_SEND_COUNTS_FIELD1_2: 19,
  KEY_SEND_COUNTS_FIELD1_3: 20,
  KEY_SEND_COUNTS_FIELD1_4: 21,
  KEY_SEND_COUNTS_FIELD1_5: 22,
  KEY_SEND_COUNTS_FIELD1_6: 23,
  KEY_SEND_COUNTS_FIELD1_7: 24,
  KEY_SEND_COUNTS_FIELD1_8: 25,
  KEY_SEND_COUNTS_FIELD1_9: 26,
  KEY_SEND_COUNTS_FIELD1_10: 27,
  KEY_SEND_COUNTS_FIELD1_11: 28,
  KEY_SEND_COUNTS_FIELD1_12: 29,
  KEY_SEND_COUNTS_FIELD1_13: 30,
  KEY_SEND_COUNTS_FIELD1_14: 31,
  KEY_SEND_COUNTS_FIELD1_15: 32,
  KEY_ECHO_COLOR_FIELD1: 33,
  KEY_ECHO_MEASURE_FIELD1_TAG: 34,
  KEY_ECHO_MEASURE_FIELD1_VALUE: 35,
  KEY_ECHO_POINT_FIELD1_X: 36,
  KEY_ECHO_POINT_FIELD1_Y: 37,
  KEY_ECHO_COUNTS_FIELD1_COUNT: 38,
  KEY_ECHO_COUNTS_FIELD1_0: 39,
  KEY_ECHO_COUNTS_FIELD1_1: 40,
  KEY_ECHO_COUNTS_FIELD1_2: 41,
  KEY_ECHO_COUNTS_FIELD1_3: 42,
  KEY_ECHO_COUNTS_FIELD1_4: 43,
  KEY_ECHO_COUNTS_FIELD1_5: 44,
  KEY_ECHO_COUNTS_FIELD1_6: 45,
  KEY_ECHO_COUNTS_FIELD1_7: 46,
  KEY_ECHO_COUNTS_FIELD1_8: 47,
  KEY_ECHO_COUNTS_FIELD1_9: 48,
  KEY_ECHO_COUNTS_FIELD1_10: 49,
  KEY_ECHO_COUNTS_FIELD1_11: 50,
  KEY_ECHO_COUNTS_FIELD1_12: 51,
  KEY_ECHO_COUNTS_FIELD1_13: 52,
  KEY_ECHO_COUNTS_FIELD1_14: 53,
  KEY_ECHO_COUNTS_FIELD1_15: 54,
  KEY_PUSH_BOOL_FIELD1: 55,
  KEY_PUSH_STRING_FIELD1: 56,
  KEY_PUSH_POINTS_FIELD1_COUNT: 57,
  KEY_PUSH_POINTS_FIELD1_0_X: 58,
  KEY_PUSH_POINTS_FIELD1_0_Y: 59,
  KEY_PUSH_POINTS_FIELD1_1_X: 60,
  KEY_PUSH_POINTS_FIELD1_1_Y: 61,
  KEY_PUSH_POINTS_FIELD1_2_X: 62,
  KEY_PUSH_POINTS_FIELD1_2_Y: 63,
  KEY_PUSH_POINTS_FIELD1_3_X: 64,
  KEY_PUSH_POINTS_FIELD1_3_Y: 65,
  KEY_PUSH_POINTS_FIELD1_4_X: 66,
  KEY_PUSH_POINTS_FIELD1_4_Y: 67,
  KEY_PUSH_POINTS_FIELD1_5_X: 68,
  KEY_PUSH_POINTS_FIELD1_5_Y: 69,
  KEY_PUSH_POINTS_FIELD1_6_X: 70,
  KEY_PUSH_POINTS_FIELD1_6_Y: 71,
  KEY_PUSH_POINTS_FIELD1_7_X: 72,
  KEY_PUSH_POINTS_FIELD1_7_Y: 73,
  KEY_PUSH_POINTS_FIELD1_8_X: 74,
  KEY_PUSH_POINTS_FIELD1_8_Y: 75,
  KEY_PUSH_POINTS_FIELD1_9_X: 76,
  KEY_PUSH_POINTS_FIELD1_9_Y: 77,
  KEY_PUSH_POINTS_FIELD1_10_X: 78,
  KEY_PUSH_POINTS_FIELD1_10_Y: 79,
  KEY_PUSH_POINTS_FIELD1_11_X: 80,
  KEY_PUSH_POINTS_FIELD1_11_Y: 81,
  KEY_PUSH_POINTS_FIELD1_12_X: 82,
  KEY_PUSH_POINTS_FIELD1_12_Y: 83,
  KEY_PUSH_POINTS_FIELD1_13_X: 84,
  KEY_PUSH_POINTS_FIELD1_13_Y: 85,
  KEY_PUSH_POINTS_FIELD1_14_X: 86,
  KEY_PUSH_POINTS_FIELD1_14_Y: 87,
  KEY_PUSH_POINTS_FIELD1_15_X: 88,
  KEY_PUSH_POINTS_FIELD1_15_Y: 89,
  KEY_PUSH_LABELS_FIELD1_COUNT: 90,
  KEY_PUSH_LABELS_FIELD1_KEY_0: 91,
  KEY_PUSH_LABELS_FIELD1_VAL_0: 92,
  KEY_PUSH_LABELS_FIELD1_KEY_1: 93,
  KEY_PUSH_LABELS_FIELD1_VAL_1: 94,
  KEY_PUSH_LABELS_FIELD1_KEY_2: 95,
  KEY_PUSH_LABELS_FIELD1_VAL_2: 96,
  KEY_PUSH_LABELS_FIELD1_KEY_3: 97,
  KEY_PUSH_LABELS_FIELD1_VAL_3: 98,
  KEY_PUSH_LABELS_FIELD1_KEY_4: 99,
  KEY_PUSH_LABELS_FIELD1_VAL_4: 100,
  KEY_PUSH_LABELS_FIELD1_KEY_5: 101,
  KEY_PUSH_LABELS_FIELD1_VAL_5: 102,
  KEY_PUSH_LABELS_FIELD1_KEY_6: 103,
  KEY_PUSH_LABELS_FIELD1_VAL_6: 104,
  KEY_PUSH_LABELS_FIELD1_KEY_7: 105,
  KEY_PUSH_LABELS_FIELD1_VAL_7: 106,
  KEY_PUSH_LABELS_FIELD1_KEY_8: 107,
  KEY_PUSH_LABELS_FIELD1_VAL_8: 108,
  KEY_PUSH_LABELS_FIELD1_KEY_9: 109,
  KEY_PUSH_LABELS_FIELD1_VAL_9: 110,
  KEY_PUSH_LABELS_FIELD1_KEY_10: 111,
  KEY_PUSH_LABELS_FIELD1_VAL_10: 112,
  KEY_PUSH_LABELS_FIELD1_KEY_11: 113,
  KEY_PUSH_LABELS_FIELD1_VAL_11: 114,
  KEY_PUSH_LABELS_FIELD1_KEY_12: 115,
  KEY_PUSH_LABELS_FIELD1_VAL_12: 116,
  KEY_PUSH_LABELS_FIELD1_KEY_13: 117,
  KEY_PUSH_LABELS_FIELD1_VAL_13: 118,
  KEY_PUSH_LABELS_FIELD1_KEY_14: 119,
  KEY_PUSH_LABELS_FIELD1_VAL_14: 120,
  KEY_PUSH_LABELS_FIELD1_KEY_15: 121,
  KEY_PUSH_LABELS_FIELD1_VAL_15: 122,
};

var COLOR_BY_CODE = {
  1: "Red",
  2: "Green",
  3: "Blue",
};

function colorNameForCode(code) {
  return Object.prototype.hasOwnProperty.call(COLOR_BY_CODE, code)
    ? COLOR_BY_CODE[code]
    : null;
}


var LIST_WIRE_OFFSET = 1;
var LIST_MAX_ELEMENTS = 16;

function elmPayloadWireInt(payload, key) {
  if (payload && typeof payload[key] === "number") {
    return payload[key];
  }

  var constantName = "KEY_" + key.toUpperCase();
  if (typeof constants[constantName] === "number") {
    var wireKey = String(constants[constantName]);
    if (payload && typeof payload[wireKey] === "number") {
      return payload[wireKey];
    }
  }

  return null;
}

function elmPayloadInt(payload, key) {
  var wire = elmPayloadWireInt(payload, key);
  return typeof wire === "number" ? wire - LIST_WIRE_OFFSET : null;
}

function elmPayloadListInt(payload, prefix) {
  var countWire = elmPayloadWireInt(payload, prefix + "_count");
  if (typeof countWire !== "number") {
    return [];
  }

  var count = countWire - LIST_WIRE_OFFSET;
  if (count < 0 || count > LIST_MAX_ELEMENTS) {
    return [];
  }

  var items = [];
  for (var i = 0; i < count; i++) {
    var wire = elmPayloadWireInt(payload, prefix + "_" + i);
    items.push(typeof wire === "number" ? wire - LIST_WIRE_OFFSET : 0);
  }

  return items;
}


function encodeListIntField(payload, prefix, list) {
  var items = Array.isArray(list) ? list : [];
  if (items.length > 16) {
    items = items.slice(0, 16);
  }
  payload[constants["KEY_" + prefix.toUpperCase() + "_COUNT"]] = items.length + 1;
  for (var i = 0; i < items.length; i++) {
    payload[constants["KEY_" + prefix.toUpperCase() + "_" + i]] = items[i] + 1;
  }
}

function decodeWatchToPhonePayload(payload) {
  if (!payload) {
    return null;
  }

  var tag = payload[String(constants.KEY_MESSAGE_TAG)];
  if (typeof tag !== "number") {
    return null;
  }

  switch (tag) {
    case 2:
      return {
        kind: "Ping"
      };

    case 3:
      return {
        kind: "SendColor",
    field1Code: payload[String(constants.KEY_SEND_COLOR_FIELD1)],
    colorName: colorNameForCode(payload[String(constants.KEY_SEND_COLOR_FIELD1)])
      };

    case 4:
      return {
        kind: "SendMeasure",
    field1: { tag: payload[String(constants.KEY_SEND_MEASURE_FIELD1_TAG)], value: payload[String(constants.KEY_SEND_MEASURE_FIELD1_VALUE)] }
      };

    case 5:
      return {
        kind: "SendPoint",
    field1: ({ x: (payload[String(constants.KEY_SEND_POINT_FIELD1_X)] || 0), y: (payload[String(constants.KEY_SEND_POINT_FIELD1_Y)] || 0) })
      };

    case 6:
      return {
        kind: "SendCounts",
    field1: (function () {
      var countWire = payload[String(constants.KEY_SEND_COUNTS_FIELD1_COUNT)];
      var count = typeof countWire === "number" ? Math.max(0, countWire - 1) : 0;
      if (count > 16) count = 16;
      var wire0 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_0)];
      var wire1 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_1)];
      var wire2 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_2)];
      var wire3 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_3)];
      var wire4 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_4)];
      var wire5 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_5)];
      var wire6 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_6)];
      var wire7 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_7)];
      var wire8 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_8)];
      var wire9 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_9)];
      var wire10 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_10)];
      var wire11 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_11)];
      var wire12 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_12)];
      var wire13 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_13)];
      var wire14 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_14)];
      var wire15 = payload[String(constants.KEY_SEND_COUNTS_FIELD1_15)];
      var out = [];
      for (var i = 0; i < count; i++) {
        var wire = [wire0, wire1, wire2, wire3, wire4, wire5, wire6, wire7, wire8, wire9, wire10, wire11, wire12, wire13, wire14, wire15][i];
        out.push(typeof wire === "number" ? wire - 1 : 0);
      }
      return out;
    })()
      };

    case 7:
      return {
        kind: "RequestPhoneExtras"
      };

    default:
      return null;
  }
}

function encodePhoneToWatchPayload(kind, value, fields) {
  var payload = {};

  switch (kind) {
    case "Pong":
      payload[String(constants.KEY_MESSAGE_TAG)] = 201;

      return payload;

    case "EchoColor":
      payload[String(constants.KEY_MESSAGE_TAG)] = 202;
      payload[String(constants.KEY_ECHO_COLOR_FIELD1)] = value;
      return payload;

    case "EchoMeasure":
      payload[String(constants.KEY_MESSAGE_TAG)] = 203;
      payload[String(constants.KEY_ECHO_MEASURE_FIELD1_TAG)] = value && value.tag;
      payload[String(constants.KEY_ECHO_MEASURE_FIELD1_VALUE)] = value && value.value;

      return payload;

    case "EchoPoint":
      payload[String(constants.KEY_MESSAGE_TAG)] = 204;
      payload[String(constants.KEY_ECHO_POINT_FIELD1_X)] = value && value.x;
      payload[String(constants.KEY_ECHO_POINT_FIELD1_Y)] = value && value.y;
      return payload;

    case "EchoCounts":
      payload[String(constants.KEY_MESSAGE_TAG)] = 205;
      encodeListIntField(payload, "echo_counts_field1", value);
      return payload;

    case "PushBool":
      payload[String(constants.KEY_MESSAGE_TAG)] = 206;
      payload[String(constants.KEY_PUSH_BOOL_FIELD1)] = (value ? 1 : 2);
      return payload;

    case "PushString":
      payload[String(constants.KEY_MESSAGE_TAG)] = 207;
      payload[String(constants.KEY_PUSH_STRING_FIELD1)] = value;
      return payload;

    case "PushPoints":
      payload[String(constants.KEY_MESSAGE_TAG)] = 208;
      (function () {
        var push_points_field1_items = Array.isArray(value) ? value.slice(0, 16) : [];
        payload[String(constants.KEY_PUSH_POINTS_FIELD1_COUNT)] = push_points_field1_items.length + 1;
        if (push_points_field1_items.length > 0) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_0_X)] = (push_points_field1_items[0] && push_points_field1_items[0].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_0_Y)] = (push_points_field1_items[0] && push_points_field1_items[0].y || 0) + 1;
        }

        if (push_points_field1_items.length > 1) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_1_X)] = (push_points_field1_items[1] && push_points_field1_items[1].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_1_Y)] = (push_points_field1_items[1] && push_points_field1_items[1].y || 0) + 1;
        }

        if (push_points_field1_items.length > 2) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_2_X)] = (push_points_field1_items[2] && push_points_field1_items[2].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_2_Y)] = (push_points_field1_items[2] && push_points_field1_items[2].y || 0) + 1;
        }

        if (push_points_field1_items.length > 3) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_3_X)] = (push_points_field1_items[3] && push_points_field1_items[3].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_3_Y)] = (push_points_field1_items[3] && push_points_field1_items[3].y || 0) + 1;
        }

        if (push_points_field1_items.length > 4) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_4_X)] = (push_points_field1_items[4] && push_points_field1_items[4].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_4_Y)] = (push_points_field1_items[4] && push_points_field1_items[4].y || 0) + 1;
        }

        if (push_points_field1_items.length > 5) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_5_X)] = (push_points_field1_items[5] && push_points_field1_items[5].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_5_Y)] = (push_points_field1_items[5] && push_points_field1_items[5].y || 0) + 1;
        }

        if (push_points_field1_items.length > 6) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_6_X)] = (push_points_field1_items[6] && push_points_field1_items[6].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_6_Y)] = (push_points_field1_items[6] && push_points_field1_items[6].y || 0) + 1;
        }

        if (push_points_field1_items.length > 7) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_7_X)] = (push_points_field1_items[7] && push_points_field1_items[7].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_7_Y)] = (push_points_field1_items[7] && push_points_field1_items[7].y || 0) + 1;
        }

        if (push_points_field1_items.length > 8) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_8_X)] = (push_points_field1_items[8] && push_points_field1_items[8].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_8_Y)] = (push_points_field1_items[8] && push_points_field1_items[8].y || 0) + 1;
        }

        if (push_points_field1_items.length > 9) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_9_X)] = (push_points_field1_items[9] && push_points_field1_items[9].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_9_Y)] = (push_points_field1_items[9] && push_points_field1_items[9].y || 0) + 1;
        }

        if (push_points_field1_items.length > 10) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_10_X)] = (push_points_field1_items[10] && push_points_field1_items[10].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_10_Y)] = (push_points_field1_items[10] && push_points_field1_items[10].y || 0) + 1;
        }

        if (push_points_field1_items.length > 11) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_11_X)] = (push_points_field1_items[11] && push_points_field1_items[11].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_11_Y)] = (push_points_field1_items[11] && push_points_field1_items[11].y || 0) + 1;
        }

        if (push_points_field1_items.length > 12) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_12_X)] = (push_points_field1_items[12] && push_points_field1_items[12].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_12_Y)] = (push_points_field1_items[12] && push_points_field1_items[12].y || 0) + 1;
        }

        if (push_points_field1_items.length > 13) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_13_X)] = (push_points_field1_items[13] && push_points_field1_items[13].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_13_Y)] = (push_points_field1_items[13] && push_points_field1_items[13].y || 0) + 1;
        }

        if (push_points_field1_items.length > 14) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_14_X)] = (push_points_field1_items[14] && push_points_field1_items[14].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_14_Y)] = (push_points_field1_items[14] && push_points_field1_items[14].y || 0) + 1;
        }

        if (push_points_field1_items.length > 15) {
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_15_X)] = (push_points_field1_items[15] && push_points_field1_items[15].x || 0) + 1;
          payload[String(constants.KEY_PUSH_POINTS_FIELD1_15_Y)] = (push_points_field1_items[15] && push_points_field1_items[15].y || 0) + 1;
        }

      })();

      return payload;

    case "PushLabels":
      payload[String(constants.KEY_MESSAGE_TAG)] = 209;
      (function () {
        var push_labels_field1_entries = Object.entries(value || {}).slice(0, 16);
        payload[String(constants.KEY_PUSH_LABELS_FIELD1_COUNT)] = push_labels_field1_entries.length + 1;
        if (push_labels_field1_entries.length > 0) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_0)] = push_labels_field1_entries[0][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_0)] = (push_labels_field1_entries[0][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 1) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_1)] = push_labels_field1_entries[1][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_1)] = (push_labels_field1_entries[1][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 2) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_2)] = push_labels_field1_entries[2][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_2)] = (push_labels_field1_entries[2][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 3) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_3)] = push_labels_field1_entries[3][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_3)] = (push_labels_field1_entries[3][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 4) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_4)] = push_labels_field1_entries[4][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_4)] = (push_labels_field1_entries[4][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 5) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_5)] = push_labels_field1_entries[5][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_5)] = (push_labels_field1_entries[5][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 6) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_6)] = push_labels_field1_entries[6][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_6)] = (push_labels_field1_entries[6][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 7) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_7)] = push_labels_field1_entries[7][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_7)] = (push_labels_field1_entries[7][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 8) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_8)] = push_labels_field1_entries[8][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_8)] = (push_labels_field1_entries[8][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 9) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_9)] = push_labels_field1_entries[9][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_9)] = (push_labels_field1_entries[9][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 10) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_10)] = push_labels_field1_entries[10][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_10)] = (push_labels_field1_entries[10][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 11) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_11)] = push_labels_field1_entries[11][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_11)] = (push_labels_field1_entries[11][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 12) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_12)] = push_labels_field1_entries[12][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_12)] = (push_labels_field1_entries[12][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 13) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_13)] = push_labels_field1_entries[13][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_13)] = (push_labels_field1_entries[13][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 14) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_14)] = push_labels_field1_entries[14][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_14)] = (push_labels_field1_entries[14][1] || 0) + 1;
        }

        if (push_labels_field1_entries.length > 15) {
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_KEY_15)] = push_labels_field1_entries[15][0];
          payload[String(constants.KEY_PUSH_LABELS_FIELD1_VAL_15)] = (push_labels_field1_entries[15][1] || 0) + 1;
        }

      })();

      return payload;

    default:
      return null;
  }
}

function wirePhoneToWatchFromElmPayload(payload) {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  var tag = typeof payload.message_tag === "number"
    ? payload.message_tag
    : payload[String(constants.KEY_MESSAGE_TAG)];
  if (typeof tag !== "number") {
    return null;
  }

  switch (tag) {
    case 201:
      return encodePhoneToWatchPayload("Pong");

    case 205:
      return encodePhoneToWatchPayload("EchoCounts", elmPayloadListInt(payload, "echo_counts_field1"));

    default:
      return null;
  }
}

var exported = constants;
exported.colorNameForCode = colorNameForCode;
exported.decodeWatchToPhonePayload = decodeWatchToPhonePayload;
exported.encodePhoneToWatchPayload = encodePhoneToWatchPayload;
exported.wirePhoneToWatchFromElmPayload = wirePhoneToWatchFromElmPayload;
module.exports = exported;
