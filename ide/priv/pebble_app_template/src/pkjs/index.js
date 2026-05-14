var pendingIncoming = [];
var incomingPort = null;
var protocol = require("./companion-protocol.js");
var generatedConfigurationUrl = null;
var configurationStorageKey = "elm-pebble.configuration.response";
var appMessageKeyNamesById = {};
var appMessageKeyIdsByName = {};

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

function deliverIncoming(payload) {
    console.log("bridge -> Elm companion", JSON.stringify(payload));
    if (incomingPort) {
        incomingPort.send(payload);
    } else {
        console.log("bridge queued incoming for Elm companion");
        pendingIncoming.push(payload);
    }
}

function openConfigurationUrl(url) {
    if (url && typeof Pebble.openURL === "function") {
        console.log("opening companion configuration", url);
        Pebble.openURL(url);
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

    if (payload && payload.api === "appMessage" && payload.op === "send") {
        console.log("Elm companion sendAppMessage payload", JSON.stringify(payload.payload || {}));
        Pebble.sendAppMessage(normalizeOutgoingAppMessage(payload.payload || {}));
        return;
    }

    console.log("Elm companion sendAppMessage payload", JSON.stringify(payload));
    Pebble.sendAppMessage(normalizeOutgoingAppMessage(payload));
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

    if (app.ports && app.ports.incoming) {
        incomingPort = app.ports.incoming;
        while (pendingIncoming.length > 0) {
            incomingPort.send(pendingIncoming.shift());
        }
    }
});
