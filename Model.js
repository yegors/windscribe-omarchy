// Pure parsing and formatting helpers for windscribe-cli output.
// Output formats per https://github.com/Windscribe/Desktop-App
// (src/windscribe-cli/strings.cpp), v2.23.x.

function markupSafe(raw) {
  return String(raw || "")
    .replace(/[\x00-\x1f\x7f]/g, " ")
    .replace(/</g, "‹")
    .replace(/>/g, "›")
    .replace(/&/g, "＆")
}

function elide(text) {
  var value = markupSafe(text).replace(/\s+/g, " ").trim()
  return value.length > 160 ? value.substring(0, 157) + "…" : value
}

function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\"'\"'") + "'"
}

// Locations, cities, and nicknames the user may connect to. The CLI is
// invoked with an argv array (never a shell), so this only guards against
// nonsense reaching the command line or the UI.
function isSafeLocation(value) {
  return /^[A-Za-z0-9][A-Za-z0-9 ._',()-]{0,63}$/.test(String(value || "").trim())
}

function field(text, name) {
  var match = String(text || "").match(new RegExp("^\\s*" + name + "\\s*:\\s*(.+)$", "im"))
  return match ? match[1].trim() : ""
}

// windscribe-cli status prints, in order (lines conditionally omitted):
//   Internet connectivity: available|unavailable
//   Login state: Logged out|Logging in|Logged in|Error: <reason>
//   Firewall state: On|Off|Always On
//   Connect state: Connected: <City>|Connecting: <City>|Disconnecting|Disconnected|Error: <reason>
//   Protocol: <Name>:<port>
//   VPN IP: <ip>  -or-  Public IP: <ip>
//   Data usage: <used> / <total|Unlimited>
//   Update available: <version>
// A leading "*" marks a pending tunnel test; a "[Network interference]"
// suffix marks a failed one.
function parseStatus(raw) {
  var text = String(raw || "")
  var result = {
    internet: field(text, "Internet connectivity"),
    loginState: field(text, "Login state"),
    firewall: field(text, "Firewall state"),
    state: "Unknown",
    city: "",
    stateError: "",
    protocol: field(text, "Protocol"),
    ip: "",
    ipIsVpn: false,
    dataUsage: field(text, "Data usage"),
    updateAvailable: field(text, "Update available"),
    tunnelTestPending: false,
    networkInterference: false
  }

  var vpnIp = field(text, "VPN IP")
  var publicIp = field(text, "Public IP")
  if (vpnIp !== "") {
    result.ip = vpnIp
    result.ipIsVpn = true
  } else if (publicIp !== "") {
    result.ip = publicIp
  }

  var connectLine = text.match(/^\s*(\*?)\s*Connect state\s*:\s*(.+)$/im)
  if (connectLine) {
    var value = connectLine[2].trim()
    result.tunnelTestPending = connectLine[1] === "*" || value.charAt(0) === "*"
    if (value.charAt(0) === "*") value = value.substring(1).trim()
    if (/\[Network interference\]\s*$/i.test(value)) {
      result.networkInterference = true
      value = value.replace(/\s*\[Network interference\]\s*$/i, "").trim()
    }
    var parts = value.match(/^(Connected|Connecting|Disconnecting|Disconnected|Error)(?:\s*:\s*(.*))?$/i)
    if (parts) {
      result.state = parts[1].charAt(0).toUpperCase() + parts[1].slice(1).toLowerCase()
      var detail = (parts[2] || "").trim()
      if (result.state === "Error") result.stateError = detail
      else result.city = detail
    }
  }
  return result
}

// windscribe-cli locations prints one location per line:
//   <Region> - <City> - <Nickname>
// with optional trailing flags " (Pro)", " (Disabled)", " (10 Gbps)" and,
// for favourites, a pinned IP suffix " [x.x.x.x]".
function parseLocations(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var out = []
  var seen = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || /^Locations\s*:?$/i.test(line) || /^No locations\.?$/i.test(line)) continue

    var flags = { pro: false, disabled: false, tenGbps: false }
    var stripped = true
    while (stripped) {
      stripped = false
      var next = line
        .replace(/\s*\[[0-9A-Fa-f:.]+\]$/, "")
        .replace(/\s*\(Pro\)$/i, function() { flags.pro = true; return "" })
        .replace(/\s*\(Disabled\)$/i, function() { flags.disabled = true; return "" })
        .replace(/\s*\(10 Gbps\)$/i, function() { flags.tenGbps = true; return "" })
      if (next !== line) {
        line = next.trim()
        stripped = true
      }
    }

    var parts = line.split(" - ")
    if (parts.length < 2) continue
    var entry = {
      country: parts[0].trim(),
      city: parts[1].trim(),
      nickname: parts.length >= 3 ? parts.slice(2).join(" - ").trim() : "",
      pro: flags.pro,
      disabled: flags.disabled,
      tenGbps: flags.tenGbps
    }
    if (entry.city === "" || /^Best Location$/i.test(entry.country)) continue
    var key = (entry.country + "|" + entry.city + "|" + entry.nickname).toLowerCase()
    if (seen[key]) continue
    seen[key] = true
    out.push(entry)
  }
  return out
}

// One size like "1.24 GiB" (Qt-localized: binary i-units, possible thousands
// separators) to bytes, or NaN.
function parseSize(text) {
  var match = String(text || "").trim().match(/^([\d.,  ]+)\s*([KMGTP]?i?B)$/i)
  if (!match) return NaN
  var num = match[1].replace(/[  ]/g, "")
  if (num.indexOf(",") !== -1 && num.indexOf(".") !== -1) num = num.replace(/,/g, "")
  else num = num.replace(",", ".")
  var value = parseFloat(num)
  if (!isFinite(value)) return NaN
  var unit = match[2].toUpperCase()
  var powers = { "B": 0, "KB": 1, "KIB": 1, "MB": 2, "MIB": 2, "GB": 3, "GIB": 3, "TB": 4, "TIB": 4, "PB": 5, "PIB": 5 }
  var p = powers[unit]
  if (p === undefined) return NaN
  var base = unit.indexOf("I") !== -1 ? 1024 : 1000
  return value * Math.pow(base, p)
}

// "512.00 MiB / 10.00 GiB" → a 0..1 fraction; "… / Unlimited" → unlimited.
function parseDataUsage(raw) {
  var parts = String(raw || "").split("/")
  if (parts.length !== 2) return { unlimited: true, fraction: 0 }
  if (/unlimited/i.test(parts[1])) return { unlimited: true, fraction: 0 }
  var used = parseSize(parts[0])
  var total = parseSize(parts[1])
  if (!isFinite(used) || !isFinite(total) || total <= 0) return { unlimited: true, fraction: 0 }
  return { unlimited: false, fraction: Math.max(0, Math.min(1, used / total)) }
}

// `ip -j route get 1.1.1.1` → the egress device and source address. When the
// tunnel is up the default route goes through it, so this finds the tunnel
// interface without knowing what Windscribe names it.
function parseRoute(raw) {
  try {
    var routes = JSON.parse(String(raw || ""))
    if (!(routes instanceof Array) || routes.length === 0) return { dev: "", src: "" }
    var dev = String(routes[0].dev || "").trim()
    var src = String(routes[0].prefsrc || "").trim()
    return {
      dev: /^[A-Za-z0-9._-]{1,32}$/.test(dev) ? dev : "",
      src: /^[0-9A-Fa-f:.]+$/.test(src) ? src : ""
    }
  } catch (error) {
    return { dev: "", src: "" }
  }
}

// Protocols supported by the Linux client, with an optional ":port" suffix.
function normalizeProtocol(value) {
  var proto = String(value || "").trim().toLowerCase()
  var match = proto.match(/^(wireguard|udp|tcp|stealth|wstunnel)(?::(\d{1,5}))?$/)
  if (!match) return ""
  if (match[2] !== undefined) {
    var port = parseInt(match[2], 10)
    if (port < 1 || port > 65535) return ""
  }
  return proto
}

function protocolLabel(value) {
  var labels = {
    "": "Automatic",
    "wireguard": "WireGuard",
    "udp": "UDP",
    "tcp": "TCP",
    "stealth": "Stealth",
    "wstunnel": "WStunnel"
  }
  var normalized = normalizeProtocol(value)
  if (normalized === "") return String(value || "").trim() === "" ? labels[""] : markupSafe(value)
  var parts = normalized.split(":")
  return labels[parts[0]] + (parts.length > 1 ? ":" + parts[1] : "")
}

function protocolBase(value) {
  var normalized = normalizeProtocol(value)
  return normalized === "" ? "" : normalized.split(":")[0]
}

function protocolPort(value) {
  var normalized = normalizeProtocol(value)
  if (normalized === "") return ""
  var parts = normalized.split(":")
  return parts.length > 1 ? parts[1] : ""
}

// `windscribe-cli ports <protocol>` returns a comma-separated list.
function parsePorts(raw) {
  var tokens = String(raw || "").match(/\d{1,5}/g) || []
  var out = []
  var seen = {}
  for (var i = 0; i < tokens.length; i++) {
    var port = parseInt(tokens[i], 10)
    if (port < 1 || port > 65535 || seen[port]) continue
    seen[port] = true
    out.push(String(port))
  }
  return out
}

function formatRate(bytesPerSecond) {
  var value = Math.max(0, Number(bytesPerSecond) || 0)
  var units = ["B/s", "KB/s", "MB/s", "GB/s"]
  var unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  var digits = value >= 100 || unit === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(digits) + " " + units[unit]
}

function formatBytes(bytes) {
  var value = Math.max(0, Number(bytes) || 0)
  var units = ["B", "KB", "MB", "GB", "TB"]
  var unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  var digits = value >= 100 || unit === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(digits) + " " + units[unit]
}

function formatDuration(seconds) {
  var value = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(value / 3600)
  var minutes = Math.floor((value % 3600) / 60)
  if (hours > 0) return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
  if (minutes > 0) return minutes + "m " + (value % 60) + "s"
  return value + "s"
}
