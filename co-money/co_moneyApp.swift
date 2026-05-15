// co_moneyApp.swift
// co-money

import SwiftUI

/// @main 入口点 | @main Entry Point
///
/// @main 属性将此结构标记为应用程序的主入口点。SwiftUI 会自动启动此结构。
/// | The @main attribute marks this struct as the app's main entry point. SwiftUI automatically
/// launches this struct when the app starts.
///
/// App 协议 | App Protocol
///
/// 遵守 App 协议的结构定义应用程序的整体生命周期和 UI 结构。每个 SwiftUI 应用程序
/// 必须有且仅有一个符合 App 协议的结构。
/// | A struct conforming to the App protocol defines the app's overall lifecycle and UI structure.
/// Every SwiftUI app must have exactly one struct that conforms to the App protocol.
///
/// body 属性必须返回一个 Scene (场景)，它描述应用程序呈现的顶级内容容器。
/// | The body property must return a Scene, which describes the top-level content container the app presents.
@main
struct co_moneyApp: App {

    /// @State 私有状态变量 | @State Private State Variable
    ///
    /// @State 创建一个私有的、由 SwiftUI 管理的状态值。当状态改变时，依赖该状态的
    /// 视图会自动重新渲染（刷新）。
    /// | @State creates a private, SwiftUI-managed state value. When the state changes, views that
    /// depend on it automatically re-render.
    ///
    /// 将 authVM 声明为 @State 确保它在应用程序的整个生命周期内保持存活，
    /// 不会被重新初始化。这很重要，因为我们需要跨多个视图共享身份验证状态。
    /// | Declaring authVM as @State ensures it stays alive for the entire app lifecycle and
    /// won't be re-initialized. This is crucial because we need to share auth state across multiple views.
    @State private var authVM = AuthViewModel()

    /// body: some Scene | 主体：某个场景
    ///
    /// 返回应用程序的场景（顶级容器）。场景定义了应用程序的 UI 结构。
    /// | Returns the app's scene (top-level container). Scenes define the app's UI structure.
    var body: some Scene {

        /// WindowGroup 窗口组 | WindowGroup
        ///
        /// WindowGroup 是 iOS/macOS 应用程序中最常见的场景类型。它为应用程序
        /// 创建一个主窗口，并管理在该窗口中显示的内容。
        /// | WindowGroup is the most common scene type for iOS/macOS apps. It creates a main window
        /// for the app and manages the content displayed in that window.
        ///
        /// 在 iOS 上，通常每个应用程序只有一个 WindowGroup。在 macOS 上，
        /// 用户可以创建多个 WindowGroup 实例来打开多个窗口。
        /// | On iOS, typically there's only one WindowGroup per app. On macOS, users can create
        /// multiple WindowGroup instances to open multiple windows.
        WindowGroup {
            /// ContentView 是应用程序的根视图（根路由器）。它将根据身份验证状态
            /// 决定显示登录视图还是主选项卡视图。
            /// | ContentView is the app's root view (root router). It decides whether to show
            /// the login view or the main tab view based on authentication state.
            ContentView()
                /// .environment 修饰符 | .environment Modifier
                ///
                /// .environment(_:) 将一个对象注入到视图环境中，使所有子视图都可以
                /// 通过 @Environment 属性包装器访问它。这是 SwiftUI 中实现依赖注入的
                /// 标准方式。
                /// | The .environment(_:) modifier injects an object into the view's environment,
                /// making it accessible to all child views via the @Environment property wrapper.
                /// This is SwiftUI's standard dependency injection pattern.
                ///
                /// 通过将 authVM 注入到环境中，任何子视图都可以使用
                /// @Environment(AuthViewModel.self) 来访问相同的实例，从而共享状态。
                /// | By injecting authVM into the environment, any child view can access the same
                /// instance using @Environment(AuthViewModel.self), enabling state sharing.
                .environment(authVM)
        }
    }
}
