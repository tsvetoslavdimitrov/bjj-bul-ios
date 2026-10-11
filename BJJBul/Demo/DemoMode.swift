#if DEBUG
import SwiftUI
import UIKit
import AVFoundation

/// DEBUG-only demo mode for screenshots.
/// Launch arguments: `-demo` (mock services, signed in as a sample gym owner) and optionally
/// `-demoScreen <name>` to open one screen directly. All data here is SAMPLE data, not real people or gyms.
enum DemoMode {
    static let screenNames = ["feed", "explore", "gymDetail", "events", "openMats", "training", "profile", "bjjPass",
                              "myGym", "reports", "kiosk", "kioskGuest", "askBJJ", "notifications", "composer", "record",
                              "marketplace", "partnerDashboard"]

    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard isOn, let index = args.firstIndex(of: "-demoScreen"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

// MARK: - Sample media (gradients + SF Symbols, written to Caches as files)

enum DemoMedia {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("demo-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func image(_ name: String, colors: [UIColor], symbol: String, size: CGSize = CGSize(width: 900, height: 900)) -> URL? {
        let url = folder.appendingPathComponent("\(name).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            drawGradient(context.cgContext, size: size, colors: colors)
            drawSymbol(symbol, size: size)
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        try? data.write(to: url)
        return url
    }

    private static func drawGradient(_ cg: CGContext, size: CGSize, colors: [UIColor]) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }

    private static func drawSymbol(_ symbol: String, size: CGSize) {
        let config = UIImage.SymbolConfiguration(pointSize: size.width * 0.32, weight: .semibold)
        if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
            let rect = CGRect(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2,
                              width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: rect)
        }
    }

    /// A 3-second gradient clip (no people, no audio) so the video card has something to play.
    static func video() async -> URL? {
        let url = folder.appendingPathComponent("demo-clip.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let size = CGSize(width: 720, height: 720)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                                         kCVPixelBufferWidthKey as String: Int(size.width),
                                         kCVPixelBufferHeightKey as String: Int(size.height)]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        let frames = 45
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            guard let buffer = pixelBuffer(size: size, progress: CGFloat(frame) / CGFloat(frames)) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 15))
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        return writer.status == .completed ? url : nil
    }

    private static func pixelBuffer(size: CGSize, progress: CGFloat) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width),
                                      height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        let start = UIColor(red: 0.1, green: 0.1 + 0.3 * progress, blue: 0.4, alpha: 1)
        let end = UIColor(red: 0.8 - 0.3 * progress, green: 0.1, blue: 0.2, alpha: 1)
        drawGradient(context, size: size, colors: [start, end])
        context.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        let dot = size.width * 0.12
        context.fillEllipse(in: CGRect(x: (size.width - dot) * progress, y: size.height / 2 - dot / 2, width: dot, height: dot))
        return buffer
    }
}

// MARK: - Demo services (SAMPLE data)

enum DemoData {
    static let ownerId = MockData.user.id

    /// SAMPLE signed-in user: a gym owner/coach of the mock gym, terms accepted.
    static var user: AppUser {
        var user = MockData.user
        user.displayName = "Demo Coach"
        user.belt = .brown
        user.stripes = 1
        user.homeGymId = MockData.gym1Id
        user.termsAcceptedAt = Date()
        user.termsVersion = AppConfig.termsVersion
        user.team = "Sample Team"
        user.teamGymId = MockData.gym1Id
        user.smoothcompProfileURL = URL(string: "https://smoothcomp.com/en/profile/1")
        return user
    }

    /// SAMPLE gyms with coordinates (fictional names and addresses).
    static let extraGyms: [Gym] = [
        MockData.makeGym(id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!, name: "Sample BJJ Лозенец",
                         latin: "Sample BJJ Lozenets", cityId: MockData.sofiaId, address: "Sample street 12, София",
                         lat: 42.6745, lng: 23.3270, monthly: 75),
        MockData.makeGym(id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!, name: "Sample Grappling Младост",
                         latin: "Sample Grappling Mladost", cityId: MockData.sofiaId, address: "Sample blvd 3, София",
                         lat: 42.6510, lng: 23.3790, monthly: 70),
        MockData.makeGym(id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!, name: "Sample Jiu-Jitsu Люлин",
                         latin: "Sample Jiu-Jitsu Lyulin", cityId: MockData.sofiaId, address: "Sample street 7, София",
                         lat: 42.7140, lng: 23.2510, monthly: 65),
        MockData.makeGym(id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!, name: "Sample BJJ Бургас",
                         latin: "Sample BJJ Burgas", cityId: MockData.varnaId, address: "Sample street 1, Бургас",
                         lat: 42.5048, lng: 27.4626, monthly: 60),
    ]

    static var gyms: [Gym] {
        var all = MockData.gyms + extraGyms
        all[0].affiliation = "Sample Affiliation"
        all[0].instagram = "sample.bjj"
        all[0].verified = true
        return all
    }

    /// SAMPLE weekly schedule for the main gym (every day, so the kiosk always has classes).
    static let schedules: [ClassSchedule] = {
        var items: [ClassSchedule] = []
        for day in 1...7 {
            items.append(ClassSchedule(id: UUID(), gymId: MockData.gym1Id, coachId: MockData.coach1Id, weekday: day,
                                       startTime: "07:00", endTime: "08:00", type: .nogi, level: .all, notes: nil))
            items.append(ClassSchedule(id: UUID(), gymId: MockData.gym1Id, coachId: MockData.coach1Id, weekday: day,
                                       startTime: "18:00", endTime: "19:00", type: .fundamentals, level: .beginner, notes: nil))
            items.append(ClassSchedule(id: UUID(), gymId: MockData.gym1Id, coachId: MockData.coach1Id, weekday: day,
                                       startTime: "19:00", endTime: "20:30", type: day % 2 == 0 ? .nogi : .gi,
                                       level: .all, notes: nil))
        }
        return items + MockData.schedules.filter { $0.gymId != MockData.gym1Id }
    }()

    static let askBJJMessages: [AIChatMessage] = [
        AIChatMessage(id: UUID(), role: .user, text: "How do I escape side control?", createdAt: Date().addingTimeInterval(-300)),
        AIChatMessage(id: UUID(), role: .assistant,
                      text: "(Sample answer) Frame first: forearm on the neck/collarbone, other hand on the hip. Bridge to make space, shrimp away, and bring your knee in to recover guard. Don't push with straight arms – keep your elbows tight.",
                      createdAt: Date().addingTimeInterval(-290)),
        AIChatMessage(id: UUID(), role: .user, text: "Има ли open mat в София тази седмица?", createdAt: Date().addingTimeInterval(-120)),
        AIChatMessage(id: UUID(), role: .assistant,
                      text: "(Примерен отговор) Да – в събота от 11:00 в Жиу-жицу Академия София (примерни данни). Провери раздел Events → Open mats за точния час.",
                      createdAt: Date().addingTimeInterval(-110)),
    ]

    /// SAMPLE marketplace products with gradient/SF Symbol images (fictional stores, no real brands).
    static var marketplaceProducts: [Product] {
        var images: [ProductCategory: URL] = [:]
        let palettes: [ProductCategory: [UIColor]] = [
            .gi: [.systemIndigo, .systemBlue], .rashguard: [.systemRed, .systemOrange],
            .shorts: [.darkGray, .black], .belts: [.systemBrown, .black],
            .gear: [.systemTeal, .systemGreen], .supplements: [.systemYellow, .systemOrange],
            .apparel: [.systemPink, .systemPurple],
        ]
        for (category, colors) in palettes {
            if let url = DemoMedia.image("product-\(category.rawValue)", colors: colors, symbol: category.symbol) {
                images[category] = url
            }
        }
        return MockMarketplaceData.products(images: images)
    }

    static var myGym: MyGym {
        MyGym(gymId: MockData.gym1Id, name: MockData.gyms[0].name, slug: "sample-gym", role: .owner,
              status: .active, hasAccess: true)
    }
}

final class DemoAuthService: AuthService {
    func currentUserId() async -> UUID? { DemoData.ownerId }
    func signInWithApple(idToken: String, nonce: String) async throws {}
    func sendEmailCode(to email: String) async throws {}
    func verifyEmailCode(email: String, code: String) async throws {}
    func signOut() async throws {}
    func deleteAccount() async throws {}
}

final class DemoUserService: UserService {
    private var user = DemoData.user
    func currentUser() async throws -> AppUser? { user }
    func update(_ user: AppUser) async throws { self.user = user }
    func favoriteGymIds() async throws -> [UUID] { [MockData.gym1Id] }
    func setFavorite(gymId: UUID, isFavorite: Bool) async throws {}
    func submitSuggestion(entityType: String, entityId: UUID?, message: String) async throws {}
    func acceptTerms(version: String) async throws {}
}

struct DemoGymService: GymService {
    func cities() async throws -> [City] { MockData.cities }
    func gyms(cityId: UUID?) async throws -> [Gym] {
        guard let cityId else { return DemoData.gyms }
        return DemoData.gyms.filter { $0.cityId == cityId }
    }
    func gym(id: UUID) async throws -> Gym? { DemoData.gyms.first { $0.id == id } }
    func schedule(gymId: UUID) async throws -> [ClassSchedule] { DemoData.schedules.filter { $0.gymId == gymId } }
}

final class DemoReviewService: ReviewService {
    private var items: [GymReview] = [
        GymReview(id: UUID(), gymId: MockData.gym1Id, userId: UUID(), authorName: "Sample A.", rating: 5,
                  body: "Страхотни треньори и приятелска атмосфера. (sample)", createdAt: Date().addingTimeInterval(-86400 * 3)),
        GymReview(id: UUID(), gymId: MockData.gym1Id, userId: UUID(), authorName: "Sample B.", rating: 4,
                  body: "Clean mats, good fundamentals class. (sample)", createdAt: Date().addingTimeInterval(-86400 * 10)),
        GymReview(id: UUID(), gymId: MockData.gym1Id, userId: UUID(), authorName: "Sample C.", rating: 5,
                  body: "Great open mats on Saturday. (sample)", createdAt: Date().addingTimeInterval(-86400 * 21)),
    ]
    func reviews(gymId: UUID) async throws -> [GymReview] { items.filter { $0.gymId == gymId } }
    func saveReview(gymId: UUID, rating: Int, body: String) async throws {}
    func deleteReview(id: UUID) async throws { items.removeAll { $0.id == id } }
}

final class DemoOpenMatService: OpenMatService {
    private let items: [OpenMat] = {
        let cal = Calendar.bulgaria
        let today = cal.startOfDay(for: Date())
        func at(_ days: Int, _ hour: Int) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: days, to: today) ?? today) ?? today
        }
        let g = DemoData.gyms
        return [
            OpenMat(id: UUID(), gymId: g[0].id, gymName: g[0].name, cityId: g[0].cityId, startsAt: at(1, 11),
                    endsAt: at(1, 13), style: .both, fee: nil, currency: "EUR", notes: "Sample open mat – all levels",
                    verified: true, postedBy: nil),
            OpenMat(id: UUID(), gymId: g[3].id, gymName: g[3].name, cityId: g[3].cityId, startsAt: at(2, 18),
                    endsAt: at(2, 20), style: .nogi, fee: 5, currency: "EUR", notes: "Sample no-gi rounds",
                    verified: false, postedBy: nil),
            OpenMat(id: UUID(), gymId: g[1].id, gymName: g[1].name, cityId: g[1].cityId, startsAt: at(4, 10),
                    endsAt: at(4, 12), style: .gi, fee: nil, currency: "EUR", notes: "Sample gi open mat",
                    verified: true, postedBy: nil),
            OpenMat(id: UUID(), gymId: g[2].id, gymName: g[2].name, cityId: g[2].cityId, startsAt: at(6, 17),
                    endsAt: at(6, 19), style: .both, fee: 10, currency: "EUR", notes: "Sample comp prep",
                    verified: false, postedBy: nil),
        ]
    }()
    func upcomingOpenMats() async throws -> [OpenMat] { items }
    func createOpenMat(_ draft: OpenMatDraft) async throws {}
    func deleteOpenMat(id: UUID) async throws {}
}

final class DemoTrainingService: TrainingService {
    /// SAMPLE: ~3 sessions a week for 8 weeks.
    private var items: [TrainingSession] = {
        let cal = Calendar.bulgaria
        let today = cal.startOfDay(for: Date())
        let techniques = [["armbar", "closed guard"], ["kimura", "side control"], ["triangle"], ["leg drag", "passing"],
                          ["rear naked choke", "back control"], ["single leg", "takedowns"]]
        var result: [TrainingSession] = []
        for week in 0..<8 {
            let perWeek = week % 3 == 0 ? 4 : 3
            for index in 0..<perWeek {
                let daysAgo = week * 7 + index * 2
                guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
                let type: TrainingType = index == 1 ? .nogi : (index == 3 ? .openmat : .gi)
                result.append(TrainingSession(id: UUID(), date: date, durationMinutes: index == 3 ? 120 : 90, type: type,
                                              gymId: MockData.gym1Id, techniques: techniques[(week + index) % techniques.count],
                                              sparringRounds: 4 + (week + index) % 4, notes: "Sample session",
                                              rating: 3 + (week + index) % 3))
            }
        }
        return result
    }()
    func sessions() async throws -> [TrainingSession] { items.sorted { $0.date > $1.date } }
    func save(_ session: TrainingSession) async throws {
        if let index = items.firstIndex(where: { $0.id == session.id }) { items[index] = session } else { items.append(session) }
    }
    func delete(id: UUID) async throws { items.removeAll { $0.id == id } }
}

final class DemoNotificationService: NotificationService {
    private var items: [AppNotification] = [
        AppNotification(id: UUID(), kind: "open_mat", title: "Sample: New open mat at a gym you follow",
                        body: "Saturday 11:00 · Жиу-жицу Академия София", url: nil,
                        createdAt: Date().addingTimeInterval(-1800), isRead: false),
        AppNotification(id: UUID(), kind: "new_event", title: "Sample: New competition in Sofia",
                        body: "Sample Open 2026 · 15.11.2026", url: nil,
                        createdAt: Date().addingTimeInterval(-86400), isRead: false),
        AppNotification(id: UUID(), kind: "like", title: "Sample: 12 people liked your post",
                        body: "Purple belt day!", url: nil, createdAt: Date().addingTimeInterval(-86400 * 2), isRead: true),
        AppNotification(id: UUID(), kind: "payment", title: "Sample: Payment confirmed",
                        body: "BJJ Pass · 10 classes", url: nil, createdAt: Date().addingTimeInterval(-86400 * 4), isRead: true),
    ]
    private var prefs = NotificationPreferences()
    func notifications() async throws -> [AppNotification] { items }
    func markAllRead() async throws { for index in items.indices { items[index].isRead = true } }
    func preferences() async throws -> NotificationPreferences { prefs }
    func savePreferences(_ preferences: NotificationPreferences) async throws { prefs = preferences }
    func registerDevice(token: String, environment: String) async throws {}
}

final class DemoAthleteService: AthleteService {
    /// SAMPLE competition record.
    private var stored: [AthleteMedal] = [
        AthleteMedal(id: UUID(), eventName: "Sample Open Sofia", placement: 1, division: "Adult / Brown / -82 kg",
                     eventDate: Date().addingTimeInterval(-86400 * 30), source: .smoothcomp, verified: true),
        AthleteMedal(id: UUID(), eventName: "Sample Cup Plovdiv", placement: 2, division: "Adult / Brown / Open",
                     eventDate: Date().addingTimeInterval(-86400 * 90), source: .smoothcomp, verified: true),
        AthleteMedal(id: UUID(), eventName: "Sample Championship", placement: 1, division: "Adult / Purple / -82 kg",
                     eventDate: Date().addingTimeInterval(-86400 * 200), source: .smoothcomp, verified: true),
        AthleteMedal(id: UUID(), eventName: "Sample Winter Open", placement: 3, division: "Adult / Purple / -82 kg",
                     eventDate: Date().addingTimeInterval(-86400 * 320), source: .manual, verified: false),
    ]
    func record(userId: UUID) async throws -> AthleteRecord? {
        AthleteRecord(wins: 18, losses: 6, winsSubmission: 11, winsPoints: 7, syncedAt: Date())
    }
    func medals(userId: UUID) async throws -> [AthleteMedal] { stored }
    func addMedal(_ draft: MedalDraft) async throws {}
    func deleteMedal(id: UUID) async throws { stored.removeAll { $0.id == id } }
    func syncSmoothcomp() async throws -> String { SmoothcompSyncStatus.cached.rawValue }
}

final class DemoSocialService: SocialService {
    private var posts: [Post] = []
    private let mock = MockSocialService()

    /// SAMPLE feed: gradient/SF Symbol images, a song card and a generated video clip.
    func prepare() async {
        guard posts.isEmpty else { return }
        let now = Date()
        let g = DemoData.gyms[0]
        let img1 = DemoMedia.image("post1", colors: [.systemPurple, .systemIndigo], symbol: "medal.fill")
        let img2 = DemoMedia.image("post2", colors: [.systemOrange, .systemRed], symbol: "figure.martial.arts")
        let img3 = DemoMedia.image("post3", colors: [.systemTeal, .systemBlue], symbol: "trophy.fill")
        let img4 = DemoMedia.image("post4", colors: [.systemGreen, .systemTeal], symbol: "sun.max.fill")
        let art = DemoMedia.image("art", colors: [.systemPink, .systemPurple], symbol: "music.note", size: CGSize(width: 300, height: 300))
        let clip = await DemoMedia.video()
        func post(_ hours: Double, _ name: String, _ belt: Belt, _ body: String, _ type: PostType, _ media: [URL?],
                  likes: Int, comments: Int, liked: Bool = false, music: MusicAttachment? = nil) -> Post {
            let date = now.addingTimeInterval(-hours * 3600)
            return Post(id: UUID(), authorId: UUID(), authorName: name, authorAvatarURL: nil, authorBelt: belt,
                        body: body, type: type, gymId: g.id, gymName: g.name, createdAt: date,
                        cursor: BGDate.iso(date), mediaURLs: media.compactMap { $0 },
                        likeCount: likes, commentCount: comments, likedByMe: liked, music: music)
        }
        posts = [
            post(1, "Sample Athlete", .purple, "Първа лилава лента днес! Благодаря на треньорите 🙏 (sample)", .promotion,
                 [img1], likes: 48, comments: 9, liked: true),
            post(3, "Demo Coach", .brown, "Saturday open mat – 30 people on the mats! (sample)", .training,
                 [clip], likes: 31, comments: 4),
            post(6, "Sample Competitor", .blue, "Gold at the Sample Open 🥇 (sample)", .competition,
                 [img3, img2], likes: 64, comments: 12),
            post(20, "Sample Grappler", .white, "Today's playlist for drilling 🎧 (sample)", .training, [],
                 likes: 17, comments: 2,
                 music: MusicAttachment(url: URL(string: "https://open.spotify.com/")!, title: "Sample Track",
                                        artist: "Sample Artist", artworkURL: art)),
            post(30, "Sample Athlete 2", .blue, "Morning no-gi before work ☀️ (sample)", .training, [img4],
                 likes: 22, comments: 1),
            post(52, "Sample Coach 2", .black, "Fundamentals: 5 sweeps from closed guard every white belt should know. (sample)",
                 .progress, [img2], likes: 90, comments: 15),
        ]
    }

    func feed(scope: FeedScope, authorId: UUID?, before: String?, limit: Int) async throws -> [Post] {
        await prepare()
        if before != nil { return [] }
        if let authorId { return posts.filter { $0.authorId == authorId } }
        return posts
    }
    func createPost(body: String, type: PostType, gymId: UUID?, media: [ComposerMedia], music: MusicAttachment?) async throws {}
    func deletePost(id: UUID) async throws { posts.removeAll { $0.id == id } }
    func setLike(postId: UUID, liked: Bool) async throws {}
    func comments(postId: UUID) async throws -> [PostComment] { try await mock.comments(postId: postId) }
    func addComment(postId: UUID, body: String) async throws {}
    func deleteComment(id: UUID) async throws {}
    func profile(userId: UUID) async throws -> PublicProfile? { try await mock.profile(userId: userId) }
    func setFollow(userId: UUID, following: Bool) async throws {}
    func report(_ target: ReportTarget, reason: ReportReason) async throws {}
    func block(userId: UUID) async throws {}
}

extension AppServices {
    /// DEBUG demo container: mocks + rich SAMPLE data, signed in as a sample gym owner.
    static let demo = AppServices(
        gyms: DemoGymService(),
        coaches: MockCoachService(),
        users: DemoUserService(),
        auth: DemoAuthService(),
        social: DemoSocialService(),
        events: MockEventService(),
        reviews: DemoReviewService(),
        openMats: DemoOpenMatService(),
        contributions: MockContributionService(),
        training: DemoTrainingService(),
        notifications: DemoNotificationService(),
        quotes: MockQuoteService(),
        ai: MockAIChatService(),
        athletes: DemoAthleteService(),
        gymManagement: MockGymManagementService(),
        kiosk: MockKioskService(),
        reports: MockReportsService(),
        marketplace: MockMarketplaceService(products: DemoData.marketplaceProducts, sampleOrders: true)
    )
}
#endif
