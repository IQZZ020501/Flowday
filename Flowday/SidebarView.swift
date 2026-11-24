import SwiftUI

struct SidebarView: View {
  @Bindable var store: TaskStore
  @State private var hoveredView: TaskView?

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 8) {
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit()
          .frame(width: 32, height: 32).accessibilityHidden(true)
        Text("Flowday").font(.system(size: 16, weight: .semibold))
          .foregroundStyle(FlowdayStyle.ink).lineLimit(1)
        Spacer()
      }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)

      List {
        Section {
          ForEach(TaskView.allCases) { view in
            let selected = store.selectedView == view
            Button {
              store.selectedView = view
            } label: {
              HStack(spacing: 9) {
                Image(systemName: view.symbol)
                  .font(.system(size: 13, weight: .regular)).frame(width: 17)
                  .foregroundStyle(selected ? FlowdayStyle.accent : FlowdayStyle.muted)
                Text(view.title).fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: 4)
                Text("\(store.count(for: view))")
                  .font(.system(size: 11)).monospacedDigit()
                  .foregroundStyle(FlowdayStyle.muted)
                  .frame(minWidth: 18, alignment: .trailing)
              }
              .font(.system(size: 12)).foregroundStyle(FlowdayStyle.ink)
              .padding(.horizontal, 9).padding(.vertical, 8)
              .background(
                selected
                  ? FlowdayStyle.selection : hoveredView == view ? FlowdayStyle.hover : .clear,
                in: RoundedRectangle(cornerRadius: 5)
              )
              .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .onHover { hoveredView = $0 ? view : nil }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .accessibilityIdentifier("nav-\(view.rawValue)")
          }
        } header: {
          Text("工作区").font(.system(size: 10, weight: .medium))
            .foregroundStyle(FlowdayStyle.muted)
        }

        if !store.allTags.isEmpty {
          Section("标签") {
            ForEach(store.allTags, id: \.name) { tag in
              Button {
                store.filter.tag = store.filter.tag == tag.name ? nil : tag.name
              } label: {
                HStack(spacing: 9) {
                  Image(systemName: "number").font(.system(size: 11)).frame(width: 17)
                  Text(tag.name).lineLimit(1)
                  Spacer()
                  Text("\(tag.count)").monospacedDigit().foregroundStyle(FlowdayStyle.muted)
                }.font(.system(size: 11)).padding(.horizontal, 5).padding(.vertical, 5)
                  .background(
                    store.filter.tag == tag.name ? FlowdayStyle.selection : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                  )
                  .contentShape(Rectangle())
              }.buttonStyle(.plain)
                .foregroundStyle(
                  store.filter.tag == tag.name ? FlowdayStyle.accent : FlowdayStyle.muted
                )
                .listRowBackground(Color.clear)
            }
          }
        }
      }.listStyle(.sidebar).scrollContentBackground(.hidden)
        .foregroundStyle(FlowdayStyle.ink)

      Rectangle().fill(FlowdayStyle.border).frame(height: 1).padding(.horizontal, 18)

      HStack {
        Label("本地保存", systemImage: "internaldrive")
          .font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
        Spacer()
        SettingsLink {
          Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(
            FlowdayStyle.muted
          )
          .frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("设置（⌘,）").accessibilityLabel("设置")
      }.padding(.horizontal, 18).padding(.vertical, 12)
    }
    .background(FlowdayStyle.sidebar)
    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
  }
}
