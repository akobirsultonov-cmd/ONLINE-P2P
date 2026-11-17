import SwiftUI
import UIKit

struct SplashContainerView: View {
    @State private var showMain = false
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            if showMain {
                RootView().transition(.opacity)
            } else {
                SplashView(fadeOut: fadeOut)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: showMain)
        .task {
            try? await Task.sleep(nanoseconds: 4_450_000_000)
            fadeOut = true
            try? await Task.sleep(nanoseconds: 420_000_000)
            showMain = true
        }
    }
}

struct SplashView: View {
    var fadeOut: Bool = false

    @State private var imageOpacity: CGFloat = 1
    @State private var effectsOpacity: CGFloat = 0
    @State private var outerRotation: Double = -20
    @State private var innerRotation: Double = 35
    @State private var spinnerRotation: Double = 0
    @State private var pulse = false
    @State private var phase = 0
    @State private var travel: CGFloat = 0
    @State private var shimmerX: CGFloat = -0.45
    @State private var exitOpacity: CGFloat = 1
    @State private var exitScale: CGFloat = 1

    private let artworkSize = CGSize(width: 864, height: 1536)
    private let green = Color(red: 0.02, green: 0.98, blue: 0.58)
    private let cyan = Color(red: 0.02, green: 0.72, blue: 1.00)
    private let bg = Color(red: 0.0, green: 0.012, blue: 0.018)

    var body: some View {
        GeometryReader { proxy in
            let layout = ArtworkLayout(viewSize: proxy.size, artworkSize: artworkSize)

            ZStack {
                bg

                if let image = Self.splashImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(imageOpacity)
                } else {
                    Color.black
                }

                Group {
                    // 1) Logo animation — light only, artwork remains untouched.
                    logoEffects(layout)

                    // 2) Stage animation — no duplicate text/icons, just motion and glow.
                    stageEffects(layout)

                    // 3) Premium lower-horizon glow.
                    globeEffects(layout)

                    // 4) Soft moving light sweep.
                    lightSweep(layout)
                }
                .opacity(effectsOpacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(exitScale)
            .opacity(exitOpacity)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background(bg.ignoresSafeArea())
        .onAppear(perform: startAnimation)
        .onChange(of: fadeOut) { value in
            guard value else { return }
            withAnimation(.easeInOut(duration: 0.40)) {
                exitOpacity = 0
                exitScale = 1.018
            }
        }
    }

    private static let splashImage: UIImage? = {
        // Load the exact approved JPEG once, before the first animated frame.
        if let url = Bundle.main.url(forResource: "SplashBackground", withExtension: "jpeg"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let url = Bundle.main.url(forResource: "SplashBackground", withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return nil
    }()

    private func logoEffects(_ layout: ArtworkLayout) -> some View {
        let center = layout.point(x: 432, y: 455)
        let d = layout.length(430)

        return ZStack {
            Circle()
                .trim(from: 0.03, to: 0.27)
                .stroke(
                    LinearGradient(colors: [green.opacity(0.18), green, cyan], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: max(2.2, layout.length(5.5)), lineCap: .round)
                )
                .frame(width: d, height: d)
                .rotationEffect(.degrees(outerRotation))
                .shadow(color: green.opacity(0.70), radius: max(5, layout.length(14)))

            Circle()
                .trim(from: 0.51, to: 0.73)
                .stroke(
                    LinearGradient(colors: [cyan, green.opacity(0.22)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: max(1.7, layout.length(4)), lineCap: .round)
                )
                .frame(width: d * 0.88, height: d * 0.88)
                .rotationEffect(.degrees(innerRotation))
                .shadow(color: cyan.opacity(0.58), radius: max(4, layout.length(10)))

            Circle()
                .stroke(green.opacity(pulse ? 0.15 : 0.025), lineWidth: max(1, layout.length(2)))
                .frame(width: d * (pulse ? 1.035 : 0.97), height: d * (pulse ? 1.035 : 0.97))

            // Small orbiting accent dots.
            Circle()
                .fill(green)
                .frame(width: max(4, layout.length(9)), height: max(4, layout.length(9)))
                .shadow(color: green.opacity(0.8), radius: max(4, layout.length(10)))
                .offset(y: -d * 0.50)
                .rotationEffect(.degrees(outerRotation * 0.72))

            Circle()
                .fill(cyan)
                .frame(width: max(3, layout.length(7)), height: max(3, layout.length(7)))
                .shadow(color: cyan.opacity(0.8), radius: max(3, layout.length(8)))
                .offset(x: d * 0.44, y: d * 0.12)
                .rotationEffect(.degrees(innerRotation * 0.50))
        }
        .position(center)
        .allowsHitTesting(false)
    }

    private func stageEffects(_ layout: ArtworkLayout) -> some View {
        let y: CGFloat = 1027
        let left = layout.point(x: 181, y: y)
        let middle = layout.point(x: 432, y: y)
        let right = layout.point(x: 683, y: y)
        let node = layout.length(94)
        let startX = left.x
        let endX = right.x
        let full = max(1, endX - startX)

        return ZStack {
            // A single moving highlight along the existing artwork connector.
            Circle()
                .fill(phase == 1 ? green : cyan)
                .frame(width: max(5, layout.length(10)), height: max(5, layout.length(10)))
                .shadow(color: phase == 1 ? green.opacity(0.9) : cyan.opacity(0.9), radius: max(5, layout.length(12)))
                .position(x: startX + full * travel, y: left.y)
                .opacity(phase > 0 ? 1 : 0)

            // Protection halo.
            Circle()
                .stroke(green.opacity(phase >= 1 ? 0.95 : 0.12), lineWidth: max(2, layout.length(4)))
                .frame(width: node * (pulse && phase >= 1 ? 1.10 : 1.02), height: node * (pulse && phase >= 1 ? 1.10 : 1.02))
                .position(left)
                .shadow(color: phase >= 1 ? green.opacity(0.72) : .clear, radius: max(5, layout.length(13)))

            // Loading ring. This sits directly over the printed loading icon.
            Circle()
                .trim(from: 0.06, to: 0.72)
                .stroke(
                    AngularGradient(colors: [cyan, green, cyan.opacity(0.15)], center: .center),
                    style: StrokeStyle(lineWidth: max(3.8, layout.length(8)), lineCap: .round)
                )
                .frame(width: node * 0.72, height: node * 0.72)
                .rotationEffect(.degrees(spinnerRotation))
                .position(middle)
                .shadow(color: cyan.opacity(phase >= 2 ? 0.90 : 0.25), radius: max(5, layout.length(12)))
                .opacity(phase == 2 ? 1 : (phase >= 3 ? 0.20 : 0.32))

            Circle()
                .stroke(cyan.opacity(phase >= 2 ? 0.95 : 0.15), lineWidth: max(2, layout.length(4)))
                .frame(width: node * (pulse && phase == 2 ? 1.10 : 1.02), height: node * (pulse && phase == 2 ? 1.10 : 1.02))
                .position(middle)
                .shadow(color: phase >= 2 ? cyan.opacity(0.75) : .clear, radius: max(5, layout.length(13)))

            // Ready halo — keep the existing printed checkmark untouched.
            Circle()
                .stroke(green.opacity(phase >= 3 ? 0.98 : 0.10), lineWidth: max(2, layout.length(4)))
                .frame(width: node * (pulse && phase >= 3 ? 1.11 : 1.02), height: node * (pulse && phase >= 3 ? 1.11 : 1.02))
                .position(right)
                .shadow(color: phase >= 3 ? green.opacity(0.82) : .clear, radius: max(5, layout.length(14)))

            if phase >= 3 {
                Circle()
                    .fill(green.opacity(0.15))
                    .frame(width: node * 1.35, height: node * 1.35)
                    .position(right)
                    .blur(radius: max(3, layout.length(8)))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private func globeEffects(_ layout: ArtworkLayout) -> some View {
        let center = layout.point(x: 432, y: 1278)
        let w = layout.length(790)
        let h = layout.length(230)

        return ZStack {
            Ellipse()
                .trim(from: 0.04, to: 0.46)
                .stroke(
                    LinearGradient(colors: [green.opacity(0.12), green, cyan], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: max(1.5, layout.length(3)), lineCap: .round)
                )
                .frame(width: w, height: h)
                .rotationEffect(.degrees(180))
                .shadow(color: cyan.opacity(0.58), radius: max(4, layout.length(10)))

            RadialGradient(
                colors: [cyan.opacity(pulse ? 0.22 : 0.10), green.opacity(0.06), .clear],
                center: .center,
                startRadius: 0,
                endRadius: w * 0.30
            )
            .frame(width: w * 0.80, height: h * 1.20)
            .offset(y: -h * 0.18)
        }
        .position(center)
        .allowsHitTesting(false)
    }

    private func lightSweep(_ layout: ArtworkLayout) -> some View {
        let width = layout.frame.width * 0.20
        return LinearGradient(
            colors: [.clear, Color.white.opacity(0.075), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: width, height: layout.frame.height * 1.15)
        .rotationEffect(.degrees(11))
        .position(
            x: layout.frame.minX + layout.frame.width * shimmerX,
            y: layout.frame.midY
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private func startAnimation() {
        // Background is already fully visible. Fade in only motion effects, never the artwork.
        imageOpacity = 1
        withAnimation(.easeOut(duration: 0.18).delay(0.06)) {
            effectsOpacity = 1
        }

        withAnimation(.linear(duration: 2.15).repeatForever(autoreverses: false)) {
            outerRotation += 360
        }
        withAnimation(.linear(duration: 3.10).repeatForever(autoreverses: false)) {
            innerRotation -= 360
        }
        withAnimation(.linear(duration: 0.82).repeatForever(autoreverses: false)) {
            spinnerRotation += 360
        }
        withAnimation(.easeInOut(duration: 0.70).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.linear(duration: 3.8).repeatForever(autoreverses: false)) {
            shimmerX = 1.35
        }

        phase = 0
        travel = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.72)) {
                phase = 1
                travel = 0.18
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.40) {
            withAnimation(.easeInOut(duration: 0.60)) {
                phase = 2
                travel = 0.50
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.80) {
            withAnimation(.easeInOut(duration: 0.70)) {
                travel = 0.84
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.30) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.70)) {
                phase = 3
                travel = 1.0
            }
        }
    }
}

private struct ArtworkLayout {
    let frame: CGRect
    let scale: CGFloat

    init(viewSize: CGSize, artworkSize: CGSize) {
        // Must match Image.scaledToFill().
        let s = max(viewSize.width / artworkSize.width, viewSize.height / artworkSize.height)
        let w = artworkSize.width * s
        let h = artworkSize.height * s
        scale = s
        frame = CGRect(
            x: (viewSize.width - w) / 2,
            y: (viewSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + x * scale, y: frame.minY + y * scale)
    }

    func length(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}
