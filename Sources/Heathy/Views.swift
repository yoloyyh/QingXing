import AppKit
import AVFoundation
import HeathyCore
import SwiftUI

enum Palette {
    static let ink = adaptive(light: NSColor(red: 0.13, green: 0.23, blue: 0.20, alpha: 1), dark: .init(white: 0.91, alpha: 1))
    static let buddyInk = Color(red: 0.13, green: 0.23, blue: 0.20)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let green = adaptive(light: .init(red: 0.17, green: 0.47, blue: 0.36, alpha: 1), dark: .init(red: 0.57, green: 0.80, blue: 0.65, alpha: 1))
    static let mint = Color(red: 0.79, green: 0.91, blue: 0.78)
    static let paper = adaptive(light: .init(red: 0.97, green: 0.97, blue: 0.94, alpha: 1), dark: .init(red: 0.13, green: 0.17, blue: 0.15, alpha: 1))
    static let surface = adaptive(light: .white, dark: .init(red: 0.19, green: 0.23, blue: 0.20, alpha: 1))
    static let line = adaptive(light: .init(red: 0.87, green: 0.89, blue: 0.84, alpha: 1), dark: .init(white: 0.3, alpha: 1))
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

@MainActor
struct DashboardView: View {
    private var palette: ThemePalette { ThemePalette(theme: state.theme) }
    @ObservedObject var state: AppState
    @ObservedObject private var startup: LoginLaunchController
    init(state: AppState, startup: LoginLaunchController? = nil) {
        self.state = state
        self.startup = startup ?? LoginLaunchController()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.quiet { quietBanner }
            if state.page == .settings { settings }
            else if state.page == .calibration { calibration }
            else { dashboard }
            footer
        }
        .padding(22)
        .frame(width: 366)
        .background(palette.paper)
        .foregroundStyle(palette.ink)
        .tint(palette.green)
    }

    private var quietBanner: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Label("安静模式已开启", systemImage: "bell.slash.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.orange)
                Text("检测结果可查看，距离、姿态和休息不弹窗。")
                    .font(.system(size: 10)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("恢复弹窗") { state.quiet = false }.controlSize(.small)
                .accessibilityLabel("关闭安静模式并恢复提醒弹窗")
        }.padding(10).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)).padding(.bottom, 12)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").foregroundStyle(palette.green).font(.system(size: 18))
                Text("轻醒").font(.system(size: 20, weight: .semibold))
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(state.cameraActive ? palette.green : palette.muted).frame(width: 6, height: 6)
                Text(state.statusLabel).font(.system(size: 11, weight: .medium))
            }.padding(.horizontal, 9).padding(.vertical, 5).background(palette.surface.opacity(0.8), in: Capsule())
            Button { state.page = state.page == .settings ? .dashboard : .settings } label: {
                Image(systemName: state.page == .settings ? "xmark" : "slider.horizontal.3").font(.system(size: 14))
            }.buttonStyle(.plain).padding(.leading, 8).accessibilityLabel(state.page == .settings ? "返回" : "设置与隐私")
        }.padding(.bottom, 14)
    }

    private var dashboard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                HealthRingView(theme: state.theme, expression: state.buddyExpression, progress: state.healthEnergy, isFull: state.restCompleted)
                    .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.healthRingLabel).font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.green).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(palette.green.opacity(0.10), in: Capsule())
                    Text(state.buddyHeadline).font(.system(size: 17, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.buddyDetail).font(.system(size: 11)).foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(state.isResting ? "本轮休息 \(state.activeRestMinutes) 分钟" : "本轮工作").font(.system(size: 12)).foregroundStyle(palette.muted)
                    Spacer()
                    if state.isResting { Text(state.restCompleted ? "已充满" : timeString(state.restRemaining)).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit() }
                    else {
                        Text("\(Int(state.workDuration / 60))").font(.system(size: 29, weight: .medium, design: .rounded))
                        Text("分钟").font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                }
                ProgressView(value: state.isResting ? state.restProgress : min(1, state.workDuration / (state.workMinutes * 60)))
                    .progressViewStyle(.linear).tint(state.restUrgency == .none ? palette.green : state.restPresentationLevel.cueColor)
                Text(state.restPlanSummary)
                    .font(.system(size: 11)).foregroundStyle(state.restUrgency == .none ? palette.muted : state.restPresentationLevel.cueColor)
                if !state.isResting {
                    Text("短暂锁屏暂停累计；离开满 \(Int(state.breakMinutes)) 分钟后重新计时")
                        .font(.system(size: 10)).foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(15).background(palette.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 15))

            VStack(spacing: 12) {
                statusRow("屏幕距离", symbol: "arrow.left.and.right", value: state.distanceLabel, warning: state.distanceWarning)
                if let reference = state.distanceReferenceDetail {
                    Text(reference).font(.system(size: 10)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let issue = state.distanceIssue {
                    Text(issue).font(.system(size: 10)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                if let decision = state.lastDistanceDecision {
                    Text("本轮提醒：" + decision).font(.system(size: 10)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                if let detail = state.distanceFollowUpDetail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                statusRow("头部姿态", symbol: "person.crop.rectangle", value: state.postureLabel, warning: state.postureWarning)
                if let issue = state.postureIssue {
                    Text(issue).font(.system(size: 10)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }

            if !state.cameraActive && !state.cameraBusy && (state.needsDistanceCalibration || (state.experimentalPosture && !state.hasHeadReference)) {
                Button(state.experimentalPosture ? "用 5 秒，记录距离和头部 →" : "用 5 秒，校准舒服的位置 →") { state.beginCalibration() }.disabled(state.isPaused || state.isResting)
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.green)
            }

            Button { state.enableCamera() } label: {
                Label(state.cameraActive ? "正在检测…" : "立即检测 · 5 秒", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(state.cameraActive || state.cameraBusy || state.isPaused || state.isResting)
            if state.needsDistanceCalibration {
                Text("首次使用需先记录参考位置，点击后进入校准引导。")
                    .font(.system(size: 10)).foregroundStyle(palette.muted)
            }

            if state.isResting {
                HStack {
                    Button(state.restCompleted ? "满血出发" : "充能中，慢慢来") { state.finishRest() }
                        .buttonStyle(.borderedProminent).disabled(!state.restCompleted)
                    if !state.restCompleted { Button("提前返回") { state.cancelRest() }.buttonStyle(.bordered) }
                }.controlSize(.regular)
            } else if state.cameraActive || state.manualTimerRunning || state.isPaused {
                HStack(spacing: 9) {
                    Button { state.beginRest() } label: {
                        Label("现在休息", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button(state.isPaused ? "继续" : "暂停 15 分钟") { state.isPaused ? state.resume() : state.pause() }
                        .buttonStyle(.bordered)
                }.controlSize(.large)
            } else {
                VStack(spacing: 8) {
                    Button { state.enableCamera() } label: {
                        Label(state.cameraBusy ? "等待摄像头…" : (state.needsDistanceCalibration ? "校准 5 秒并开始" : "检测 5 秒"), systemImage: "video").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(state.cameraBusy)
                    Button("先用休息计时，不开摄像头") { state.toggleManualTimer() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(palette.muted)
                }
            }

            DailyHealthAchievements(theme: state.theme, adjustments: state.adjustments, rests: state.rests)

            if case .denied = state.cameraStatus {
                Button("摄像头未授权 · 前往系统设置") { state.openCameraPermissions() }.font(.system(size: 11))
            }
            Text(state.cameraDetail).font(.system(size: 10)).foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 15)
    }

    private var settings: some View {
        ScrollView { SettingsView(state: state, startup: startup).padding(.trailing, 3) }.frame(height: 480).padding(.bottom, 16)
    }

    private var calibration: some View {
        VStack(spacing: 14) {
            if let session = state.cameraSession {
                CameraPreview(session: session).frame(height: 178).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomLeading) {
                        Text("仅预览 · 不录制").font(.system(size: 10)).padding(6).background(.black.opacity(0.45), in: Capsule())
                            .foregroundStyle(.white).padding(8)
                    }
            }
            Text(state.calibrationHeadline).font(.system(size: 19, weight: .semibold))
            Text(state.calibrationInstruction).font(.system(size: 12)).foregroundStyle(palette.muted)
                .multilineTextAlignment(.center).frame(minHeight: 38)
            if !state.calibrationCaptureStarted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("直接记录你的参考姿势").font(.system(size: 12, weight: .medium))
                    Text("采用 60 cm 作为默认参考，之后靠近约 5 cm 提醒。")
                        .font(.system(size: 10)).foregroundStyle(palette.muted)
                    Text("参考 OSHA 建议的 50–100 cm 范围。60 cm 是预设值，距离变化根据人像估算。")
                        .font(.system(size: 10)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                Button("坐好啦，记录参考 5 秒") { state.startCalibrationCapture() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!state.canStartCalibration)
            }
            if state.calibrationCaptureStarted && (!state.calibrationComplete || (state.experimentalPosture && !state.hasHeadReference)) { ProgressView(value: state.calibrationProgress) }
            if state.calibrationCaptureStarted && !state.latestSample.isValid { Text(state.observationMessage).font(.system(size: 11)).foregroundStyle(.orange) }
            if state.calibrationCaptureStarted && state.experimentalPosture, let issue = state.postureIssue {
                Text(issue).font(.system(size: 11)).foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Text("低头和侧倾只需脸部清晰，无需双肩入镜。肩部清晰时，可补充相对头肩位置判断。")
                .font(.system(size: 10)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            Text(state.cameraActive ? "剩余 \(state.scanSecondsRemaining) 秒，到时自动关闭摄像头" : state.cameraDetail)
                .font(.system(size: 11)).foregroundStyle(palette.green)
            Button(state.calibrationComplete ? "完成，返回" : (state.calibrationCaptureStarted ? "取消并关闭摄像头" : "返回")) {
                if state.calibrationComplete { state.page = .dashboard } else { state.disableCamera() }
            }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(.vertical, 8).padding(.bottom, 15)
    }

    private var footer: some View {
        VStack(spacing: 11) {
            Rectangle().fill(palette.line).frame(height: 1)
            HStack {
                Button { state.tryDemo() } label: { Label("试试提醒", systemImage: "play.circle") }
                    .disabled(!state.canPreviewRestReminder || state.page == .calibration)
                Spacer()
                if state.cameraActive || state.cameraBusy {
                    Button("停止检测") { state.disableCamera() }
                } else if state.page != .calibration && state.checksEnabled && state.automaticChecks {
                    Button("检测 5 秒") { state.enableCamera() }.disabled(state.isPaused || state.isResting)
                    Button("停止自动检测") { state.disableCamera() }
                } else if state.page != .calibration && state.manualTimerRunning {
                    Button("检测 5 秒") { state.enableCamera() }.disabled(state.isPaused || state.isResting)
                    Button("暂停计时") { state.toggleManualTimer() }
                } else if state.page != .calibration {
                    Button("退出") { NSApplication.shared.terminate(nil) }
                }
            }.font(.system(size: 11)).foregroundStyle(palette.muted).buttonStyle(.plain)
        }
    }

    private func statusRow(_ title: String, symbol: String, value: String, warning: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).frame(width: 17).foregroundStyle(palette.muted)
            Text(title).foregroundStyle(palette.muted)
            Spacer(minLength: 3)
            Text(value).foregroundStyle(warning ? Color.orange : palette.ink).lineLimit(1).minimumScaleFactor(0.8)
        }.font(.system(size: 11))
    }
    private func timeString(_ seconds: TimeInterval) -> String { String(format: "%02d:%02d", Int(ceil(seconds)) / 60, Int(ceil(seconds)) % 60) }
}

struct SettingsView: View {
    private var palette: ThemePalette { ThemePalette(theme: state.theme) }
    @ObservedObject var state: AppState
    @ObservedObject var startup: LoginLaunchController
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("按你的节奏来").font(.system(size: 19, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text("外观主题").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in
                        Button { state.theme = theme } label: {
                            VStack(spacing: 4) {
                                OwlArtwork(theme: theme).frame(width: 60, height: 60)
                                HStack(spacing: 3) {
                                    Text(theme.title)
                                    if state.theme == theme { Image(systemName: "checkmark.circle.fill") }
                                }.font(.system(size: 10, weight: .medium))
                            }.frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(ThemePalette(theme: theme).surface, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(state.theme == theme ? palette.green : palette.line, lineWidth: state.theme == theme ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel("切换为" + theme.title + "主题")
                            .accessibilityValue(state.theme == theme ? "已选中" : "未选中")
                    }
                }
                Text("界面、猫头鹰和 Dock 图标同步切换，选择会自动保存。")
                    .font(.system(size: 10)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("登录时启动轻醒", isOn: Binding(get: { startup.enabled }, set: { startup.setEnabled($0) }))
                    .toggleStyle(.switch).font(.system(size: 12))
                Text(startup.detail).font(.system(size: 10)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                if startup.needsApproval {
                    HStack {
                        Button("到系统登录项中允许") { startup.openSettings() }
                        Button("取消申请") { startup.setEnabled(false) }
                    }.font(.system(size: 11))
                }
                if let issue = startup.issue { Text(issue).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Text("会记住已开启的自动检测：下次启动后，每 30 分钟检测 5 秒。关闭窗口继续运行，退出后停止本次运行。")
                    .font(.system(size: 10)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }.onAppear { startup.refresh() }
            Menu {
                Button("靠太近 · 大眼睛和晕圈") { state.tryDemo(expression: .tooClose) }
                Button("距离复查 · 看看三级提醒") { state.tryDistanceDemo() }
                Button("低头 · 抬抬头") { state.tryDemo(expression: .headDown) }
                Button("侧倾 · 轻轻回正") { state.tryDemo(expression: .headTilt) }
                Button("该休息 · 打哈欠伸翅膀") { state.tryRestDemo() }
                Button("休息中 · 闭眼放松") { state.tryDemo(expression: .resting) }
                Button("调整奖励 · 开心星星") { state.tryDemo(expression: .happy) }
                Button("检测中 · 睁眼观察") { state.tryDemo(expression: .checking) }
                Button("没看清 · 疑惑") { state.tryDemo(expression: .unclear) }
            } label: {
                Label("看看小猫头鹰的表情", systemImage: "face.smiling")
            }.font(.system(size: 12)).disabled(!state.canPreviewRestReminder)
            VStack(alignment: .leading, spacing: 11) {
                Text("工作与休息").font(.system(size: 13, weight: .semibold))
                Stepper(value: $state.workMinutes, in: 15...90, step: 5) {
                    Text("工作 \(Int(state.workMinutes)) 分钟后提醒").frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 12))
                Stepper(value: $state.breakMinutes, in: 1...20, step: 1) {
                    Text("每次休息 \(Int(state.breakMinutes)) 分钟").frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 12))
                Text("快捷方案 · 工作 / 休息（分钟）").font(.system(size: 10)).foregroundStyle(palette.muted)
                HStack(spacing: 7) {
                    schedulePreset(work: 25, rest: 5)
                    schedulePreset(work: 45, rest: 5)
                    schedulePreset(work: 50, rest: 10)
                }
                Text(state.isResting ? "本轮休息 \(state.activeRestMinutes) 分钟；修改将在下次休息生效。" : "每工作 \(Int(state.workMinutes)) 分钟，离开屏幕活动 \(Int(state.breakMinutes)) 分钟。")
                    .font(.system(size: 10)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                Link("休息建议 · HSE：每小时离屏 5–10 分钟", destination: URL(string: "https://www.hse.gov.uk/msd/dse/work-routine.htm")!)
                    .font(.system(size: 10))
            }.padding(13).background(palette.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            Toggle("安静模式", isOn: $state.quiet).toggleStyle(.switch)
            Text("开启后只更新状态栏，不弹出提醒或庆祝。会议时可以手动开启。")
                .font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, -10)
            Toggle("超时后增强休息提醒", isOn: $state.strongRestReminders).toggleStyle(.switch).font(.system(size: 12))
            Text("超时 3 分钟亮起边框，10 分钟显示居中大卡片。开始休息立即撤掉；可暂缓 5 分钟。")
                .font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, -9)
                .fixedSize(horizontal: false, vertical: true)
            Button("预览休息提醒") { state.tryRestDemo() }.font(.system(size: 12)).disabled(!state.canPreviewRestReminder)
            Toggle("每 30 分钟检测 5 秒", isOn: $state.automaticChecks).toggleStyle(.switch).font(.system(size: 12))
            Text("确认靠近后改为每 5 分钟复查，恢复后回到半小时。每轮最多 5 秒；会记住自动检测选择，关闭后仅手动。")
                .font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, -10)
            if state.cameras.count > 1 {
                Picker("摄像头", selection: Binding(get: { state.selectedCameraID }, set: { state.selectCamera($0) })) {
                    ForEach(state.cameras) { camera in Text(camera.name).tag(camera.id) }
                }.font(.system(size: 11)).disabled(state.cameraActive || state.cameraBusy)
            }
            Toggle("低头 / 侧倾提醒", isOn: $state.experimentalPosture).toggleStyle(.switch).font(.system(size: 12))
            Text("仅需脸部清晰，比较低头和侧倾相对参考的持续变化；双肩不是必要条件。不测颈椎角度，头部靠近由距离提醒单独判断。")
                .font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, -9)
            Button("重新校准 5 秒") { state.beginCalibration() }.font(.system(size: 12))
                .disabled(state.cameraActive || state.cameraBusy || state.isPaused || state.isResting)
            Link("距离建议来源 · OSHA", destination: URL(string: "https://www.osha.gov/etools/computer-workstations/components/monitors")!)
                .font(.system(size: 10))
            VStack(alignment: .leading, spacing: 8) {
                Label("只看被允许的摄像头", systemImage: "lock.shield").font(.system(size: 12, weight: .semibold))
                Text("画面仅在内存里分析，不录制、不保存、不上传。无需麦克风、屏幕录制、文件或键鼠权限，也不读取其他应用。")
                Text("本地只保存设置、校准参考和当日次数。摄像头工作时系统指示灯会亮。")
                Button("管理系统摄像头授权") { state.openCameraPermissions() }.font(.system(size: 11))
            }.font(.system(size: 10)).foregroundStyle(palette.muted).padding(13)
                .background(palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("清除本地数据") { confirmClear = true }.foregroundStyle(palette.muted)
                Spacer()
                Button("退出轻醒") { NSApplication.shared.terminate(nil) }.foregroundStyle(palette.muted)
            }.font(.system(size: 11)).buttonStyle(.plain)
        }
        .confirmationDialog("清除设置、校准参考和当日次数？这也会关闭摄像头检测。系统授权需在系统设置中撤销。", isPresented: $confirmClear) {
            Button("清除并关闭检测", role: .destructive) { startup.setEnabled(false); state.clearLocalData() }
            Button("取消", role: .cancel) {}
        }
    }

    private func schedulePreset(work: Double, rest: Double) -> some View {
        let selected = state.workMinutes == work && state.breakMinutes == rest
        return Button {
            state.workMinutes = work
            state.breakMinutes = rest
        } label: {
            Text("\(Int(work)) / \(Int(rest))").font(.system(size: 11, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .foregroundStyle(selected ? palette.green : palette.ink)
                .background(selected ? palette.green.opacity(0.12) : palette.paper, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? palette.green : palette.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct ReminderCard: View {
    private var palette: ThemePalette { ThemePalette(theme: state.theme) }
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        if let notice = state.notice {
            let restLevel = notice.kind == .rest ? state.restPresentationLevel : .none
            let isDistance = notice.kind == .distance
            let isReward = notice.kind == .reward
            let isRestReward = isReward && notice.rewardKind == .rest
            let cueLevel = max(restLevel, isDistance ? notice.distanceLevel.emphasis : .none)
            VStack(spacing: 9) {
                HStack {
                    Text(notice.isDemo ? "轻醒 · 提醒演示" : (isReward ? "轻醒 · \(isRestReward ? "满血时刻" : "调整成功")" : (notice.kind == .rest ? "轻醒 · 休息时间到" : (isDistance ? "轻醒 · 距离提醒" : "轻醒 · 小小提醒")))).font(.system(size: 10)).foregroundStyle(palette.muted)
                    Spacer()
                    Button { state.closeNotice() } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(.plain).accessibilityLabel((notice.kind == .rest || isDistance) && !notice.isDemo ? "收起并稍后复查或提醒" : "收起提醒")
                }
                if notice.kind == .rest {
                    Text(state.restOverdueMinutes == 0 ? "休息时间到啦" : "已超时 \(state.restOverdueMinutes) 分钟")
                        .font(.system(size: restLevel == .urgent ? 15 : 12, weight: .semibold))
                        .foregroundStyle(restLevel.cueColor).padding(.horizontal, 11).padding(.vertical, 5)
                        .background(restLevel.cueColor.opacity(0.10), in: Capsule())
                }
                if isDistance {
                    Text(notice.distanceLevel == .gentle ? "距离太近 · 请往后坐一点" : (notice.distanceLevel == .firm ? "复查后仍然偏近" : "多次复查仍然偏近"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(cueLevel.cueColor)
                        .padding(.horizontal, 11).padding(.vertical, 5).background(cueLevel.cueColor.opacity(0.10), in: Capsule())
                }
                if isRestReward {
                    HealthRingView(theme: state.theme, expression: .happy, progress: 1, isFull: true)
                        .frame(width: 166, height: 166).id(notice.id)
                    Text("100%").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(palette.green)
                } else if isReward {
                    ZStack(alignment: .bottomTrailing) {
                        BuddyView(theme: state.theme, expression: .happy).frame(width: 148, height: 136).id(notice.id)
                        Text("+1").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(palette.green)
                            .padding(.horizontal, 12).padding(.vertical, 5).background(palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(palette.green.opacity(0.3), lineWidth: 2)).offset(x: 15)
                    }.padding(.horizontal, 15)
                } else {
                    BuddyView(theme: state.theme, expression: notice.buddyExpression)
                        .frame(width: cueLevel == .urgent || isDistance ? 126 : 104, height: cueLevel == .urgent || isDistance ? 118 : 98)
                }
                Text(!notice.isDemo && (isDistance || notice.kind == .posture) && state.cameraActive && state.isRecovering ? "正在确认调整，请保持" : (!notice.isDemo && (isDistance || notice.kind == .posture) && state.recoveryUnconfirmed ? "本轮未完成确认" : notice.title)).font(.system(size: cueLevel == .urgent || isDistance || isReward ? 22 : (cueLevel == .overdue ? 19 : 17), weight: .semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(!notice.isDemo && (isDistance || notice.kind == .posture) && state.recoveryUnconfirmed && !state.cameraActive ? "已看到回到参考范围，但稳定样本不足。摄像头已关闭，可坐稳后再复查 5 秒。" : notice.message).font(.system(size: cueLevel == .urgent || isDistance ? 13 : 11)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if isRestReward && !notice.isDemo && state.restCompleted {
                    Button { state.finishRest() } label: {
                        Text("满血出发").font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                    }.buttonStyle(.plain).foregroundStyle(colorScheme == .dark ? palette.buddyInk : .white)
                        .background(palette.green, in: RoundedRectangle(cornerRadius: 11))
                    Text("也可以继续休息，满血状态会保留").font(.system(size: 10)).foregroundStyle(palette.muted)
                } else if isReward && !notice.isDemo {
                    DailyHealthAchievements(theme: state.theme, adjustments: state.adjustments, rests: state.rests)
                } else if notice.isDemo && isDistance {
                    if notice.distanceLevel < .urgent {
                        Button("看看复查后还没调整的提醒") { state.advanceDistanceDemo() }.buttonStyle(.bordered)
                    }
                    Button("模拟调整完成，看看奖励") { state.completeDemo() }.buttonStyle(.borderedProminent)
                } else if notice.isDemo && notice.kind == .rest {
                    if notice.restLevel != .urgent && state.strongRestReminders {
                        Button("再醒目一级") { state.advanceRestDemo() }.buttonStyle(.bordered)
                    }
                    Button { state.completeDemo() } label: {
                        Text("模拟休息完成，看看奖励").font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11).contentShape(RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).foregroundStyle(colorScheme == .dark ? palette.buddyInk : .white)
                        .background(restLevel.cueColor, in: RoundedRectangle(cornerRadius: 11))
                } else if notice.isDemo && notice.kind != .reward {
                    Button("模拟我已经调整好啦") { state.completeDemo() }.buttonStyle(.borderedProminent).controlSize(.small)
                } else if notice.kind == .rest {
                    Button { state.beginRest() } label: {
                        Text("现在休息 \(Int(state.breakMinutes)) 分钟").font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).foregroundStyle(colorScheme == .dark ? palette.buddyInk : .white)
                        .background(restLevel.cueColor, in: RoundedRectangle(cornerRadius: 11))
                    Button("5 分钟后再提醒") { state.snooze() }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(palette.muted)
                    Label("休息满时长，健康环充满", systemImage: "bolt.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(restLevel.cueColor)
                } else if notice.kind == .distance || notice.kind == .posture || notice.kind == .recovering {
                    if !state.cameraActive && !state.cameraBusy {
                        if isDistance {
                            Button { state.enableCamera() } label: {
                                Text("调整好了，复查 5 秒").font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                            }.buttonStyle(.plain).foregroundStyle(colorScheme == .dark ? palette.buddyInk : .white)
                                .background(cueLevel.cueColor, in: RoundedRectangle(cornerRadius: 11)).disabled(state.isPaused || state.isResting)
                        } else {
                            Button("调整好了，复查 5 秒") { state.enableCamera() }
                            .buttonStyle(.borderedProminent).controlSize(.small).disabled(state.isPaused || state.isResting)
                        }
                    }
                    HStack {
                        Button(state.automaticChecks ? (isDistance ? "5 分钟后复查" : "5 分钟后提醒") : "稍后手动复查") { state.snooze() }
                        Spacer()
                        Button("这个判断不准") { state.dismissReminder() }
                    }.font(.system(size: 10)).foregroundStyle(palette.muted).buttonStyle(.plain).padding(.top, 5)
                }
            }
            .padding(cueLevel == .urgent || isDistance || isReward ? 24 : 18).frame(width: cueLevel == .urgent || isDistance || isReward ? 360 : (notice.kind == .rest ? 300 : 278))
            .background(palette.paper, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(notice.kind == .rest || isDistance ? cueLevel.cueColor.opacity(0.55) : palette.line, lineWidth: notice.kind == .rest || isDistance ? 2 : 1))
            .foregroundStyle(palette.ink).tint(notice.kind == .rest || isDistance ? cueLevel.cueColor : palette.green)
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: PreviewSurface, context: Context) { view.preview.session = session }
    static func dismantleNSView(_ view: PreviewSurface, coordinator: ()) { view.preview.session = nil }
}

final class PreviewSurface: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); preview.frame = bounds }
}
