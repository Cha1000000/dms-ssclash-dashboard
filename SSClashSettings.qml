import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginSettings {
    id: root
    pluginId: "ssclashDashboard"

    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    StyledText {
        width: parent.width
        text: root.tr("settings_title")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("settings_desc")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "apiUrl"
        label: root.tr("setting_api_url")
        description: root.tr("setting_api_url_desc")
        placeholder: "http://192.168.10.1:9090"
        defaultValue: "http://192.168.10.1:9090"
    }

    StringSetting {
        settingKey: "secret"
        label: root.tr("setting_secret")
        description: root.tr("setting_secret_desc")
        placeholder: ""
        defaultValue: ""
    }

    ColorSetting {
        settingKey: "accentColor"
        label: root.tr("setting_accent_color")
        description: root.tr("setting_accent_color_desc")
        defaultValue: "#19b5ff"
    }

    StringSetting {
        settingKey: "testUrl"
        label: root.tr("setting_test_url")
        description: root.tr("setting_test_url_desc")
        placeholder: "https://www.google.com/generate_204"
        defaultValue: "https://www.google.com/generate_204"
    }

    SliderSetting {
        settingKey: "testTimeout"
        label: root.tr("setting_test_timeout")
        description: root.tr("setting_test_timeout_desc")
        defaultValue: 5000
        minimum: 1000
        maximum: 10000
        unit: "ms"
        leftIcon: "timer"
    }

    SliderSetting {
        settingKey: "pollInterval"
        label: root.tr("setting_poll_interval")
        description: root.tr("setting_poll_interval_desc")
        defaultValue: 30
        minimum: 10
        maximum: 120
        unit: "s"
        leftIcon: "schedule"
    }

    ToggleSetting {
        settingKey: "showGlobalGroup"
        label: root.tr("setting_show_global")
        description: root.tr("setting_show_global_desc")
        defaultValue: true
    }
}
