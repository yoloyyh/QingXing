import AppKit
import CoreServices
import ServiceManagement

@MainActor
final class LoginLaunchController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var issue: String?

    init() { status = SMAppService.mainApp.status }
    var enabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }
    var detail: String {
        switch status {
        case .enabled: return "登录后在菜单栏后台运行，不自动打开主窗口。"
        case .requiresApproval: return "等待 macOS 批准，暂时不能在登录时自动启动。"
        case .notRegistered: return "开启后，登录电脑无需手动打开轻醒。"
        case .notFound: return "请从轻醒.app 中设置登录启动。"
        @unknown default: return "请到系统登录项中查看启动状态。"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ value: Bool) {
        issue = nil
        refresh()
        do {
            if value {
                if needsApproval { openSettings(); return }
                if !enabled { try SMAppService.mainApp.register() }
            } else if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            issue = "登录启动设置未成功：\(error.localizedDescription)"
        }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
