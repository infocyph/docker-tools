(function () {
  "use strict";

  function configuredTimezone() {
    var body = document.body;
    var value = body ? String(body.getAttribute("data-ap-timezone") || "").trim() : "";
    return value || "UTC";
  }

  function normalizeIso(value) {
    var raw = String(value || "").trim();
    if (!raw) {
      return "";
    }
    return raw.replace(/\.(\d{3})\d+(Z|[+-]\d{2}:\d{2})$/i, ".$1$2");
  }

  function asDate(value) {
    if (value instanceof Date) {
      return isFinite(value.getTime()) ? value : null;
    }
    if (typeof value === "number" && isFinite(value)) {
      var millis = Math.abs(value) < 100000000000 ? value * 1000 : value;
      var numericDate = new Date(millis);
      return isFinite(numericDate.getTime()) ? numericDate : null;
    }
    var raw = normalizeIso(value);
    if (!raw) {
      return null;
    }
    var parsed = new Date(raw);
    return isFinite(parsed.getTime()) ? parsed : null;
  }

  function parts(value) {
    var date = asDate(value);
    if (!date) {
      return null;
    }
    try {
      var formatter = new Intl.DateTimeFormat("en-GB", {
        timeZone: configuredTimezone(),
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: false
      });
      var out = {};
      formatter.formatToParts(date).forEach(function (part) {
        if (part.type !== "literal") {
          out[part.type] = part.value;
        }
      });
      return out;
    } catch (e) {
      return null;
    }
  }

  function formatDateTime(value, fallback) {
    var p = parts(value);
    if (!p) {
      return fallback == null ? String(value || "") : String(fallback);
    }
    return p.year + "-" + p.month + "-" + p.day + " " + p.hour + ":" + p.minute + ":" + p.second;
  }

  function formatTime(value, fallback) {
    var p = parts(value);
    if (!p) {
      return fallback == null ? String(value || "") : String(fallback);
    }
    return p.hour + ":" + p.minute;
  }

  function formatEpochSeconds(value, fallback) {
    var epoch = Number(value);
    if (!isFinite(epoch) || epoch <= 0) {
      return fallback == null ? "" : String(fallback);
    }
    return formatDateTime(epoch, fallback);
  }

  function formatEpochTime(value, fallback) {
    var epoch = Number(value);
    if (!isFinite(epoch) || epoch <= 0) {
      return fallback == null ? "" : String(fallback);
    }
    return formatTime(epoch, fallback);
  }

  function localizeDockerLine(value) {
    var line = String(value || "");
    var match = line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))\s?(.*)$/);
    if (!match) {
      return line;
    }
    var local = formatDateTime(match[1], match[1]);
    return match[2] ? local + " " + match[2] : local;
  }

  window.AdminPanelTime = Object.freeze({
    timezone: configuredTimezone,
    formatDateTime: formatDateTime,
    formatTime: formatTime,
    formatEpochSeconds: formatEpochSeconds,
    formatEpochTime: formatEpochTime,
    localizeDockerLine: localizeDockerLine
  });
})();
