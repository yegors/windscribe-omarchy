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

// Create or harden ~/.local/state/omarchy-windscribe. mkdir -p follows a
// planted symlink and leaves an existing directory's mode alone; this
// refuses a link at the leaf, creates 0700, and chmod's a leftover 0755.
function stateDirPrepareCommand(dir) {
  return "umask 077; dir=" + shellQuote(dir) + "; "
    + "if [ -L \"$dir\" ]; then echo 'Windscribe state path is a symlink; refusing' >&2; exit 1; fi; "
    + "if [ -d \"$dir\" ]; then chmod 700 \"$dir\" || exit 1; "
    + "elif [ -e \"$dir\" ]; then echo 'Windscribe state path is not a directory' >&2; exit 1; "
    + "else mkdir -p \"$(dirname \"$dir\")\" || exit 1; mkdir -m 700 \"$dir\" || exit 1; fi; "
    + "if [ -L \"$dir\" ] || [ ! -d \"$dir\" ]; then echo 'Windscribe state path is not a real directory' >&2; exit 1; fi"
}

// Sign-in/update completion marker. mktemp creates the bytes O_EXCL; GNU
// mv -T renames over the destination so a planted symlink is replaced
// rather than followed. The panel polls the final path with cat.
function terminalCommandWithResult(command, resultPath) {
  return "result=" + shellQuote(resultPath)
    + "; umask 077; code=1"
    + "; trap 'tmp=$(mktemp \"${result}.XXXXXX\") && printf \"%s\" \"$code\" > \"$tmp\" && mv -f -T \"$tmp\" \"$result\"; rm -f -- \"$tmp\"' EXIT"
    + "; " + command + "; code=$?; exit \"$code\""
}

function outputLimitExitCode() {
  return 125
}

// Wrap argv without turning it back into a shell string. The helper caps each
// output stream before Quickshell can collect it and returns 125 on overflow.
function boundedCommand(limiterPath, maxBytes, command) {
  var limit = Math.floor(Number(maxBytes))
  if (!isFinite(limit) || limit < 1) limit = 65536
  limit = Math.min(limit, 1048576)
  var result = [String(limiterPath), String(limit)]
  for (var i = 0; i < command.length; i++) result.push(String(command[i]))
  return result
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

// The first label that appears. The status contract gained new labels in the
// 2.25 client; trying both keeps an older pinned CLI readable.
function firstField(text, names) {
  for (var i = 0; i < names.length; i++) {
    var value = field(text, names[i])
    if (value !== "") return value
  }
  return ""
}

// windscribe-cli status prints one "Label: value" line per item. The 2.25
// client renamed the labels and reworded the connection detail; both forms
// are read so the plugin works with a pinned older CLI too.
//   2.23-2.24                          2.25+
//   Internet connectivity: available    Internet: Available
//   Login state: Logged in              Login: Logged in
//   Firewall state: Off                 Firewall: Off
//   Connect state: Connected: <City>    Connection: Connected to <City>
//   Protocol: <Name>:<port>             Protocol: <Name>:<port>
//   VPN IP: <ip> / Public IP: <ip>      IP: <ip> (VPN) / <ip> (public)
//   Data usage: <used> / <total>        Data usage: <used> / <limit>
//   Update available: <version>         Update: <version> available
// A leading "*" (2.24) or a "(checking the connection)" suffix (2.25) marks a
// pending tunnel test; "[Network interference]" (2.24) or "(network
// interference detected)" (2.25) marks a failed one.
function parseStatus(raw) {
  var text = String(raw || "")
  var result = {
    internet: firstField(text, ["Internet connectivity", "Internet"]).toLowerCase(),
    loginState: firstField(text, ["Login state", "Login"]),
    firewall: firstField(text, ["Firewall state", "Firewall"]),
    state: "Unknown",
    city: "",
    stateError: "",
    protocol: field(text, "Protocol"),
    ip: "",
    ipIsVpn: false,
    dataUsage: field(text, "Data usage"),
    updateAvailable: firstField(text, ["Update available", "Update"])
      .replace(/\s+available$/i, ""),
    tunnelTestPending: false,
    networkInterference: false
  }

  // 2.25 folds both addresses into one labelled line and appends the mode.
  var ipMode = field(text, "IP").match(/^(.+?)\s*\((VPN|public)\)$/i)
  if (ipMode) {
    result.ip = ipMode[1].trim()
    result.ipIsVpn = ipMode[2].toLowerCase() === "vpn"
  } else {
    var vpnIp = field(text, "VPN IP")
    var publicIp = field(text, "Public IP")
    if (vpnIp !== "") {
      result.ip = vpnIp
      result.ipIsVpn = true
    } else if (publicIp !== "") {
      result.ip = publicIp
    }
  }

  var connectLine = text.match(/^\s*(\*?)\s*(?:Connect state|Connection)\s*:\s*(.+)$/im)
  if (connectLine) {
    var value = connectLine[2].trim()
    result.tunnelTestPending = connectLine[1] === "*" || value.charAt(0) === "*"
    if (value.charAt(0) === "*") value = value.substring(1).trim()
    var stripped = true
    while (stripped) {
      stripped = false
      var next = value
        .replace(/\s*\(checking the connection\)\s*$/i, function() {
          result.tunnelTestPending = true
          return ""
        })
        .replace(/\s*\(network interference detected\)\s*$/i, function() {
          result.networkInterference = true
          return ""
        })
        .replace(/\s*\[Network interference\]\s*$/i, function() {
          result.networkInterference = true
          return ""
        })
      if (next !== value) {
        value = next.trim()
        stripped = true
      }
    }
    // 2.24 said "Connected: City"; 2.25 says "Connected to City".
    var parts = value.match(/^(Connected|Connecting|Disconnecting|Disconnected|Error)(?:\s*(?::|\bto\b)\s*(.*))?$/i)
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

// Display rows for the exit list. Entries arrive already ordered (best row,
// pinned favourites, then the CLI's region-sorted locations) and carry a
// `group` tag: "best" for the unheaded first row, "favourites" for the pinned
// rows, the region name for the rest. One header is inserted wherever that
// tag changes; entries with no group never open one. `grouped` false (the
// search result list) keeps every row flat. Header labels are the panel's
// lowercase slug form; entries are returned untouched plus their index, so
// cursor arithmetic stays against the entry list, never the display rows.
function groupLocationRows(entries, grouped) {
  var flat = grouped === false
  var rows = []
  var current = ""
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i] || {}
    var group = String(entry.group || "")
    if (!flat && group !== "" && group !== "best" && group !== current) {
      rows.push({ kind: "header", label: group === "favourites" ? "favourites" : slugify(group) })
      current = group
    }
    rows.push({ kind: "entry", entry: entry, entryIndex: i })
  }
  return rows
}

// One size like "1.24 GiB" (Qt-localized: binary i-units, possible thousands
// separators) or "0 bytes" (the 2.25 CLI's byte form) to bytes, or NaN.
function parseSize(text) {
  var match = String(text || "").trim().match(/^([\d.,  ]+)\s*([KMGTP]?i?B|bytes?)$/i)
  if (!match) return NaN
  var num = match[1].replace(/[  ]/g, "")
  if (num.indexOf(",") !== -1 && num.indexOf(".") !== -1) num = num.replace(/,/g, "")
  else num = num.replace(",", ".")
  var value = parseFloat(num)
  if (!isFinite(value)) return NaN
  var unit = match[2].toUpperCase()
  if (unit === "BYTE" || unit === "BYTES") unit = "B"
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

// Terminal-style shorthand for a normalized protocol base ("wireguard" → "wg").
function protocolShortName(value) {
  var map = { wireguard: "wg", udp: "udp", tcp: "tcp", stealth: "stealth", wstunnel: "ws" }
  return map[protocolBase(value)] || ""
}

// The status line's "Protocol: WireGuard:443" value → "wg/443".
function protocolStatusShort(value) {
  var raw = String(value || "").trim()
  if (raw === "") return ""
  var parts = raw.split(":")
  var map = { wireguard: "wg", udp: "udp", tcp: "tcp", stealth: "stealth", wstunnel: "ws" }
  var name = map[parts[0].trim().toLowerCase()] || markupSafe(parts[0]).trim().toLowerCase()
  var port = parts.length > 1 ? parts[1].replace(/\D/g, "") : ""
  return port !== "" ? name + "/" + port : name
}

// Lowercase, dash-joined display form: "Washington DC" → "washington-dc".
function slugify(value) {
  return markupSafe(value).toLowerCase().trim().replace(/\s+/g, "-")
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

// updateEntryInline replaces the whole widget entry with the settings object
// it is handed, so an automatic write made before the bar has injected that
// entry would delete every other key. Only the last-city label is saved
// without a user action; require a settled panel session and a real change.
function shouldPersistLastLocation(stored, live, sessionReady) {
  if (sessionReady !== true) return false
  var next = String(live === undefined || live === null ? "" : live).trim()
  if (next === "") return false
  var current = String(stored === undefined || stored === null ? "" : stored)
  return current !== next
}
