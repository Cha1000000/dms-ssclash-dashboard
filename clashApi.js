.pragma library

var DEFAULT_URL = "http://192.168.10.1:9090";
var DEFAULT_TEST_URL = "https://www.google.com/generate_204";
var DEFAULT_TIMEOUT = 5000;

function normalizeBaseUrl(url) {
    var u = (url || "").trim();
    if (!u)
        u = DEFAULT_URL;
    if (u.indexOf("http://") !== 0 && u.indexOf("https://") !== 0)
        u = "http://" + u;
    return u.replace(/\/+$/, "");
}

function request(baseUrl, secret, method, path, body, timeoutMs, onSuccess, onError) {
    var xhr = new XMLHttpRequest();
    var fullUrl = normalizeBaseUrl(baseUrl) + path;
    xhr.open(method, fullUrl, true);
    xhr.timeout = timeoutMs || 6000;

    if (secret && secret.trim().length > 0)
        xhr.setRequestHeader("Authorization", "Bearer " + secret.trim());
    if (body !== null && body !== undefined)
        xhr.setRequestHeader("Content-Type", "application/json");

    var finished = false;
    function fail(msg) {
        if (finished)
            return;
        finished = true;
        if (onError)
            onError(msg);
    }

    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || finished)
            return;
        finished = true;
        if (xhr.status >= 200 && xhr.status < 300) {
            var text = (xhr.responseText || "").trim();
            if (!text) {
                if (onSuccess)
                    onSuccess({});
                return;
            }
            try {
                var parsed = JSON.parse(text);
                if (onSuccess)
                    onSuccess(parsed);
            } catch (e) {
                if (onSuccess)
                    onSuccess({ raw: text });
            }
        } else {
            if (onError)
                onError("HTTP " + xhr.status);
        }
    };

    xhr.onerror = function () {
        fail("Network error");
    };
    xhr.ontimeout = function () {
        fail("Timeout");
    };

    try {
        if (body !== null && body !== undefined)
            xhr.send(JSON.stringify(body));
        else
            xhr.send();
    } catch (e) {
        fail(String(e));
    }
}

function getLastDelay(proxyObj) {
    if (!proxyObj)
        return 0;
    var hist = proxyObj.history;
    if (hist && hist.length > 0) {
        var last = hist[hist.length - 1];
        if (last && typeof last.delay === "number")
            return last.delay;
    }
    return 0;
}

function resolveDelay(proxiesMap, name, depth) {
    if (!proxiesMap || !name || (depth || 0) > 6)
        return 0;
    var p = proxiesMap[name];
    if (!p)
        return 0;
    var d = getLastDelay(p);
    if (d > 0)
        return d;
    if (p.now && p.now !== name)
        return resolveDelay(proxiesMap, p.now, (depth || 0) + 1);
    return 0;
}

function formatProtocol(proxyObj) {
    if (!proxyObj)
        return "";
    var rawType = String(proxyObj.type || "");
    var t = rawType.toLowerCase();
    var map = {
        "hysteria2": "hy2",
        "hysteria": "hy",
        "wireguard": "wg",
        "shadowsocks": "ss",
        "shadowsocksr": "ssr",
        "rejectdrop": "reject",
        "passrule": "pass",
        "urltest": "url-test",
        "loadbalance": "lb"
    };
    var shortType = map[t] || t;
    if (shortType === "reject" || shortType === "compatible" || shortType === "pass")
        return shortType;
    if (proxyObj.xudp)
        return shortType + " / xudp";
    if (proxyObj.udp)
        return shortType + " / udp";
    return shortType;
}

function isGroupObject(p) {
    return !!(p && Array.isArray(p.all) && p.all.length > 0);
}

function buildGroupsModel(proxiesMap, showGlobalGroup) {
    if (!proxiesMap)
        return [];

    var orderedNames = [];
    var seen = {};
    var globalObj = proxiesMap["GLOBAL"];

    if (globalObj && Array.isArray(globalObj.all)) {
        for (var i = 0; i < globalObj.all.length; i++) {
            var candidate = globalObj.all[i];
            var p = proxiesMap[candidate];
            if (isGroupObject(p) && !p.hidden && candidate !== "GLOBAL" && !seen[candidate]) {
                orderedNames.push(candidate);
                seen[candidate] = true;
            }
        }
    }

    var allKeys = Object.keys(proxiesMap);
    for (var j = 0; j < allKeys.length; j++) {
        var k = allKeys[j];
        var item = proxiesMap[k];
        if (isGroupObject(item) && !item.hidden && k !== "GLOBAL" && !seen[k]) {
            orderedNames.push(k);
            seen[k] = true;
        }
    }

    if (showGlobalGroup && isGroupObject(globalObj)) {
        orderedNames.push("GLOBAL");
    }

    var result = [];
    for (var gIdx = 0; gIdx < orderedNames.length; gIdx++) {
        var gName = orderedNames[gIdx];
        var g = proxiesMap[gName];
        if (!g)
            continue;

        var nodes = [];
        var aliveCount = 0;
        var allList = g.all || [];
        for (var nIdx = 0; nIdx < allList.length; nIdx++) {
            var nName = allList[nIdx];
            var nObj = proxiesMap[nName] || {};
            var nDelay = resolveDelay(proxiesMap, nName, 0);
            var nAlive = nObj.alive !== false && (nDelay > 0 || nObj.alive === true);
            if (nObj.alive === true)
                aliveCount++;
            nodes.push({
                name: nName,
                type: String(nObj.type || ""),
                protocol: formatProtocol(nObj),
                alive: nObj.alive === true,
                delay: nDelay,
                isGroup: isGroupObject(nObj),
                isSelected: (g.now === nName)
            });
        }

        var groupDelay = resolveDelay(proxiesMap, g.now, 0);
        var fixedName = (g.fixed && typeof g.fixed === "string") ? g.fixed : "";
        var groupType = String(g.type || "");
        var canUnfix = fixedName.length > 0 && (groupType === "Fallback" || groupType === "URLTest");

        result.push({
            name: gName,
            type: groupType,
            now: String(g.now || ""),
            fixed: fixedName,
            canUnfix: canUnfix,
            icon: String(g.icon || ""),
            delay: groupDelay,
            aliveCount: aliveCount,
            totalCount: allList.length,
            testUrl: String(g.testUrl || ""),
            nodes: nodes
        });
    }

    return result;
}

function fetchDashboardState(baseUrl, secret, showGlobalGroup, onSuccess, onError) {
    var proxiesDone = false;
    var configsDone = false;
    var versionDone = false;
    var failed = false;

    var proxiesMap = null;
    var mode = "rule";
    var version = "";

    function tryFinish() {
        if (failed || !proxiesDone || !configsDone || !versionDone)
            return;
        onSuccess({
            proxiesMap: proxiesMap,
            groups: buildGroupsModel(proxiesMap, showGlobalGroup),
            mode: mode,
            version: version
        });
    }

    request(baseUrl, secret, "GET", "/proxies", null, 5000, function (data) {
        proxiesMap = (data && data.proxies) ? data.proxies : {};
        proxiesDone = true;
        tryFinish();
    }, function (err) {
        if (!failed) {
            failed = true;
            if (onError)
                onError(err);
        }
    });

    request(baseUrl, secret, "GET", "/configs", null, 5000, function (data) {
        if (data && data.mode)
            mode = String(data.mode).toLowerCase();
        configsDone = true;
        tryFinish();
    }, function () {
        configsDone = true;
        tryFinish();
    });

    request(baseUrl, secret, "GET", "/version", null, 4000, function (data) {
        if (data && data.version)
            version = String(data.version);
        versionDone = true;
        tryFinish();
    }, function () {
        versionDone = true;
        tryFinish();
    });
}

function selectProxy(baseUrl, secret, groupName, proxyName, onSuccess, onError) {
    var path = "/proxies/" + encodeURIComponent(groupName);
    request(baseUrl, secret, "PUT", path, { name: proxyName }, 5000, onSuccess, onError);
}

function unfixProxy(baseUrl, secret, groupName, onSuccess, onError) {
    var path = "/proxies/" + encodeURIComponent(groupName);
    request(baseUrl, secret, "DELETE", path, null, 5000, onSuccess, onError);
}

function setMode(baseUrl, secret, mode, onSuccess, onError) {
    request(baseUrl, secret, "PATCH", "/configs", { mode: mode }, 5000, onSuccess, onError);
}

function testGroupDelay(baseUrl, secret, groupName, testUrl, timeoutMs, onSuccess, onError) {
    var url = (testUrl || DEFAULT_TEST_URL).trim();
    var timeout = timeoutMs || DEFAULT_TIMEOUT;
    var path = "/group/" + encodeURIComponent(groupName)
        + "/delay?url=" + encodeURIComponent(url)
        + "&timeout=" + encodeURIComponent(String(timeout));
    request(baseUrl, secret, "GET", path, null, timeout + 3000, onSuccess, onError);
}

function testProxyDelay(baseUrl, secret, proxyName, testUrl, timeoutMs, onSuccess, onError) {
    var url = (testUrl || DEFAULT_TEST_URL).trim();
    var timeout = timeoutMs || DEFAULT_TIMEOUT;
    var path = "/proxies/" + encodeURIComponent(proxyName)
        + "/delay?url=" + encodeURIComponent(url)
        + "&timeout=" + encodeURIComponent(String(timeout));
    request(baseUrl, secret, "GET", path, null, timeout + 3000, onSuccess, onError);
}

function filterGroups(groups, query) {
    if (!groups || groups.length === 0)
        return [];
    var q = (query || "").trim();
    if (!q)
        return groups;

    var regex = null;
    try {
        regex = new RegExp(q, "i");
    } catch (e) {
        regex = null;
    }

    function matches(text) {
        if (!text)
            return false;
        if (regex)
            return regex.test(text);
        return text.toLowerCase().indexOf(q.toLowerCase()) >= 0;
    }

    var out = [];
    for (var i = 0; i < groups.length; i++) {
        var g = groups[i];
        if (matches(g.name) || matches(g.now)) {
            out.push(g);
            continue;
        }
        var matchedNodes = [];
        for (var j = 0; j < g.nodes.length; j++) {
            var n = g.nodes[j];
            if (matches(n.name) || matches(n.protocol))
                matchedNodes.push(n);
        }
        if (matchedNodes.length > 0) {
            out.push({
                name: g.name,
                type: g.type,
                now: g.now,
                fixed: g.fixed,
                canUnfix: g.canUnfix,
                icon: g.icon,
                delay: g.delay,
                aliveCount: g.aliveCount,
                totalCount: g.totalCount,
                testUrl: g.testUrl,
                nodes: matchedNodes,
                forceExpand: true
            });
        }
    }
    return out;
}
