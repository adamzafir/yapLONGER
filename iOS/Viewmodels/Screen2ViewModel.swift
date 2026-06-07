import Foundation
import SwiftUI
import Combine

struct Review: Identifiable, Codable {
    var id: UUID
    var cis: Int
    var wpm: Int
    var pauseControl: Int
    var pitchVariation: Int?
    var pitchConfidence: Double?
    var recognizedWordCount: Int?
    var duration: TimeInterval?
    var audioURL: URL?
    var date: Date

    init(
        id: UUID = UUID(),
        cis: Int,
        wpm: Int,
        pauseControl: Int = 0,
        pitchVariation: Int? = nil,
        pitchConfidence: Double? = nil,
        recognizedWordCount: Int? = nil,
        duration: TimeInterval? = nil,
        audioURL: URL? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.cis = cis
        self.wpm = wpm
        self.pauseControl = pauseControl
        self.pitchVariation = pitchVariation
        self.pitchConfidence = pitchConfidence
        self.recognizedWordCount = recognizedWordCount
        self.duration = duration
        self.audioURL = audioURL
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cis = (try? container.decode(Int.self, forKey: .cis)) ?? 0
        wpm = (try? container.decode(Int.self, forKey: .wpm)) ?? 0
        pauseControl = (try? container.decode(Int.self, forKey: .pauseControl)) ?? cis
        pitchVariation = try? container.decode(Int.self, forKey: .pitchVariation)
        pitchConfidence = try? container.decode(Double.self, forKey: .pitchConfidence)
        recognizedWordCount = try? container.decode(Int.self, forKey: .recognizedWordCount)
        duration = try? container.decode(TimeInterval.self, forKey: .duration)
        audioURL = try? container.decode(URL.self, forKey: .audioURL)
        date = (try? container.decode(Date.self, forKey: .date)) ?? Date()
    }

    var resolvedAudioURL: URL? {
        guard let audioURL else { return nil }
        if FileManager.default.fileExists(atPath: audioURL.path) {
            return audioURL
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let migratedURL = documents.appendingPathComponent(audioURL.lastPathComponent)
        return FileManager.default.fileExists(atPath: migratedURL.path) ? migratedURL : nil
    }
}

struct Reviews: Identifiable, Codable  {
    var id: UUID
    var reviewsItems: [Review] = []

    init(id: UUID = UUID(), reviewsItems: [Review] = []) {
        self.id = id
        self.reviewsItems = reviewsItems
    }
}

struct ScriptItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var scriptText: String
    var lastAccessed: Date
    var pastReviews: Reviews

    init(
        id: UUID = UUID(),
        title: String,
        scriptText: String,
        lastAccessed: Date = Date(),
        pastReviews: Reviews = Reviews(id: UUID(), reviewsItems: [])
    ) {
        self.id = id
        self.title = title
        self.scriptText = scriptText
        self.lastAccessed = lastAccessed
        self.pastReviews = pastReviews
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decode(String.self, forKey: .title)) ?? "Untitled Script"
        scriptText = (try? container.decode(String.self, forKey: .scriptText)) ?? ""
        lastAccessed = (try? container.decode(Date.self, forKey: .lastAccessed)) ?? Date.distantPast

        if let decodedReviews = try? container.decode(Reviews.self, forKey: .pastReviews) {
            pastReviews = decodedReviews
        } else {
            pastReviews = Reviews(id: UUID(), reviewsItems: [])
        }
    }
}

class Screen2ViewModel: NSObject, ObservableObject {
    @Published var scriptItems: [ScriptItem] = [
    ]
    
    private var untitledCount: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private let fileURL: URL
    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("scripts.json")
        super.init()
        
        load()
        sortByRecency()
        
        $scriptItems
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)
    }

    func addNewScriptAtFront(title: String? = nil, scriptText: String = "") {
        let providedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle: String
        if let t = providedTitle, !t.isEmpty {
            finalTitle = t
        } else {
            if untitledCount == 0 {
                finalTitle = "Untitled Script"
            } else {
                finalTitle = "Untitled Script \(untitledCount + 1)"
            }
            untitledCount += 1
        }

        let newItem = ScriptItem(
            id: UUID(),
            title: finalTitle,
            scriptText: scriptText,
            lastAccessed: Date(),
            pastReviews: Reviews(id: UUID(), reviewsItems: [])
        )
        scriptItems.insert(newItem, at: 0)
        sortByRecency()
        save()
    }
    
    func markAccessed(id: UUID) {
        guard let idx = scriptItems.firstIndex(where: { $0.id == id }) else { return }
        scriptItems[idx].lastAccessed = Date()
        sortByRecency()
        save()
    }
    
    func updateScript(id: UUID, title: String? = nil, scriptText: String? = nil) {
        guard let idx = scriptItems.firstIndex(where: { $0.id == id }) else { return }
        if let title { scriptItems[idx].title = title }
        if let scriptText { scriptItems[idx].scriptText = scriptText }
        scriptItems[idx].lastAccessed = Date()
        sortByRecency()
        save()
    }
    
    func appendReview(to scriptID: UUID, cis: Int, wpm: Int, audioURL: URL?) {
        guard let idx = scriptItems.firstIndex(where: { $0.id == scriptID }) else { return }
        let review = Review(id: UUID(), cis: cis, wpm: wpm, audioURL: audioURL, date: Date())
        insert(review: review, into: idx)
    }

    func appendReview(_ review: Review, to scriptID: UUID) {
        guard let idx = scriptItems.firstIndex(where: { $0.id == scriptID }) else { return }
        insert(review: review, into: idx)
    }

    private func insert(review: Review, into index: Int) {
        scriptItems[index].pastReviews.reviewsItems.insert(review, at: 0)
        scriptItems[index].pastReviews.reviewsItems.sort { $0.date > $1.date }
        scriptItems[index].lastAccessed = Date()
        save()
    }
    
    private func sortByRecency() {
        scriptItems.sort { $0.lastAccessed > $1.lastAccessed }
    }
    
    // MARK: - Persistence
    
    func save() {
        do {
            let data = try JSONEncoder().encode(scriptItems)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save scripts: \(error.localizedDescription)")
        }
    }
    
    func load() {
        do {
            let fm = FileManager.default
            guard fm.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            if let decoded = try? JSONDecoder().decode([ScriptItem].self, from: data) {
                self.scriptItems = normalizeScripts(decoded)
            } else {
                struct OldScriptItem: Identifiable, Codable {
                    var id: UUID
                    var title: String
                    var scriptText: String
                }
                let old = try JSONDecoder().decode([OldScriptItem].self, from: data)
                self.scriptItems = old.map {
                    ScriptItem(
                        id: $0.id,
                        title: $0.title,
                        scriptText: $0.scriptText,
                        lastAccessed: Date.distantPast,
                        pastReviews: Reviews(id: UUID(), reviewsItems: [])
                    )
                }
                save()
            }
            sortByRecency()
            let untitledBase = "Untitled Script"
            let maxSuffix = scriptItems.compactMap { item -> Int? in
                if item.title == untitledBase { return 1 }
                if item.title.hasPrefix(untitledBase + " ") {
                    let suffix = item.title.dropFirst((untitledBase + " ").count)
                    return Int(suffix)
                }
                return nil
            }.max() ?? 0
            self.untitledCount = max(0, maxSuffix)
        } catch {
            print("Failed to load scripts: \(error.localizedDescription)")
        }
    }

    private func normalizeScripts(_ scripts: [ScriptItem]) -> [ScriptItem] {
        scripts.map { item in
            var script = item
            script.pastReviews.reviewsItems.sort { $0.date > $1.date }
            return script
        }
    }
}
