.pragma library

function parseKeyValue(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var tab = line.indexOf("\t")
    if (tab <= 0) continue
    var key = line.slice(0, tab).trim()
    var val = line.slice(tab + 1).trim()
    if (key) out[key] = val
  }
  return out
}

function clampBrightness(v) {
  var n = Math.round(Number(v))
  if (!isFinite(n)) return 0
  return Math.max(1, Math.min(100, n))
}

function normalizeScale(scale) {
  var n = Number(scale)
  if (!isFinite(n) || n <= 0) return String(scale || "1")
  return String(Math.round(n * 100) / 100)
}

function parseMonitorState(raw) {
  var lines = String(raw || "").split("\n")
  var bStr = String(lines[0] || "").trim()
  var brightnessAvailable = bStr !== "unavailable" && bStr !== "" && isFinite(parseInt(bStr, 10))
  var brightnessPercent = brightnessAvailable ? Math.max(0, Math.min(100, parseInt(bStr, 10))) : 100
  var focusedMonitor = String(lines[5] || "").trim()
  var monitorScale = normalizeScale(String(lines[6] || "1").trim())
  var displays = []
  var enabledCount = 0
  try {
    var parsed = JSON.parse(String(lines[7] || "[]").trim() || "[]")
    if (Array.isArray(parsed)) {
      displays = parsed
      for (var i = 0; i < parsed.length; i++) {
        if (parsed[i] && parsed[i].enabled) enabledCount++
      }
    }
  } catch (e) {}

  return {
    brightnessAvailable: brightnessAvailable,
    brightnessPercent: brightnessPercent,
    focusedMonitor: focusedMonitor,
    monitorScale: monitorScale,
    displays: displays,
    enabledDisplayCount: enabledCount
  }
}

function parseProfiles(raw) {
  var lines = String(raw || "").split("\n")
  var profiles = []
  var activeProfile = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    var name = String(parts[0] || "").trim()
    if (!name) continue
    profiles.push(name)
    if (String(parts[1] || "").trim() === "1") activeProfile = name
  }
  if (!activeProfile && profiles.length > 0) activeProfile = profiles[0]
  return {
    profiles: profiles,
    activeProfile: activeProfile
  }
}

function profileLabelRu(name) {
  var key = String(name || "").toLowerCase()
  if (key === "power-saver") return "Экономия"
  if (key === "balanced") return "Баланс"
  if (key === "performance") return "Максимум"
  return name ? (name.charAt(0).toUpperCase() + name.slice(1)) : "Баланс"
}

function profileIcon(name) {
  var key = String(name || "").toLowerCase()
  if (key === "power-saver") return "󰌪"
  if (key === "balanced") return "󰗑"
  if (key === "performance") return "󰓅"
  return "󰗑"
}

function isAudioSource(node) {
  if (!node || node.isSink || node.isStream) return false
  if (node.audio) return true
  var name = String(node.name || "").toLowerCase()
  return name.indexOf("alsa_input") === 0 || name.indexOf("bluez_input") === 0
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  return node.isSink === true
}

function friendlyDeviceLabel(node) {
  if (!node) return "Устройство"
  var raw = String(node.description || node.nickname || node.name || "Устройство").trim()
  raw = raw
    .replace(/\s+Analog Stereo$/i, "")
    .replace(/\s+Digital Stereo\s*\([^)]*\)$/i, "")
    .replace(/\s+Multichannel$/i, "")
    .replace(/^Built-in Audio\s+/i, "")
  return raw || "Устройство"
}

function isHeadphones(node) {
  if (!node) return false
  var s = (String(node.name || "") + " " + String(node.description || "") + " " + String(node.nickname || "")).toLowerCase()
  return s.indexOf("headphone") !== -1 || s.indexOf("headset") !== -1 || s.indexOf("airpods") !== -1 || s.indexOf("buds") !== -1 || s.indexOf("bluez") !== -1
}

function sinkGlyph(node) {
  if (!node) return ""
  var s = (String(node.name || "") + " " + String(node.description || "")).toLowerCase()
  if (s.indexOf("bluez") !== -1) return "󰂯"
  if (isHeadphones(node)) return "󰋋"
  if (s.indexOf("hdmi") !== -1 || s.indexOf("displayport") !== -1) return "󰓃"
  return ""
}

function sourceGlyph(node) {
  if (!node) return "󰍬"
  var s = (String(node.name || "") + " " + String(node.description || "")).toLowerCase()
  if (s.indexOf("bluez") !== -1 || s.indexOf("headset") !== -1) return "󰋎"
  return "󰍬"
}

function btDeviceLabel(dev) {
  if (!dev) return "Bluetooth-устройство"
  var name = String(dev.name || dev.deviceName || dev.alias || dev.address || "").trim()
  return name || "Bluetooth-устройство"
}

function btDeviceGlyph(dev) {
  if (!dev) return "󰂯"
  var icon = String(dev.icon || "").toLowerCase()
  var name = btDeviceLabel(dev).toLowerCase()
  if (icon.indexOf("audio") !== -1 || icon.indexOf("head") !== -1 || name.indexOf("airpods") !== -1 || name.indexOf("buds") !== -1 || name.indexOf("wh-") !== -1 || name.indexOf("wf-") !== -1) return "󰋋"
  if (icon.indexOf("mouse") !== -1 || name.indexOf("mouse") !== -1 || name.indexOf("mx master") !== -1) return "󰍽"
  if (icon.indexOf("keyboard") !== -1 || name.indexOf("keyboard") !== -1 || name.indexOf("keychron") !== -1 || name.indexOf("mx keys") !== -1) return "󰌌"
  if (icon.indexOf("phone") !== -1) return "󰄜"
  if (icon.indexOf("input-gaming") !== -1 || name.indexOf("controller") !== -1 || name.indexOf("dualshock") !== -1 || name.indexOf("dualsense") !== -1 || name.indexOf("xbox") !== -1) return "󰊗"
  return "󰂯"
}

function isAddressLike(s) {
  return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(String(s || "").trim())
}

function bluetoothDeviceLists(devices) {
  var connected = []
  var paired = []
  var discovered = []
  var list = devices || []
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d || !d.address) continue
    var label = btDeviceLabel(d)
    var row = {
      address: String(d.address),
      name: label,
      glyph: btDeviceGlyph(d),
      connected: !!d.connected,
      paired: !!(d.paired || d.bonded || d.trusted),
      batteryAvailable: !!(d.batteryAvailable && d.battery !== undefined && d.battery >= 0),
      batteryPercent: d.battery !== undefined ? Math.round(Number(d.battery) <= 1 ? Number(d.battery) * 100 : Number(d.battery)) : -1
    }
    if (row.connected) {
      connected.push(row)
    } else if (row.paired) {
      paired.push(row)
    } else if (!isAddressLike(label)) {
      discovered.push(row)
    }
  }
  return {
    connected: connected,
    paired: paired,
    discovered: discovered
  }
}

function wifiSignalGlyph(strength) {
  var s = Number(strength || 0)
  if (s > 1) s = s / 100.0
  if (s >= 0.75) return "󰤨"
  if (s >= 0.50) return "󰤥"
  if (s >= 0.25) return "󰤢"
  if (s > 0.0) return "󰤟"
  return "󰤯"
}

function wifiNetworkRows(rawNetworks) {
  var list = rawNetworks || []
  var bySsid = {}
  for (var i = 0; i < list.length; i++) {
    var n = list[i]
    if (!n) continue
    var ssid = String(n.ssid || n.name || "").trim()
    if (!ssid) continue
    var strength = Number(n.signalStrength !== undefined ? n.signalStrength : (n.strength || 0))
    if (strength > 1) strength = strength / 100.0
    var connected = !!n.connected
    var known = !!(n.known || n.saved || connected)
    var secure = !!(n.security && String(n.security) !== "none" && String(n.security) !== "0") || !!n.isSecure
    var existing = bySsid[ssid]
    if (!existing || connected || (!existing.connected && strength > existing.strength)) {
      bySsid[ssid] = {
        ssid: ssid,
        strength: strength,
        percent: Math.round(Math.max(0, Math.min(1, strength)) * 100),
        glyph: wifiSignalGlyph(strength),
        connected: connected,
        known: known,
        secure: secure,
        netObj: n
      }
    }
  }
  var rows = []
  for (var k in bySsid) rows.push(bySsid[k])
  rows.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    return b.strength - a.strength
  })
  return rows
}
