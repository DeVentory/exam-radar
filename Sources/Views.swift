import SwiftUI
import AppKit
import EventKit

let accent = Color(red: 1.0, green: 0.70, blue: 0.30)
let sky = Color(red: 0.45, green: 0.72, blue: 1.0)

@main
struct ExamRadarApp: App {
    @StateObject private var radar = Radar()

    var body: some Scene {
        MenuBarExtra {
            RootView().environmentObject(radar)
        } label: {
            Text(radar.menuLabel).monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

func hm(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeZone = kst
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}

func dayTitle(_ d: Date) -> String {
    d.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month().day().weekday())
}

// MARK: - 루트

struct RootView: View {
    @EnvironmentObject var radar: Radar

    var body: some View {
        VStack(spacing: 12) {
            header
            Picker("", selection: $radar.tab) {
                Text("⏰ 일정").tag(0)
                Text("📅 캘린더").tag(1)
                Text("🧠 퀴즈").tag(2)
                Text("📊 약점").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch radar.tab {
                case 0: ScheduleView()
                case 1: CalendarView()
                case 2: QuizView()
                default: StatsView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(16)
        .frame(width: 440, height: 660)
        .onAppear { radar.reloadExams() }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("📡 시험 레이더").font(.system(size: 18, weight: .bold))
                Text(radar.now.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month().day().weekday(.wide)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(clock).font(.system(size: 20, weight: .medium, design: .monospaced))
        }
    }

    var clock: String {
        let f = DateFormatter()
        f.timeZone = kst
        f.dateFormat = "HH:mm:ss"
        return f.string(from: radar.now)
    }

    var footer: some View {
        HStack {
            Text(radar.calAccess == true ? "🔗 캘린더 연동 중" : "📄 exams.json")
            if radar.pinnedExam != nil { Text("· 📌 고정") }
            if radar.launchAtLogin { Text("· 🔁") }
            Text("· \(quizScope) · \(radar.questions.count)문항")
            Spacer()
            Button("종료") { NSApp.terminate(nil) }.buttonStyle(.borderless)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
}

/// 캘린더 접근이 없을 때 안내
struct AccessBanner: View {
    @EnvironmentObject var radar: Radar

    var body: some View {
        if radar.calAccess == false {
            HStack(spacing: 8) {
                Text("캘린더 접근이 꺼져 있어서 exams.json을 보여주고 있어요.").font(.caption)
                Spacer()
                Button("설정 열기") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .font(.caption)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.15)))
        }
    }
}

// MARK: - 일정

struct ScheduleView: View {
    @EnvironmentObject var radar: Radar

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                AccessBanner()
                ForEach(radar.exams) { e in row(e) }
                if radar.exams.isEmpty {
                    Text("다가오는 시험·마감이 없어요.")
                        .font(.callout).foregroundStyle(.secondary).padding(.top, 40)
                }
            }
        }
    }

    func row(_ e: Exam) -> some View {
        let past = e.done || e.at <= radar.now
        let isNext = radar.menuExam?.id == e.id
        let pinned = radar.pinnedExam?.id == e.id
        let d = Radar.days(until: e.at, from: radar.now)
        return HStack(alignment: .top, spacing: 10) {
            Text(e.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text([e.kind, e.at.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month().day().weekday().hour().minute()), e.place]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !e.note.isEmpty {
                    Text(e.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                if !e.source.isEmpty && e.source != "exams.json" {
                    HStack(spacing: 4) {
                        Circle().fill(e.color).frame(width: 6, height: 6)
                        Text(e.source).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if !past {
                    Button { radar.togglePin(e) } label: {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                            .foregroundStyle(pinned ? accent : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(pinned ? "메뉴바 고정 풀기" : "메뉴바에 고정")
                }
                if past {
                    Text("✅").font(.title3)
                } else {
                    Text(d <= 0 ? "D-DAY" : "D-\(d)")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(isNext ? accent : .primary)
                    Text(Radar.hms(e.at.timeIntervalSince(radar.now)))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isNext ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isNext ? accent : .clear, lineWidth: 1.5))
        .opacity(past ? 0.45 : 1)
    }
}

// MARK: - 캘린더

struct CalendarView: View {
    @EnvironmentObject var radar: Radar
    let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        let _ = radar.calVersion
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccessBanner()
                monthHeader
                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { i, w in
                        Text(w).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(i == 0 ? .red : (i == 6 ? sky : .secondary))
                    }
                    ForEach(cells, id: \.self) { cell($0) }
                }
                chips
                Divider()
                dayList
                Divider()
                upcoming
            }
        }
    }

    var monthHeader: some View {
        HStack {
            Text(radar.calMonth.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).year().month(.wide)))
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Button { radar.moveMonth(-1) } label: { Image(systemName: "chevron.left") }
            Button("오늘") { radar.goToday() }
            Button { radar.moveMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
    }

    /// 달력에 그릴 날짜들 (일요일 시작, 앞뒤 달 포함)
    var cells: [Date] {
        let first = radar.calMonth
        let offset = kcal.component(.weekday, from: first) - 1
        let n = kcal.range(of: .day, in: .month, for: first)!.count
        let total = Int((Double(offset + n) / 7).rounded(.up)) * 7
        let start = kcal.date(byAdding: .day, value: -offset, to: first)!
        return (0..<total).map { kcal.date(byAdding: .day, value: $0, to: start)! }
    }

    func cell(_ d: Date) -> some View {
        let inMonth = kcal.isDate(d, equalTo: radar.calMonth, toGranularity: .month)
        let isToday = kcal.isDateInToday(d)
        let isSel = kcal.isDate(d, inSameDayAs: radar.selectedDay)
        let wd = kcal.component(.weekday, from: d)
        let evs = radar.events(on: d)
        var colors: [Color] = []
        var seen = Set<String>()
        for e in evs where seen.insert(e.calendar.title).inserted && colors.count < 4 {
            colors.append(Color(cgColor: e.calendar.cgColor))
        }
        let red = wd == 1 || radar.isHoliday(d)
        return Button { radar.selectedDay = d } label: {
            VStack(spacing: 3) {
                Text("\(kcal.component(.day, from: d))")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(red ? .red : (wd == 7 ? sky : .primary))
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSel ? accent.opacity(0.3) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isToday ? accent : .clear, lineWidth: 1.2))
            .opacity(inMonth ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(radar.allCalendars, id: \.calendarIdentifier) { c in
                    let off = radar.hiddenCals.contains(c.title)
                    Button { radar.toggleCal(c.title) } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color(cgColor: c.cgColor)).frame(width: 6, height: 6)
                            Text(c.title).font(.system(size: 11))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(off ? 0.02 : 0.07)))
                        .opacity(off ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var dayList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle(radar.selectedDay)).font(.system(size: 13, weight: .semibold))
            let evs = radar.events(on: radar.selectedDay)
            if evs.isEmpty {
                Text("일정 없음").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(evs, id: \.calendarItemIdentifier) { eventRow($0, showDay: false) }
        }
    }

    var upcoming: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("다가오는 7일").font(.system(size: 13, weight: .semibold))
            let evs = radar.upcoming(days: 7)
            if evs.isEmpty {
                Text("일정 없음").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(evs, id: \.calendarItemIdentifier) { eventRow($0, showDay: true) }
        }
    }

    func eventRow(_ e: EKEvent, showDay: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title ?? "").font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text([showDay ? dayTitle(e.startDate) : "",
                      e.isAllDay ? "종일" : "\(hm(e.startDate))–\(hm(e.endDate))",
                      e.location ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(e.calendar.title.first.map(String.init) ?? "").font(.system(size: 12))
        }
    }
}

// MARK: - 퀴즈

/// 핵심 용어 칩을 줄바꿈하며 늘어놓는 레이아웃
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct QuizView: View {
    @EnvironmentObject var radar: Radar
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["전체", "약점"] + radar.chapters, id: \.self) { f in
                        Button { radar.setFilter(f) } label: {
                            Text(f == "약점" ? "⚠️ 약점" : f)
                                .font(.system(size: 12, weight: radar.filter == f ? .bold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(radar.filter == f ? sky.opacity(0.25) : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help(chapterNames[f] ?? f)
                    }
                }
            }

            if let q = radar.current {
                card(q)
            } else {
                VStack(spacing: 8) {
                    Text("🎉").font(.system(size: 40))
                    Text(radar.filter == "약점" ? "약점 상자가 비었어요." : "문제가 없어요.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
        .onAppear { focused = true }
        .onChange(of: radar.current?.id) { focused = true }
    }

    func card(_ q: Question) -> some View {
        let b = radar.box(q)
        let hits = radar.keywordHits(q)
        let got = hits.filter(\.1).count
        let wrote = !radar.typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let recommendKnown = wrote && !hits.isEmpty && Double(got) / Double(hits.count) >= 0.8
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\(q.ch) \(chapterNames[q.ch] ?? "") · p\(q.p)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(sky)
                if q.weak == true {
                    Text("자주 틀림").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.25)))
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { i in
                        Circle().fill(i <= b ? accent : Color.primary.opacity(0.15)).frame(width: 6, height: 6)
                    }
                }
                .help("상자 \(b)/5 — 높을수록 잘 아는 문제")
            }

            Text(q.q).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)

            if !radar.revealed {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $radar.typed)
                        .font(.system(size: 13))
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if radar.typed.isEmpty {
                        Text("답을 써 보세요. 강의자료 용어 그대로!")
                            .font(.system(size: 13)).foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? sky.opacity(0.6) : .clear, lineWidth: 1))

                HStack(spacing: 8) {
                    Button { radar.revealed = true } label: {
                        Text("모르겠어 (⌘.)").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(".", modifiers: .command)
                    Button { radar.revealed = true } label: {
                        Text("제출 (⌘↩)").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).tint(sky)
                }
                .controlSize(.large)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !hits.isEmpty {
                            Text(wrote ? "핵심 용어 \(got)/\(hits.count)" : "핵심 용어")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            FlowLayout {
                                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                                    Text((wrote ? (h.1 ? "✅ " : "❌ ") : "") + h.0)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Capsule().fill(!wrote ? sky.opacity(0.15) : (h.1 ? Color.green.opacity(0.18) : Color.red.opacity(0.18))))
                                }
                            }
                        }
                        if wrote {
                            Text("내 답").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Text(radar.typed).font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        }
                        Text("정답").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text(q.a).font(.system(size: 13)).lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(sky.opacity(0.10)))
                        if let n = q.note {
                            Text("📌 " + n.replacingOccurrences(of: "**", with: ""))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if wrote && !hits.isEmpty {
                    Text(recommendKnown ? "핵심 용어를 거의 다 썼어요 → 알았어 추천" : "빠진 용어가 있어요 → 몰랐어 추천")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button { radar.answer(known: false) } label: {
                        Text("😵 몰랐어 (⌘1)").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut("1", modifiers: .command)
                    .buttonStyle(.borderedProminent).tint(recommendKnown ? .gray.opacity(0.5) : .red.opacity(0.75))
                    Button { radar.answer(known: true) } label: {
                        Text("😎 알았어 (⌘2)").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut("2", modifiers: .command)
                    .buttonStyle(.borderedProminent).tint(recommendKnown ? accent : .gray.opacity(0.5))
                }
                .controlSize(.large)
            }

            HStack {
                Text("이번 세션 \(radar.sessionKnown)/\(radar.sessionTotal)")
                Spacer()
                Button("건너뛰기 (⌘→)") { radar.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .buttonStyle(.borderless)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 약점 통계

struct StatsView: View {
    @EnvironmentObject var radar: Radar
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("챕터별 숙련도").font(.system(size: 13, weight: .semibold))
                ForEach(radar.chapters, id: \.self) { ch in
                    let m = radar.mastery(ch)
                    HStack(spacing: 8) {
                        Text("\(ch) \(chapterNames[ch] ?? "")").font(.system(size: 12)).frame(width: 130, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(m > 0.6 ? Color.green : (m > 0.3 ? sky : accent))
                                    .frame(width: max(6, g.size.width * m))
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int(m * 100))%").font(.system(size: 11, design: .monospaced)).frame(width: 36, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { radar.setFilter(ch); radar.tab = 2 }
                }

                Divider()
                Text("가장 많이 틀린 문제").font(.system(size: 13, weight: .semibold))
                if radar.mostWrong.isEmpty {
                    Text("아직 틀린 문제가 없어요. 퀴즈 탭에서 시작해 보세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(radar.mostWrong) { q in
                    Button {
                        radar.show(q)
                        radar.tab = 2
                    } label: {
                        HStack(alignment: .top) {
                            Text("✗\(radar.cards[q.id]?.wrong ?? 0)").font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.q).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                if let last = radar.cards[q.id]?.lastAnswer {
                                    Text("내 마지막 답: " + last.replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                Text("설정").font(.system(size: 13, weight: .semibold))
                Toggle("로그인할 때 자동 실행", isOn: Binding(
                    get: { radar.launchAtLogin },
                    set: { radar.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                if let err = radar.loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    if confirmReset {
                        Text("기록을 모두 지울까요?").font(.caption)
                        Button("지우기") { radar.resetProgress(); confirmReset = false }.tint(.red)
                        Button("취소") { confirmReset = false }
                    } else {
                        Button("학습 기록 초기화") { confirmReset = true }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }
}
