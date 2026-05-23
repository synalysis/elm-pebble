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
var companionSimulatorSettings = {
    calendar_events: []
};
var appMessageOutbox = [];
var appMessageSending = false;

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

function normalizeOutgoingAppMessage(payload) {
    if (!payload) {
        return payload;
    }

    var normalized = {};
    Object.keys(payload).forEach(function (key) {
        var id = appMessageKeyIdsByName[key];
        normalized[typeof id === "number" ? id : key] = payload[key];
    });

    return normalized;
}

function sendQueuedAppMessage(payload) {
    appMessageOutbox.push(normalizeOutgoingAppMessage(payload || {}));
    drainAppMessageOutbox();
}

function drainAppMessageOutbox() {
    if (appMessageSending || appMessageOutbox.length === 0) {
        return;
    }

    var payload = appMessageOutbox[0];
    appMessageSending = true;

    Pebble.sendAppMessage(
        payload,
        function () {
            appMessageOutbox.shift();
            appMessageSending = false;
            drainAppMessageOutbox();
        },
        function (error) {
            console.log("Elm companion sendAppMessage failed", JSON.stringify(error || {}));
            appMessageSending = false;
            setTimeout(drainAppMessageOutbox, 50);
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
        }
    });
}

function finishCompanionBoot() {
    flushPendingPlatformIncomingPorts();
    flushUnhandledPlatformIncoming();
    deliverLifecycleEvent("lifecycle.ready", {});
}

function deliverIncoming(payload) {
    if (isPlatformEnvelope(payload)) {
        deliverPlatformIncoming(payload);
        return;
    }

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

function handleEnvironmentCommand(request) {
    bridgeCommandError(request, "environment", "Environment data unavailable without platform location and tide support");
}

function handleWeatherCommand(request) {
    bridgeCommandError(request, "weather", "Weather data unavailable from this Pebble companion runtime");
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

function companionApplySimulatorSettings(settings) {
    if (!settings || typeof settings !== "object") {
        return;
    }

    companionSimulatorSettings = settings;
    deliverCalendarUpcoming(null, calendarEventsFromSettings());
}

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
        deliverLifecycleEvent("lifecycle.ready", {});
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
        console.log("Elm companion sendAppMessage payload", JSON.stringify(payload.payload || {}));
        sendQueuedAppMessage(payload.payload || {});
        return;
    }

    console.log("Elm companion sendAppMessage payload", JSON.stringify(payload));
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
}

installXmlHttpRequestCompatibility();

Pebble.addEventListener("appmessage", function (event) {
    if (!event || !event.payload) {
        return;
    }

    console.log("watch -> Elm companion", JSON.stringify(event.payload));
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

Pebble.addEventListener("ready", function () {
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
});
