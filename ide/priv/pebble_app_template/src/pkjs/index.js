var pendingIncoming = [];
var pendingPlatformIncoming = {};
var pendingUnhandledPlatformMessages = [];
var pendingGeolocationIncoming = [];
var incomingPort = null;
var platformIncomingPorts = {};
var geolocationIncomingPort = null;
var platformHandlers = {};
var pendingBridgeResponseIds = {};
var protocol = require("./companion-protocol.js");
var generatedConfigurationUrl = null;
var configurationStorageKey = "elm-pebble.configuration.response";
var appMessageKeyNamesById = {};
var appMessageKeyIdsByName = {};
var geolocationWatches = {};
var companionStorage = {};
var companionPreferences = {};
function companionGlobalRoot() {
    if (typeof globalThis !== "undefined") {
        return globalThis;
    }

    if (typeof self !== "undefined") {
        return self;
    }

    if (typeof window !== "undefined") {
        return window;
    }

    return this;
}

function defaultCompanionSimulatorSettings() {
    return {
        calendar_events: [],
        weather: {
            temperatureC: 21,
            condition: "clear",
            humidityPercent: 50,
            pressureHpa: 1013,
            windKph: 8
        }
    };
}

function peekPendingCompanionSimulatorSettings() {
    var root = companionGlobalRoot();
    var pending = root.__elmPebblePendingSimulatorSettings;

    if (pending && typeof pending === "object") {
        return pending;
    }

    if (typeof __elmPebblePendingSimulatorSettings !== "undefined") {
        return __elmPebblePendingSimulatorSettings;
    }

    return null;
}

function takePendingCompanionSimulatorSettings() {
    var root = companionGlobalRoot();
    var pending = root.__elmPebblePendingSimulatorSettings;

    if (pending && typeof pending === "object") {
        try {
            delete root.__elmPebblePendingSimulatorSettings;
        } catch (_error) {
            root.__elmPebblePendingSimulatorSettings = undefined;
        }

        return pending;
    }

    if (typeof __elmPebblePendingSimulatorSettings !== "undefined") {
        pending = __elmPebblePendingSimulatorSettings;
        try {
            delete __elmPebblePendingSimulatorSettings;
        } catch (_error) {
            __elmPebblePendingSimulatorSettings = undefined;
        }

        return pending;
    }

    return null;
}

var companionSimulatorSettings = (function () {
    var pending = peekPendingCompanionSimulatorSettings();
    if (pending) {
        var normalized = normalizeCompanionSimulatorSettings(pending);
        companionGlobalRoot().__elmPebbleCompanionSimulatorSettings = normalized;
        return normalized;
    }

    return defaultCompanionSimulatorSettings();
})();
var appMessageOutbox = [];
var appMessageSending = false;
var appMessageHeadRetries = 0;
var companionWatchAppReady = false;
var companionWatchReadyBootTimer = null;
var APP_MESSAGE_MAX_RETRIES = 24;
var APP_MESSAGE_BASE_DELAY_MS = 200;
var COMPANION_WATCH_READY_BOOT_TIMEOUT_MS = 12000;
var lifecycleReadyDelivered = false;
var companionSimulatorSettingsReady = false;

function markCompanionWatchAppReady(source) {
    if (companionWatchAppReady) {
        return;
    }

    companionWatchAppReady = true;
    appMessageHeadRetries = 0;

    if (companionWatchReadyBootTimer != null) {
        clearTimeout(companionWatchReadyBootTimer);
        companionWatchReadyBootTimer = null;
    }

    console.log("Elm companion watch app ready", source || "");
    drainAppMessageOutbox();
}

function scheduleCompanionWatchReadyBootTimeout() {
    if (companionWatchReadyBootTimer != null) {
        return;
    }

    companionWatchReadyBootTimer = setTimeout(function () {
        companionWatchReadyBootTimer = null;

        if (!companionWatchAppReady) {
            markCompanionWatchAppReady("boot_timeout");
        }
    }, COMPANION_WATCH_READY_BOOT_TIMEOUT_MS);
}

function markCompanionSimulatorSettingsReady() {
    companionSimulatorSettingsReady = true;
}

function companionSimulatorSettingsPending() {
    return !!peekPendingCompanionSimulatorSettings();
}

function hasExplicitCompanionSimulatorWeather(settings) {
    if (!settings || typeof settings !== "object") {
        return false;
    }

    if (settings.weather && typeof settings.weather === "object" && !Array.isArray(settings.weather)) {
        return true;
    }

    return settings.weather_temperatureC != null || settings.weather_condition != null;
}

function companionWeatherSignature(settings) {
    var weather = weatherFromSettingsObject(settings);
    if (!weather) {
        return null;
    }

    return String(weather.temperatureC) + ":" + String(weather.condition || "clear");
}

function weatherFromSettingsObject(settings) {
    if (!settings || typeof settings !== "object") {
        return null;
    }

    var weather = settings.weather;
    if (!weather || typeof weather !== "object" || Array.isArray(weather)) {
        if (settings.weather_temperatureC == null && settings.weather_condition == null) {
            return null;
        }

        weather = {
            temperatureC: settings.weather_temperatureC,
            condition: settings.weather_condition,
            humidityPercent: settings.weather_humidityPercent,
            pressureHpa: settings.weather_pressureHpa,
            windKph: settings.weather_windKph
        };
    }

    return {
        temperatureC: Number(weather.temperatureC != null ? weather.temperatureC : 0),
        condition: String(weather.condition || "clear"),
        humidityPercent: Number(weather.humidityPercent != null ? weather.humidityPercent : 0),
        pressureHpa: Number(weather.pressureHpa != null ? weather.pressureHpa : 0),
        windKph: Number(weather.windKph != null ? weather.windKph : 0)
    };
}

var lastDeliveredCompanionWeatherSignature = null;

function isCompanionWeatherAppMessage(payload) {
    if (!payload || typeof payload !== "object") {
        return false;
    }

    // Phone-to-watch wire tags start at 201 for every companion protocol; only
    // weather payloads use the provide_temperature / provide_condition field keys.
    var temperatureTag = appMessageValue(payload, "provide_temperature_field1_tag");
    var temperatureValue = appMessageValue(payload, "provide_temperature_field1_value");
    var conditionField = appMessageValue(payload, "provide_condition_field1");

    if (typeof temperatureTag === "number" && typeof temperatureValue === "number") {
        return true;
    }

    return typeof conditionField === "number";
}

function readStoredConfigurationResponse() {
    if (typeof localStorage === "undefined" || !localStorage) {
        return null;
    }

    try {
        var response = localStorage.getItem(configurationStorageKey);
        return typeof response === "string" ? response : null;
    } catch (_error) {
        return null;
    }
}

function writeStoredConfigurationResponse(response) {
    if (typeof localStorage === "undefined" || !localStorage || typeof response !== "string") {
        return;
    }

    try {
        localStorage.setItem(configurationStorageKey, response);
    } catch (_error) {
    }
}

function companionFlags() {
    return {
        configurationResponse: readStoredConfigurationResponse()
    };
}

Object.keys(protocol).forEach(function (key) {
    if (key.indexOf("KEY_") !== 0 || typeof protocol[key] !== "number") {
        return;
    }

    var name = key.substring(4).toLowerCase();
    appMessageKeyNamesById[protocol[key]] = name;
    appMessageKeyIdsByName[name] = protocol[key];
});

function appMessageValue(payload, name) {
    if (!payload) {
        return undefined;
    }

    var id = appMessageKeyIdsByName[name];
    if (Object.prototype.hasOwnProperty.call(payload, name)) {
        return payload[name];
    }
    if (Object.prototype.hasOwnProperty.call(payload, String(id))) {
        return payload[String(id)];
    }
    if (Object.prototype.hasOwnProperty.call(payload, id)) {
        return payload[id];
    }
    return undefined;
}

function normalizeIncomingAppMessage(payload) {
    if (!payload) {
        return payload;
    }

    var normalized = {};
    Object.keys(payload).forEach(function (key) {
        var name = appMessageKeyNamesById[key] || key;
        normalized[name] = payload[key];
    });

    Object.keys(appMessageKeyIdsByName).forEach(function (name) {
        var value = appMessageValue(payload, name);
        if (typeof value !== "undefined") {
            normalized[name] = value;
        }
    });

    return normalized;
}

function wireAppMessageKey(id) {
    return String(id);
}

function wirePayloadFromObject(payload) {
    if (!payload) {
        return {};
    }

    var wire = {};
    Object.keys(payload).forEach(function (key) {
        wire[wireAppMessageKey(key)] = payload[key];
    });
    return wire;
}

function normalizeOutgoingAppMessage(payload) {
    if (!payload) {
        return payload;
    }

    var normalized = {};
    Object.keys(payload).forEach(function (key) {
        var id = appMessageKeyIdsByName[key];
        if (typeof id === "number") {
            normalized[wireAppMessageKey(id)] = payload[key];
            return;
        }

        normalized[key] = payload[key];
    });

    return normalized;
}

function companionPhoneToWatchWirePayload(payload) {
    if (!payload || typeof payload !== "object") {
        return normalizeOutgoingAppMessage(payload || {});
    }

    var tag = typeof payload.message_tag === "number"
        ? payload.message_tag
        : payload[wireAppMessageKey(protocol.KEY_MESSAGE_TAG)];

    if (tag === 201 &&
        typeof payload.provide_temperature_field1_tag === "number" &&
        typeof payload.provide_temperature_field1_value === "number" &&
        typeof protocol.encodePhoneToWatchPayload === "function") {
        return wirePayloadFromObject(protocol.encodePhoneToWatchPayload("ProvideTemperature", {
            tag: payload.provide_temperature_field1_tag,
            value: payload.provide_temperature_field1_value
        }));
    }

    if (tag === 202 &&
        typeof payload.provide_condition_field1 === "number" &&
        typeof protocol.encodePhoneToWatchPayload === "function") {
        return wirePayloadFromObject(protocol.encodePhoneToWatchPayload(
            "ProvideCondition",
            payload.provide_condition_field1
        ));
    }

    if (typeof protocol.wirePhoneToWatchFromElmPayload === "function") {
        var encoded = protocol.wirePhoneToWatchFromElmPayload(payload);
        if (encoded) {
            return wirePayloadFromObject(encoded);
        }
    }

    return normalizeOutgoingAppMessage(payload);
}

function sendQueuedAppMessage(payload) {
    if (!companionSimulatorSettingsReady && isCompanionWeatherAppMessage(payload)) {
        console.log("Elm companion weather AppMessage deferred until simulator settings ready");
        return;
    }

    appMessageOutbox.push(companionPhoneToWatchWirePayload(payload || {}));

    if (!companionWatchAppReady) {
        return;
    }

    drainAppMessageOutbox();
}

function cloneAppMessagePayload(payload) {
    try {
        return JSON.parse(JSON.stringify(payload || {}));
    } catch (_error) {
        return payload || {};
    }
}

function installAppMessageSafeSend() {
    if (typeof Pebble === "undefined" || typeof Pebble.sendAppMessage !== "function") {
        return false;
    }

    if (Pebble.sendAppMessage.__elmSafeSend) {
        return true;
    }

    var original = Pebble.sendAppMessage;
    Pebble.sendAppMessage = function (message, success, failure) {
        return sendPebbleWireAppMessage(message, success, failure, original);
    };
    Pebble.sendAppMessage.__elmSafeSend = true;
    Pebble.sendAppMessage.__elmSafeOriginal = original;
    return true;
}

function pebbleSendAppMessageOriginal() {
    if (typeof Pebble === "undefined" || typeof Pebble.sendAppMessage !== "function") {
        return null;
    }

    installAppMessageSafeSend();
    return Pebble.sendAppMessage.__elmSafeOriginal || Pebble.sendAppMessage;
}

function sendImmediateAppMessage(payload, delayMs, attempt) {
    attempt = typeof attempt === "number" ? attempt : 0;
    var original = pebbleSendAppMessageOriginal();
    if (!original) {
        return false;
    }

    setTimeout(function () {
        var wire = companionPhoneToWatchWirePayload(payload || {});
        sendPebbleWireAppMessage(
            wire,
            function () {},
            function (error) {
                console.log("companion weather AppMessage failed", JSON.stringify(error || {}));
                if (attempt < 4) {
                    sendImmediateAppMessage(payload, 400 * (attempt + 1), attempt + 1);
                }
            },
            original
        );
    }, typeof delayMs === "number" ? delayMs : 0);
    return true;
}

function sendPebbleWireAppMessage(wire, success, failure, fallback) {
    var payload = cloneAppMessagePayload(wire);
    var send = typeof fallback === "function" ? fallback : Pebble.sendAppMessage;
    send.call(Pebble, payload, success, failure);
    return true;
}

function drainAppMessageOutbox() {
    if (!companionWatchAppReady || appMessageSending || appMessageOutbox.length === 0) {
        return;
    }

    var payload = appMessageOutbox[0];
    appMessageSending = true;

    sendPebbleWireAppMessage(
        payload,
        function () {
            appMessageOutbox.shift();
            appMessageSending = false;
            appMessageHeadRetries = 0;
            setTimeout(drainAppMessageOutbox, 250);
        },
        function (error) {
            var errorText = error == null ? "null" : JSON.stringify(error);
            console.log("Elm companion sendAppMessage failed", errorText);
            appMessageSending = false;
            appMessageHeadRetries += 1;

            if (appMessageHeadRetries >= APP_MESSAGE_MAX_RETRIES) {
                console.log(
                    "Elm companion sendAppMessage giving up after retries",
                    String(appMessageHeadRetries),
                    JSON.stringify(payload || {})
                );
                appMessageOutbox.shift();
                appMessageHeadRetries = 0;
                setTimeout(drainAppMessageOutbox, 250);
                return;
            }

            var delay = Math.min(
                APP_MESSAGE_BASE_DELAY_MS * appMessageHeadRetries,
                4000
            );
            setTimeout(drainAppMessageOutbox, delay);
        }
    );
}

function isPlatformEnvelope(payload) {
    if (!payload || typeof payload !== "object") {
        return false;
    }

    if (typeof payload.event === "string") {
        return true;
    }

    return typeof payload.id === "string" && typeof payload.ok === "boolean";
}
var PLATFORM_INCOMING_PORT_NAMES = {
    battery: "batteryPlatformIncoming",
    locale: "localePlatformIncoming",
    connectivity: "connectivityPlatformIncoming",
    notifications: "notificationsPlatformIncoming",
    weather: "weatherPlatformIncoming",
    "weather-current": "weatherCurrentPlatformIncoming",
    "weather-forecast": "weatherForecastPlatformIncoming",
    calendar: "calendarPlatformIncoming",
    "calendar-upcoming": "calendarUpcomingPlatformIncoming",
    "calendar-next": "calendarNextPlatformIncoming",
    environment: "environmentPlatformIncoming",
    storage: "storagePlatformIncoming",
    preferences: "preferencesPlatformIncoming",
    configuration: "configurationPlatformIncoming",
    webSocket: "webSocketPlatformIncoming",
    "webSocket-commands": "webSocketCommandsPlatformIncoming",
    lifecycle: "lifecyclePlatformIncoming",
    "timeline-token": "timelineTokenPlatformIncoming",
    "timeline-commands": "timelineCommandsPlatformIncoming"
};

function queuePlatformIncoming(handlerId, payload) {
    if (!pendingPlatformIncoming[handlerId]) {
        pendingPlatformIncoming[handlerId] = [];
    }

    pendingPlatformIncoming[handlerId].push(payload);
}

function deliverPlatformIncomingToHandler(handlerId, payload) {
    var port = platformIncomingPorts[handlerId];

    if (port) {
        port.send(payload);
        return;
    }

    queuePlatformIncoming(handlerId, payload);
}

function platformHandlerIdsForPayload(payload) {
    var handlerIds = matchingPlatformHandlers(payload);

    if (handlerIds.length > 0) {
        return handlerIds;
    }

    if (typeof payload.id === "string" && typeof payload.ok === "boolean") {
        if (pendingBridgeResponseIds[payload.id]) {
            return Object.keys(platformHandlers).filter(function (handlerId) {
                return matchesHandlerInterest(platformHandlers[handlerId], payload);
            });
        }
    }

    return [];
}

function matchesHandlerInterest(interest, payload) {
    if (!interest) {
        return false;
    }

    if (typeof payload.event === "string") {
        if (!interest.eventPrefixes.length) {
            return false;
        }

        return interest.eventPrefixes.some(function (prefix) {
            return payload.event.indexOf(prefix) === 0;
        });
    }

    if (typeof payload.id === "string" && typeof payload.ok === "boolean") {
        if (!interest.resultIdPrefixes.length) {
            return false;
        }

        return interest.resultIdPrefixes.some(function (prefix) {
            return payload.id.indexOf(prefix) === 0;
        });
    }

    return false;
}

function matchingPlatformHandlers(payload) {
    return Object.keys(platformHandlers).filter(function (handlerId) {
        return matchesHandlerInterest(platformHandlers[handlerId], payload);
    });
}

function matchesPlatformInterest(payload) {
    if (typeof payload.id === "string" && typeof payload.ok === "boolean") {
        if (pendingBridgeResponseIds[payload.id]) {
            return true;
        }
    }

    return matchingPlatformHandlers(payload).length > 0;
}

function deliverPlatformIncoming(payload) {
    console.log("platform bridge -> Elm companion", JSON.stringify(payload));

    var handlerIds = platformHandlerIdsForPayload(payload);

    if (handlerIds.length === 0) {
        pendingUnhandledPlatformMessages.push(payload);
        return;
    }

    handlerIds.forEach(function (handlerId) {
        deliverPlatformIncomingToHandler(handlerId, payload);
    });
}

function flushUnhandledPlatformIncoming() {
    if (!pendingUnhandledPlatformMessages.length) {
        return;
    }

    var pending = pendingUnhandledPlatformMessages;
    pendingUnhandledPlatformMessages = [];

    pending.forEach(function (payload) {
        deliverPlatformIncoming(payload);
    });
}

function flushPendingPlatformIncomingPorts() {
    Object.keys(platformIncomingPorts).forEach(function (handlerId) {
        var pending = pendingPlatformIncoming[handlerId] || [];

        while (pending.length > 0) {
            platformIncomingPorts[handlerId].send(pending.shift());
        }
    });
}

var DEFAULT_PLATFORM_HANDLER_INTERESTS = {
    "weather-current": {
        eventPrefixes: [],
        resultIdPrefixes: ["weather-current"]
    },
    "weather-forecast": {
        eventPrefixes: [],
        resultIdPrefixes: ["weather-forecast"]
    }
};

function registerDefaultPlatformHandler(handlerId) {
    var interest = DEFAULT_PLATFORM_HANDLER_INTERESTS[handlerId];

    if (!interest || platformHandlers[handlerId]) {
        return;
    }

    platformHandlers[handlerId] = {
        eventPrefixes: interest.eventPrefixes,
        resultIdPrefixes: interest.resultIdPrefixes
    };
}

function wireCompanionIncomingPorts(app) {
    if (app.ports && app.ports.incoming) {
        incomingPort = app.ports.incoming;
        while (pendingIncoming.length > 0) {
            incomingPort.send(pendingIncoming.shift());
        }
    }

    if (app.ports && app.ports.geolocationIncoming) {
        geolocationIncomingPort = app.ports.geolocationIncoming;
        while (pendingGeolocationIncoming.length > 0) {
            geolocationIncomingPort.send(pendingGeolocationIncoming.shift());
        }
    }

    Object.keys(PLATFORM_INCOMING_PORT_NAMES).forEach(function (handlerId) {
        var portName = PLATFORM_INCOMING_PORT_NAMES[handlerId];

        if (app.ports && app.ports[portName]) {
            platformIncomingPorts[handlerId] = app.ports[portName];
            registerDefaultPlatformHandler(handlerId);
        }
    });
}

function deliverLifecycleReadyOnce() {
    if (lifecycleReadyDelivered) {
        return;
    }

    lifecycleReadyDelivered = true;
    deliverLifecycleEvent("lifecycle.ready", {});
}

function applyPendingCompanionSimulatorSettings() {
    var pending = takePendingCompanionSimulatorSettings();

    if (!pending) {
        return false;
    }

    companionApplySimulatorSettings(pending);
    return true;
}

function finishCompanionBoot() {
    flushPendingPlatformIncomingPorts();
    flushUnhandledPlatformIncoming();
    applyPendingCompanionSimulatorSettings();
    deliverLifecycleReadyOnce();
    scheduleCompanionWatchReadyBootTimeout();
}

function deliverIncoming(payload) {
    if (isPlatformEnvelope(payload)) {
        deliverPlatformIncoming(payload);
        return;
    }

    markCompanionWatchAppReady("watch_inbound");
    console.log("watch -> Elm companion", JSON.stringify(payload));
    if (incomingPort) {
        incomingPort.send(payload);
    } else {
        console.log("watch queued incoming for Elm companion");
        pendingIncoming.push(payload);
    }
}

function deliverGeolocationIncoming(payload) {
    console.log("geolocation bridge -> Elm companion", JSON.stringify(payload));
    if (geolocationIncomingPort) {
        geolocationIncomingPort.send(payload);
    } else {
        pendingGeolocationIncoming.push(payload);
    }
}

function openConfigurationUrl(url) {
    if (url && typeof Pebble.openURL === "function") {
        console.log("opening companion configuration", url);
        Pebble.openURL(url);
    }
}

function geolocationAvailable() {
    return typeof navigator !== "undefined" && navigator.geolocation;
}

function deliverGeolocationPosition(position) {
    var coords = position && position.coords ? position.coords : {};
    var payload = {
        event: "geolocation.position",
        payload: {
            latitude: Number(coords.latitude),
            longitude: Number(coords.longitude),
            accuracy: Number(coords.accuracy || 0)
        }
    };
    deliverGeolocationIncoming(payload);
}

function deliverGeolocationError(error) {
    var payload = {
        event: "geolocation.error",
        payload: {
            message: error && error.message ? String(error.message) : "Geolocation unavailable"
        }
    };
    deliverGeolocationIncoming(payload);
}


function deliverLifecycleEvent(event, payload) {
    deliverPlatformIncoming({
        event: event,
        payload: payload || {}
    });
}

function deliverBridgeError(api, message) {
    deliverPlatformIncoming({
        event: api + ".error",
        payload: {
            message: message,
            type: "unsupported",
            retryable: false
        }
    });
}

function deliverBridgeResult(id, ok, payload, error) {
    var envelope = {
        id: id || "bridge-result",
        ok: !!ok
    };

    if (payload) {
        envelope.payload = payload;
    }
    if (error) {
        envelope.error = error;
    }

    deliverPlatformIncoming(envelope);

    if (id && pendingBridgeResponseIds[id]) {
        delete pendingBridgeResponseIds[id];
    }
}

function localePayload() {
    var locale = "en-US";

    if (typeof navigator !== "undefined" && typeof navigator.language === "string" && navigator.language !== "") {
        locale = navigator.language;
    }

    var parts = locale.split(/[-_]/);
    var language = parts[0] || "en";
    var region = parts[1] || "";
    var uses24h = false;

    try {
        uses24h = !new Intl.DateTimeFormat(locale, { hour: "numeric" }).format(new Date(2020, 0, 1, 13)).match(/AM|PM/i);
    } catch (_error) {
        uses24h = false;
    }

    return {
        locale: locale,
        language: language,
        region: region,
        uses24h: uses24h
    };
}

function deliverLocaleStatus(request) {
    var requestId = request && request.id;
    var payload = localePayload();

    if (requestId) {
        deliverBridgeResult(requestId, true, payload);
    } else {
        deliverPlatformIncoming({
            event: "locale.status",
            payload: payload
        });
    }
}

function deliverNetworkStatus(request) {
    var requestId = request && request.id;
    var payload = {
        online: typeof navigator === "undefined" || typeof navigator.onLine !== "boolean" ? true : navigator.onLine
    };

    if (requestId) {
        deliverBridgeResult(requestId, true, payload);
    } else {
        deliverPlatformIncoming({
            event: "network.status",
            payload: payload
        });
    }
}

function deliverBatteryStatus(request) {
    var requestId = request && request.id;

    function deliverPayload(payload) {
        if (requestId) {
            deliverBridgeResult(requestId, true, payload);
        } else {
            deliverPlatformIncoming({
                event: "battery.status",
                payload: payload
            });
        }
    }

    if (typeof navigator !== "undefined" && typeof navigator.getBattery === "function") {
        navigator.getBattery().then(function (battery) {
            deliverPayload({
                percent: Math.round(Number(battery.level || 0) * 100),
                charging: !!battery.charging
            });
        }, function (error) {
            if (requestId) {
                deliverBridgeResult(requestId, false, null, {
                    type: "unsupported",
                    message: error && error.message ? String(error.message) : "Battery information unavailable",
                    retryable: false
                });
            } else {
                deliverBridgeError("battery", error && error.message ? String(error.message) : "Battery information unavailable");
            }
        });
        return;
    }

    if (requestId) {
        deliverBridgeResult(requestId, false, null, {
            type: "unsupported",
            message: "Battery information unavailable",
            retryable: false
        });
    } else {
        deliverBridgeError("battery", "Battery information unavailable");
    }
}

function encodeStorageValue(value) {
    if (typeof value === "string") {
        return { kind: "string", value: value };
    }
    if (typeof value === "number") {
        return { kind: "int", value: Math.round(value) };
    }
    if (typeof value === "boolean") {
        return { kind: "bool", value: value };
    }
    return { kind: "json", value: value };
}

function storagePayloadValue(payload) {
    if (!payload || !payload.value) {
        return null;
    }

    return payload.value;
}

function handleStorageCommand(payload) {
    var body = payload.payload || {};
    var key = typeof body.key === "string" ? body.key : "";

    if (payload.op === "set") {
        companionStorage[key] = storagePayloadValue(body);
        deliverBridgeResult(payload.id, true, { key: key });
        return;
    }

    if (payload.op === "get") {
        if (Object.prototype.hasOwnProperty.call(companionStorage, key)) {
            deliverBridgeResult(payload.id, true, companionStorage[key]);
        } else {
            deliverBridgeResult(payload.id, false, null, {
                type: "not_found",
                message: "Storage key not found",
                retryable: false
            });
        }
        return;
    }

    if (payload.op === "remove") {
        delete companionStorage[key];
        deliverBridgeResult(payload.id, true, { key: key });
        return;
    }

    if (payload.op === "clear") {
        companionStorage = {};
        deliverBridgeResult(payload.id, true, {});
    }
}

function handlePreferencesCommand(payload) {
    var body = payload.payload || {};
    var key = typeof body.key === "string" ? body.key : "";

    if (payload.op === "set") {
        companionPreferences[key] = body.value;
        deliverPlatformIncoming({
            event: "preferences.saved",
            payload: { key: key }
        });
        return;
    }

    if (payload.op === "get") {
        var value = Object.prototype.hasOwnProperty.call(companionPreferences, key) ? companionPreferences[key] : null;
        var responsePayload = {
            key: key,
            value: value
        };

        if (payload.id) {
            deliverBridgeResult(payload.id, true, responsePayload);
        } else {
            deliverPlatformIncoming({
                event: "preferences.value",
                payload: responsePayload
            });
        }
        return;
    }

    if (payload.op === "subscribe") {
        Object.keys(companionPreferences).forEach(function (storedKey) {
            deliverPlatformIncoming({
                event: "preferences.value",
                payload: {
                    key: storedKey,
                    value: companionPreferences[storedKey]
                }
            });
        });
    }
}

function bridgeCommandError(request, api, message) {
    if (request && request.id) {
        deliverBridgeResult(request.id, false, null, {
            type: "unsupported",
            message: message,
            retryable: false
        });
    } else {
        deliverBridgeError(api, message);
    }
}

function syncCompanionSimulatorSettingsFromGlobal() {
    var root = companionGlobalRoot();
    var settings = root.__elmPebbleCompanionSimulatorSettings;

    if (!settings || typeof settings !== "object") {
        return false;
    }

    companionSimulatorSettings = normalizeCompanionSimulatorSettings(settings);
    return true;
}

function currentCompanionSimulatorSettings() {
    var root = companionGlobalRoot();
    var settings = root.__elmPebbleCompanionSimulatorSettings;

    if (settings && typeof settings === "object") {
        return normalizeCompanionSimulatorSettings(settings);
    }

    return companionSimulatorSettings;
}

function handleEnvironmentCommand(request) {
    bridgeCommandError(request, "environment", "Environment data unavailable without platform location and tide support");
}

function weatherFromSettings() {
    return weatherFromSettingsObject(currentCompanionSimulatorSettings());
}

function normalizeCompanionSimulatorSettings(settings) {
    if (!settings || typeof settings !== "object") {
        return companionSimulatorSettings;
    }

    var normalized = {};
    Object.keys(settings).forEach(function (key) {
        normalized[key] = settings[key];
    });

    var weather = settings.weather;
    if (!weather || typeof weather !== "object" || Array.isArray(weather)) {
        if (settings.weather_temperatureC != null || settings.weather_condition != null) {
            weather = {
                temperatureC: settings.weather_temperatureC,
                condition: settings.weather_condition,
                humidityPercent: settings.weather_humidityPercent,
                pressureHpa: settings.weather_pressureHpa,
                windKph: settings.weather_windKph
            };
        }
    }

    if (weather && typeof weather === "object" && !Array.isArray(weather)) {
        normalized.weather = {
            temperatureC: Number(weather.temperatureC != null ? weather.temperatureC : 21),
            condition: String(weather.condition || "clear"),
            humidityPercent: Number(weather.humidityPercent != null ? weather.humidityPercent : 50),
            pressureHpa: Number(weather.pressureHpa != null ? weather.pressureHpa : 1013),
            windKph: Number(weather.windKph != null ? weather.windKph : 8)
        };
    }

    if (!Array.isArray(normalized.calendar_events)) {
        normalized.calendar_events = [];
    }

    return normalized;
}

var WEATHER_CONDITION_WIRE_CODES = {
    clear: 1,
    cloudy: 2,
    fog: 3,
    drizzle: 4,
    rain: 5,
    snow: 6,
    showers: 7,
    storm: 8,
    unknownweather: 9
};

function weatherConditionWireCode(condition) {
    var normalized = String(condition || "clear").toLowerCase().replace(/[^a-z0-9]+/g, "");
    return WEATHER_CONDITION_WIRE_CODES[normalized] || WEATHER_CONDITION_WIRE_CODES.clear;
}

function deliverWeatherToWatch() {
    var info = weatherFromSettings();
    if (!info) {
        return false;
    }

    sendImmediateAppMessage({
        message_tag: 201,
        provide_temperature_field1_tag: 1,
        provide_temperature_field1_value: info.temperatureC
    }, 0);
    sendImmediateAppMessage({
        message_tag: 202,
        provide_condition_field1: weatherConditionWireCode(info.condition)
    }, 350);
    return true;
}

function conditionToWeatherCode(condition) {
    var normalized = String(condition || "clear").toLowerCase();
    // Open-Meteo WMO weather_code values for simulated Open-Meteo HTTP JSON.
    var codes = {
        clear: 0,
        cloudy: 2,
        fog: 45,
        drizzle: 51,
        rain: 61,
        snow: 71,
        showers: 80,
        storm: 95
    };

    return Object.prototype.hasOwnProperty.call(codes, normalized) ? codes[normalized] : 0;
}

function openMeteoJsonFromSettings() {
    var weather = weatherFromSettings();
    if (!weather) {
        return null;
    }

    return JSON.stringify({
        current: {
            temperature_2m: weather.temperatureC,
            weather_code: conditionToWeatherCode(weather.condition)
        }
    });
}

function shouldUseSimulatorWeather() {
    return (
        hasExplicitCompanionSimulatorWeather(currentCompanionSimulatorSettings()) ||
        hasExplicitCompanionSimulatorWeather(peekPendingCompanionSimulatorSettings())
    );
}

function wmoCodeToCondition(code) {
    if (code === 0) {
        return "clear";
    }

    if (code <= 3) {
        return "cloudy";
    }

    if (code <= 48) {
        return "fog";
    }

    if (code <= 57) {
        return "drizzle";
    }

    if (code <= 67) {
        return "rain";
    }

    if (code <= 77) {
        return "snow";
    }

    if (code <= 86) {
        return "showers";
    }

    if (code <= 99) {
        return "storm";
    }

    return "unknownweather";
}

function weatherInfoFromOpenMeteoBody(bodyText) {
    var parsed;

    try {
        parsed = JSON.parse(bodyText);
    } catch (_parseError) {
        return null;
    }

    if (!parsed || !parsed.current) {
        return null;
    }

    var current = parsed.current;
    var temperature = current.temperature_2m;

    if (typeof temperature !== "number" || !isFinite(temperature)) {
        return null;
    }

    return {
        temperatureC: Math.round(temperature),
        condition: wmoCodeToCondition(Number(current.weather_code || 0)),
        humidityPercent:
            typeof current.relative_humidity_2m === "number"
                ? Math.round(current.relative_humidity_2m)
                : undefined,
        pressureHpa:
            typeof current.surface_pressure === "number"
                ? Math.round(current.surface_pressure)
                : undefined,
        windKph:
            typeof current.wind_speed_10m === "number"
                ? Math.round(current.wind_speed_10m)
                : undefined
    };
}

function fetchOpenMeteoWeather(latitude, longitude, callback) {
    var url =
        "https://api.open-meteo.com/v1/forecast?latitude=" +
        encodeURIComponent(latitude) +
        "&longitude=" +
        encodeURIComponent(longitude) +
        "&current=temperature_2m,weather_code,relative_humidity_2m,surface_pressure,wind_speed_10m&forecast_days=1";
    var xhr = new XMLHttpRequest();
    xhr.timeout = 15000;

    xhr.onload = function () {
        if (xhr.status < 200 || xhr.status >= 300) {
            callback(null);
            return;
        }

        callback(weatherInfoFromOpenMeteoBody(xhr.responseText));
    };

    xhr.onerror = function () {
        callback(null);
    };

    xhr.ontimeout = function () {
        callback(null);
    };

    xhr.open("GET", url);
    xhr.send();
}

function fetchWeatherFromGeolocation(callback) {
    if (!geolocationAvailable()) {
        callback(null);
        return;
    }

    navigator.geolocation.getCurrentPosition(
        function (position) {
            fetchOpenMeteoWeather(position.coords.latitude, position.coords.longitude, callback);
        },
        function () {
            callback(null);
        },
        { enableHighAccuracy: false, timeout: 15000, maximumAge: 300000 }
    );
}

function resolveWeatherInfo(callback) {
    if (shouldUseSimulatorWeather()) {
        callback(weatherFromSettings());
        return;
    }

    fetchWeatherFromGeolocation(callback);
}

function deliverWeatherInfo(requestId, info, eventName) {
    if (!info) {
        return false;
    }

    if (eventName === "weather.forecast") {
        var payload = { forecast: [info] };

        if (requestId) {
            deliverBridgeResult(requestId, true, payload);
        }

        deliverPlatformIncoming({
            event: eventName,
            payload: payload
        });

        return true;
    }

    if (requestId) {
        deliverBridgeResult(requestId, true, info);
    }

    deliverPlatformIncoming({
        event: "weather.current",
        payload: info
    });

    return true;
}

function deliverWeatherCurrent(requestId, attempt) {
    attempt = typeof attempt === "number" ? attempt : 0;

    if (!companionSimulatorSettingsReady && companionSimulatorSettingsPending() && attempt < 40) {
        setTimeout(function () {
            deliverWeatherCurrent(requestId, attempt + 1);
        }, 50);
        return false;
    }

    resolveWeatherInfo(function (info) {
        deliverWeatherInfo(requestId, info, "weather.current");
    });

    return true;
}

function handleWeatherCommand(request) {
    var op = request && request.op;
    var requestId = request && request.id;

    if (op === "current" || op === "subscribe") {
        setTimeout(function () {
            syncCompanionSimulatorSettingsFromGlobal();
            applyPendingCompanionSimulatorSettings();
            deliverWeatherCurrent(requestId);
        }, 150);
        return;
    }

    if (op === "forecast") {
        setTimeout(function () {
            syncCompanionSimulatorSettingsFromGlobal();
            applyPendingCompanionSimulatorSettings();
            resolveWeatherInfo(function (info) {
                if (!deliverWeatherInfo(requestId, info, "weather.forecast")) {
                    bridgeCommandError(request, "weather", "Weather unavailable");
                }
            });
        }, 150);
        return;
    }

    bridgeCommandError(request, "weather", "Unsupported weather operation: " + op);
}

function normalizeCalendarEvent(raw) {
    if (!raw || typeof raw !== "object") {
        return null;
    }

    var startMillis = Number(raw.startMillis || 0);
    var endMillis = Number(raw.endMillis || (startMillis + 3600000));

    return {
        id: String(raw.id || "event"),
        title: String(raw.title || "Event"),
        startMillis: startMillis,
        endMillis: endMillis,
        allDay: !!raw.allDay,
        location: raw.location ? String(raw.location) : undefined
    };
}

function calendarEventsFromSettings() {
    var events = companionSimulatorSettings.calendar_events;
    if (!Array.isArray(events)) {
        return [];
    }

    return events.map(normalizeCalendarEvent).filter(function (event) {
        return event !== null;
    });
}

function deliverCalendarNext(requestId, event) {
    var payload = { event: event || null };

    if (requestId) {
        deliverBridgeResult(requestId, true, payload);
        return;
    }

    deliverPlatformIncoming({
        event: "calendar.next",
        payload: payload
    });
}

function deliverCalendarUpcoming(requestId, events) {
    var payload = { events: events || [] };

    if (requestId) {
        deliverBridgeResult(requestId, true, payload);
        return;
    }

    deliverPlatformIncoming({
        event: "calendar.upcoming",
        payload: payload
    });
}

function handleCalendarCommand(request) {
    var op = request && request.op;
    var requestId = request && request.id;
    var events = calendarEventsFromSettings();
    var limit = 5;

    if (request && request.payload && typeof request.payload.limit === "number") {
        limit = request.payload.limit;
    }

    if (op === "nextEvent" || op === "current") {
        deliverCalendarNext(requestId, events.length > 0 ? events[0] : null);
        return;
    }

    if (op === "upcoming") {
        deliverCalendarUpcoming(requestId, events.slice(0, Math.max(0, limit)));
        return;
    }

    if (op === "subscribe") {
        deliverCalendarUpcoming(null, events);
        if (requestId) {
            deliverBridgeResult(requestId, true, { events: events });
        }
        return;
    }

    bridgeCommandError(request, "calendar", "Unsupported calendar operation: " + op);
}

function requestCompanionWeatherRefresh() {
    if (!protocol || typeof protocol.KEY_MESSAGE_TAG !== "number") {
        return;
    }

    var payload = {};
    payload[wireAppMessageKey(protocol.KEY_MESSAGE_TAG)] = 2;
    if (typeof protocol.KEY_REQUEST_WEATHER_FIELD1 === "number") {
        payload[wireAppMessageKey(protocol.KEY_REQUEST_WEATHER_FIELD1)] = 0;
    }
    deliverIncoming(normalizeIncomingAppMessage(payload));
}

function companionSupportsWeatherPlatform() {
    return !!(
        platformIncomingPorts.weather ||
        platformIncomingPorts["weather-current"] ||
        platformIncomingPorts["weather-forecast"]
    );
}

function companionSupportsCalendarPlatform() {
    return !!(
        platformIncomingPorts.calendar ||
        platformIncomingPorts["calendar-upcoming"] ||
        platformIncomingPorts["calendar-next"]
    );
}

function companionApplySimulatorSettings(settings) {
    if (!settings || typeof settings !== "object") {
        return;
    }

    if (settings.watchAppRunning === true) {
        markCompanionWatchAppReady("simulator_settings");

        if (
            Object.keys(settings).length === 1 &&
            Object.prototype.hasOwnProperty.call(settings, "watchAppRunning")
        ) {
            return;
        }
    }

    companionSimulatorSettings = normalizeCompanionSimulatorSettings(settings);
    companionGlobalRoot().__elmPebbleCompanionSimulatorSettings = companionSimulatorSettings;
    markCompanionSimulatorSettingsReady();

    if (companionSupportsCalendarPlatform()) {
        deliverCalendarUpcoming(null, calendarEventsFromSettings());
    }

    if (companionSupportsWeatherPlatform() && shouldUseSimulatorWeather()) {
        var signature = companionWeatherSignature(companionSimulatorSettings);

        if (signature) {
            console.log(
                "companion weather apply",
                signature,
                JSON.stringify(weatherFromSettings() || {})
            );

            if (signature !== lastDeliveredCompanionWeatherSignature) {
                lastDeliveredCompanionWeatherSignature = signature;
                deliverWeatherToWatch();
            }
        }
    }
}

companionGlobalRoot().companionApplySimulatorSettings = companionApplySimulatorSettings;
companionGlobalRoot().markCompanionWatchAppReady = markCompanionWatchAppReady;
companionGlobalRoot().syncCompanionSimulatorSettingsFromGlobal = syncCompanionSimulatorSettingsFromGlobal;
companionGlobalRoot().deliverWeatherToWatch = deliverWeatherToWatch;

function handleNotificationsCommand(request) {
    bridgeCommandError(request, "notifications", "Notification status unavailable from this Pebble companion runtime");
}

function handleGeolocationCommand(payload) {
    if (!geolocationAvailable()) {
        deliverGeolocationError({ message: "Geolocation unavailable" });
        return;
    }

    if (payload.op === "getCurrentPosition") {
        navigator.geolocation.getCurrentPosition(deliverGeolocationPosition, deliverGeolocationError);
        return;
    }

    if (payload.op === "watch") {
        var watchId = navigator.geolocation.watchPosition(deliverGeolocationPosition, deliverGeolocationError);
        geolocationWatches[payload.id || String(watchId)] = watchId;
        return;
    }

    if (payload.op === "clearWatch") {
        var requestedId = payload.payload && payload.payload.watchId;
        var watchKey = String(requestedId);
        var storedId = geolocationWatches[watchKey];
        navigator.geolocation.clearWatch(typeof storedId === "number" ? storedId : requestedId);
        delete geolocationWatches[watchKey];
    }
}

function handleOutgoing(payload) {
    if (payload && payload.registerBridgeResponse) {
        pendingBridgeResponseIds[payload.registerBridgeResponse] = true;
        return;
    }

    if (payload && payload.registerPlatformHandler) {
        var registration = payload.registerPlatformHandler;

        if (registration && typeof registration.handlerId === "string") {
            var handlerId = registration.handlerId;
            var interest = registration.interest || {};

            platformHandlers[handlerId] = {
                eventPrefixes: Array.isArray(interest.eventPrefixes) ? interest.eventPrefixes : [],
                resultIdPrefixes: Array.isArray(interest.resultIdPrefixes) ? interest.resultIdPrefixes : []
            };
            flushUnhandledPlatformIncoming();
        }

        return;
    }

    if (payload && payload.api === "configuration") {
        if (payload.op === "open") {
            console.log("Elm companion requested configuration", JSON.stringify(payload.payload || {}));
            openConfigurationUrl((payload.payload && payload.payload.url) || generatedConfigurationUrl);
        }
        return;
    }

    if (payload && payload.api === "lifecycle" && payload.op === "subscribe") {
        deliverLifecycleReadyOnce();
        return;
    }

    if (payload && payload.api === "geolocation") {
        console.log("Elm companion geolocation command", JSON.stringify({ id: payload.id, op: payload.op }));
        handleGeolocationCommand(payload);
        return;
    }

    if (payload && payload.api === "network") {
        deliverNetworkStatus(payload);
        return;
    }

    if (payload && payload.api === "battery") {
        deliverBatteryStatus(payload);
        return;
    }

    if (payload && payload.api === "locale") {
        deliverLocaleStatus(payload);
        return;
    }

    if (payload && payload.api === "storage") {
        handleStorageCommand(payload);
        return;
    }

    if (payload && payload.api === "preferences") {
        handlePreferencesCommand(payload);
        return;
    }

    if (payload && payload.api === "environment") {
        handleEnvironmentCommand(payload);
        return;
    }

    if (payload && payload.api === "weather") {
        handleWeatherCommand(payload);
        return;
    }

    if (payload && payload.api === "calendar") {
        handleCalendarCommand(payload);
        return;
    }

    if (payload && payload.api === "notifications") {
        handleNotificationsCommand(payload);
        return;
    }

    if (payload && payload.api === "webSocket") {
        bridgeCommandError(payload, "webSocket", "WebSocket unavailable from this Pebble companion runtime");
        return;
    }

    if (payload && payload.api === "timeline") {
        bridgeCommandError(payload, "timeline", "Timeline unavailable from this Pebble companion runtime");
        return;
    }

    if (payload && payload.api === "lifecycle") {
        return;
    }

    if (payload && payload.api === "appMessage" && payload.op === "send") {
        sendQueuedAppMessage(payload.payload || {});
        return;
    }

    sendQueuedAppMessage(payload);
}

function installXmlHttpRequestCompatibility() {
    if (typeof XMLHttpRequest === "undefined") {
        return;
    }

    var proto = XMLHttpRequest.prototype;
    if (!proto) {
        return;
    }

    if (typeof proto.getAllResponseHeaders !== "function") {
        proto.getAllResponseHeaders = function () {
            return "";
        };
    }

    if (typeof proto.addEventListener !== "function") {
        proto.addEventListener = function (name, callback) {
            if (typeof callback !== "function") {
                return;
            }

            var property = "on" + name;
            var previous = this[property];
            this[property] = function (event) {
                if (
                    name === "load" &&
                    typeof this.responseText !== "undefined" &&
                    (typeof this.response === "undefined" || this.response === null || this.response === "")
                ) {
                    try {
                        this.response = this.responseText;
                    } catch (_error) {
                    }
                }
                if (typeof previous === "function") {
                    previous.call(this, event);
                }
                callback.call(this, event);
            };
        };
    }

    if (proto.__elmPebbleHttpSimulatorInstalled) {
        return;
    }

    proto.__elmPebbleHttpSimulatorInstalled = true;

    var originalOpen = proto.open;
    var originalSend = proto.send;

    proto.open = function (method, url) {
        this.__elmPebbleHttpMethod = method;
        this.__elmPebbleHttpUrl = url;
        return originalOpen.apply(this, arguments);
    };

    proto.send = function (_body) {
        var simulated = simulatedHttpResponse(this.__elmPebbleHttpMethod, this.__elmPebbleHttpUrl);
        if (simulated) {
            var xhr = this;
            setTimeout(function () {
                try {
                    xhr.status = 200;
                    xhr.responseText = simulated;
                    xhr.response = simulated;
                } catch (_error) {
                }

                if (typeof xhr.onload === "function") {
                    xhr.onload({});
                }

                if (typeof xhr.onreadystatechange === "function") {
                    xhr.readyState = 4;
                    xhr.onreadystatechange();
                }
            }, 0);
            return;
        }

        return originalSend.apply(this, arguments);
    };
}

function simulatedHttpResponse(method, _url) {
    if (String(method || "").toUpperCase() !== "GET") {
        return null;
    }

    return openMeteoJsonFromSettings();
}

installXmlHttpRequestCompatibility();

Pebble.addEventListener("appmessage", function (event) {
    if (!event || !event.payload) {
        return;
    }

    markCompanionWatchAppReady("watch_appmessage");
    deliverIncoming(normalizeIncomingAppMessage(event.payload));
});

if (generatedConfigurationUrl) {
    Pebble.addEventListener("showConfiguration", function () {
        console.log("Pebble showConfiguration event");
        deliverLifecycleEvent("lifecycle.showConfiguration", {});
        openConfigurationUrl(generatedConfigurationUrl);
    });

    Pebble.addEventListener("webviewclosed", function (event) {
        var response = event && typeof event.response === "string" ? event.response : null;
        console.log("Pebble webviewclosed response", response);
        writeStoredConfigurationResponse(response);

        deliverPlatformIncoming({
            event: "configuration.closed",
            payload: {
                response: response
            }
        });

        deliverLifecycleEvent("lifecycle.webviewclosed", {
            response: response
        });
    });
}

var elmModule = require("./elm-companion.js");

function initElmCompanionApp() {
    var elmRoot = elmModule.Elm || (typeof Elm !== "undefined" ? Elm : null);
    var app;

    if (!elmRoot || !elmRoot.CompanionApp) {
        throw new Error("Elm.CompanionApp is not available");
    }

    try {
        app = elmRoot.CompanionApp.init({ flags: companionFlags() });
    } catch (_error) {
        app = elmRoot.CompanionApp.init();
    }

    if (app.ports && app.ports.outgoing) {
        app.ports.outgoing.subscribe(function (payload) {
            handleOutgoing(payload);
        });
    }

    if (app.ports && app.ports.geolocationOutgoing) {
        app.ports.geolocationOutgoing.subscribe(function (payload) {
            handleOutgoing(payload);
        });
    }

    wireCompanionIncomingPorts(app);

    // Elm init commands run on the next macrotask via Process.sleep(0). Defer boot
    // until handlers are registered and early bridge pushes can be replayed.
    setTimeout(function () {
        finishCompanionBoot();
    }, 0);
}

function bootElmCompanionWhenReady(attempt) {
    attempt = typeof attempt === "number" ? attempt : 0;
    syncCompanionSimulatorSettingsFromGlobal();
    applyPendingCompanionSimulatorSettings();

    var awaitingExplicit =
        companionSimulatorSettingsPending() ||
        hasExplicitCompanionSimulatorWeather(peekPendingCompanionSimulatorSettings()) ||
        hasExplicitCompanionSimulatorWeather(companionGlobalRoot().__elmPebbleCompanionSimulatorSettings);

    if (!companionSimulatorSettingsReady && awaitingExplicit && attempt < 60) {
        setTimeout(function () {
            bootElmCompanionWhenReady(attempt + 1);
        }, 50);
        return;
    }

    if (!companionSimulatorSettingsReady) {
        var globalSettings = companionGlobalRoot().__elmPebbleCompanionSimulatorSettings;
        if (hasExplicitCompanionSimulatorWeather(globalSettings)) {
            companionApplySimulatorSettings(globalSettings);
        } else {
            markCompanionSimulatorSettingsReady();
        }
    }

    initElmCompanionApp();
}

Pebble.addEventListener("ready", function () {
    installAppMessageSafeSend();
    bootElmCompanionWhenReady(0);
});
