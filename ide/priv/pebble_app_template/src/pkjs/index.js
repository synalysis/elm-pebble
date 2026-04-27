var elmModule = require("./elm-companion.js");

Pebble.addEventListener("ready", function () {
    var elmRoot = elmModule.Elm || (typeof Elm !== "undefined" ? Elm : null);
    var app;

    if (!elmRoot || !elmRoot.CompanionApp) {
        throw new Error("Elm.CompanionApp is not available");
    }

    try {
        app = elmRoot.CompanionApp.init({ flags: null });
    } catch (_error) {
        app = elmRoot.CompanionApp.init();
    }

    if (app.ports && app.ports.outgoing) {
        app.ports.outgoing.subscribe(function (payload) {
            Pebble.sendAppMessage(
                payload,
                function () {
                    console.log("Elm companion -> watch", JSON.stringify(payload));
                },
                function (error) {
                    console.log("Elm companion send failed:", JSON.stringify(error));
                }
            );
        });
    }

    if (app.ports && app.ports.incoming) {
        Pebble.addEventListener("appmessage", function (event) {
            if (event && event.payload) {
                app.ports.incoming.send(event.payload);
            }
        });
    }
});
