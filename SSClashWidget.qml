import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr
import "clashApi.js" as Api

PluginComponent {
    id: root

    // --- Localization ---
    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    // --- Plugin settings ---
    property string apiUrl: Api.normalizeBaseUrl(pluginData.apiUrl || Api.DEFAULT_URL)
    property string apiSecret: pluginData.secret || ""
    property color accentColor: {
        var c = pluginData.accentColor;
        return (typeof c === "string" && c.length > 0) ? c : "#19b5ff";
    }
    property string testUrl: (pluginData.testUrl && pluginData.testUrl.length > 0) ? pluginData.testUrl : Api.DEFAULT_TEST_URL
    property int testTimeout: pluginData.testTimeout || Api.DEFAULT_TIMEOUT
    property int pollIntervalMs: Math.max(10, pluginData.pollInterval || 30) * 1000
    property bool showGlobalGroup: pluginData.showGlobalGroup !== false

    // --- State ---
    property bool online: false
    property bool isLoading: true
    property bool isTestingAll: false
    property string coreVersion: ""
    property string currentMode: "rule"
    property string searchQuery: ""
    property string lastError: ""

    property var proxiesMap: ({})
    property var allGroups: []
    property var testingGroupsMap: ({})
    property var testingNodesMap: ({})

    // Persisted collapsed group state (defaults match user's dashboard: WARP & GLOBAL collapsed)
    property var collapsedMap: ({ "WARP": true, "GLOBAL": true })
    property bool _collapsedLoaded: false

    readonly property var filteredGroups: Api.filterGroups(allGroups, searchQuery)

    readonly property var _leftOrder: ["AI", "YOUTUBE", "PROXY", "WARP"]
    readonly property var _rightOrder: ["GEMINI", "ANTIGRAVITY", "META", "GLOBAL"]

    readonly property var _columnSplit: {
        var left = [];
        var right = [];
        var byName = {};
        for (var i = 0; i < filteredGroups.length; i++)
            byName[filteredGroups[i].name] = filteredGroups[i];

        var assigned = {};
        for (var l = 0; l < _leftOrder.length; l++) {
            var ln = _leftOrder[l];
            if (byName[ln]) {
                left.push(byName[ln]);
                assigned[ln] = true;
            }
        }
        for (var r = 0; r < _rightOrder.length; r++) {
            var rn = _rightOrder[r];
            if (byName[rn]) {
                right.push(byName[rn]);
                assigned[rn] = true;
            }
        }
        // Any additional custom groups get balanced across columns
        for (var k = 0; k < filteredGroups.length; k++) {
            var g = filteredGroups[k];
            if (assigned[g.name])
                continue;
            if (left.length <= right.length)
                left.push(g);
            else
                right.push(g);
        }
        return { left: left, right: right };
    }

    readonly property var leftColumnGroups: _columnSplit.left
    readonly property var rightColumnGroups: _columnSplit.right

    readonly property bool allCollapsed: {
        if (!allGroups || allGroups.length === 0)
            return false;
        for (var i = 0; i < allGroups.length; i++) {
            if (!collapsedMap[allGroups[i].name])
                return false;
        }
        return true;
    }

    readonly property string iconSource: "file://" + PluginService.pluginDirectory + "/ssclashDashboard/icon.svg"

    popoutWidth: 1080
    popoutHeight: 0

    pillRightClickAction: function () {
        root.refresh();
    }

    onPluginDataChanged: {
        loadCollapsedState();
        if (Object.keys(proxiesMap).length > 0)
            allGroups = Api.buildGroupsModel(proxiesMap, showGlobalGroup);
    }

    onInteractionActiveChanged: {
        if (interactionActive)
            refresh();
    }

    Component.onCompleted: {
        loadCollapsedState();
        refresh();
    }

    // --- Collapsed groups persistence ---
    function loadCollapsedState() {
        var raw = pluginData.collapsedGroups;
        if (typeof raw === "string" && raw.length > 0) {
            try {
                var parsed = JSON.parse(raw);
                if (parsed && typeof parsed === "object") {
                    collapsedMap = parsed;
                    _collapsedLoaded = true;
                    return;
                }
            } catch (e) {}
        } else if (raw && typeof raw === "object") {
            collapsedMap = raw;
            _collapsedLoaded = true;
            return;
        }
        if (!_collapsedLoaded) {
            collapsedMap = { "WARP": true, "GLOBAL": true };
            _collapsedLoaded = true;
        }
    }

    function saveCollapsedState(nextMap) {
        collapsedMap = nextMap;
        if (pluginService && pluginService.savePluginData && pluginId)
            pluginService.savePluginData(pluginId, "collapsedGroups", JSON.stringify(nextMap));
    }

    function toggleGroupCollapsed(groupName) {
        var next = Object.assign({}, collapsedMap);
        next[groupName] = !next[groupName];
        saveCollapsedState(next);
    }

    function toggleCollapseAll() {
        var target = !allCollapsed;
        var next = {};
        for (var i = 0; i < allGroups.length; i++)
            next[allGroups[i].name] = target;
        saveCollapsedState(next);
    }

    // --- API Actions ---
    function refresh() {
        isLoading = true;
        Api.fetchDashboardState(apiUrl, apiSecret, showGlobalGroup, function (state) {
            proxiesMap = state.proxiesMap;
            allGroups = state.groups;
            currentMode = state.mode;
            coreVersion = state.version;
            online = true;
            lastError = "";
            isLoading = false;
        }, function (err) {
            online = false;
            lastError = err || "Error";
            isLoading = false;
        });
    }

    function selectNode(groupName, nodeName) {
        if (proxiesMap && proxiesMap[groupName]) {
            var nextMap = Object.assign({}, proxiesMap);
            var gCopy = Object.assign({}, nextMap[groupName]);
            gCopy.now = nodeName;
            if (gCopy.type === "Fallback" || gCopy.type === "URLTest")
                gCopy.fixed = nodeName;
            nextMap[groupName] = gCopy;
            proxiesMap = nextMap;
            allGroups = Api.buildGroupsModel(proxiesMap, showGlobalGroup);
        }

        Api.selectProxy(apiUrl, apiSecret, groupName, nodeName, function () {
            refresh();
        }, function () {
            refresh();
        });
    }

    function unfixGroup(groupName) {
        if (proxiesMap && proxiesMap[groupName]) {
            var nextMap = Object.assign({}, proxiesMap);
            var gCopy = Object.assign({}, nextMap[groupName]);
            gCopy.fixed = "";
            nextMap[groupName] = gCopy;
            proxiesMap = nextMap;
            allGroups = Api.buildGroupsModel(proxiesMap, showGlobalGroup);
        }

        Api.unfixProxy(apiUrl, apiSecret, groupName, function () {
            refresh();
        }, function () {
            refresh();
        });
    }

    function switchMode(newMode) {
        if (currentMode === newMode)
            return;
        currentMode = newMode;
        Api.setMode(apiUrl, apiSecret, newMode, function () {
            refresh();
        }, function () {
            refresh();
        });
    }

    function setGroupTesting(groupName, active) {
        var m = Object.assign({}, testingGroupsMap);
        if (active)
            m[groupName] = true;
        else
            delete m[groupName];
        testingGroupsMap = m;
    }

    function setNodeTesting(nodeName, active) {
        var m = Object.assign({}, testingNodesMap);
        if (active)
            m[nodeName] = true;
        else
            delete m[nodeName];
        testingNodesMap = m;
    }

    function testGroupLatency(groupName, onDone) {
        if (testingGroupsMap[groupName]) {
            if (onDone)
                onDone();
            return;
        }
        setGroupTesting(groupName, true);
        var urlToUse = testUrl;
        if (proxiesMap && proxiesMap[groupName] && proxiesMap[groupName].testUrl)
            urlToUse = proxiesMap[groupName].testUrl;

        Api.testGroupDelay(apiUrl, apiSecret, groupName, urlToUse, testTimeout, function () {
            setGroupTesting(groupName, false);
            refresh();
            if (onDone)
                onDone();
        }, function () {
            setGroupTesting(groupName, false);
            refresh();
            if (onDone)
                onDone();
        });
    }

    function testNodeLatency(groupName, nodeName) {
        if (testingNodesMap[nodeName])
            return;
        setNodeTesting(nodeName, true);
        var urlToUse = testUrl;
        if (proxiesMap && proxiesMap[groupName] && proxiesMap[groupName].testUrl)
            urlToUse = proxiesMap[groupName].testUrl;

        Api.testProxyDelay(apiUrl, apiSecret, nodeName, urlToUse, testTimeout, function () {
            setNodeTesting(nodeName, false);
            refresh();
        }, function () {
            setNodeTesting(nodeName, false);
            refresh();
        });
    }

    function testAllGroupsLatency() {
        if (isTestingAll || !allGroups || allGroups.length === 0)
            return;
        isTestingAll = true;
        var targets = [];
        for (var i = 0; i < allGroups.length; i++) {
            var gn = allGroups[i].name;
            if (gn !== "GLOBAL")
                targets.push(gn);
        }
        if (targets.length === 0)
            targets.push(allGroups[0].name);

        var pending = targets.length;
        for (var j = 0; j < targets.length; j++) {
            testGroupLatency(targets[j], function () {
                pending--;
                if (pending <= 0) {
                    isTestingAll = false;
                    refresh();
                }
            });
        }
    }

    // Background liveness polling
    Timer {
        interval: root.pollIntervalMs
        running: true
        repeat: true
        onTriggered: {
            if (!root.isLoading && !root.isTestingAll)
                root.refresh();
        }
    }

    IpcHandler {
        target: "ssclash"

        function toggle(): string {
            if (root.interactionActive) {
                root.closePopout();
                return "CLOSED";
            }
            root.triggerPopout();
            return "OPENED";
        }

        function open(): string {
            if (!root.interactionActive)
                root.triggerPopout();
            return "OPENED";
        }

        function close(): string {
            root.closePopout();
            return "CLOSED";
        }

        function refresh(): string {
            root.refresh();
            return "REFRESHED";
        }
    }

    // --- Inline Group Card component (reloads cleanly with root widget) ---
    component GroupCard: StyledRect {
        id: card

        required property var groupData
        required property color accentColor
        required property bool isCollapsed
        required property bool isTestingGroup
        required property var testingNodesMap

        signal toggleCollapse(string groupName)
        signal selectNode(string groupName, string nodeName)
        signal unfixGroup(string groupName)
        signal testGroup(string groupName)
        signal testNode(string groupName, string nodeName)

        readonly property bool effectiveCollapsed: isCollapsed && !(groupData && groupData.forceExpand)
        readonly property color cardBg: Theme.surfaceContainerHigh
        readonly property color tileBg: Theme.surfaceContainer
        readonly property color subtleBorder: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

        radius: Theme.cornerRadius
        color: cardBg
        border.width: 1
        border.color: subtleBorder
        implicitHeight: mainCol.implicitHeight + 20

        function delayColor(delay, alive) {
            if (!alive || delay <= 0)
                return Theme.surfaceVariantText;
            if (delay < 200)
                return Theme.success;
            if (delay < 450)
                return Theme.warning;
            return Theme.error;
        }

        function dotColor(node) {
            if (!node.alive || node.delay <= 0)
                return Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g, Theme.surfaceVariantText.b, 0.45);
            return delayColor(node.delay, node.alive);
        }

        Column {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 8

            // Header row
            Item {
                id: headerRow
                width: parent.width
                height: 26

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.toggleCollapse(card.groupData.name)
                }

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Item {
                        width: 20
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            id: groupIconImg
                            anchors.fill: parent
                            source: card.groupData.icon || ""
                            sourceSize.width: 24
                            sourceSize.height: 24
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                            cache: true
                            visible: status === Image.Ready
                        }

                        DankIcon {
                            anchors.centerIn: parent
                            name: card.groupData.name === "GLOBAL" ? "public" : "lan"
                            size: 17
                            color: card.accentColor
                            visible: groupIconImg.status !== Image.Ready
                        }
                    }

                    StyledText {
                        text: card.groupData.name
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "· " + card.groupData.type + " · " + card.groupData.aliveCount + "/" + card.groupData.totalCount
                        font.pixelSize: 11
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    // Group latency pill (click to test group delay)
                    Rectangle {
                        height: 22
                        width: Math.max(38, groupDelayRow.implicitWidth + 14)
                        radius: 11
                        color: groupDelayMa.containsMouse
                               ? Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.22)
                               : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)
                        border.width: 1
                        border.color: groupDelayMa.containsMouse
                                      ? Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.7)
                                      : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)

                        Row {
                            id: groupDelayRow
                            anchors.centerIn: parent
                            spacing: 3

                            DankIcon {
                                name: "bolt"
                                size: 12
                                color: card.isTestingGroup ? card.accentColor : Theme.surfaceVariantText
                                visible: card.isTestingGroup || card.groupData.delay <= 0
                                anchors.verticalCenter: parent.verticalCenter

                                SequentialAnimation on opacity {
                                    running: card.isTestingGroup
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 400 }
                                    NumberAnimation { to: 1.0; duration: 400 }
                                }
                            }

                            StyledText {
                                visible: !card.isTestingGroup && card.groupData.delay > 0
                                text: String(card.groupData.delay)
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: card.delayColor(card.groupData.delay, true)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: groupDelayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                mouse.accepted = true;
                                card.testGroup(card.groupData.name);
                            }
                        }
                    }

                    // Expand / collapse chevron
                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        color: collapseMa.containsMouse
                               ? Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.65)
                               : "transparent"

                        DankIcon {
                            anchors.centerIn: parent
                            name: card.effectiveCollapsed ? "expand_more" : "expand_less"
                            size: 16
                            color: Theme.surfaceVariantText
                        }

                        MouseArea {
                            id: collapseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                mouse.accepted = true;
                                card.toggleCollapse(card.groupData.name);
                            }
                        }
                    }
                }
            }

            // Active node status row (lock / auto icon + active node name)
            Row {
                width: parent.width
                spacing: 6

                Rectangle {
                    width: 20
                    height: 20
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: (card.groupData.canUnfix && lockMa.containsMouse)
                           ? Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.22)
                           : "transparent"
                    border.width: (card.groupData.canUnfix && lockMa.containsMouse) ? 1 : 0
                    border.color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.7)

                    DankIcon {
                        anchors.centerIn: parent
                        name: card.groupData.canUnfix
                              ? (lockMa.containsMouse ? "lock_open" : "lock")
                              : "arrow_circle_right"
                        size: 14
                        color: card.groupData.canUnfix ? card.accentColor : Theme.surfaceVariantText
                    }

                    MouseArea {
                        id: lockMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: card.groupData.canUnfix
                        cursorShape: card.groupData.canUnfix ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: card.unfixGroup(card.groupData.name)
                    }
                }

                StyledText {
                    text: card.groupData.now || "—"
                    font.pixelSize: 12
                    color: Theme.surfaceVariantText
                    width: parent.width - 26
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.toggleCollapse(card.groupData.name)
                    }
                }
            }

            // Collapsed view: compact colored status dots
            Flow {
                visible: card.effectiveCollapsed
                width: parent.width
                spacing: 5

                Repeater {
                    model: card.effectiveCollapsed ? card.groupData.nodes : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isSel: modelData.name === card.groupData.now
                        width: isSel ? 12 : 9
                        height: isSel ? 12 : 9
                        radius: width / 2
                        color: isSel ? card.accentColor : card.dotColor(modelData)
                        border.width: isSel ? 2 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.85)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.toggleCollapse(card.groupData.name)
                        }
                    }
                }
            }

            // Expanded view: 3-column grid of server tiles
            Grid {
                id: nodesGrid
                visible: !card.effectiveCollapsed
                width: parent.width
                columns: 3
                columnSpacing: 6
                rowSpacing: 6

                readonly property real tileWidth: Math.floor((width - columnSpacing * (columns - 1)) / columns)

                Repeater {
                    model: card.effectiveCollapsed ? [] : card.groupData.nodes
                    delegate: Rectangle {
                        id: nodeTile
                        required property var modelData
                        readonly property bool isSelected: modelData.name === card.groupData.now
                        readonly property bool isTestingThis: !!(card.testingNodesMap && card.testingNodesMap[modelData.name])

                        width: nodesGrid.tileWidth
                        height: 60
                        radius: 8
                        clip: true

                        color: {
                            if (isSelected)
                                return Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, tileMa.containsMouse ? 0.30 : 0.22);
                            if (tileMa.containsMouse)
                                return Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.09);
                            return card.tileBg;
                        }

                        border.width: isSelected ? 2 : 1
                        border.color: {
                            if (isSelected)
                                return card.accentColor;
                            if (tileMa.containsMouse)
                                return Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.45);
                            return Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16);
                        }

                        Behavior on color {
                            ColorAnimation { duration: 110 }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 110 }
                        }

                        // Neon left edge indicator on active server
                        Rectangle {
                            visible: nodeTile.isSelected
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: card.accentColor
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.selectNode(card.groupData.name, nodeTile.modelData.name)
                        }

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: nodeTile.isSelected ? 9 : 8
                            anchors.rightMargin: 7
                            anchors.topMargin: 5
                            anchors.bottomMargin: 5

                            StyledText {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: nodeFooterRow.top
                                anchors.bottomMargin: 3
                                text: nodeTile.modelData.name
                                font.pixelSize: 11
                                lineHeight: 1.05
                                font.weight: nodeTile.isSelected ? Font.DemiBold : Font.Medium
                                color: nodeTile.isSelected ? "#f2fbff" : Theme.surfaceText
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                id: nodeFooterRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 17

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.right: nodeDelayPill.left
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: nodeTile.modelData.protocol || nodeTile.modelData.type
                                    font.pixelSize: 10
                                    color: nodeTile.isSelected
                                           ? Qt.rgba(0.84, 0.95, 1.0, 0.85)
                                           : Theme.surfaceVariantText
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    id: nodeDelayPill
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 17
                                    width: Math.max(28, nodeDelayContent.implicitWidth + 10)
                                    radius: 8
                                    color: nodeDelayMa.containsMouse
                                           ? Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.32)
                                           : (nodeTile.isSelected
                                              ? Qt.rgba(0, 0, 0, 0.44)
                                              : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.65))

                                    Item {
                                        id: nodeDelayContent
                                        anchors.centerIn: parent
                                        implicitWidth: (nodeTile.isTestingThis || nodeTile.modelData.delay <= 0) ? 12 : delayLbl.implicitWidth
                                        implicitHeight: 14

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "bolt"
                                            size: 11
                                            color: nodeTile.isTestingThis
                                                   ? card.accentColor
                                                   : (nodeTile.isSelected ? "#d6f2ff" : Theme.surfaceVariantText)
                                            visible: nodeTile.isTestingThis || nodeTile.modelData.delay <= 0

                                            SequentialAnimation on opacity {
                                                running: nodeTile.isTestingThis
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.25; duration: 350 }
                                                NumberAnimation { to: 1.0; duration: 350 }
                                            }
                                        }

                                        StyledText {
                                            id: delayLbl
                                            anchors.centerIn: parent
                                            visible: !nodeTile.isTestingThis && nodeTile.modelData.delay > 0
                                            text: String(nodeTile.modelData.delay)
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: card.delayColor(nodeTile.modelData.delay, true)
                                        }
                                    }

                                    MouseArea {
                                        id: nodeDelayMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            mouse.accepted = true;
                                            card.testNode(card.groupData.name, nodeTile.modelData.name);
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

    // --- Compact Bar Pills (Icon + status dot only) ---
    horizontalBarPill: Component {
        Item {
            readonly property int iconPx: Math.max(16, root.iconSize)
            implicitWidth: iconPx + 6
            implicitHeight: iconPx

            Image {
                id: hPillIcon
                anchors.centerIn: parent
                source: root.iconSource
                sourceSize.width: iconPx
                sourceSize.height: iconPx
                width: iconPx
                height: iconPx
                smooth: true
                asynchronous: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.online ? root.accentColor : Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: 7
                height: 7
                radius: 4
                anchors.right: hPillIcon.right
                anchors.bottom: hPillIcon.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -1
                color: root.isTestingAll
                       ? Theme.warning
                       : (root.online ? Theme.success : Theme.error)
                border.width: 1
                border.color: Theme.surface
            }
        }
    }

    verticalBarPill: Component {
        Item {
            readonly property int iconPx: Math.max(16, root.iconSize)
            implicitWidth: iconPx
            implicitHeight: iconPx + 4

            Image {
                id: vPillIcon
                anchors.centerIn: parent
                source: root.iconSource
                sourceSize.width: iconPx
                sourceSize.height: iconPx
                width: iconPx
                height: iconPx
                smooth: true
                asynchronous: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.online ? root.accentColor : Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: 7
                height: 7
                radius: 4
                anchors.right: vPillIcon.right
                anchors.bottom: vPillIcon.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -1
                color: root.isTestingAll
                       ? Theme.warning
                       : (root.online ? Theme.success : Theme.error)
                border.width: 1
                border.color: Theme.surface
            }
        }
    }

    // --- Wide 2-Column Popout Dashboard ---
    popoutContent: Component {
        Item {
            id: popoutRoot
            property var closePopout: null
            property var parentPopout: null

            readonly property real maxBodyHeight: 800
            readonly property real bodyContentHeight: {
                if (!root.online)
                    return offlineCard.implicitHeight;
                if (root.filteredGroups.length === 0)
                    return emptySearchCard.implicitHeight;
                return Math.max(leftCol.implicitHeight, rightCol.implicitHeight) + 6;
            }
            readonly property real clampedBodyHeight: Math.min(maxBodyHeight, Math.max(180, bodyContentHeight))

            width: parent ? parent.width : root.popoutWidth
            implicitHeight: toolbar.height + 10 + clampedBodyHeight

            Column {
                anchors.fill: parent
                spacing: 10

                // --- Top Toolbar ---
                Item {
                    id: toolbar
                    width: parent.width
                    height: 36

                    // Segmented mode selector (Rule / Global / Direct)
                    StyledRect {
                        id: modeBar
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: 34
                        width: modeRow.implicitWidth + 6
                        radius: 17
                        color: Theme.surfaceContainerHigh
                        border.width: 1
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

                        Row {
                            id: modeRow
                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: [
                                    { key: "rule", label: root.tr("mode_rule") },
                                    { key: "global", label: root.tr("mode_global") },
                                    { key: "direct", label: root.tr("mode_direct") }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isActive: root.currentMode === modelData.key
                                    height: 28
                                    width: modeLbl.implicitWidth + 20
                                    radius: 14
                                    color: isActive
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (modeMa.containsMouse ? Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5) : "transparent")
                                    border.width: isActive ? 1 : 0
                                    border.color: root.accentColor

                                    StyledText {
                                        id: modeLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: 12
                                        font.weight: isActive ? Font.DemiBold : Font.Normal
                                        color: isActive ? "#f2fbff" : Theme.surfaceVariantText
                                    }

                                    MouseArea {
                                        id: modeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.switchMode(modelData.key)
                                    }
                                }
                            }
                        }
                    }

                    // Search box
                    StyledRect {
                        id: searchBox
                        anchors.left: modeBar.right
                        anchors.leftMargin: 10
                        anchors.right: actionsRow.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 34
                        radius: 17
                        color: Theme.surfaceContainerHigh
                        border.width: searchInput.activeFocus ? 2 : 1
                        border.color: searchInput.activeFocus
                                      ? root.accentColor
                                      : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

                        DankIcon {
                            id: searchIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            size: 16
                            color: searchInput.activeFocus ? root.accentColor : Theme.surfaceVariantText
                        }

                        TextInput {
                            id: searchInput
                            anchors.left: searchIcon.right
                            anchors.leftMargin: 7
                            anchors.right: clearSearchBtn.visible ? clearSearchBtn.left : parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.surfaceText
                            selectionColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                            selectedTextColor: "#ffffff"
                            font.pixelSize: 13
                            clip: true
                            text: root.searchQuery
                            onTextChanged: {
                                if (root.searchQuery !== text)
                                    root.searchQuery = text;
                            }
                            Keys.onEscapePressed: event => {
                                if (text.length > 0) {
                                    text = "";
                                    root.searchQuery = "";
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.tr("search_placeholder")
                                font.pixelSize: 13
                                color: Theme.surfaceVariantText
                                visible: searchInput.text.length === 0
                            }
                        }

                        Rectangle {
                            id: clearSearchBtn
                            visible: searchInput.text.length > 0
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 11
                            color: clearMa.containsMouse
                                   ? Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.7)
                                   : "transparent"

                            DankIcon {
                                anchors.centerIn: parent
                                name: "close"
                                size: 14
                                color: Theme.surfaceVariantText
                            }

                            MouseArea {
                                id: clearMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    root.searchQuery = "";
                                }
                            }
                        }
                    }

                    // Right action buttons
                    Row {
                        id: actionsRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        StyledRect {
                            height: 30
                            width: statusChipRow.implicitWidth + 16
                            radius: 15
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2)

                            Row {
                                id: statusChipRow
                                anchors.centerIn: parent
                                spacing: 6

                                Rectangle {
                                    width: 7
                                    height: 7
                                    radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.online ? Theme.success : Theme.error
                                }

                                StyledText {
                                    text: root.online
                                          ? (root.coreVersion ? root.coreVersion : root.tr("online"))
                                          : root.tr("offline")
                                    font.pixelSize: 11
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Collapse / Expand all
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: collapseAllMa.containsMouse
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                   : Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: collapseAllMa.containsMouse
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.65)
                                          : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

                            DankIcon {
                                anchors.centerIn: parent
                                name: root.allCollapsed ? "unfold_more" : "unfold_less"
                                size: 18
                                color: collapseAllMa.containsMouse ? root.accentColor : Theme.surfaceText
                            }

                            MouseArea {
                                id: collapseAllMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleCollapseAll()
                            }
                        }

                        // Test all groups latency
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: (root.isTestingAll || testAllMa.containsMouse)
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                                   : Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: (root.isTestingAll || testAllMa.containsMouse)
                                          ? root.accentColor
                                          : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

                            DankIcon {
                                anchors.centerIn: parent
                                name: "bolt"
                                size: 18
                                color: (root.isTestingAll || testAllMa.containsMouse) ? root.accentColor : Theme.surfaceText

                                SequentialAnimation on opacity {
                                    running: root.isTestingAll
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 380 }
                                    NumberAnimation { to: 1.0; duration: 380 }
                                }
                            }

                            MouseArea {
                                id: testAllMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.testAllGroupsLatency()
                            }
                        }

                        // Refresh
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: refreshMa.containsMouse
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                   : Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: refreshMa.containsMouse
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.65)
                                          : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

                            DankIcon {
                                anchors.centerIn: parent
                                name: "refresh"
                                size: 18
                                color: refreshMa.containsMouse ? root.accentColor : Theme.surfaceText
                            }

                            MouseArea {
                                id: refreshMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.refresh()
                            }
                        }
                    }
                }

                // --- Offline / Error state ---
                StyledRect {
                    id: offlineCard
                    visible: !root.online
                    width: parent.width
                    implicitHeight: offlineCol.implicitHeight + 44
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.width: 1
                    border.color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.4)

                    Column {
                        id: offlineCol
                        anchors.centerIn: parent
                        spacing: 8

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: root.isLoading ? "hourglass_empty" : "cloud_off"
                            size: 30
                            color: root.isLoading ? root.accentColor : Theme.error
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.isLoading ? root.tr("connecting") : root.tr("offline_title")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            visible: !root.isLoading
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.tr("offline_desc") + " " + root.apiUrl + (root.lastError ? " (" + root.lastError + ")" : "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Rectangle {
                            visible: !root.isLoading
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: retryLbl.implicitWidth + 28
                            height: 30
                            radius: 15
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, retryMa.containsMouse ? 0.34 : 0.22)
                            border.width: 1
                            border.color: root.accentColor

                            StyledText {
                                id: retryLbl
                                anchors.centerIn: parent
                                text: root.tr("retry")
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#f2fbff"
                            }

                            MouseArea {
                                id: retryMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.refresh()
                            }
                        }
                    }
                }

                // --- Empty search state ---
                StyledRect {
                    id: emptySearchCard
                    visible: root.online && root.filteredGroups.length === 0
                    width: parent.width
                    implicitHeight: emptySearchCol.implicitHeight + 40
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: emptySearchCol
                        anchors.centerIn: parent
                        spacing: 8

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "search_off"
                            size: 28
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.tr("no_results")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                        }

                        Rectangle {
                            visible: root.searchQuery.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: clearBtnLbl.implicitWidth + 24
                            height: 28
                            radius: 14
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                            border.width: 1
                            border.color: root.accentColor

                            StyledText {
                                id: clearBtnLbl
                                anchors.centerIn: parent
                                text: root.tr("clear_search")
                                font.pixelSize: 12
                                color: "#f2fbff"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    root.searchQuery = "";
                                }
                            }
                        }
                    }
                }

                // --- Scrollable 2-Column Proxy Groups Grid ---
                DankFlickable {
                    id: groupsFlick
                    visible: root.online && root.filteredGroups.length > 0
                    width: parent.width
                    height: popoutRoot.clampedBodyHeight
                    contentWidth: width
                    contentHeight: Math.max(leftCol.implicitHeight, rightCol.implicitHeight) + 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: columnsRow
                        width: groupsFlick.width
                        spacing: 10

                        readonly property real colWidth: Math.floor((width - spacing) / 2)

                        // Left column (even indices: AI, YOUTUBE, PROXY, ANTIGRAVITY)
                        Column {
                            id: leftCol
                            width: columnsRow.colWidth
                            spacing: 10

                            Repeater {
                                model: root.leftColumnGroups
                                delegate: GroupCard {
                                    required property var modelData
                                    width: leftCol.width
                                    groupData: modelData
                                    accentColor: root.accentColor
                                    isCollapsed: !!root.collapsedMap[modelData.name]
                                    isTestingGroup: !!root.testingGroupsMap[modelData.name]
                                    testingNodesMap: root.testingNodesMap
                                    onToggleCollapse: gn => root.toggleGroupCollapsed(gn)
                                    onSelectNode: (gn, nn) => root.selectNode(gn, nn)
                                    onUnfixGroup: gn => root.unfixGroup(gn)
                                    onTestGroup: gn => root.testGroupLatency(gn)
                                    onTestNode: (gn, nn) => root.testNodeLatency(gn, nn)
                                }
                            }
                        }

                        // Right column (odd indices: GEMINI, WARP, META, GLOBAL)
                        Column {
                            id: rightCol
                            width: columnsRow.colWidth
                            spacing: 10

                            Repeater {
                                model: root.rightColumnGroups
                                delegate: GroupCard {
                                    required property var modelData
                                    width: rightCol.width
                                    groupData: modelData
                                    accentColor: root.accentColor
                                    isCollapsed: !!root.collapsedMap[modelData.name]
                                    isTestingGroup: !!root.testingGroupsMap[modelData.name]
                                    testingNodesMap: root.testingNodesMap
                                    onToggleCollapse: gn => root.toggleGroupCollapsed(gn)
                                    onSelectNode: (gn, nn) => root.selectNode(gn, nn)
                                    onUnfixGroup: gn => root.unfixGroup(gn)
                                    onTestGroup: gn => root.testGroupLatency(gn)
                                    onTestNode: (gn, nn) => root.testNodeLatency(gn, nn)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
