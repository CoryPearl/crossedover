import Foundation

public enum GameWindowingPolicy {
    /// Opt-in Mac Driver configuration. A shooter must retain relative mouse
    /// capture while allowing native window movement and fullscreen transitions.
    public static func registry(for appID: String) -> String? {
        let executable: String
        let cursorClipping: String
        switch appID {
        case "11020": executable = "TmForever.exe"; cursorClipping = "N"
        case "730": executable = "cs2.exe"; cursorClipping = "Y"
        default: return nil
        }
        return """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(executable)\\Mac Driver]
        "AllowCursorClipping"="\(cursorClipping)"
        "FullscreenIgnoreMaxSize"="Y"
        "NativeFullscreen"="\(appID == "730" ? "Y" : "N")"
        "CursorClippingLocksWindows"="N"
        "CursorClippingFollowsWindow"="\(appID == "730" ? "Y" : "N")"
        "AllowImmovableWindows"="N"
        "CaptureDisplaysForFullscreen"="N"
        "WindowsFloatWhenInactive"="none"
        "LeftCommandIsCtrl"="N"
        "RightCommandIsCtrl"="N"
        "LeftOptionIsAlt"="Y"

        [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(executable)\\DllOverrides]
        "gameoverlayrenderer"=""
        "gameoverlayrenderer64"=""

        """
    }
}
