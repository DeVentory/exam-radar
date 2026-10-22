import Foundation
import AppKit
import EventKit
import SwiftUI
import ServiceManagement

// MARK: - 데이터 모델

struct Question: Codable, Identifiable, Hashable {
    let id: String
    let ch: String
    let p: String
    let q: String
    let a: String
    let weak: Bool?
    let note: String?
    let kw: [String]?
}

private struct ExamFile: Codable { let items: [ExamItem] }
private struct ExamItem: Codable {
    let emoji: String?
    let name: String
    let kind: String?
    let date: String
    let time: String?
    let place: String?
    let note: String?
    let done: Bool?
}

struct Exam: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let short: String
    let kind: String
    let place: String
    let note: String
    let at: Date
    var done: Bool
    var source = ""
    var color: Color = .secondary
}

/// Leitner 상자 하나의 기록. box 1(자주) ~ 5(드물게)
struct Card: Codable {
    var box: Int
    var seen = 0
    var wrong = 0
    var last: Date?
    var lastAnswer: String?
}

let kst = TimeZone(identifier: "Asia/Seoul")!
var kcal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = kst
    c.locale = Locale(identifier: "ko_KR")
    return c
}()


// MARK: - 채점

func normalize(_ s: String) -> String {
    s.lowercased().filter { !" \n\t·,.()（）".contains($0) }
}

/// 핵심 용어 하나("구조 기반|코드 기반"처럼 대안 포함)가 답에 들어 있는지
func contains(_ answer: String, keyword: String) -> Bool {
    let a = normalize(answer)
    return keyword.split(separator: "|").contains { a.contains(normalize(String($0))) }
}

// MARK: - 앱 상태

final class Radar: ObservableObject {
    @Published var now = Date()
    @Published var exams: [Exam] = []
    @Published var cards: [String: Card] = [:]
    @Published var current: Question?
    @Published var revealed = false
    @Published var typed = ""
    @Published var filter = "전체"
    @Published var tab = 0
    @Published var sessionKnown = 0
    @Published var sessionTotal = 0
    /// 메뉴바에 고정할 시험 ("SE 중간|2026-10-22"). 시험이 지나면 자동으로 풀린다
    @Published var pinnedKey: String? = UserDefaults.standard.string(forKey: "pinned") {
        didSet { UserDefaults.standard.set(pinnedKey, forKey: "pinned") }
    }
    /// 일정 탭에서 직접 체크한 완료 상태 ("SE 중간|2026-10-22": true). exams.json의 done보다 앞선다
    @Published var doneMarks: [String: Bool] = UserDefaults.standard.dictionary(forKey: "done") as? [String: Bool] ?? [:] {
        didSet { UserDefaults.standard.set(doneMarks, forKey: "done") }
    }
    /// 일정 탭에서 완료한 일정 숨기기
    @Published var hideDone = UserDefaults.standard.bool(forKey: "hideDone") {
        didSet { UserDefaults.standard.set(hideDone, forKey: "hideDone") }
    }

    /// 로그인할 때 자동 실행 (시스템 설정 → 일반 → 로그인 항목에 등록)
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    // 캘린더
    @Published var calAccess: Bool?
    @Published var calMonth = kcal.date(from: kcal.dateComponents([.year, .month], from: Date()))!
    @Published var selectedDay = kcal.startOfDay(for: Date())
    @Published var hiddenCals: Set<String> = []
    @Published var calVersion = 0
    let store = EKEventStore()
    private var monthCache: [Date: [EKEvent]] = [:]

    let questions: [Question]
    private var recent: [String] = []
    private var timer: Timer?

    static let examsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(examsJSONPath)
    static let progressURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExamRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress.json")
    }()

    init() {
        if let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let qs = try? JSONDecoder().decode([Question].self, from: data) {
            questions = qs
        } else {
            questions = []
        }
        loadProgress()
        reloadExams()
        next()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.calAccess = granted
                self?.reloadExams()
            }
        }
        // 캘린더 앱이나 iCloud에서 일정이 바뀌면 다시 읽는다
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.monthCache.removeAll()
            self?.calVersion += 1
            self?.reloadExams()
        }
    }

    // MARK: 시험 일정

    func reloadExams() {
        let notes = loadExamsJSON()
        let list = calAccess == true ? examsFromCalendar(enrich: notes) : notes
        exams = list.map { e in
            var e = e
            if let d = doneMarks[Self.doneKey(e)] { e.done = d }
            return e
        }
    }

    /// 아침 브리프의 exams.json. 캘린더를 못 읽을 때 그대로 쓰고, 읽을 때는 메모를 붙이는 데만 쓴다
    private func loadExamsJSON() -> [Exam] {
        guard let data = try? Data(contentsOf: Self.examsURL),
              let file = try? JSONDecoder().decode(ExamFile.self, from: data) else { return [] }
        let f = DateFormatter()
        f.timeZone = kst
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return file.items.compactMap { it in
            // "10:30"이 아니면(마감, 23:59 전 등) 그날 23:59로 본다
            var hm = "23:59"
            if let t = it.time, t.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil { hm = t }
            guard let at = f.date(from: "\(it.date) \(hm)") else { return nil }
            return Exam(id: it.name + it.date, emoji: it.emoji ?? "📌", name: it.name,
                        short: Self.alias(it.name) ?? it.name, kind: it.kind ?? "", place: it.place ?? "",
                        note: it.note ?? "", at: at, done: it.done ?? false, source: "exams.json")
        }.sorted { $0.at < $1.at }
    }

    private func examsFromCalendar(enrich notes: [Exam]) -> [Exam] {
        let cals = store.calendars(for: .event).filter { examCalendars.contains($0.title) }
        guard !cals.isEmpty else { return notes }
        let start = kcal.startOfDay(for: Date())
        let end = kcal.date(byAdding: .day, value: 150, to: start)!
        let evs = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: cals))
        return evs.compactMap { e -> Exam? in
            let title = e.title ?? ""
            guard title.range(of: examPattern, options: .regularExpression) != nil else { return nil }
            let at = Self.examTime(e)
            let name = Self.cleanTitle(title)
            let alias = Self.alias(title)
            // 같은 날 같은 과목인 exams.json 항목이 있으면 그 이모지·메모를 쓴다
            let match = notes.first { kcal.isDate($0.at, inSameDayAs: at) && $0.short == alias }
            let calEmoji = e.calendar.title.first.map(String.init) ?? "📌"
            let kind = ["중간", "기말", "퀴즈", "과제", "레포트", "마감", "시험"].first { title.contains($0) } ?? ""
            return Exam(id: e.eventIdentifier ?? title + "\(at)",
                        emoji: match?.emoji ?? (calEmoji == "📚" ? "📝" : calEmoji),
                        name: name,
                        short: [alias, kind].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                        kind: match?.kind ?? "",
                        place: e.location?.isEmpty == false ? e.location! : (match?.place ?? ""),
                        note: match?.note ?? "",
                        at: at,
                        done: match?.done ?? false,
                        source: e.calendar.title,
                        color: Color(cgColor: e.calendar.cgColor))
        }.sorted { $0.at < $1.at }
    }

    static func alias(_ title: String) -> String? {
        courseAlias.first { title.contains($0.0) }?.1
    }

    /// 제목에 적힌 시간("0900", "2359", "18:30")이 있으면 그 시간, 종일 일정이면 23:59, 아니면 시작 시간
    static func examTime(_ e: EKEvent) -> Date {
        let title = e.title ?? ""
        let day = kcal.startOfDay(for: e.startDate)
        if let r = title.range(of: #"(?<!\d)([01]\d|2[0-3]):?([0-5]\d)(?!\d)"#, options: .regularExpression) {
            let digits = title[r].filter(\.isNumber)
            let n = Int(digits) ?? 0
            // 2020~2099처럼 연도로 보이는 4자리는 시간으로 보지 않는다
            if !(digits.count == 4 && (2020...2099).contains(n)) {
                return kcal.date(bySettingHour: n / 100, minute: n % 100, second: 0, of: day) ?? e.startDate
            }
        }
        if e.isAllDay { return kcal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? e.startDate }
        return e.startDate
    }

    static func cleanTitle(_ t: String) -> String {
        // Canvas 제목 끝의 "[시스템프로그래밍 3분반]"은 " · 시스템프로그래밍"으로 줄인다
        var s = t.replacingOccurrences(of: #"\s*\[([^\]]*?)\s*\d+분반\]\s*$"#, with: " · $1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s(?:[01]\d|2[0-3]):?[0-5]\d(?!\d)"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 문제은행에 있는 챕터 번호들 ("01", "02", ...)
    var chapters: [String] { Array(Set(questions.map(\.ch))).sorted() }

    var nextExam: Exam? { exams.first { !$0.done && $0.at > now } }

    static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = kst
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func pinKey(_ e: Exam) -> String { "\(e.short)|\(ymd(e.at))" }

    /// 완료 표시용 키. 같은 과목·같은 날 과제가 여러 개일 수 있어서 줄임말 대신 제목을 쓴다
    static func doneKey(_ e: Exam) -> String { "\(e.name)|\(ymd(e.at))" }

    func toggleDone(_ e: Exam) {
        doneMarks[Self.doneKey(e)] = !e.done
        // 끝난 지 30일 넘은 표시는 지운다
        let cutoff = Self.ymd(kcal.date(byAdding: .day, value: -30, to: now)!)
        doneMarks = doneMarks.filter { String($0.key.split(separator: "|").last ?? "") >= cutoff }
        reloadExams()
    }

    var doneCount: Int { exams.filter(\.done).count }

    var pinnedExam: Exam? {
        guard let k = pinnedKey else { return nil }
        return exams.first { Self.pinKey($0) == k && !$0.done && $0.at > now }
    }

    /// 메뉴바에 보여줄 시험: 고정한 시험이 있으면 그것, 없으면 가장 가까운 시험
    var menuExam: Exam? { pinnedExam ?? nextExam }

    func togglePin(_ e: Exam) {
        pinnedKey = pinnedKey == Self.pinKey(e) ? nil : Self.pinKey(e)
    }

    static func days(until d: Date, from now: Date) -> Int {
        kcal.dateComponents([.day], from: kcal.startOfDay(for: now), to: kcal.startOfDay(for: d)).day ?? 0
    }

    static func hms(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return String(format: "%02d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60)
    }

    var menuLabel: String {
        guard let e = menuExam else { return "📡 시험 레이더" }
        let d = Self.days(until: e.at, from: now)
        let dd = d <= 0 ? "D-DAY" : "D-\(d)"
        return "\(e.emoji) \(e.short) \(dd) · \(Self.hms(e.at.timeIntervalSince(now)))"
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "로그인 항목을 바꾸지 못했어요: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: 캘린더 탭

    var allCalendars: [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    func events(inMonth m: Date) -> [EKEvent] {
        if let c = monthCache[m] { return c }
        guard calAccess == true else { return [] }
        let end = kcal.date(byAdding: .month, value: 1, to: m)!
        let evs = store.events(matching: store.predicateForEvents(withStart: m, end: end, calendars: nil))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        monthCache[m] = evs
        return evs
    }

    func visible(_ e: EKEvent) -> Bool { !hiddenCals.contains(e.calendar.title) }

    func events(on day: Date) -> [EKEvent] {
        let m = kcal.date(from: kcal.dateComponents([.year, .month], from: day))!
        let next = kcal.date(byAdding: .day, value: 1, to: day)!
        return events(inMonth: m).filter { visible($0) && $0.startDate < next && $0.endDate > day }
    }

    func upcoming(days n: Int) -> [EKEvent] {
        guard calAccess == true else { return [] }
        let start = Date()
        let end = kcal.date(byAdding: .day, value: n, to: kcal.startOfDay(for: start))!
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter(visible).sorted { $0.startDate < $1.startDate }
    }

    func isHoliday(_ day: Date) -> Bool {
        events(on: day).contains { $0.calendar.title == holidayCalendar }
    }

    func moveMonth(_ by: Int) {
        calMonth = kcal.date(byAdding: .month, value: by, to: calMonth)!
    }

    func goToday() {
        calMonth = kcal.date(from: kcal.dateComponents([.year, .month], from: Date()))!
        selectedDay = kcal.startOfDay(for: Date())
    }

    func toggleCal(_ title: String) {
        if hiddenCals.contains(title) { hiddenCals.remove(title) } else { hiddenCals.insert(title) }
    }

    // MARK: 퀴즈 (Leitner)

    func initialBox(_ q: Question) -> Int { q.weak == true ? 1 : 2 }
    func box(_ q: Question) -> Int { cards[q.id]?.box ?? initialBox(q) }

    var pool: [Question] {
        switch filter {
        case "전체": return questions
        case "약점": return questions.filter { box($0) <= 2 && (cards[$0.id] != nil || $0.weak == true) }
        default: return questions.filter { $0.ch == filter }
        }
    }

    func next() {
        let all = pool
        let fresh = all.filter { !recent.contains($0.id) }
        let cand = fresh.isEmpty ? all : fresh
        guard !cand.isEmpty else { current = nil; return }
        let weight = [0, 16, 8, 4, 2, 1]
        let total = cand.reduce(0) { $0 + weight[box($1)] }
        var r = Int.random(in: 0..<max(total, 1))
        var pick = cand[0]
        for q in cand {
            r -= weight[box(q)]
            if r < 0 { pick = q; break }
        }
        show(pick)
    }

    func show(_ q: Question) {
        current = q
        revealed = false
        typed = ""
        recent.append(q.id)
        if recent.count > 6 { recent.removeFirst() }
    }

    /// 핵심 용어별 포함 여부
    func keywordHits(_ q: Question) -> [(String, Bool)] {
        (q.kw ?? []).map { k in (k.split(separator: "|").first.map(String.init) ?? k, contains(typed, keyword: k)) }
    }

    func answer(known: Bool) {
        guard let q = current else { return }
        var c = cards[q.id] ?? Card(box: initialBox(q))
        c.seen += 1
        if known {
            c.box = min(5, c.box + 1)
            sessionKnown += 1
        } else {
            c.box = 1
            c.wrong += 1
        }
        c.last = Date()
        if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { c.lastAnswer = typed }
        cards[q.id] = c
        sessionTotal += 1
        saveProgress()
        next()
    }

    func setFilter(_ f: String) {
        filter = f
        recent.removeAll()
        next()
    }

    func mastery(_ ch: String) -> Double {
        let qs = questions.filter { $0.ch == ch }
        guard !qs.isEmpty else { return 0 }
        return qs.reduce(0.0) { $0 + Double(box($1) - 1) / 4.0 } / Double(qs.count)
    }

    var mostWrong: [Question] {
        questions.filter { (cards[$0.id]?.wrong ?? 0) > 0 }
            .sorted { (cards[$0.id]?.wrong ?? 0) > (cards[$1.id]?.wrong ?? 0) }
            .prefix(8).map { $0 }
    }

    func resetProgress() {
        cards = [:]
        sessionKnown = 0
        sessionTotal = 0
        saveProgress()
        next()
    }

    private func loadProgress() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.progressURL),
           let c = try? dec.decode([String: Card].self, from: data) { cards = c }
    }

    private func saveProgress() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(cards) { try? data.write(to: Self.progressURL, options: .atomic) }
    }
}
