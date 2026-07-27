const constants = {
  KEY_REQUEST_TAG: 10,
  KEY_REQUEST_VALUE: 11,
  KEY_RESPONSE_TAG: 12,
  KEY_RESPONSE_VALUE: 13,
  WATCH_TO_PHONE_TAG_REQUEST_WEATHER: 2,
  PHONE_TO_WATCH_TAG_PROVIDE_TEMPERATURE: 201,
  LOCATION_BERLIN: 1,
  LOCATION_ZURICH: 2,
  LOCATION_NEW_YORK: 3,
};

const LOCATION_NAME_BY_CODE = {
  1: "Berlin",
  2: "Zurich",
  3: "NewYork",
};

const LOCATION_QUERY_BY_CODE = {
  1: "latitude=52.52&longitude=13.41",
  2: "latitude=47.37&longitude=8.54",
  3: "latitude=40.71&longitude=-74.01",
};

function locationNameForCode(code) {
  return Object.prototype.hasOwnProperty.call(LOCATION_NAME_BY_CODE, code)
    ? LOCATION_NAME_BY_CODE[code]
    : null;
}

function decodeWatchToPhonePayload(payload) {
  if (!payload) {
    return null;
  }

  const tag = payload[constants.KEY_REQUEST_TAG];
  const value = payload[constants.KEY_REQUEST_VALUE];
  if (typeof tag !== "number" || typeof value !== "number") {
    return null;
  }

  switch (tag) {
    case constants.WATCH_TO_PHONE_TAG_REQUEST_WEATHER:
      return {
        kind: "RequestWeather",
        value: value,
        locationCode: value,
        locationName: locationNameForCode(value)
      };
    default:
      return null;
  }
}

function encodePhoneToWatchPayload(kind, value) {
  const payload = {};

  switch (kind) {
    case "ProvideTemperature":
      payload[constants.KEY_RESPONSE_TAG] = constants.PHONE_TO_WATCH_TAG_PROVIDE_TEMPERATURE;
      payload[constants.KEY_RESPONSE_VALUE] = value;
      return payload;
    default:
      return null;
  }
}

module.exports = Object.assign({}, constants, {
  LOCATION_NAME_BY_CODE: LOCATION_NAME_BY_CODE,
  LOCATION_QUERY_BY_CODE: LOCATION_QUERY_BY_CODE,
  locationNameForCode: locationNameForCode,
  decodeWatchToPhonePayload: decodeWatchToPhonePayload,
  encodePhoneToWatchPayload: encodePhoneToWatchPayload
});
