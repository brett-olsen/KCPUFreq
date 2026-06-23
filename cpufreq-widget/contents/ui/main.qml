import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Qt.labs.settings 1.0
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    // ── system data ───────────────────────────────────────────────────────────
    property string cpuModel:       "Reading…"
    property string boardVendor:    ""
    property string boardModel:     ""
    property string osName:         ""
    property string kernelVersion:  ""
    property string cpuDriver:      ""
    property int    coreCount:      0
    property int    coresOnline:    1
    property real   freqMin:        0
    property real   freqMax:        0
    property real   freqMinSet:     0
    property real   freqMaxSet:     0

    // Applying flags — true while waiting for kernel to confirm a user change
    property bool   applyingMin:    false
    property bool   applyingMax:    false
    property bool   applyingCores:  false
    property bool   applyingTurbo:  false

    // Target values the user requested — compared against poll to confirm
    property real   targetMin:      -1
    property real   targetMax:      -1
    property int    targetCores:    -1
    property bool   targetTurbo:    false
    property real   loadPercent:    0
    property real   memPercent:     0
    property bool   turboEnabled:   false
    property string activeGovernor: "—"
    property var    governors:      []
    property var    profiles:       []
    property var    coreFreqs:      []

    // ── user options ──────────────────────────────────────────────────────────
    property bool   rememberSettings: true
    property int    refreshSecs:      3
    property bool   showFreqInTitle:  true
    property string titleFontFamily:  "Noto Sans"
    property int    titleFontSize:    13
    property string appFontFamily:    "Noto Sans"
    property int    appFontSize:      11
    property color  tintColor:        "#5588ff"
    property string graphSize:        "large"
    property string bgStyle:          "solid"   // "solid" or "system"

    // ── graph history (updated only on poll tick) ─────────────────────────────
    property real   cpuTemp:          0
    readonly property int graphPoints: 60
    property var    histTemp:         []
    property var    histLoad:         []
    property var    histFreq:         []
    property int    graphVersion:     0   // increment to trigger canvas repaint

    // Available system fonts for dropdown
    readonly property var fontList: [
        "Noto Sans", "Sans", "DejaVu Sans", "Liberation Sans",
        "Arial", "Helvetica", "Ubuntu", "Cantarell",
        "Noto Mono", "DejaVu Sans Mono", "Liberation Mono",
        "JetBrains Mono", "Fira Code", "Hack", "Inconsolata",
        "Source Code Pro", "Courier New", "Monospace"
    ]

    // Preset tint colours
    readonly property var tintPresets: [
        { name: "Blue",    color: "#5588ff" },
        { name: "Cyan",    color: "#00bcd4" },
        { name: "Green",   color: "#44bb44" },
        { name: "Teal",    color: "#00897b" },
        { name: "Purple",  color: "#9c27b0" },
        { name: "Pink",    color: "#e91e8c" },
        { name: "Orange",  color: "#ff6d00" },
        { name: "Red",     color: "#f44336" },
        { name: "White",   color: "#dddddd" },
        { name: "Gold",    color: "#ffb300" }
    ]

    // ── persistent settings ───────────────────────────────────────────────────
    Settings {
        id: savedSettings
        category: "kcpufreq"
        property alias refreshSecs:      root.refreshSecs
        property alias showFreqInTitle:  root.showFreqInTitle
        property alias titleFontFamily:  root.titleFontFamily
        property alias titleFontSize:    root.titleFontSize
        property alias appFontFamily:    root.appFontFamily
        property alias appFontSize:      root.appFontSize
        property alias tintColor:        root.tintColor
        property alias rememberSettings: root.rememberSettings
        property alias graphSize:        root.graphSize
        property alias bgStyle:          root.bgStyle
    }

    // ── DataSource: read ──────────────────────────────────────────────────────
    P5Support.DataSource {
        id: cmdSrc
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) {
            var out  = (data["stdout"] || "").trim()
            var name = src.includes("# ") ? src.split("# ").pop() : ""
            if (name) dispatch(name, out)
            disconnectSource(src)
        }
    }

    P5Support.DataSource {
        id: execSrc
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) { disconnectSource(src) }
    }

    function runCmd(cmd) { execSrc.connectSource(cmd) }

    function dispatch(name, out) {
        if      (name === "cpuModel")    { if (out) root.cpuModel = out }
        else if (name === "boardVendor") root.boardVendor   = out
        else if (name === "boardModel")  root.boardModel    = out
        else if (name === "osName")      root.osName        = out
        else if (name === "kernelVer")   root.kernelVersion = out
        else if (name === "cpuDriver")   root.cpuDriver     = out || "N/A"
        else if (name === "governors") {
            var g = out.split(/\s+/).filter(function(s){ return s.length > 0 })
            if (g.length > 0) root.governors = g
        }
        else if (name === "profiles") {
            var p = out.split(/\s+/).filter(function(s){ return s.length > 0 })
            if (p.length > 0) root.profiles = p
        }
        else if (name === "freqMin")    { var v1 = parseFloat(out)/1000; if (v1>0) root.freqMin    = v1 }
        else if (name === "freqMax")    { var v2 = parseFloat(out)/1000; if (v2>0) root.freqMax    = v2 }
        else if (name === "freqMinSet") {
            var v3 = parseFloat(out)/1000
            if (v3 > 0) {
                root.freqMinSet = v3
                if (root.applyingMin && Math.abs(v3 - root.targetMin) < 50)
                    root.applyingMin = false
            }
        }
        else if (name === "freqMaxSet") {
            var v4 = parseFloat(out)/1000
            if (v4 > 0) {
                root.freqMaxSet = v4
                if (root.applyingMax && Math.abs(v4 - root.targetMax) < 50)
                    root.applyingMax = false
            }
        }
        else if (name === "governor")   { if (out) root.activeGovernor = out }
        else if (name === "turbo") {
            var turboOn = (out === "0")
            root.turboEnabled = turboOn
            if (root.applyingTurbo && turboOn === root.targetTurbo)
                root.applyingTurbo = false
        }
        else if (name === "cpuTemp") {
            var t = parseFloat(out)
            if (!isNaN(t) && t > 0) root.cpuTemp = t
        }
        else if (name === "coreCount") {
            var nc = parseInt(out)
            if (!isNaN(nc) && nc > 0) { root.coreCount = nc; root.coreFreqs = new Array(nc).fill(0) }
        }
        else if (name === "coresOnline") {
            var co = parseInt(out)
            if (!isNaN(co) && co > 0) {
                root.coresOnline = co
                if (root.applyingCores && co === root.targetCores)
                    root.applyingCores = false
            }
        }
        else if (name.startsWith("load_"))  { var l  = parseFloat(out); if (!isNaN(l)) root.loadPercent = Math.min(l, 100) }
        else if (name === "mem") {
            var pts = out.split(/\s+/)
            if (pts.length >= 2) { var tot = parseFloat(pts[0]), used = parseFloat(pts[1]); if (tot>0) root.memPercent = (used/tot)*100 }
        }
        else if (name.startsWith("coreFreq_")) {
            var idx = parseInt(name.split("_")[1])
            var f   = parseFloat(out) / 1000
            if (!isNaN(idx) && !isNaN(f) && f > 0) {
                var arr = root.coreFreqs.slice(); arr[idx] = f; root.coreFreqs = arr
            }
        }
    }

    function fetch(name, cmd) {
        cmdSrc.connectSource("bash -c '" + cmd.replace(/'/g, "'\\''") + "' # " + name)
    }

    function fetchAll() {
        fetch("cpuModel",    "cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | xargs")
        fetch("boardVendor", "cat /sys/class/dmi/id/board_vendor 2>/dev/null || true")
        fetch("boardModel",  "cat /sys/class/dmi/id/board_name 2>/dev/null || true")
        fetch("osName",      "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'")
        fetch("kernelVer",   "uname -r")
        fetch("cpuDriver",   "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo N/A")
        fetch("coreCount",   "nproc --all")
        fetch("governors",   "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || true")
        fetch("profiles",    "cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || echo 'powersave balanced performance'")
        fetch("freqMin",     "cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null || echo 0")
        fetch("freqMax",     "cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 0")
        fetch("freqMinSet",  "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null || echo 0")
        fetch("freqMaxSet",  "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo 0")
        fetch("governor",    "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A")
        fetch("turbo",       "cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo N/A")
        fetch("cpuTemp",     "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1 | awk '{printf \"%.0f\", $1/1000}' || echo 0")
        fetch("load_" + Date.now(), "T=/tmp/kcpufreq_stat; if [ -f $T ]; then read a b c d e f g h i j k < $T; read a2 b2 c2 d2 e2 f2 g2 h2 i2 j2 k2 < /proc/stat; dt=$(( (b2+c2+d2+e2+f2+g2+h2+i2)-(b+c+d+e+f+g+h+i) )); di=$(( (e2+f2)-(e+f) )); if [ $dt -gt 0 ]; then echo $(( (dt-di)*100/dt )); else echo 0; fi; else echo 0; fi; grep ^cpu /proc/stat | head -1 > $T")
        fetch("mem",         "free -m | awk 'NR==2{print $2,$3}'")
        fetch("coresOnline", "cat /sys/devices/system/cpu/online 2>/dev/null | sed 's/.*-//' | awk '{print $1+1}' || echo 1")
        var maxCores = root.coreCount > 0 ? root.coreCount : 16
        for (var i = 0; i < maxCores; i++)
            fetch("coreFreq_" + i, "cat /sys/devices/system/cpu/cpu" + i + "/cpufreq/scaling_cur_freq 2>/dev/null || echo 0")
    }

    Timer {
        id: pollTimer
        interval: root.refreshSecs * 1000
        repeat: true; running: true
        onTriggered: { fetchAll(); historyTimer.restart() }
    }
    onRefreshSecsChanged: { pollTimer.stop(); pollTimer.interval = root.refreshSecs * 1000; pollTimer.start() }
    Component.onCompleted: {
        root.histTemp = []; root.histLoad = []; root.histFreq = []
        fetchAll()
        historyTimer.restart()
    }

    // Push history on every poll tick — use a delayed timer so fetchAll values settle first
    Timer {
        id: historyTimer
        interval: 800   // fires 0.8s after poll tick, giving fetches time to complete
        repeat: false
        running: false
        onTriggered: {
            var avgFreq = root.freqMax > 0 && root.coreFreqs.length > 0
                ? (root.coreFreqs.reduce(function(a,b){return a+(b||0)},0) / root.coreFreqs.length) / root.freqMax * 100
                : 0
            var t = root.histTemp.slice(); t.push(root.cpuTemp > 0 ? root.cpuTemp : 0)
            if (t.length > root.graphPoints) t.shift(); root.histTemp = t

            var l = root.histLoad.slice(); l.push(root.loadPercent)
            if (l.length > root.graphPoints) l.shift(); root.histLoad = l

            var f = root.histFreq.slice(); f.push(avgFreq)
            if (f.length > root.graphPoints) f.shift(); root.histFreq = f

            root.graphVersion++
        }
    }

    function applyGovernor(gov) {
        var n = root.coreCount > 0 ? root.coreCount : 8
        for (var i = 0; i < n; i++) runCmd("pkexec cpupower -c " + i + " frequency-set -g " + gov)
    }
    function applyMinFreq(mhz) {
        var safeMhz = Math.round(Math.max(root.freqMin > 0 ? root.freqMin : 400, mhz))
        if (safeMhz <= 0 || safeMhz > 9999999) return
        root.targetMin = safeMhz
        root.applyingMin = true
        var n = root.coreCount > 0 ? root.coreCount : 8
        for (var i = 0; i < n; i++) runCmd("pkexec cpupower -c " + i + " frequency-set -d " + safeMhz + "MHz")
    }
    function applyMaxFreq(mhz) {
        var safeMhz = Math.round(Math.min(root.freqMax > 0 ? root.freqMax : 9999999, mhz))
        if (safeMhz <= 0) return
        root.targetMax = safeMhz
        root.applyingMax = true
        var n = root.coreCount > 0 ? root.coreCount : 8
        for (var i = 0; i < n; i++) runCmd("pkexec cpupower -c " + i + " frequency-set -u " + safeMhz + "MHz")
    }
    function applyCoresOnline(count) {
        var total = root.coreCount > 0 ? root.coreCount : 8
        for (var i = 1; i < total; i++) {
            var online = (i < count) ? 1 : 0
            runCmd("pkexec bash -c 'echo " + online + " > /sys/devices/system/cpu/cpu" + i + "/online'")
        }
    }
    function applyTurbo(enabled) {
        var val = enabled ? 0 : 1
        runCmd("pkexec bash -c 'echo " + val + " > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null; echo " + (enabled?1:0) + " > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null; true'")
    }

    function paintGraph(ctx, w, h) {
        if (w <= 0 || h <= 0) return
        ctx.clearRect(0, 0, w, h)
        ctx.strokeStyle = "#2a2a2a"; ctx.lineWidth = 1
        for (var g = 1; g < 4; g++) {
            var gy = Math.round(h * g / 4) + 0.5
            ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
        }
        var pts = root.graphPoints
        var maxT = Math.max(100, root.cpuTemp + 20)
        var d = root.histTemp; var n = d.length
        if (n >= 2) {
            ctx.strokeStyle = "#ff4444"; ctx.lineWidth = 1.5; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.beginPath()
            for (var i = 0; i < n; i++) { var x=w*(pts-n+i)/(pts-1); var y=Math.max(1,Math.min(h-1,h-h*Math.min(Math.max(d[i],0),maxT)/maxT)); i===0?ctx.moveTo(x,y):ctx.lineTo(x,y) }
            ctx.stroke()
        }
        d = root.histLoad; n = d.length
        if (n >= 2) {
            ctx.strokeStyle = "#44cc44"; ctx.lineWidth = 1.5; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.beginPath()
            for (var i2 = 0; i2 < n; i2++) { var x2=w*(pts-n+i2)/(pts-1); var y2=Math.max(1,Math.min(h-1,h-h*Math.min(Math.max(d[i2],0),100)/100)); i2===0?ctx.moveTo(x2,y2):ctx.lineTo(x2,y2) }
            ctx.stroke()
        }
        d = root.histFreq; n = d.length
        if (n >= 2) {
            ctx.strokeStyle = "#aa66ff"; ctx.lineWidth = 1.5; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.beginPath()
            for (var i3 = 0; i3 < n; i3++) { var x3=w*(pts-n+i3)/(pts-1); var y3=Math.max(1,Math.min(h-1,h-h*Math.min(Math.max(d[i3],0),100)/100)); i3===0?ctx.moveTo(x3,y3):ctx.lineTo(x3,y3) }
            ctx.stroke()
        }
        if (root.cpuTemp > 0) { ctx.fillStyle="#666666"; ctx.font="bold "+(root.appFontSize-2)+"px sans-serif"; ctx.textAlign="right"; ctx.textBaseline="top"; ctx.fillText(root.cpuTemp.toFixed(0)+"°C",w-2,2) }
    }

    function paintIcon(ctx, w, h, color) {
        var s = w / 64
        ctx.clearRect(0, 0, w, h)
        ctx.strokeStyle = color; ctx.lineJoin = "round"; ctx.lineCap = "round"
        ctx.lineWidth = 2.5*s; ctx.strokeRect(16*s,16*s,32*s,32*s); ctx.strokeRect(22*s,22*s,20*s,20*s)
        ctx.lineWidth = 2*s
        var pins = [23,30,37,44]
        for (var i=0;i<pins.length;i++) {
            var p=pins[i]
            ctx.beginPath(); ctx.moveTo(p*s,16*s); ctx.lineTo(p*s,10*s); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(p*s,48*s); ctx.lineTo(p*s,54*s); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(16*s,p*s); ctx.lineTo(10*s,p*s); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(48*s,p*s); ctx.lineTo(54*s,p*s); ctx.stroke()
        }
        ctx.lineWidth = 1.8*s; ctx.beginPath()
        var pts=[[23,32],[25.5,32],[27,26],[29,38],[31,26],[33,38],[35,26],[37,38],[39,32],[41,32]]
        ctx.moveTo(pts[0][0]*s,pts[0][1]*s)
        for (var j=1;j<pts.length;j++) ctx.lineTo(pts[j][0]*s,pts[j][1]*s)
        ctx.stroke()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // COMPACT — icon + freq only, NO "KCPUFreq" text
    // ─────────────────────────────────────────────────────────────────────────
    compactRepresentation: Item {
        Layout.minimumWidth: cRow.implicitWidth + 8
        Layout.minimumHeight: Kirigami.Units.iconSizes.medium
        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }
        Row {
            id: cRow
            anchors.centerIn: parent; spacing: 4
            Canvas {
                id: compactCanvas
                width: root.titleFontSize + 4
                height: root.titleFontSize + 4
                onPaint: root.paintIcon(getContext("2d"), width, height, Kirigami.Theme.textColor)
                Connections { target: root; function onTintColorChanged() { compactCanvas.requestPaint() } }
                Connections { target: root; function onTitleFontSizeChanged() { compactCanvas.requestPaint() } }
            }
            Text {
                visible: root.showFreqInTitle && root.coreFreqs.length > 0 && root.coreFreqs[0] > 0
                text: root.coreFreqs.length > 0 && root.coreFreqs[0] > 0
                      ? (root.coreFreqs[0] >= 1000
                         ? (root.coreFreqs[0]/1000).toFixed(2) + " GHz"
                         : root.coreFreqs[0].toFixed(0) + " MHz")
                      : ""
                color: Kirigami.Theme.textColor
                font.bold: true
                font.family: root.titleFontFamily
                font.pixelSize: root.titleFontSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FULL REPRESENTATION
    // ─────────────────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        width: 460
        height: Math.min(outerCol.implicitHeight + 24, 740)

        Rectangle { anchors.fill: parent; color: root.bgStyle === "solid" ? "#2a2a2a" : "transparent"; radius: 8 }

        ColumnLayout {
            id: outerCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            spacing: 0

            // ── Tabs ──────────────────────────────────────────────────────
            property int activeTab: 0

            Item { height: 8 }

            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: ["Overview", "Options"]
                    delegate: Rectangle {
                        id: tb
                        property bool active: outerCol.activeTab === index
                        Layout.fillWidth: true; height: root.appFontSize + 16
                        color: active ? "#2a2a2a" : "#222"
                        Rectangle {
                            anchors.bottom: parent.bottom; width: parent.width; height: 2
                            color: tb.active ? root.tintColor : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent; text: modelData
                            color: tb.active ? root.tintColor : "#888"
                            font.pixelSize: root.appFontSize; font.bold: tb.active
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: outerCol.activeTab = index }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a"; Layout.bottomMargin: 10 }

            // ══════════════════════════════════════════════════════════════
            // OVERVIEW TAB
            // ══════════════════════════════════════════════════════════════
            Item {
                Layout.fillWidth: true
                visible: outerCol.activeTab === 0
                // Height is driven by whichever column is taller
                implicitHeight: Math.max(leftCol.implicitHeight, rightCol.implicitHeight)
                height: implicitHeight

                // Left column — hard pixel boundary, clips overflow
                ColumnLayout {
                    id: leftCol
                    anchors { left: parent.left; top: parent.top; right: parent.horizontalCenter; rightMargin: 8 }
                    clip: true
                    spacing: 2

                    Text { text: root.cpuModel; color: "#dddddd"; font.pixelSize: root.appFontSize+1; font.family: root.appFontFamily; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Text {
                        text: root.boardVendor + (root.boardModel ? " " + root.boardModel : "")
                        color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily
                        wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: root.boardVendor !== ""
                    }
                    Text { text: root.osName;        color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                    Text { text: root.kernelVersion; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                    Text { text: "Driver  " + root.cpuDriver; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }

                    Item { height: 10 }

                    GridLayout {
                        columns: 4
                        columnSpacing: 4
                        rowSpacing: 6
                        Layout.fillWidth: true
                        Repeater {
                            model: root.coreCount > 0 ? root.coreCount : 0
                            delegate: ColumnLayout {
                                spacing: 2
                                property bool online: index < root.coresOnline
                                Text { text: "CPU"+index; color: online?"#dddddd":"#555"; font.pixelSize: root.appFontSize; font.bold: true; font.family: root.appFontFamily }
                                Text {
                                    text: { var f=root.coreFreqs[index]||0; return f>=1000?(f/1000).toFixed(2)+" GHz":f.toFixed(0)+" MHz" }
                                    color: online ? root.tintColor : "#444"; font.pixelSize: root.appFontSize-1; font.family: root.appFontFamily
                                }
                                Rectangle {
                                    width: 32; height: 3; color: "#333"; radius: 1
                                    Rectangle {
                                        width: parent.width * (root.coreFreqs[index]||0) / (root.freqMax||1)
                                        height: parent.height; color: online ? root.tintColor : "#333"; radius: 1
                                        Behavior on width { NumberAnimation { duration: 400 } }
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 8 }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "System Load"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily; Layout.fillWidth: true }
                        Text { text: root.loadPercent.toFixed(0)+"%"; color: "#aaaaaa"; font.pixelSize: root.appFontSize }
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 5; color: "#333"; radius: 2
                        Rectangle {
                            width: parent.width * Math.min(root.loadPercent/100, 1)
                            height: parent.height; color: root.tintColor; radius: 2
                            Behavior on width { NumberAnimation { duration: 400 } }
                        }
                    }

                    Item { height: 5 }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Memory"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily; Layout.fillWidth: true }
                        Text { text: root.memPercent.toFixed(1)+"%"; color: "#aaaaaa"; font.pixelSize: root.appFontSize }
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 5; color: "#333"; radius: 2
                        Rectangle {
                            width: parent.width * Math.min(root.memPercent/100, 1)
                            height: parent.height; color: root.tintColor; radius: 2
                            Behavior on width { NumberAnimation { duration: 400 } }
                        }
                    }
                }

                // Right column — hard pixel boundary, clips overflow
                ColumnLayout {
                    id: rightCol
                    anchors { left: parent.horizontalCenter; leftMargin: 8; right: parent.right; top: parent.top }
                    clip: true
                    spacing: 8

                    // ── Branding — matches height of left info block ───────
                    Rectangle {
                        id: brandingBlock
                        Layout.fillWidth: true
                        height: brandingContent.implicitHeight + 24
                        color: "#1e1e1e"; radius: 6

                        ColumnLayout {
                            id: brandingContent
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                spacing: 8
                                Layout.bottomMargin: 6
                                Canvas {
                                    id: bIcon
                                    width: Math.round((root.titleFontSize + 6) * 1.5)
                                    height: Math.round((root.titleFontSize + 6) * 1.5)
                                    onPaint: root.paintIcon(getContext("2d"), width, height, root.tintColor)
                                    Connections { target: root; function onTintColorChanged() { bIcon.requestPaint() } }
                                    Connections { target: root; function onTitleFontSizeChanged() { bIcon.requestPaint() } }
                                }
                                Text {
                                    text: "KCPUFreq"
                                    color: "white"; font.bold: true
                                    font.pixelSize: root.titleFontSize + 6
                                }
                            }
                            Text {
                                text: "A KDE Plasma Widget for cpufreq"
                                color: "#888"; font.pixelSize: root.appFontSize - 1
                            }
                            Text { text: "Brett Olsen"; color: "#666"; font.pixelSize: root.appFontSize - 1 }
                            Text {
                                text: "github.com/brett-olsen"
                                color: root.tintColor
                                font.pixelSize: root.appFontSize - 1
                                font.underline: true
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/brett-olsen")
                                }
                            }
                            Item { height: 8 }
                        }
                    }

                    // Power Profile
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Power Profile"; color: "#888"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                        Item { Layout.fillWidth: true }
                        QQC2.ComboBox {
                            implicitWidth: 128; font.pixelSize: root.appFontSize
                            model: root.profiles.length > 0 ? root.profiles : ["powersave","balanced","performance"]
                            currentIndex: Math.max(0, model.indexOf(root.activeGovernor))
                            contentItem: Text { text: parent.displayText; color: "white"; font.pixelSize: root.appFontSize; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                            background: Rectangle { color: "#3a3a3a"; border.color: "#555"; border.width: 1; radius: 3 }
                            popup.background: Rectangle { color: "#222"; border.color: "#555"; radius: 3 }
                            onActivated: function(i) { applyGovernor(model[i]) }
                        }
                    }

                    // Governor
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Governor"; color: "#888"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                        Item { Layout.fillWidth: true }
                        QQC2.ComboBox {
                            implicitWidth: 128; font.pixelSize: root.appFontSize
                            model: root.governors.length > 0 ? root.governors : ["schedutil","powersave","performance","ondemand","conservative","userspace"]
                            currentIndex: Math.max(0, model.indexOf(root.activeGovernor))
                            contentItem: Text { text: parent.displayText; color: "white"; font.pixelSize: root.appFontSize; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                            background: Rectangle { color: "#3a3a3a"; border.color: "#555"; border.width: 1; radius: 3 }
                            popup.background: Rectangle { color: "#222"; border.color: "#555"; radius: 3 }
                            onActivated: function(i) { applyGovernor(model[i]) }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                    // Minimum freq
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Minimum"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                        Item { Layout.fillWidth: true }
                        QQC2.BusyIndicator { running: root.applyingMin; width: root.appFontSize+4; height: root.appFontSize+4; visible: root.applyingMin }
                        Text { text: root.freqMinSet>=1000?(root.freqMinSet/1000).toFixed(3)+" GHz":root.freqMinSet.toFixed(0)+" MHz"; color: "#aaaaaa"; font.pixelSize: root.appFontSize }
                    }
                    QQC2.Slider {
                        id: sMin; Layout.fillWidth: true
                        enabled: !root.applyingMin
                        opacity: root.applyingMin ? 0.4 : 1.0
                        from: root.freqMin>0?root.freqMin:400
                        to:   root.freqMax>0?root.freqMax:5000
                        value: root.freqMinSet>0?root.freqMinSet:(root.freqMin>0?root.freqMin:400)
                        stepSize: 100; live: false
                        onPressedChanged: {
                            if (!pressed) { root.freqMinSet = value; applyMinFreq(value) }
                        }
                    }

                    // Maximum freq
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Maximum"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                        Item { Layout.fillWidth: true }
                        QQC2.BusyIndicator { running: root.applyingMax; width: root.appFontSize+4; height: root.appFontSize+4; visible: root.applyingMax }
                        Text { text: root.freqMaxSet>=1000?(root.freqMaxSet/1000).toFixed(3)+" GHz":root.freqMaxSet.toFixed(0)+" MHz"; color: "#aaaaaa"; font.pixelSize: root.appFontSize }
                    }
                    QQC2.Slider {
                        id: sMax; Layout.fillWidth: true
                        enabled: !root.applyingMax
                        opacity: root.applyingMax ? 0.4 : 1.0
                        from: root.freqMin>0?root.freqMin:400
                        to:   root.freqMax>0?root.freqMax:5000
                        value: root.freqMaxSet>0?root.freqMaxSet:(root.freqMax>0?root.freqMax:5000)
                        stepSize: 100; live: false
                        onPressedChanged: {
                            if (!pressed) { root.freqMaxSet = value; applyMaxFreq(value) }
                        }
                    }

                    // Cores Online
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Cores Online"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                        Item { Layout.fillWidth: true }
                        QQC2.BusyIndicator { running: root.applyingCores; width: root.appFontSize+4; height: root.appFontSize+4; visible: root.applyingCores }
                        Text { text: root.coresOnline; color: "#aaaaaa"; font.pixelSize: root.appFontSize }
                    }
                    QQC2.Slider {
                        id: sCores; Layout.fillWidth: true
                        enabled: !root.applyingCores
                        opacity: root.applyingCores ? 0.4 : 1.0
                        from: 1; to: root.coreCount>0?root.coreCount:8
                        value: root.coresOnline
                        stepSize: 1; live: false
                        onPressedChanged: {
                            if (!pressed) {
                                root.targetCores = Math.round(value)
                                root.applyingCores = true
                                root.coresOnline = root.targetCores
                                applyCoresOnline(root.targetCores)
                            }
                        }
                    }

                    // Turbo Boost
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Turbo Boost"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.appFontFamily }
                        Item { Layout.fillWidth: true }
                        QQC2.BusyIndicator { running: root.applyingTurbo; width: root.appFontSize+4; height: root.appFontSize+4; visible: root.applyingTurbo }
                        Rectangle {
                            width: 56; height: root.appFontSize+10; radius: 4
                            opacity: root.applyingTurbo ? 0.4 : 1.0
                            color: root.turboEnabled ? "#336622" : "#444"
                            border.color: root.turboEnabled ? "#44aa33" : "#555"
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Text { anchors.centerIn: parent; text: root.turboEnabled?"ON":"OFF"; color: root.turboEnabled?"#88ff66":"#888"; font.bold: true; font.pixelSize: root.appFontSize }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.applyingTurbo
                                onClicked: {
                                    root.targetTurbo = !root.turboEnabled
                                    root.applyingTurbo = true
                                    applyTurbo(root.targetTurbo)
                                }
                            }
                        }
                    }

                    // Remember settings
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.CheckBox {
                            id: cbRemember; checked: root.rememberSettings; onCheckedChanged: root.rememberSettings = checked
                            contentItem: Text {
                                text: "Remember settings"; color: "#aaaaaa"; font.pixelSize: root.appFontSize
                                leftPadding: cbRemember.indicator.width+4; verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Small graph — fixed height, fills the empty space nicely
                    Rectangle {
                        id: smallGraph
                        Layout.fillWidth: true
                        height: 150
                        visible: root.graphSize === "small"
                        color: "#1e1e1e"; radius: 6

                        // Legend inside, top-left
                        Column {
                            anchors { left: parent.left; top: parent.top; margins: 6 }
                            spacing: 3
                            Row {
                                spacing: 3
                                Rectangle { width: 8; height: 2; color: "#ff4444"; radius: 1; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Temp"; color: "#aaaaaa"; font.pixelSize: root.appFontSize - 3 }
                            }
                            Row {
                                spacing: 3
                                Rectangle { width: 8; height: 2; color: "#44cc44"; radius: 1; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Load"; color: "#aaaaaa"; font.pixelSize: root.appFontSize - 3 }
                            }
                            Row {
                                spacing: 3
                                Rectangle { width: 8; height: 2; color: "#aa66ff"; radius: 1; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Freq"; color: "#aaaaaa"; font.pixelSize: root.appFontSize - 3 }
                            }
                        }

                        Canvas {
                            id: graphSmall
                            anchors { fill: parent; margins: 6 }
                            property int ver: root.graphVersion
                            onVerChanged: requestPaint()
                            onPaint: root.paintGraph(getContext("2d"), width, height)
                        }
                    }
                }   // end rightCol
            }   // end parent Item

            // ── Large graph — full width below both columns ───────────────
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 12
                height: 120
                visible: outerCol.activeTab === 0 && root.graphSize === "large"

                Column {
                    id: graphLegend
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 52
                    spacing: 5
                    Row { spacing: 4
                        Rectangle { width: 12; height: 2; color: "#ff4444"; radius: 1; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Temp"; color: "#aaaaaa"; font.pixelSize: root.appFontSize - 2 }
                    }
                    Row { spacing: 4
                        Rectangle { width: 12; height: 2; color: "#44cc44"; radius: 1; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Load"; color: "#aaaaaa"; font.pixelSize: root.appFontSize - 2 }
                    }
                    Row { spacing: 4
                        Rectangle { width: 12; height: 2; color: "#aa66ff"; radius: 1; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Freq"; color: "#aaaaaa"; font.pixelSize: root.appFontSize - 2 }
                    }
                }

                Rectangle {
                    anchors { left: graphLegend.right; leftMargin: 6; right: parent.right; top: parent.top; bottom: parent.bottom }
                    color: "#1e1e1e"; radius: 6
                    Canvas {
                        id: graphCanvas
                        anchors { fill: parent; margins: 6 }
                        property int ver: root.graphVersion
                        onVerChanged: requestPaint()
                        onPaint: paintGraph(getContext("2d"), width, height)
                    }
                }
            }
            // OPTIONS TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                visible: outerCol.activeTab === 1
                spacing: 12

                // ── Titlebar ──────────────────────────────────────────────
                Text { text: "Titlebar"; color: root.tintColor; font.bold: true; font.pixelSize: root.appFontSize+1 }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Font"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.ComboBox {
                        id: titleFontCombo
                        implicitWidth: 170
                        model: root.fontList
                        currentIndex: {
                            var idx = root.fontList.indexOf(root.titleFontFamily)
                            return idx >= 0 ? idx : 0
                        }
                        font.pixelSize: root.appFontSize
                        contentItem: Text { text: parent.displayText; color: "white"; font.pixelSize: root.appFontSize; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                        background: Rectangle { color: "#3a3a3a"; border.color: "#555"; border.width: 1; radius: 3 }
                        popup.background: Rectangle { color: "#222"; border.color: "#555"; radius: 3 }
                        onActivated: function(i) { root.titleFontFamily = root.fontList[i] }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Size"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.Slider {
                        id: sTitleSize; implicitWidth: 130
                        from: 9; to: 32; stepSize: 1; live: true
                        value: root.titleFontSize
                        onMoved: root.titleFontSize = Math.round(value)
                    }
                    Text { text: root.titleFontSize+"px"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 36 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Show CPU speed"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.CheckBox { checked: root.showFreqInTitle; onCheckedChanged: root.showFreqInTitle = checked }
                }


                Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                // ── Application ───────────────────────────────────────────
                Text { text: "Application"; color: root.tintColor; font.bold: true; font.pixelSize: root.appFontSize+1 }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Font"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.ComboBox {
                        id: appFontCombo
                        implicitWidth: 170
                        model: root.fontList
                        currentIndex: {
                            var idx = root.fontList.indexOf(root.appFontFamily)
                            return idx >= 0 ? idx : 0
                        }
                        font.pixelSize: root.appFontSize
                        contentItem: Text { text: parent.displayText; color: "white"; font.pixelSize: root.appFontSize; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                        background: Rectangle { color: "#3a3a3a"; border.color: "#555"; border.width: 1; radius: 3 }
                        popup.background: Rectangle { color: "#222"; border.color: "#555"; radius: 3 }
                        onActivated: function(i) { root.appFontFamily = root.fontList[i] }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Size"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.Slider {
                        id: sAppSize; implicitWidth: 130
                        from: 8; to: 32; stepSize: 1; live: true
                        value: root.appFontSize
                        onMoved: root.appFontSize = Math.round(value)
                    }
                    Text { text: root.appFontSize+"px"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 36 }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                // ── Tint Color ────────────────────────────────────────────
                Text { text: "Tint Color"; color: root.tintColor; font.bold: true; font.pixelSize: root.appFontSize+1 }

                // Preset swatches
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: root.tintPresets
                        delegate: Rectangle {
                            width: 36; height: 24; radius: 4
                            color: modelData.color
                            border.color: root.tintColor === modelData.color ? "white" : "transparent"
                            border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: "white"
                                font.pixelSize: 8
                                font.bold: true
                                style: Text.Outline
                                styleColor: "#00000088"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.tintColor = modelData.color
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                // ── Polling ───────────────────────────────────────────────
                Text { text: "Polling"; color: root.tintColor; font.bold: true; font.pixelSize: root.appFontSize+1 }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Refresh rate"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.Slider {
                        id: sRefresh; implicitWidth: 130
                        from: 1; to: 30; stepSize: 1; live: true
                        value: root.refreshSecs
                        onMoved: root.refreshSecs = Math.round(value)
                    }
                    Text { text: root.refreshSecs+"s"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 36 }
                }

                Item { height: 4 }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                // ── Page Background ───────────────────────────────────────
                Text { text: "Page Background"; color: root.tintColor; font.bold: true; font.pixelSize: root.appFontSize+1 }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Style"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.ComboBox {
                        implicitWidth: 120; font.pixelSize: root.appFontSize
                        model: ["Solid", "System"]
                        currentIndex: root.bgStyle === "system" ? 1 : 0
                        contentItem: Text { text: parent.displayText; color: "white"; font.pixelSize: root.appFontSize; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                        background: Rectangle { color: "#3a3a3a"; border.color: "#555"; border.width: 1; radius: 3 }
                        popup.background: Rectangle { color: "#222"; border.color: "#555"; radius: 3 }
                        onActivated: function(i) { root.bgStyle = i === 1 ? "system" : "solid" }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                // ── Graph ─────────────────────────────────────────────────
                Text { text: "Graph"; color: root.tintColor; font.bold: true; font.pixelSize: root.appFontSize+1 }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Graph size"; color: "#aaaaaa"; font.pixelSize: root.appFontSize; Layout.minimumWidth: 110 }
                    Item { Layout.fillWidth: true }
                    QQC2.ComboBox {
                        implicitWidth: 120; font.pixelSize: root.appFontSize
                        model: ["Large", "Small"]
                        currentIndex: root.graphSize === "small" ? 1 : 0
                        contentItem: Text { text: parent.displayText; color: "white"; font.pixelSize: root.appFontSize; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                        background: Rectangle { color: "#3a3a3a"; border.color: "#555"; border.width: 1; radius: 3 }
                        popup.background: Rectangle { color: "#222"; border.color: "#555"; radius: 3 }
                        onActivated: function(i) { root.graphSize = i === 1 ? "small" : "large" }
                    }
                }

                Item { height: 4 }
            }

            // ── Status bar ────────────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a"; Layout.topMargin: 10; Layout.bottomMargin: 6 }
            RowLayout {
                Layout.fillWidth: true; Layout.bottomMargin: 6; spacing: 6
                Text { text: "☺"; color: "#44bb44"; font.pixelSize: root.appFontSize+4 }
                Text { text: "SYSTEM STATUS OK"; color: "#44bb44"; font.bold: true; font.pixelSize: root.appFontSize }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.coreFreqs.length > 0 && root.coreFreqs[0] > 0
                    text: root.coreFreqs[0] >= 1000
                          ? (root.coreFreqs[0]/1000).toFixed(2) + " GHz"
                          : root.coreFreqs[0].toFixed(0) + " MHz"
                    color: "#aaaaaa"; font.pixelSize: root.appFontSize; font.family: root.titleFontFamily
                }
                Text {
                    text: "  ↻ " + root.refreshSecs + "s"; color: "#555"; font.pixelSize: root.appFontSize - 1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: fetchAll() }
                }
            }
        }
    }
}
