import SwiftUI

extension View {
    func secondaryPageStyle() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
