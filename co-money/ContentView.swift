// ContentView.swift
// co-money
// 根路由器：根据身份验证状态显示 LoginView 或 MainTabView
// Root router: shows LoginView or MainTabView depending on auth state

import SwiftUI

/// ContentView 根视图路由器 | ContentView Root View Router
///
/// 这个视图是应用程序的核心路由逻辑。它充当"守门员"的角色，根据用户是否
/// 已登录来决定显示哪个视图：
/// - 如果用户已登录 (isLoggedIn == true)，显示 MainTabView（应用程序主界面）
/// - 如果用户未登录 (isLoggedIn == false)，显示 LoginView（登录界面）
/// | This view is the app's core routing logic. It acts as a "gatekeeper" deciding which view
/// to show based on whether the user is logged in:
/// - If logged in (isLoggedIn == true): show MainTabView (main app interface)
/// - If not logged in (isLoggedIn == false): show LoginView (login interface)
///
/// 这种模式称为"条件路由"（Conditional Routing），在单屏应用程序中很常见。
/// | This pattern is called "Conditional Routing", commonly used in single-screen apps.
struct ContentView: View {

    /// @Environment 环境变量 | @Environment Property Wrapper
    ///
    /// @Environment 从视图环境中读取一个对象。在 co_moneyApp.swift 中，
    /// 我们使用 .environment(authVM) 将 AuthViewModel 注入到环境中。
    /// | @Environment reads an object from the view's environment. In co_moneyApp.swift,
    /// we inject the AuthViewModel into the environment using .environment(authVM).
    ///
    /// @Environment(AuthViewModel.self) 告诉 SwiftUI：
    /// "从环境中查找类型为 AuthViewModel 的对象"
    /// | @Environment(AuthViewModel.self) tells SwiftUI:
    /// "Find an object of type AuthViewModel in the environment"
    ///
    /// private 修饰符使 authVM 仅在此视图内部可访问。
    /// | The private modifier makes authVM accessible only within this view.
    ///
    /// 每当 authVM 中的数据改变时，这个视图会自动重新渲染，导致 if 条件被重新评估。
    /// | Whenever data in authVM changes, this view automatically re-renders, causing the if
    /// condition to be re-evaluated.
    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        /// Group 视图分组 | Group View Container
        ///
        /// Group 是一个简单的容器，用于在不改变视图布局的情况下对多个视图进行分组。
        /// 这里使用 Group 是因为 if-else 在 SwiftUI 中不能直接用于视图的顶级内容。
        /// | Group is a simple container for grouping multiple views without affecting layout.
        /// We use Group here because if-else can't be used directly at the top level of a view's content.
        ///
        /// Group 不添加任何额外的 UI 元素或间距，它只是一个逻辑容器。
        /// | Group doesn't add any extra UI elements or spacing; it's just a logical container.
        Group {
            /// 条件路由 | Conditional Routing
            ///
            /// 根据 authVM.isLoggedIn 布尔值显示不同的视图：
            /// | Show different views based on the authVM.isLoggedIn boolean:
            if authVM.isLoggedIn {
                /// 用户已登录 | User is logged in
                /// 显示应用程序的主界面，包含选项卡导航
                /// | Show the app's main interface with tab navigation
                MainTabView()
            } else {
                /// 用户未登录 | User is not logged in
                /// 显示登录界面，允许用户进行身份验证
                /// | Show the login interface to allow user authentication
                LoginView()
            }
        }

        /// .animation 动画修饰符 | .animation Modifier
        ///
        /// .animation 应用一个平滑的转换动画到因特定值改变而导致的视图更新。
        /// | The .animation modifier applies a smooth transition animation to view updates caused by a specific value change.
        ///
        /// 参数说明 | Parameter Explanation:
        /// - .easeInOut(duration: 0.3): 动画类型为"缓入缓出"，持续时间为 0.3 秒
        ///   | Animation type is "ease in/ease out" with a 0.3 second duration
        /// - value: authVM.isLoggedIn: 监视 isLoggedIn 值。当此值改变时，应用动画
        ///   | value: authVM.isLoggedIn: Watch the isLoggedIn value. Apply animation when it changes
        ///
        /// 实际效果：当用户登录或登出时，LoginView 和 MainTabView 之间的过渡会有
        /// 平滑的淡入淡出动画，而不是硬生生的切换。
        /// | In practice: When user logs in/out, the transition between LoginView and MainTabView
        /// will have a smooth fade animation instead of a harsh cut.
        .animation(.easeInOut(duration: 0.3), value: authVM.isLoggedIn)
    }
}
