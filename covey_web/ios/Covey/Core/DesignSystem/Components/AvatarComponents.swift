import SwiftUI

/// Single avatar — image if available, otherwise initials disc.
struct Avatar: View {
    let urlString: String?
    let initials: String
    var size: CGFloat = 40
    var tone: Tone = .neutral

    enum Tone { case neutral, moss, clay, slate, saffron }

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(CoveyColor.edge.opacity(0.6), lineWidth: 0.6))
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(toneBg)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold, design: .serif))
                .foregroundStyle(toneFg)
        }
    }

    private var toneBg: Color {
        switch tone {
        case .neutral: return CoveyColor.paperSunken
        case .moss: return CoveyColor.mossSoft.opacity(0.7)
        case .clay: return CoveyColor.claySoft.opacity(0.7)
        case .slate: return CoveyColor.slateSoft.opacity(0.7)
        case .saffron: return CoveyColor.saffron.opacity(0.4)
        }
    }
    private var toneFg: Color {
        switch tone {
        case .neutral: return CoveyColor.inkMuted
        case .moss: return CoveyColor.ink
        case .clay: return CoveyColor.ink
        case .slate: return CoveyColor.ink
        case .saffron: return CoveyColor.ink
        }
    }
}

/// Overlapping avatar cluster — "garland" of attendees, friends, or crew members.
struct AvatarCluster: View {
    struct Member: Identifiable, Hashable {
        let id: UUID
        let urlString: String?
        let initials: String
        init(id: UUID = UUID(), urlString: String?, initials: String) {
            self.id = id
            self.urlString = urlString
            self.initials = initials
        }
    }

    let members: [Member]
    var maxVisible: Int = 4
    var size: CGFloat = 32
    var overlap: CGFloat = 0.32

    var body: some View {
        let visible = Array(members.prefix(maxVisible))
        let extra = members.count - visible.count

        HStack(spacing: -size * overlap) {
            ForEach(Array(visible.enumerated()), id: \.offset) { (idx, m) in
                Avatar(urlString: m.urlString, initials: m.initials, size: size, tone: tone(for: idx))
                    .background(
                        Circle()
                            .fill(CoveyColor.paper)
                            .frame(width: size + 4, height: size + 4)
                    )
                    .zIndex(Double(visible.count - idx))
            }
            if extra > 0 {
                ZStack {
                    Circle().fill(CoveyColor.ink)
                    Text("+\(extra)")
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(CoveyColor.inkInverse)
                }
                .frame(width: size, height: size)
                .overlay(Circle().stroke(CoveyColor.edge.opacity(0.5), lineWidth: 0.6))
                .background(
                    Circle().fill(CoveyColor.paper).frame(width: size + 4, height: size + 4)
                )
            }
        }
    }

    private func tone(for index: Int) -> Avatar.Tone {
        let palette: [Avatar.Tone] = [.moss, .clay, .slate, .saffron, .neutral]
        return palette[index % palette.count]
    }
}

/// A compact row card: avatar + display name + handle + optional trailing slot.
struct UserMiniCard<Trailing: View>: View {
    let profile: UserProfile
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: CoveySpacing.sm) {
            Avatar(
                urlString: profile.avatarUrl,
                initials: initials(from: profile.displayName),
                size: 42
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).coveyTitle()
                Text("@\(profile.username)")
                    .coveyMono()
            }
            Spacer(minLength: 0)
            trailing
        }
    }

    private func initials(from name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()
    }
}

extension UserMiniCard where Trailing == EmptyView {
    init(profile: UserProfile) {
        self.init(profile: profile, trailing: { EmptyView() })
    }
}
