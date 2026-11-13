import SwiftUI
import SwipeSelect

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                MailDemo().tabItem { Label("Mail", systemImage: "envelope") }.tag(0)
                GridDemo().tabItem { Label("Photos", systemImage: "square.grid.3x3") }.tag(1)
                ListDemo().tabItem { Label("List", systemImage: "list.bullet") }.tag(2)
                ChatDemo().tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(3)
                HorizontalDemo().tabItem { Label("Horizontal", systemImage: "rectangle.split.3x1") }.tag(4)
            }
        }
    }

    @State private var tab = Int(ProcessInfo.processInfo.environment["TAB"] ?? "") ?? 0
}

// MARK: - Data

struct Mail: Identifiable, Hashable {
    let id: Int
    let from: String
    let subject: String
    let lines: Int
    var locked = false
}

let names = ["Anna", "Boris", "Vika", "Gleb", "Dasha", "Egor", "Jane", "Ilya"]
let subjects = ["Weekly report", "Call at 3 pm", "Invoice #482", "Vacation plans", "PR review", "New design"]
let preview = "Message preview that takes one or several lines depending on the email. "

func makeMails(_ n: Int) -> [Mail] {
    (0..<n).map { i in
        Mail(id: i, from: names[i % names.count], subject: "\(subjects[i % subjects.count]) #\(i + 1)", lines: [1, 2, 3, 4][(i * 7) % 4])
    }
}

// MARK: - Mail: long press enters selection mode, then the checkbox column

struct MailDemo: View {
    @State private var side: EdgeSide = ProcessInfo.processInfo.environment["SIDE"] == "trailing" ? .trailing : .leading
    @State private var mails = makeMails(200)
    @StateObject private var controller = SwipeSelectController<Int>()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(mails.enumerated()), id: \.element.id) { i, mail in
                        MailRow(mail: mail, selected: controller.isSelected(mail.id),
                                showCheckbox: controller.isSelectionMode, side: side) { controller.toggle(mail.id) }
                            .swipeSelectItem(i)
                        Divider()
                    }
                }
            }
            .swipeSelect(controller, count: mails.count, id: { mails.indices.contains($0) ? mails[$0].id : nil },
                         activation: [.longPress(when: .idle), .edge(side: side)])
            .navigationTitle(controller.isSelectionMode ? "Selected: \(controller.count)" : "Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Strip", selection: $side) {
                        Image(systemName: "sidebar.left").tag(EdgeSide.leading)
                        Image(systemName: "sidebar.right").tag(EdgeSide.trailing)
                    }
                    .pickerStyle(.segmented)
                }
                if controller.isSelectionMode {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { controller.clear() } }
                }
            }
        }
    }
}

struct MailRow: View {
    let mail: Mail
    let selected: Bool
    let showCheckbox: Bool
    let side: EdgeSide
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if side == .leading { checkbox }
            VStack(alignment: .leading, spacing: 4) {
                Text(mail.from).font(.headline)
                Text(mail.subject)
                Text(String(repeating: preview, count: mail.lines)).font(.subheadline).foregroundStyle(.secondary).lineLimit(mail.lines)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if side == .trailing { checkbox }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var checkbox: some View {
        if showCheckbox {
            Button(action: toggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Photos: long press, then swipe across

struct GridDemo: View {
    @State private var columns = 4
    private let count = 10_000
    @StateObject private var controller = SwipeSelectController<Int>()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
                    ForEach(0..<count, id: \.self) { i in
                        let selected = controller.isSelected(i)
                        Rectangle()
                            .fill(Color(hue: Double((i * 37) % 360) / 360, saturation: 0.45, brightness: 0.9))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .bottomTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, .blue).padding(4)
                                }
                            }
                            .opacity(selected ? 0.75 : 1)
                            .swipeSelectItem(i)
                    }
                }
            }
            .swipeSelect(controller, count: count, id: { $0 }, activation: [.longPress(when: .idle), .pan()])
            .safeAreaInset(edge: .top) {
                Picker("Columns", selection: $columns) {
                    ForEach([2, 3, 4, 6], id: \.self) { Text("\($0) columns").tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle(controller.isSelectionMode ? "Selected: \(controller.count)" : "Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if controller.isSelectionMode {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { controller.clear() } }
                }
            }
        }
    }
}

// MARK: - SwiftUI List

struct ListDemo: View {
    @State private var mails = makeMails(100).map { m -> Mail in var m = m; m.locked = m.id % 9 == 4; return m }
    @StateObject private var controller = SwipeSelectController<Int>(selectionMode: true)

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(mails.enumerated()), id: \.element.id) { i, mail in
                    HStack {
                        Image(systemName: mail.locked ? "lock.fill" : controller.isSelected(mail.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(mail.locked ? Color.secondary : Color.accentColor)
                            .font(.title3)
                        VStack(alignment: .leading) {
                            Text(mail.from).font(.headline)
                            Text(mail.subject).foregroundStyle(.secondary)
                        }
                    }
                    .swipeSelectItem(i)
                }
            }
            .listStyle(.plain)
            .swipeSelect(controller, count: mails.count, id: { mails.indices.contains($0) ? mails[$0].id : nil },
                         isSelectable: { !mails[$0].locked })
            .navigationTitle("List · selected \(controller.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Chat: newest at the bottom

struct ChatDemo: View {
    private let messages = (0..<150).map { i in (id: i, text: String(repeating: "Message \(i + 1). ", count: 1 + (i * 5) % 4), mine: i % 3 == 0) }
    @StateObject private var controller = SwipeSelectController<Int>()

    var body: some View {
        NavigationStack {
            ScrollViewReader { _ in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(messages, id: \.id) { m in
                            let selected = controller.isSelected(m.id)
                            HStack {
                                if m.mine { Spacer(minLength: 60) }
                                Text(m.text)
                                    .padding(10)
                                    .background(m.mine ? Color.blue.opacity(0.85) : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(m.mine ? .white : .primary)
                                if !m.mine { Spacer(minLength: 60) }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .background(selected ? Color.accentColor.opacity(0.18) : .clear)
                            .swipeSelectItem(m.id)
                            .id(m.id)
                        }
                    }
                }
                .defaultScrollAnchor(.bottom)
            }
            .swipeSelect(controller, count: messages.count, id: { $0 }, activation: [.longPress()])
            .navigationTitle(controller.isSelectionMode ? "Selected: \(controller.count)" : "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if controller.isSelectionMode { Button("Done") { controller.clear() } } }
        }
    }
}

// MARK: - Horizontal

struct HorizontalDemo: View {
    @StateObject private var controller = SwipeSelectController<Int>()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("Long press a card, then drag sideways.").foregroundStyle(.secondary).padding()
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(0..<100, id: \.self) { i in
                            let selected = controller.isSelected(i)
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hue: Double((i * 29) % 360) / 360, saturation: 0.5, brightness: 0.85))
                                .frame(width: 90 + CGFloat((i * 13) % 50), height: 160)
                                .overlay { Text("\(i + 1)").font(.title2.bold()).foregroundStyle(.white) }
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.blue : .clear, lineWidth: 4))
                                .swipeSelectItem(i)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 180)
                .swipeSelect(controller, count: 100, id: { $0 }, activation: [.longPress()])
                Spacer()
            }
            .navigationTitle("Selected: \(controller.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
