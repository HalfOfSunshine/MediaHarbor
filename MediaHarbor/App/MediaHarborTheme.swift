import SwiftUI
import UIKit

enum MediaHarborTheme {
    static let tabSelectedUIColor = UIColor(red: 0.16, green: 0.73, blue: 0.78, alpha: 1.0)
    static let tabUnselectedUIColor = UIColor(red: 0.64, green: 0.68, blue: 0.73, alpha: 1.0)
    static let tabBackgroundUIColor = UIColor(red: 0.985, green: 0.99, blue: 0.995, alpha: 1.0)
    static let tabShadowUIColor = UIColor(red: 0.10, green: 0.16, blue: 0.23, alpha: 0.06)

    static var tabSelectedColor: Color {
        Color(uiColor: tabSelectedUIColor)
    }

    static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = tabBackgroundUIColor
        appearance.shadowColor = tabShadowUIColor

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: tabUnselectedUIColor
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: tabSelectedUIColor
        ]

        let layouts = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]

        for layout in layouts {
            layout.normal.iconColor = tabUnselectedUIColor
            layout.normal.titleTextAttributes = normalAttributes
            layout.selected.iconColor = tabSelectedUIColor
            layout.selected.titleTextAttributes = selectedAttributes
        }

        let tabBarAppearance = UITabBar.appearance()
        tabBarAppearance.standardAppearance = appearance
        tabBarAppearance.scrollEdgeAppearance = appearance
        tabBarAppearance.tintColor = tabSelectedUIColor
        tabBarAppearance.unselectedItemTintColor = tabUnselectedUIColor

        let itemAppearance = UITabBarItem.appearance()
        itemAppearance.setTitleTextAttributes(normalAttributes, for: .normal)
        itemAppearance.setTitleTextAttributes(selectedAttributes, for: .selected)
    }
}
