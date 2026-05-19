var pendingIncoming = [];
var pendingGeolocationIncoming = [];
var incomingPort = null;
var geolocationIncomingPort = null;
var protocol = require("./companion-protocol.js");
var generatedConfigurationUrl = null;
var configurationStorageKey = "elm-pebble.configuration.response";
var appMessageKeyNamesById = {};
var appMessageKeyIdsByName = {};
var geolocationWatches = {};
var companionStorage = {};
var companionPreferences = {};
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

function deliverIncoming(payload) {
    console.log("bridge -> Elm companion", JSON.stringify(payload));
    if (incomingPort) {
        incomingPort.send(payload);
    } else {
        console.log("bridge queued incoming for Elm companion");
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
    deliverIncoming(payload);
    deliverGeolocationIncoming(payload);
}

function deliverGeolocationError(error) {
    var payload = {
        event: "geolocation.error",
        payload: {
            message: error && error.message ? String(error.message) : "Geolocation unavailable"
        }
    };
    deliverIncoming(payload);
    deliverGeolocationIncoming(payload);
}

function deliverBridgeError(api, message) {
    deliverIncoming({
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

    deliverIncoming(envelope);
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

function deliverLocaleStatus() {
    deliverIncoming({
        event: "locale.status",
        payload: localePayload()
    });
}

function deliverNetworkStatus() {
    deliverIncoming({
        event: "network.status",
        payload: {
            online: typeof navigator === "undefined" || typeof navigator.onLine !== "boolean" ? true : navigator.onLine
        }
    });
}

function deliverBatteryStatus() {
    if (typeof navigator !== "undefined" && typeof navigator.getBattery === "function") {
        navigator.getBattery().then(function (battery) {
            deliverIncoming({
                event: "battery.status",
                payload: {
                    percent: Math.round(Number(battery.level || 0) * 100),
                    charging: !!battery.charging
                }
            });
        }, function (error) {
            deliverBridgeError("battery", error && error.message ? String(error.message) : "Battery information unavailable");
        });
        return;
    }

    deliverBridgeError("battery", "Battery information unavailable");
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
        deliverIncoming({
            event: "preferences.saved",
            payload: { key: key }
        });
        return;
    }

    if (payload.op === "get") {
        deliverIncoming({
            event: "preferences.value",
            payload: {
                key: key,
                value: Object.prototype.hasOwnProperty.call(companionPreferences, key) ? companionPreferences[key] : null
            }
        });
        return;
    }

    if (payload.op === "subscribe") {
        Object.keys(companionPreferences).forEach(function (storedKey) {
            deliverIncoming({
                event: "preferences.value",
                payload: {
                    key: storedKey,
                    value: companionPreferences[storedKey]
                }
            });
        });
    }
}

function handleEnvironmentCommand() {
    deliverBridgeError("environment", "Environment data unavailable without platform location and tide support");
}

function handleWeatherCommand() {
    deliverBridgeError("weather", "Weather data unavailable from this Pebble companion runtime");
}

function handleCalendarCommand() {
    deliverBridgeError("calendar", "Calendar data unavailable from this Pebble companion runtime");
}

function handleNotificationsCommand() {
    deliverBridgeError("notifications", "Notification status unavailable from this Pebble companion runtime");
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
    if (payload && payload.api === "configuration") {
        if (payload.op === "open") {
            console.log("Elm companion requested configuration", JSON.stringify(payload.payload || {}));
            openConfigurationUrl((payload.payload && payload.payload.url) || generatedConfigurationUrl);
        }
        return;
    }

    if (payload && payload.api === "geolocation") {
        console.log("Elm companion geolocation command", JSON.stringify({ id: payload.id, op: payload.op }));
        handleGeolocationCommand(payload);
        return;
    }

    if (payload && payload.api === "network") {
        deliverNetworkStatus();
        return;
    }

    if (payload && payload.api === "battery") {
        deliverBatteryStatus();
        return;
    }

    if (payload && payload.api === "locale") {
        deliverLocaleStatus();
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
        openConfigurationUrl(generatedConfigurationUrl);
    });

    Pebble.addEventListener("webviewclosed", function (event) {
        var response = event && typeof event.response === "string" ? event.response : null;
        console.log("Pebble webviewclosed response", response);
        writeStoredConfigurationResponse(response);

        deliverIncoming({
            event: "configuration.closed",
            payload: {
                response: response
            }
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
});
