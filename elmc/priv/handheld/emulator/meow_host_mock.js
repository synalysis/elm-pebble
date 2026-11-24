/**
 * Browser stand-in for the portable handheld host.
 * Profiles: "meowkit" (320x240 rgb565), "flipper-zero" (128x64 mono),
 * "flipper-one" (metrics supplied by the device; width 0 until published).
 */
export function createHandheldHost(canvas, profileName) {
  const profiles = {
    meowkit: { width: 320, height: 240, colorDepth: 16 },
    "flipper-zero": { width: 128, height: 64, colorDepth: 1 },
    "flipper-one": { width: 0, height: 0, colorDepth: 16 },
  };
  const profile = profiles[profileName] || profiles.meowkit;
  const ctx = canvas.getContext("2d");
  canvas.width = profile.width || 1;
  canvas.height = profile.height || 1;
  const modules = {
    nfc: profileName === "meowkit" || profileName === "flipper-zero" ? {} : null,
    usb: profileName === "meowkit" ? {} : null,
  };
  return {
    abi: { major: 1, minor: 1 },
    metrics() {
      return { width: profile.width, height: profile.height, colorDepth: profile.colorDepth };
    },
    draw(op, args, text) {
      if (!ctx || !profile.width) return;
      const color = profile.colorDepth <= 1 ? (args[4] ? "#bbee00" : "#000") : "#f00";
      if (op === 2) {
        ctx.fillStyle = "#000";
        ctx.fillRect(0, 0, profile.width, profile.height);
      } else if (op === 6) {
        ctx.fillStyle = color;
        ctx.fillRect(args[0], args[1], args[2], args[3]);
      } else if (text) {
        ctx.fillStyle = "#fff";
        ctx.fillText(text, args[0] || 0, args[1] || 12);
      }
    },
    moduleReady(id) {
      if (id === 1) return modules.nfc ? 1 : 0;
      if (id === 4) return modules.usb ? 1 : 0;
      return 0;
    },
  };
}
