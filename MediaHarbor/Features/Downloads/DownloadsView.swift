import SwiftUI

struct DownloadsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EmptyStateCard(
                        title: "下一步做 qBittorrent",
                        message: "这个标签页已经预留给下载器管理。等 Jellyfin 稳定后，我们可以在这里继续加队列状态、暂停/继续、分类标签和下载完成后的动作。",
                        buttonTitle: "先把 Jellyfin 做好",
                        action: {}
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Text("第二阶段")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .padding()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("规划中")
                            .font(.headline)

                        Label("当前下载队列和传输速度", systemImage: "speedometer")
                        Label("暂停、继续和删除操作", systemImage: "pause.circle")
                        Label("分类和标签管理", systemImage: "tag")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding()
            }
            .navigationTitle("下载")
        }
    }
}
