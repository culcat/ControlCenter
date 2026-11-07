import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "ControlCenterModel.js" as Model

Panel {
  id: root
  moduleName: "aleksandr.control-center"
  ipcTarget: "aleksandr.control-center"
  manageIpc: false

  // --- Theme & Typography tokens ---
  readonly property color fg: bar ? bar.foreground : Commons.Color.popups.text
  readonly property color bg: Commons.Color.popups.background
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dimFg: Qt.rgba(fg.r, fg.g, fg.b, 0.58)
  readonly property color subtleFg: Qt.rgba(fg.r, fg.g, fg.b, 0.38)
  readonly property color cardFill: Qt.rgba(fg.r, fg.g, fg.b, 0.045)
  readonly property color cardHoverFill: Qt.rgba(fg.r, fg.g, fg.b, 0.085)
  readonly property color cardActiveFill: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
  readonly property color cardBorder: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property color cardHoverBorder: Qt.rgba(accent.r, accent.g, accent.b, 0.38)
  readonly property color badgeOnFill: accent
  readonly property color badgeOnText: Commons.Color.popups.background
  readonly property color badgeOffFill: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color badgeOffText: Qt.rgba(fg.r, fg.g, fg.b, 0.82)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string uiFontFamily: "Inter, Noto Sans, Liberation Sans, sans-serif"
  readonly property int bentoRadius: Math.max(Style.cornerRadius, Style.space(12))

  // --- Navigation state ---
  // "main" | "wifi" | "bluetooth" | "audio" | "display"
  property string currentPage: "main"
  readonly property bool showMediaAlways: setting("showMediaAlways", true) !== false

  // --- Audio (PipeWire) state ---
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  property string volumeSinkName: ""
  property real wheelAccumulator: 0

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && !n.isSink && !n.isStream && Model.isAudioSource(n)) {
        if ((n.name || "") === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && n.isStream && Model.isPlaybackStream(n) && n.audio) {
        if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
        list.push(n)
      }
    }
    return list
  }

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.candidateStreams }

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  readonly property real outputVolume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false
  readonly property string activeSinkLabel: Model.friendlyDeviceLabel(volumeSink || sink)

  onSinkChanged: resolveVolumeSink()

  function resolveVolumeSink() {
    if (!volumeSinkProc.running) volumeSinkProc.running = true
  }

  function outputIcon(vol) {
    if (!sink || !sink.audio) return ""
    if (Model.isHeadphones(sink)) return "󰋋"
    if (outputMuted) return ""
    var v = vol === undefined ? outputVolume : vol
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio) return outputVolume
    var clamped = Math.max(0, Math.min(1, v))
    volumeSink.audio.volume = clamped
    return clamped
  }

  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached(["omarchy-audio-output-set-default", String(node.id), String(node.name)])
    }
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached(["omarchy-audio-input-set-default", String(node.id), String(node.name)])
    }
  }

  function showVolumeOsd(vol) {
    Quickshell.execDetached([
      "omarchy-shell", "shell", "summon", "omarchy.osd",
      JSON.stringify({ icon: outputIcon(vol), value: Math.round(vol * 100) })
    ])
  }

  // --- Network & Wi-Fi state ---
  readonly property bool nmAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: {
    for (var i = 0; i < netDevices.length; i++) {
      if (netDevices[i] && netDevices[i].type === DeviceType.Wifi) return netDevices[i]
    }
    return null
  }
  readonly property bool wifiEnabled: nmAvailable ? !!Networking.wifiEnabled : false
  readonly property var wifiRawNetworks: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property var wifiRows: Model.wifiNetworkRows(wifiRawNetworks)
  readonly property var connectedWifiRow: {
    for (var i = 0; i < wifiRows.length; i++) {
      if (wifiRows[i].connected) return wifiRows[i]
    }
    return null
  }
  readonly property string connectedWifiSsid: connectedWifiRow ? connectedWifiRow.ssid : ""
  property var netInfo: ({})
  property string dnsProvider: "DHCP"
  property string wifiPasswordSsid: ""
  property string wifiPasswordText: ""
  readonly property bool vpnActive: {
    var iface = String(netInfo.iface || "")
    return iface.indexOf("amn") === 0 || iface.indexOf("tun") === 0 || iface.indexOf("wg") === 0 || iface.indexOf("tailscale") === 0
  }
  readonly property string wifiSubtitle: {
    if (!wifiEnabled) return "Выкл."
    if (connectedWifiSsid) return connectedWifiSsid
    return "Вкл."
  }
  readonly property string vpnSubtitle: {
    var ip = String(netInfo.ip || "")
    var ping = Number(netInfo.internet_ping_ms || -1)
    if (vpnActive) {
      return (ip || "Активен") + (ping > 0 ? " · " + Math.round(ping) + " мс" : "")
    }
    if (ip) return ip + (ping > 0 ? " · " + Math.round(ping) + " мс" : "")
    return connectedWifiSsid ? "Подключено" : "Нет сети"
  }

  function toggleWifi() {
    if (!nmAvailable) return
    Networking.wifiEnabled = !Networking.wifiEnabled
    Qt.callLater(refreshNetwork)
  }

  function connectWifiRow(row) {
    if (!row || !row.netObj) return
    if (row.connected) {
      if (typeof row.netObj.disconnect === "function") row.netObj.disconnect()
      else Quickshell.execDetached(["nmcli", "connection", "down", row.ssid])
      return
    }
    if (row.secure && !row.known) {
      if (wifiPasswordSsid === row.ssid) {
        wifiPasswordSsid = ""
        wifiPasswordText = ""
      } else {
        wifiPasswordSsid = row.ssid
        wifiPasswordText = ""
      }
      return
    }
    if (typeof row.netObj.connect === "function") row.netObj.connect()
    else Quickshell.execDetached(["nmcli", "device", "wifi", "connect", row.ssid])
  }

  function submitWifiPassword(ssid, password) {
    if (!ssid || !password) return
    wifiPasswordSsid = ""
    wifiPasswordText = ""
    Quickshell.execDetached(["nmcli", "device", "wifi", "connect", ssid, "password", password])
  }

  function setDnsProvider(provider) {
    dnsProvider = provider
    Quickshell.execDetached(["omarchy-dns", provider])
  }

  // --- Bluetooth state ---
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btEnabled: btAdapter ? !!btAdapter.enabled : false
  readonly property bool btDiscovering: btAdapter ? !!btAdapter.discovering : false
  readonly property var btDevicesRaw: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var btGroups: Model.bluetoothDeviceLists(btDevicesRaw)
  readonly property var btConnected: btGroups.connected || []
  readonly property var btPaired: btGroups.paired || []
  readonly property var btDiscovered: btGroups.discovered || []
  property var btPending: ({})

  readonly property string btSubtitle: {
    if (!btAdapter) return "Нет адаптера"
    if (!btEnabled) return "Выкл."
    if (btConnected.length === 1) return btConnected[0].name
    if (btConnected.length > 1) return btConnected.length + " устр."
    return "Вкл."
  }

  function toggleBluetooth() {
    if (!btAdapter) return
    btAdapter.enabled = !btAdapter.enabled
  }

  function toggleBtScan() {
    if (!btAdapter || !btAdapter.enabled) return
    Quickshell.execDetached(["bluetoothctl", btDiscovering ? "--timeout=1" : "--timeout=15", "scan", btDiscovering ? "off" : "on"])
  }

  function toggleBtDevice(row) {
    if (!row || !row.address) return
    var action = row.connected ? "disconnect" : (row.paired ? "connect" : "pair")
    var copy = Object.assign({}, btPending)
    copy[row.address] = row.connected ? "Отключение…" : "Подключение…"
    btPending = copy
    btPendingClearTimer.restart()
    Quickshell.execDetached(["omarchy-bluetooth-device", action, row.address])
  }

  Timer {
    id: btPendingClearTimer
    interval: 4500
    repeat: false
    onTriggered: root.btPending = ({})
  }

  // --- Focus (DND), Night Light, Stay Awake state ---
  readonly property string homeDir: Quickshell.env("HOME")
  property bool dndEnabled: false
  property bool nightlightEnabled: false
  property int nightlightTemp: 6500
  property bool stayAwake: false

  function toggleDnd() {
    dndEnabled = !dndEnabled
    Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", dndEnabled ? "true" : "false"])
  }

  function toggleNightlight() {
    nightlightEnabled = !nightlightEnabled
    nightlightTemp = nightlightEnabled ? 4000 : 6500
    Quickshell.execDetached(["omarchy-shell", "nightlight", nightlightEnabled ? "enable" : "disable"])
  }

  function toggleStayAwake() {
    stayAwake = !stayAwake
    Quickshell.execDetached(["omarchy-shell", "idle", stayAwake ? "disable" : "enable"])
  }

  FileView {
    id: dndFileWatcher
    path: root.homeDir + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.dndEnabled = parsed.dnd === true
      } catch (e) {}
    }
    onFileChanged: reload()
  }

  FileView {
    id: stayAwakeDirWatcher
    path: root.homeDir + "/.local/state/omarchy/indicators"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshToggles()
  }

  // --- Display / Brightness / Scale / Text Size state ---
  property bool brightnessAvailable: true
  property int brightnessPercent: 100
  property int pendingBrightnessPercent: 100
  property bool brightnessSetQueued: false
  property string focusedMonitor: ""
  property string monitorScale: "1.6"
  property var displays: []
  readonly property var scalePresets: ["1", "1.25", "1.6", "2"]
  readonly property var textSizeStops: [10, 11, 12, 14, 16, 18, 20]

  function setBrightness(val) {
    var pct = Model.clampBrightness(val)
    brightnessPercent = pct
    pendingBrightnessPercent = pct
    if (setBrightnessProc.running) {
      brightnessSetQueued = true
      return
    }
    brightnessSetQueued = false
    var cmd = ["omarchy-brightness-display", "--no-osd"]
    if (focusedMonitor) {
      cmd.push("--monitor")
      cmd.push(focusedMonitor)
    }
    cmd.push(pct + "%")
    setBrightnessProc.command = cmd
    setBrightnessProc.running = true
  }

  function setDisplayScale(scale) {
    monitorScale = String(scale)
    Quickshell.execDetached(["bash", "-lc", "omarchy-hyprland-monitor-scaling " + Util.shellQuote(String(scale))])
  }

  function setTextSizePx(px) {
    Quickshell.execDetached(["omarchy-display-text-size", String(px)])
  }

  // --- Power Profiles, Battery & System Telemetry state ---
  readonly property bool batteryPresent: !!(UPower.displayDevice && UPower.displayDevice.isPresent)
  readonly property int batteryPercent: {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return 0
    var p = Number(d.percentage || 0)
    return Math.round(p <= 1 && p > 0 ? p * 100 : p)
  }
  readonly property bool batteryCharging: !!(UPower.displayDevice && UPower.displayDevice.isPresent && !UPower.onBattery)
  property var powerProfiles: ["power-saver", "balanced", "performance"]
  property string activePowerProfile: "performance"
  property string sysCpu: "0%"
  property string sysMem: ""
  readonly property string sysMemShort: {
    var parts = String(sysMem || "").split("/")
    return parts.length > 0 ? parts[0].trim() : ""
  }

  function setPowerProfile(profile) {
    if (!profile) return
    activePowerProfile = profile
    var mode = (batteryPresent && UPower.onBattery) ? "battery" : "ac"
    Quickshell.execDetached(["omarchy-powerprofiles-set", mode, profile])
  }

  // --- Media Player (MPRIS) state ---
  readonly property var mprisPlayers: {
    var raw = Mpris.players ? Mpris.players.values : []
    var list = []
    for (var i = 0; i < raw.length; i++) {
      var p = raw[i]
      if (p && (p.trackTitle || p.trackArtist || p.isPlaying || p.canPlay)) list.push(p)
    }
    return list
  }
  property int selectedPlayerIndex: 0
  readonly property var activePlayer: {
    if (mprisPlayers.length === 0) return null
    for (var i = 0; i < mprisPlayers.length; i++) {
      if (mprisPlayers[i].isPlaying) return mprisPlayers[i]
    }
    var idx = Math.max(0, Math.min(selectedPlayerIndex, mprisPlayers.length - 1))
    return mprisPlayers[idx]
  }
  readonly property bool hasMedia: activePlayer !== null
  readonly property string mediaTitle: activePlayer && activePlayer.trackTitle ? String(activePlayer.trackTitle) : "Не воспроизводится"
  readonly property string mediaArtist: {
    if (!activePlayer) return "Медиаплеер"
    var artist = String(activePlayer.trackArtist || "").trim()
    var app = String(activePlayer.identity || activePlayer.desktopEntry || "").trim()
    if (artist && app) return artist + " · " + app
    return artist || app || "Медиа"
  }
  readonly property string mediaArtUrl: activePlayer && activePlayer.trackArtUrl ? String(activePlayer.trackArtUrl) : ""
  readonly property bool mediaPlaying: !!(activePlayer && activePlayer.isPlaying)

  function cycleMediaPlayer() {
    if (mprisPlayers.length <= 1) return
    selectedPlayerIndex = (selectedPlayerIndex + 1) % mprisPlayers.length
  }

  // --- Refresh & Background Processes ---
  function refreshAll() {
    refreshMonitor()
    refreshNetwork()
    refreshPower()
    refreshToggles()
    resolveVolumeSink()
  }

  function refreshMonitor() {
    if (!monitorStateProc.running) monitorStateProc.running = true
  }

  function refreshNetwork() {
    if (!netStatusProc.running) netStatusProc.running = true
    if (!dnsStatusProc.running) dnsStatusProc.running = true
    if (opened && wifiDevice) wifiDevice.scannerEnabled = true
  }

  function refreshPower() {
    if (!profilesProc.running) profilesProc.running = true
    if (!sysStatsProc.running) sysStatsProc.running = true
  }

  function refreshToggles() {
    if (!togglesProbeProc.running) togglesProbeProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      currentPage = "main"
      wifiPasswordSsid = ""
      wifiPasswordText = ""
      refreshAll()
    } else {
      if (wifiDevice) wifiDevice.scannerEnabled = false
    }
  }

  Component.onCompleted: refreshAll()

  Timer {
    interval: 4000
    running: root.opened
    repeat: true
    onTriggered: root.refreshAll()
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.resolveVolumeSink()
  }

  Process {
    id: volumeSinkProc
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.volumeSinkName = String(text || "").trim()
    }
  }

  Process {
    id: monitorStateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseMonitorState(text)
        root.brightnessAvailable = parsed.brightnessAvailable
        if (!setBrightnessProc.running) root.brightnessPercent = parsed.brightnessPercent
        root.focusedMonitor = parsed.focusedMonitor
        root.monitorScale = parsed.monitorScale
        root.displays = parsed.displays
      }
    }
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (!running && root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: netStatusProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.netInfo = Model.parseKeyValue(text)
    }
  }

  Process {
    id: dnsStatusProc
    command: ["omarchy-dns"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = String(text || "").trim()
        if (d) root.dnsProvider = d
      }
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseProfiles(text)
        if (parsed.profiles.length > 0) {
          root.powerProfiles = parsed.profiles
          root.activePowerProfile = parsed.activeProfile
        }
      }
    }
  }

  Process {
    id: sysStatsProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var kv = Model.parseKeyValue(text)
        if (kv.cpu) root.sysCpu = kv.cpu
        if (kv.memory) root.sysMem = kv.memory
      }
    }
  }

  Process {
    id: togglesProbeProc
    command: [
      "bash", "-c",
      "dnd=$(omarchy-shell notifications dndState 2>/dev/null || echo off); " +
      "nl=$(omarchy-shell nightlight status 2>/dev/null || echo '{}'); " +
      "sa=$([[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]] && echo yes || echo no); " +
      "printf '%s\\n%s\\n%s\\n' \"$dnd\" \"$nl\" \"$sa\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var dndRaw = String(lines[0] || "").trim()
        if (dndRaw === "on" || dndRaw === "off") root.dndEnabled = (dndRaw === "on")
        try {
          var nlJson = JSON.parse(String(lines[1] || "{}"))
          if (nlJson.enabled !== undefined) root.nightlightEnabled = !!nlJson.enabled
          if (nlJson.temperature) root.nightlightTemp = Number(nlJson.temperature)
        } catch (e) {}
        var saRaw = String(lines[2] || "").trim()
        if (saRaw === "yes" || saRaw === "no") root.stayAwake = (saRaw === "yes")
      }
    }
  }

  // --- IPC Handler ---
  IpcHandler {
    target: "aleksandr.control-center"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function openPage(page: string) {
      root.open()
      root.currentPage = page || "main"
    }
  }

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // --- Top Bar Button (macOS two-switches icon) ---
  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    tooltipText: "Пункт управления · Звук " + (root.outputMuted ? "Выкл." : Math.round(root.outputVolume * 100) + "%")
      + (root.connectedWifiSsid ? " · " + root.connectedWifiSsid : "")

    iconComponent: Component {
      Item {
        id: switchGlyph
        readonly property color glyphColor: barButton.active && barButton.useActiveColor
          ? barButton.activeColor
          : barButton.foreground
        readonly property int pillH: Math.max(5, Math.round(height * 0.38))
        readonly property int pillW: Math.max(12, Math.round(width * 0.94))
        readonly property int knobD: Math.max(3, pillH - 2)

        // Top switch (ON — knob on right, filled pill)
        Rectangle {
          width: switchGlyph.pillW
          height: switchGlyph.pillH
          radius: height / 2
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(parent.height * 0.12)
          color: Qt.rgba(switchGlyph.glyphColor.r, switchGlyph.glyphColor.g, switchGlyph.glyphColor.b, 0.28)
          border.width: 1.2
          border.color: switchGlyph.glyphColor

          Rectangle {
            width: switchGlyph.knobD
            height: switchGlyph.knobD
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 1
            color: switchGlyph.glyphColor
          }
        }

        // Bottom switch (OFF — knob on left)
        Rectangle {
          width: switchGlyph.pillW
          height: switchGlyph.pillH
          radius: height / 2
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(parent.height - switchGlyph.pillH - parent.height * 0.12)
          color: "transparent"
          border.width: 1.2
          border.color: switchGlyph.glyphColor

          Rectangle {
            width: switchGlyph.knobD
            height: switchGlyph.knobD
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 1
            color: switchGlyph.glyphColor
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.toggleOutputMute()
      } else {
        root.toggle()
      }
    }

    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var vol = root.setOutputVolume(root.outputVolume + wheel.steps * 0.05)
      root.showVolumeOsd(vol)
    }
  }

  // --- Main Floating Control Center Panel ---
  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(14)
    contentWidth: panel.fittedContentWidth(Style.space(384))
    contentHeight: panel.fittedContentHeight(activePageContainer.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.currentPage !== "main") {
          root.currentPage = "main"
        } else {
          root.close()
        }
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Item {
        id: activePageContainer
        width: parent.width
        implicitHeight: root.currentPage === "main" ? mainColumn.implicitHeight : subPageColumn.implicitHeight

        // =====================================================================
        // MAIN BENTO GRID VIEW
        // =====================================================================
        Column {
          id: mainColumn
          visible: root.currentPage === "main"
          width: parent.width
          spacing: Style.space(10)

          // --- ROW 1: Top 2x2 Bento Grid (Connectivity Left | Focus + NightLight/StayAwake Right) ---
          Row {
            id: topBentoRow
            width: parent.width
            spacing: Style.space(10)
            readonly property real colWidth: Math.floor((width - spacing) / 2)
            readonly property int bentoHeight: Style.space(162)

            // LEFT CARD: Connectivity (Wi-Fi, Bluetooth, VPN/Network)
            BentoCard {
              width: topBentoRow.colWidth
              height: topBentoRow.bentoHeight
              padding: Style.space(10)

              Column {
                anchors.fill: parent
                spacing: Style.space(6)
                readonly property real rowH: Math.floor((height - spacing * 2) / 3)

                // 1. Wi-Fi Row
                ConnectivityRow {
                  width: parent.width
                  height: parent.rowH
                  iconText: root.wifiEnabled ? (root.connectedWifiRow ? root.connectedWifiRow.glyph : "󰤨") : "󰤭"
                  title: "Wi-Fi"
                  subtitle: root.wifiSubtitle
                  active: root.wifiEnabled
                  hasChevron: true
                  onIconClicked: root.toggleWifi()
                  onRowClicked: {
                    root.refreshNetwork()
                    root.currentPage = "wifi"
                  }
                }

                // 2. Bluetooth Row
                ConnectivityRow {
                  width: parent.width
                  height: parent.rowH
                  iconText: !root.btEnabled ? "󰂲" : (root.btConnected.length > 0 ? "󰂱" : "󰂯")
                  title: "Bluetooth"
                  subtitle: root.btSubtitle
                  active: root.btEnabled
                  hasChevron: true
                  onIconClicked: root.toggleBluetooth()
                  onRowClicked: root.currentPage = "bluetooth"
                }

                // 3. VPN / Network Row
                ConnectivityRow {
                  width: parent.width
                  height: parent.rowH
                  iconText: root.vpnActive ? "󰖂" : "󰈀"
                  title: root.vpnActive ? ("VPN · " + String(root.netInfo.iface || "tun")) : "Сеть"
                  subtitle: root.vpnSubtitle
                  active: root.vpnActive || !!root.netInfo.ip
                  hasChevron: true
                  onIconClicked: {
                    root.refreshNetwork()
                    root.currentPage = "wifi"
                  }
                  onRowClicked: {
                    root.refreshNetwork()
                    root.currentPage = "wifi"
                  }
                }
              }
            }

            // RIGHT COLUMN: Focus (Top) + Night Light & Stay Awake (Bottom)
            Column {
              width: topBentoRow.colWidth
              height: topBentoRow.bentoHeight
              spacing: Style.space(10)
              readonly property int halfHeight: Math.floor((height - spacing) / 2)

              // Top Right: Do Not Disturb (Focus)
              BentoCard {
                width: parent.width
                height: parent.halfHeight
                active: root.dndEnabled
                clickable: true
                onClicked: root.toggleDnd()

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  CircleBadge {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Style.space(34)
                    iconText: root.dndEnabled ? "󰂛" : "󰂚"
                    active: root.dndEnabled
                    interactive: false
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(44)
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: "Не беспокоить"
                      color: root.fg
                      font.family: root.uiFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: root.dndEnabled ? "Включено" : "Выкл."
                      color: root.dndEnabled ? root.accent : root.dimFg
                      font.family: root.uiFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }

              // Bottom Right: 2 Square Mini-Tiles (Night Light + Stay Awake)
              Row {
                width: parent.width
                height: parent.halfHeight
                spacing: Style.space(10)
                readonly property real miniWidth: Math.floor((width - spacing) / 2)

                // Mini-Tile 1: Night Light
                BentoCard {
                  width: parent.miniWidth
                  height: parent.height
                  active: root.nightlightEnabled
                  clickable: true
                  onClicked: root.toggleNightlight()

                  Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(10)
                    spacing: Style.space(4)

                    CircleBadge {
                      anchors.horizontalCenter: parent.horizontalCenter
                      size: Style.space(28)
                      iconText: "󰔎"
                      active: root.nightlightEnabled
                      interactive: false
                    }

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: "Ночной свет"
                      color: root.fg
                      font.family: root.uiFontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }
                  }
                }

                // Mini-Tile 2: Stay Awake (Caffeine)
                BentoCard {
                  width: parent.miniWidth
                  height: parent.height
                  active: root.stayAwake
                  clickable: true
                  onClicked: root.toggleStayAwake()

                  Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(10)
                    spacing: Style.space(4)

                    CircleBadge {
                      anchors.horizontalCenter: parent.horizontalCenter
                      size: Style.space(28)
                      iconText: "󰅶"
                      active: root.stayAwake
                      interactive: false
                    }

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: "Не спать"
                      color: root.fg
                      font.family: root.uiFontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }

          // --- ROW 2: Power Profile & System Telemetry Bento Card ---
          BentoCard {
            width: parent.width
            implicitHeight: powerCardCol.implicitHeight + Style.space(20)
            padding: Style.space(10)

            Column {
              id: powerCardCol
              width: parent.width
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Style.space(18)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "ПИТАНИЕ И РЕЖИМ"
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }

                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.batteryPresent
                    ? ((root.batteryCharging ? "󰂄 " : "󰁹 ") + root.batteryPercent + "% · CPU " + root.sysCpu)
                    : ("CPU " + root.sysCpu + (root.sysMemShort ? " · RAM " + root.sysMemShort : ""))
                  color: root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Row {
                id: profileSegmentRow
                width: parent.width
                spacing: Style.space(6)
                readonly property real pillW: root.powerProfiles.length > 0
                  ? Math.floor((width - spacing * (root.powerProfiles.length - 1)) / root.powerProfiles.length)
                  : width

                Repeater {
                  model: root.powerProfiles
                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool isCurrent: String(modelData) === root.activePowerProfile
                    width: profileSegmentRow.pillW
                    height: Style.space(30)
                    radius: Math.max(Style.space(8), Style.cornerRadius)
                    color: isCurrent
                      ? root.badgeOnFill
                      : (profMouse.containsMouse ? root.cardHoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06))
                    border.width: isCurrent ? 0 : 1
                    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(5)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.profileIcon(modelData)
                        color: isCurrent ? root.badgeOnText : root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.profileLabelRu(modelData)
                        color: isCurrent ? root.badgeOnText : root.fg
                        font.family: root.uiFontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: isCurrent ? Font.DemiBold : Font.Medium
                      }
                    }

                    MouseArea {
                      id: profMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setPowerProfile(String(modelData))
                    }
                  }
                }
              }
            }
          }

          // --- ROW 3: Display Brightness & Scale Card ---
          BentoCard {
            width: parent.width
            implicitHeight: displayCardCol.implicitHeight + Style.space(20)
            padding: Style.space(10)

            Column {
              id: displayCardCol
              width: parent.width
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Style.space(20)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "ЭКРАН"
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }

                SubPagePillButton {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: (root.brightnessAvailable
                    ? Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "% · "
                    : "") + root.monitorScale + "x ›"
                  onClicked: {
                    root.refreshMonitor()
                    root.currentPage = "display"
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(10)

                CircleBadge {
                  id: sunBadge
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(28)
                  iconText: "󰃠"
                  active: root.brightnessPercent >= 50
                  onClicked: root.setBrightness(root.brightnessPercent >= 75 ? 35 : 100)
                }

                PanelSlider {
                  id: brightnessSlider
                  bar: root.bar
                  width: parent.width - sunBadge.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  minimum: 1
                  maximum: 100
                  step: 5
                  integer: true
                  value: root.brightnessPercent
                  onMoved: function(v) { root.setBrightness(v) }
                }
              }
            }
          }

          // --- ROW 4: Sound & Output Device Card ---
          BentoCard {
            width: parent.width
            implicitHeight: soundCardCol.implicitHeight + Style.space(20)
            padding: Style.space(10)

            Column {
              id: soundCardCol
              width: parent.width
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Style.space(20)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "ЗВУК"
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }

                SubPagePillButton {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  maxWidth: parent.width * 0.72
                  text: root.activeSinkLabel + " · "
                    + (root.outputMuted ? "Выкл." : Math.round((volumeSlider.dragging ? volumeSlider.liveValue : root.outputVolume) * 100) + "%")
                    + " ›"
                  onClicked: root.currentPage = "audio"
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(10)

                CircleBadge {
                  id: volBadge
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(28)
                  iconText: root.outputIcon(volumeSlider.dragging ? volumeSlider.liveValue : root.outputVolume)
                  active: !root.outputMuted && root.outputVolume > 0
                  onClicked: root.toggleOutputMute()
                }

                PanelSlider {
                  id: volumeSlider
                  bar: root.bar
                  width: parent.width - volBadge.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.outputVolume
                  onMoved: function(v) { root.setOutputVolume(v) }
                  onRightClicked: root.toggleOutputMute()
                }
              }
            }
          }

          // --- ROW 5: Now Playing (MPRIS Media Card) ---
          BentoCard {
            visible: root.hasMedia || root.showMediaAlways
            width: parent.width
            height: Style.space(66)
            padding: Style.space(10)

            Row {
              anchors.fill: parent
              spacing: Style.space(10)

              // Album Art or Music Glyph
              Rectangle {
                id: artBox
                width: Style.space(46)
                height: Style.space(46)
                anchors.verticalCenter: parent.verticalCenter
                radius: Math.max(Style.space(10), Style.cornerRadius)
                color: root.mediaPlaying ? root.cardActiveFill : root.badgeOffFill
                border.width: 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
                clip: true

                Image {
                  id: albumArtImg
                  anchors.fill: parent
                  visible: root.mediaArtUrl !== "" && status === Image.Ready
                  source: root.mediaArtUrl
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  smooth: true
                }

                Text {
                  anchors.centerIn: parent
                  visible: !albumArtImg.visible
                  text: root.mediaPlaying ? "󰎈" : "󰎆"
                  color: root.mediaPlaying ? root.accent : root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: root.mprisPlayers.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.cycleMediaPlayer()
                }
              }

              // Track Title & Artist
              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - artBox.width - mediaControlsRow.width - parent.spacing * 2
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: root.mediaTitle
                  color: root.hasMedia ? root.fg : root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.mediaArtist + (root.mprisPlayers.length > 1 ? " (" + (root.selectedPlayerIndex + 1) + "/" + root.mprisPlayers.length + ")" : "")
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                MouseArea {
                  width: parent.width
                  height: parent.height
                  visible: root.mprisPlayers.length > 1
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.cycleMediaPlayer()
                }
              }

              // Transport Controls (Prev / Play-Pause / Next)
              Row {
                id: mediaControlsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                MediaIconButton {
                  iconText: "󰒮"
                  enabled: !!(root.activePlayer && root.activePlayer.canGoPrevious)
                  onClicked: if (root.activePlayer) root.activePlayer.previous()
                }

                MediaIconButton {
                  iconText: root.mediaPlaying ? "󰏤" : "󰐊"
                  prominent: root.hasMedia
                  enabled: !!(root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause))
                  onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                }

                MediaIconButton {
                  iconText: "󰒭"
                  enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
                  onClicked: if (root.activePlayer) root.activePlayer.next()
                }
              }
            }
          }

          // --- ROW 6: Quick Actions Footer Strip ---
          Row {
            id: footerActionsRow
            width: parent.width
            spacing: Style.space(8)
            readonly property real actionW: Math.floor((width - spacing * 3) / 4)

            QuickActionPill {
              width: footerActionsRow.actionW
              iconText: "󰄀"
              label: "Скриншот"
              onClicked: {
                root.close()
                Quickshell.execDetached(["bash", "-lc", "sleep 0.18 && omarchy-capture-screenshot"])
              }
            }

            QuickActionPill {
              width: footerActionsRow.actionW
              iconText: "󰕧"
              label: "Запись"
              onClicked: {
                root.close()
                Quickshell.execDetached(["bash", "-lc", "sleep 0.18 && omarchy-screenrecord"])
              }
            }

            QuickActionPill {
              width: footerActionsRow.actionW
              iconText: "󰸌"
              label: "Стиль"
              onClicked: {
                root.close()
                Quickshell.execDetached(["omarchy-menu", "toggle", "style"])
              }
            }

            QuickActionPill {
              width: footerActionsRow.actionW
              iconText: "󰌾"
              label: "Блок."
              onClicked: {
                root.close()
                Quickshell.execDetached(["omarchy-system-lock"])
              }
            }
          }
        }

        // =====================================================================
        // SUB-PAGE DRILL-DOWN VIEWS ("wifi", "bluetooth", "audio", "display")
        // =====================================================================
        Column {
          id: subPageColumn
          visible: root.currentPage !== "main"
          width: parent.width
          spacing: Style.space(10)

          // Sub-page Navigation Header
          Item {
            width: parent.width
            height: Style.space(32)

            Rectangle {
              id: backBtn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(28)
              width: backRow.implicitWidth + Style.space(16)
              radius: Math.max(Style.space(8), Style.cornerRadius)
              color: backMouse.containsMouse ? root.cardHoverFill : root.cardFill
              border.width: 1
              border.color: root.cardBorder

              Row {
                id: backRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: "‹"
                  color: root.fg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Назад"
                  color: root.fg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Medium
                }
              }

              MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentPage = "main"
              }
            }

            Text {
              anchors.centerIn: parent
              text: root.currentPage === "wifi" ? "Wi-Fi и Сеть" :
                    (root.currentPage === "bluetooth" ? "Bluetooth" :
                    (root.currentPage === "audio" ? "Звук и Микрофон" : "Экран и Текст"))
              color: root.fg
              font.family: root.uiFontFamily
              font.pixelSize: Style.font.subtitle
              font.weight: Font.DemiBold
            }

            ToggleSwitch {
              visible: root.currentPage === "wifi" || root.currentPage === "bluetooth"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.currentPage === "wifi" ? root.wifiEnabled : root.btEnabled
              foreground: root.fg
              onToggled: {
                if (root.currentPage === "wifi") root.toggleWifi()
                else if (root.currentPage === "bluetooth") root.toggleBluetooth()
              }
            }
          }

          PanelSeparator { foreground: root.fg }

          // -----------------------------------------------------------------
          // 1. WI-FI & NETWORK SUB-PAGE
          // -----------------------------------------------------------------
          Column {
            visible: root.currentPage === "wifi"
            width: parent.width
            spacing: Style.space(10)

            // Active Connection Summary Card
            BentoCard {
              width: parent.width
              implicitHeight: netSummaryCol.implicitHeight + Style.space(18)
              padding: Style.space(10)

              Column {
                id: netSummaryCol
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: "АКТИВНОЕ ПОДКЛЮЧЕНИЕ"
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }

                Text {
                  width: parent.width
                  text: (root.connectedWifiSsid ? "Wi-Fi: " + root.connectedWifiSsid : "Проводная / Туннель")
                    + (root.vpnActive ? "  ·  VPN: " + root.netInfo.iface : "")
                  color: root.fg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: "IP: " + (root.netInfo.ip || "—")
                    + (root.netInfo.internet_ping_ms ? "  ·  Пинг: " + Math.round(Number(root.netInfo.internet_ping_ms)) + " мс" : "")
                    + "  ·  DNS: " + root.dnsProvider
                  color: root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                // DNS quick selector pills
                Row {
                  width: parent.width
                  topPadding: Style.space(4)
                  spacing: Style.space(6)
                  readonly property var dnsList: ["DHCP", "Cloudflare", "Google"]
                  readonly property real dnsW: Math.floor((width - spacing * 2) / 3)

                  Repeater {
                    model: parent.dnsList
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool activeDns: root.dnsProvider.toLowerCase() === String(modelData).toLowerCase()
                      width: parent.dnsW
                      height: Style.space(26)
                      radius: Math.max(Style.space(6), Style.cornerRadius)
                      color: activeDns ? root.badgeOnFill : (dnsMouse.containsMouse ? root.cardHoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06))
                      border.width: activeDns ? 0 : 1
                      border.color: root.cardBorder

                      Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        color: activeDns ? root.badgeOnText : root.fg
                        font.family: root.uiFontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: activeDns ? Font.DemiBold : Font.Normal
                      }

                      MouseArea {
                        id: dnsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDnsProvider(String(modelData))
                      }
                    }
                  }
                }
              }
            }

            Text {
              text: "ДОСТУПНЫЕ СЕТИ WI-FI (" + root.wifiRows.length + ")"
              color: root.dimFg
              font.family: root.uiFontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Bold
              font.letterSpacing: 0.8
            }

            Flickable {
              width: parent.width
              height: Math.min(wifiListCol.implicitHeight, Style.space(320))
              contentWidth: width
              contentHeight: wifiListCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: wifiListCol
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.wifiRows
                  delegate: BentoCard {
                    required property var modelData
                    width: wifiListCol.width
                    implicitHeight: wifiItemCol.implicitHeight + Style.space(14)
                    active: modelData.connected
                    padding: Style.space(8)

                    Column {
                      id: wifiItemCol
                      width: parent.width
                      spacing: Style.space(6)

                      Item {
                        width: parent.width
                        height: Style.space(28)

                        Text {
                          id: wIcon
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.glyph
                          color: modelData.connected ? root.accent : root.fg
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.title
                        }

                        Text {
                          anchors.left: wIcon.right
                          anchors.leftMargin: Style.space(10)
                          anchors.right: wActionLabel.left
                          anchors.rightMargin: Style.space(8)
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.ssid + (modelData.secure ? "  󰌾" : "")
                          color: root.fg
                          font.family: root.uiFontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                          elide: Text.ElideRight
                        }

                        Text {
                          id: wActionLabel
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.connected ? "Подключено" : (modelData.percent + "%")
                          color: modelData.connected ? root.accent : root.dimFg
                          font.family: root.uiFontFamily
                          font.pixelSize: Style.font.caption
                          font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.connectWifiRow(modelData)
                        }
                      }

                      // Inline Password Prompt for Secured Networks
                      Row {
                        visible: root.wifiPasswordSsid === modelData.ssid
                        width: parent.width
                        spacing: Style.space(6)

                        Rectangle {
                          width: parent.width - connectPassBtn.width - parent.spacing
                          height: Style.space(28)
                          radius: Math.max(Style.space(6), Style.cornerRadius)
                          color: Qt.rgba(0, 0, 0, 0.25)
                          border.width: 1
                          border.color: root.accent

                          TextInput {
                            id: passField
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(8)
                            anchors.rightMargin: Style.space(8)
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            clip: true
                            onAccepted: root.submitWifiPassword(modelData.ssid, text)
                          }
                        }

                        Rectangle {
                          id: connectPassBtn
                          width: Style.space(56)
                          height: Style.space(28)
                          radius: Math.max(Style.space(6), Style.cornerRadius)
                          color: root.badgeOnFill

                          Text {
                            anchors.centerIn: parent
                            text: "Вход"
                            color: root.badgeOnText
                            font.family: root.uiFontFamily
                            font.pixelSize: Style.font.caption
                            font.weight: Font.DemiBold
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submitWifiPassword(modelData.ssid, passField.text)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // -----------------------------------------------------------------
          // 2. BLUETOOTH SUB-PAGE
          // -----------------------------------------------------------------
          Column {
            visible: root.currentPage === "bluetooth"
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              height: Style.space(26)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.btEnabled
                  ? ("УСТРОЙСТВА (" + (root.btConnected.length + root.btPaired.length + root.btDiscovered.length) + ")")
                  : "BLUETOOTH ВЫКЛЮЧЕН"
                color: root.dimFg
                font.family: root.uiFontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Bold
                font.letterSpacing: 0.8
              }

              SubPagePillButton {
                visible: root.btEnabled
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.btDiscovering ? "󰂰 Поиск…" : "󰂯 Поиск устройств"
                onClicked: root.toggleBtScan()
              }
            }

            Flickable {
              width: parent.width
              height: Math.min(btListCol.implicitHeight, Style.space(360))
              contentWidth: width
              contentHeight: btListCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: btListCol
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.btConnected.concat(root.btPaired).concat(root.btDiscovered)
                  delegate: BentoCard {
                    required property var modelData
                    width: btListCol.width
                    height: Style.space(42)
                    active: modelData.connected
                    clickable: true
                    padding: Style.space(10)
                    onClicked: root.toggleBtDevice(modelData)

                    Item {
                      anchors.fill: parent

                      Text {
                        id: btRowGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.glyph
                        color: modelData.connected ? root.accent : root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                      }

                      Text {
                        anchors.left: btRowGlyph.right
                        anchors.leftMargin: Style.space(10)
                        anchors.right: btStateText.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: root.fg
                        font.family: root.uiFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                      }

                      Text {
                        id: btStateText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.btPending[modelData.address]
                          ? root.btPending[modelData.address]
                          : (modelData.connected
                            ? ("Подключено" + (modelData.batteryAvailable ? " · " + modelData.batteryPercent + "%" : ""))
                            : (modelData.paired ? "Сопряжено" : "Подключить"))
                        color: modelData.connected ? root.accent : root.dimFg
                        font.family: root.uiFontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                      }
                    }
                  }
                }
              }
            }
          }

          // -----------------------------------------------------------------
          // 3. AUDIO & MICROPHONE SUB-PAGE
          // -----------------------------------------------------------------
          Flickable {
            visible: root.currentPage === "audio"
            width: parent.width
            height: Math.min(audioSubCol.implicitHeight, Style.space(460))
            contentWidth: width
            contentHeight: audioSubCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: audioSubCol
              width: parent.width
              spacing: Style.space(10)

              Text {
                text: "УСТРОЙСТВА ВЫВОДА"
                color: root.dimFg
                font.family: root.uiFontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Bold
                font.letterSpacing: 0.8
              }

              Repeater {
                model: root.candidateSinks
                delegate: BentoCard {
                  required property var modelData
                  readonly property bool isDefault: root.sink && modelData && root.sink.name === modelData.name
                  width: audioSubCol.width
                  height: Style.space(38)
                  active: isDefault
                  clickable: true
                  padding: Style.space(10)
                  onClicked: root.setDefaultSink(modelData)

                  Item {
                    anchors.fill: parent

                    Text {
                      id: sinkIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.sinkGlyph(modelData)
                      color: isDefault ? root.accent : root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.left: sinkIcon.right
                      anchors.leftMargin: Style.space(10)
                      anchors.right: sinkCheck.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.friendlyDeviceLabel(modelData)
                      color: root.fg
                      font.family: root.uiFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.weight: isDefault ? Font.DemiBold : Font.Normal
                      elide: Text.ElideRight
                    }

                    Text {
                      id: sinkCheck
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: isDefault ? "󰄬" : ""
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }

              // Input / Microphone Section
              Text {
                visible: root.candidateSources.length > 0 || !!root.source
                text: "МИКРОФОН (" + (root.inputMuted ? "Выкл." : Math.round(root.inputVolume * 100) + "%") + ")"
                color: root.dimFg
                font.family: root.uiFontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Bold
                font.letterSpacing: 0.8
              }

              BentoCard {
                visible: !!root.source
                width: audioSubCol.width
                height: Style.space(46)
                padding: Style.space(10)

                Row {
                  anchors.fill: parent
                  spacing: Style.space(10)

                  CircleBadge {
                    id: micBadge
                    anchors.verticalCenter: parent.verticalCenter
                    size: Style.space(28)
                    iconText: root.inputMuted ? "󰍭" : "󰍬"
                    active: !root.inputMuted
                    onClicked: root.toggleInputMute()
                  }

                  PanelSlider {
                    bar: root.bar
                    width: parent.width - micBadge.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    minimum: 0
                    maximum: 1
                    step: 0.05
                    value: root.inputVolume
                    onMoved: function(v) { root.setInputVolume(v) }
                    onRightClicked: root.toggleInputMute()
                  }
                }
              }

              Repeater {
                model: root.candidateSources
                delegate: BentoCard {
                  required property var modelData
                  readonly property bool isDefaultSrc: root.source && modelData && root.source.name === modelData.name
                  width: audioSubCol.width
                  height: Style.space(36)
                  active: isDefaultSrc
                  clickable: true
                  padding: Style.space(10)
                  onClicked: root.setDefaultSource(modelData)

                  Item {
                    anchors.fill: parent

                    Text {
                      id: srcIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.sourceGlyph(modelData)
                      color: isDefaultSrc ? root.accent : root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.left: srcIcon.right
                      anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.friendlyDeviceLabel(modelData)
                      color: root.fg
                      font.family: root.uiFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.weight: isDefaultSrc ? Font.DemiBold : Font.Normal
                      elide: Text.ElideRight
                    }
                  }
                }
              }

              // Per-App Streams Section
              Text {
                visible: root.candidateStreams.length > 0
                text: "ПРИЛОЖЕНИЯ"
                color: root.dimFg
                font.family: root.uiFontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Bold
                font.letterSpacing: 0.8
              }

              Repeater {
                model: root.candidateStreams
                delegate: BentoCard {
                  required property var modelData
                  width: audioSubCol.width
                  implicitHeight: streamCol.implicitHeight + Style.space(16)
                  padding: Style.space(8)

                  Column {
                    id: streamCol
                    width: parent.width
                    spacing: Style.space(4)

                    Item {
                      width: parent.width
                      height: Style.space(18)

                      Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.friendlyDeviceLabel(modelData)
                        color: root.fg
                        font.family: root.uiFontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.audio ? Math.round(modelData.audio.volume * 100) + "%" : ""
                        color: root.dimFg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    PanelSlider {
                      bar: root.bar
                      width: parent.width
                      minimum: 0
                      maximum: 1
                      step: 0.05
                      value: modelData.audio ? modelData.audio.volume : 1
                      onMoved: function(v) {
                        if (modelData && modelData.audio) modelData.audio.volume = v
                      }
                    }
                  }
                }
              }
            }
          }

          // -----------------------------------------------------------------
          // 4. DISPLAY & TEXT SCALE SUB-PAGE
          // -----------------------------------------------------------------
          Column {
            visible: root.currentPage === "display"
            width: parent.width
            spacing: Style.space(10)

            BentoCard {
              width: parent.width
              implicitHeight: scaleCol.implicitHeight + Style.space(20)
              padding: Style.space(10)

              Column {
                id: scaleCol
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "МАСШТАБ МОНИТОРА (" + (root.focusedMonitor || "Экран") + ")"
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }

                Row {
                  id: scalePillsRow
                  width: parent.width
                  spacing: Style.space(6)
                  readonly property real pillW: Math.floor((width - spacing * (root.scalePresets.length - 1)) / root.scalePresets.length)

                  Repeater {
                    model: root.scalePresets
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool activeScale: root.monitorScale === String(modelData)
                      width: scalePillsRow.pillW
                      height: Style.space(30)
                      radius: Math.max(Style.space(8), Style.cornerRadius)
                      color: activeScale ? root.badgeOnFill : (scaleMouse.containsMouse ? root.cardHoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06))
                      border.width: activeScale ? 0 : 1
                      border.color: root.cardBorder

                      Text {
                        anchors.centerIn: parent
                        text: String(modelData) + "x"
                        color: activeScale ? root.badgeOnText : root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.weight: activeScale ? Font.DemiBold : Font.Normal
                      }

                      MouseArea {
                        id: scaleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDisplayScale(String(modelData))
                      }
                    }
                  }
                }
              }
            }

            BentoCard {
              width: parent.width
              implicitHeight: textSizeCol.implicitHeight + Style.space(20)
              padding: Style.space(10)

              Column {
                id: textSizeCol
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "РАЗМЕР ШРИФТА ИНТЕРФЕЙСА (" + Style.font.baseSize + " px)"
                  color: root.dimFg
                  font.family: root.uiFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }

                Row {
                  id: fontPillsRow
                  width: parent.width
                  spacing: Style.space(5)
                  readonly property real pillW: Math.floor((width - spacing * (root.textSizeStops.length - 1)) / root.textSizeStops.length)

                  Repeater {
                    model: root.textSizeStops
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool activeFont: Style.font.baseSize === Number(modelData)
                      width: fontPillsRow.pillW
                      height: Style.space(28)
                      radius: Math.max(Style.space(6), Style.cornerRadius)
                      color: activeFont ? root.badgeOnFill : (fontMouse.containsMouse ? root.cardHoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06))
                      border.width: activeFont ? 0 : 1
                      border.color: root.cardBorder

                      Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        color: activeFont ? root.badgeOnText : root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: activeFont ? Font.DemiBold : Font.Normal
                      }

                      MouseArea {
                        id: fontMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setTextSizePx(Number(modelData))
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // =========================================================================
  // REUSABLE BENTO COMPONENTS
  // =========================================================================

  component BentoCard: Rectangle {
    id: bentoCard
    property bool active: false
    property bool clickable: false
    property real padding: 0
    default property alias content: innerHolder.data
    signal clicked()

    radius: root.bentoRadius
    color: active
      ? root.cardActiveFill
      : (bentoHover.hovered && clickable ? root.cardHoverFill : root.cardFill)
    border.width: 1
    border.color: active || (bentoHover.hovered && clickable) ? root.cardHoverBorder : root.cardBorder

    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 130 } }

    // Top inner glass highlight (macOS sheen)
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: 1
      anchors.leftMargin: parent.radius * 0.65
      anchors.rightMargin: parent.radius * 0.65
      height: 1
      color: Qt.rgba(1, 1, 1, 0.06)
    }

    HoverHandler { id: bentoHover }

    MouseArea {
      anchors.fill: parent
      enabled: bentoCard.clickable
      cursorShape: bentoCard.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: bentoCard.clicked()
    }

    Item {
      id: innerHolder
      anchors.fill: parent
      anchors.margins: bentoCard.padding
    }
  }

  component CircleBadge: Rectangle {
    id: badge
    property int size: Style.space(32)
    property string iconText: ""
    property bool active: false
    property bool interactive: true
    signal clicked()

    width: size
    height: size
    radius: size / 2
    color: active
      ? root.badgeOnFill
      : (badgeMouse.containsMouse && interactive ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18) : root.badgeOffFill)

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: badge.iconText
      color: badge.active ? root.badgeOnText : root.badgeOffText
      font.family: root.fontFamily
      font.pixelSize: Math.round(badge.size * 0.48)
    }

    MouseArea {
      id: badgeMouse
      anchors.fill: parent
      enabled: badge.interactive
      hoverEnabled: badge.interactive
      cursorShape: badge.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: badge.clicked()
    }
  }

  component ConnectivityRow: Item {
    id: connRow
    property string iconText: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool hasChevron: true
    signal iconClicked()
    signal rowClicked()

    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      radius: Math.max(Style.space(8), Style.cornerRadius)
      color: rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"
    }

    CircleBadge {
      id: rowBadge
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      size: Style.space(32)
      iconText: connRow.iconText
      active: connRow.active
      z: 2
      onClicked: connRow.iconClicked()
    }

    Item {
      anchors.left: rowBadge.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom

      Column {
        anchors.left: parent.left
        anchors.right: chevronLabel.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          text: connRow.title
          color: root.fg
          font.family: root.uiFontFamily
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: connRow.subtitle
          color: connRow.active ? root.accent : root.dimFg
          font.family: root.uiFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: chevronLabel
        visible: connRow.hasChevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: root.dimFg
        font.family: root.uiFontFamily
        font.pixelSize: Style.font.title
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: connRow.rowClicked()
      }
    }
  }

  component SubPagePillButton: Rectangle {
    id: pillBtn
    property string text: ""
    property real maxWidth: Style.space(230)
    signal clicked()

    height: Style.space(22)
    width: Math.min(maxWidth, pillLabel.implicitWidth + Style.space(14))
    radius: height / 2
    color: pillMouse.containsMouse ? root.cardHoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

    Text {
      id: pillLabel
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(7)
      anchors.rightMargin: Style.space(7)
      horizontalAlignment: Text.AlignHCenter
      text: pillBtn.text
      color: root.dimFg
      font.family: root.uiFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pillBtn.clicked()
    }
  }

  component MediaIconButton: Rectangle {
    id: mediaBtn
    property string iconText: ""
    property bool prominent: false
    signal clicked()

    width: prominent ? Style.space(32) : Style.space(26)
    height: prominent ? Style.space(32) : Style.space(26)
    radius: width / 2
    opacity: enabled ? 1.0 : 0.35
    color: prominent
      ? root.badgeOnFill
      : (mBtnMouse.containsMouse ? root.cardHoverFill : "transparent")

    Text {
      anchors.centerIn: parent
      text: mediaBtn.iconText
      color: mediaBtn.prominent ? root.badgeOnText : root.fg
      font.family: root.fontFamily
      font.pixelSize: mediaBtn.prominent ? Style.font.body : Style.font.bodySmall
    }

    MouseArea {
      id: mBtnMouse
      anchors.fill: parent
      enabled: mediaBtn.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mediaBtn.clicked()
    }
  }

  component QuickActionPill: BentoCard {
    id: qaPill
    property string iconText: ""
    property string label: ""

    height: Style.space(48)
    clickable: true

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(3)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: qaPill.iconText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: qaPill.label
        color: root.dimFg
        font.family: root.uiFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
