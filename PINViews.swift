import SwiftUI
import UIKit

enum PINActionMode: String, Identifiable {
    case create, change, disable
    var id: String { rawValue }
}

struct PINSetupView: View {
    let mode: PINActionMode
    let onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var firstPIN = ""
    @State private var step = 0
    @State private var errorText: String?
    @State private var shake = false

    private var title: String {
        switch mode {
        case .create:
            return step == 0 ? "Создайте PIN-код" : "Повторите PIN-код"
        case .change:
            if step == 0 { return "Текущий PIN-код" }
            if step == 1 { return "Новый PIN-код" }
            return "Повторите новый PIN"
        case .disable:
            return "Введите PIN-код"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            return step == 0 ? "Придумайте 4 цифры для защиты приложения" : "Введите код ещё раз для подтверждения"
        case .change:
            if step == 0 { return "Сначала подтвердите текущий код" }
            if step == 1 { return "Теперь придумайте новый код из 4 цифр" }
            return "Повторите новый код"
        case .disable:
            return "Подтвердите текущий PIN, чтобы отключить защиту"
        }
    }

    private var progressText: String {
        switch mode {
        case .create:
            return step == 0 ? "Шаг 1 из 2" : "Шаг 2 из 2"
        case .change:
            return "Шаг \(step + 1) из 3"
        case .disable:
            return "Проверка PIN"
        }
    }

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    topBar
                    securityHero
                    pinDots

                    if let errorText {
                        errorBanner(errorText)
                    }

                    PINPad(pin: $pin, onComplete: handlePIN)
                        .frame(maxWidth: 350)
                        .modifier(ShakeEffect(animatableData: shake ? 1 : 0))

                    securityHint
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
        }
        .presentationDetents([.large])
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("PIN-код")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(progressText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Capsule())
                .frame(width: 76)
        }
        .padding(.top, 8)
    }

    private var securityHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.green.opacity(0.28), AppTheme.green.opacity(0.05), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 138, height: 138)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 92, height: 92)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppTheme.green.opacity(0.45), lineWidth: 1)
                    )

                Image(systemName: mode == .disable ? "lock.open.fill" : "lock.shield.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.green)
                    .shadow(color: AppTheme.green.opacity(0.28), radius: 12)
            }

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    private var pinDots: some View {
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(index < pin.count ? AppTheme.green.opacity(0.20) : Color.white.opacity(0.045))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(index < pin.count ? AppTheme.green.opacity(0.9) : Color.white.opacity(0.10), lineWidth: 1)
                        )

                    Circle()
                        .fill(index < pin.count ? AppTheme.green : Color.white.opacity(0.20))
                        .frame(width: index < pin.count ? 11 : 8, height: index < pin.count ? 11 : 8)
                        .shadow(color: index < pin.count ? AppTheme.green.opacity(0.45) : .clear, radius: 6)
                }
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: pin.count)
            }
        }
        .padding(.vertical, 2)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
        }
        .foregroundStyle(Color.red.opacity(0.95))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.red.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.16), lineWidth: 1)
        )
    }

    private var securityHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(AppTheme.green)
            Text("PIN хранится защищённо в Keychain этого iPhone")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fail(_ message: String, resetTo newStep: Int? = nil) {
        errorText = message
        pin = ""
        if let newStep { step = newStep }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation(.default) { shake.toggle() }
    }

    private func successFeedback() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func handlePIN(_ value: String) {
        errorText = nil

        switch mode {
        case .create:
            if step == 0 {
                firstPIN = value
                step = 1
                pin = ""
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else if value == firstPIN, PINManager.setPIN(value) {
                successFeedback()
                onComplete(true)
                dismiss()
            } else {
                firstPIN = ""
                fail("PIN-коды не совпадают. Попробуйте ещё раз", resetTo: 0)
            }

        case .change:
            if step == 0 {
                if PINManager.verify(value) {
                    step = 1
                    pin = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    fail("Неверный текущий PIN-код")
                }
            } else if step == 1 {
                firstPIN = value
                step = 2
                pin = ""
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else if value == firstPIN, PINManager.setPIN(value) {
                successFeedback()
                onComplete(true)
                dismiss()
            } else {
                firstPIN = ""
                fail("PIN-коды не совпадают. Введите новый PIN снова", resetTo: 1)
            }

        case .disable:
            if PINManager.verify(value) {
                _ = PINManager.clearPIN()
                successFeedback()
                onComplete(false)
                dismiss()
            } else {
                fail("Неверный PIN-код")
            }
        }
    }
}

struct PINPad: View {
    @Binding var pin: String
    var onComplete: (String) -> Void

    private let rows = [["1","2","3"],["4","5","6"],["7","8","9"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(row, id: \.self) { digit in
                        key(digit)
                    }
                }
            }

            HStack(spacing: 18) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 76)

                key("0")

                Button {
                    guard !pin.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    pin.removeLast()
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(Color.white.opacity(0.035))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.07), lineWidth: 1))
                }
                .buttonStyle(PINPressButtonStyle())
            }
        }
    }

    private func key(_ digit: String) -> some View {
        Button {
            guard pin.count < 4 else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            pin.append(digit)

            if pin.count == 4 {
                let value = pin
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    onComplete(value)
                }
            }
        } label: {
            Text(digit)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(PINPressButtonStyle())
    }
}

private struct PINPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
                y: 0
            )
        )
    }
}

struct AppLockView: View {
    let faceIDEnabled: Bool
    let pinEnabled: Bool
    let onUnlocked: () -> Void
    let onFaceID: () -> Void

    @State private var pin = ""
    @State private var errorText: String?
    @State private var shake = false

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            RadialGradient(
                colors: [AppTheme.green.opacity(0.14), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 360
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 34)

                    ZStack {
                        Circle()
                            .fill(AppTheme.green.opacity(0.08))
                            .frame(width: 126, height: 126)
                            .overlay(Circle().stroke(AppTheme.green.opacity(0.18), lineWidth: 1))

                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 47, weight: .semibold))
                            .foregroundStyle(AppTheme.green)
                            .shadow(color: AppTheme.green.opacity(0.28), radius: 14)
                    }

                    VStack(spacing: 7) {
                        Text("P2P Offline")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(pinEnabled ? "Введите PIN-код для входа" : "Приложение заблокировано")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }

                    if pinEnabled {
                        HStack(spacing: 14) {
                            ForEach(0..<4, id: \.self) { index in
                                Circle()
                                    .fill(index < pin.count ? AppTheme.green : Color.white.opacity(0.16))
                                    .frame(width: 13, height: 13)
                                    .shadow(color: index < pin.count ? AppTheme.green.opacity(0.42) : .clear, radius: 6)
                            }
                        }
                        .modifier(ShakeEffect(animatableData: shake ? 1 : 0))
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: pin.count)

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red)
                        }

                        PINPad(pin: $pin) { value in
                            if PINManager.verify(value) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onUnlocked()
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                errorText = "Неверный PIN-код"
                                pin = ""
                                withAnimation(.default) { shake.toggle() }
                            }
                        }
                        .frame(maxWidth: 350)
                    }

                    if faceIDEnabled {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onFaceID()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "faceid")
                                    .font(.system(size: 22, weight: .medium))
                                Text("Войти через Face ID")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(AppTheme.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(AppTheme.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.green.opacity(0.22), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 350)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
