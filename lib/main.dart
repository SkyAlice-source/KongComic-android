import 'dart:async';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/pages/auth_page.dart';
import 'package:kong_comic/pages/main_page.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kong_comic/utils/translations.dart';
import 'components/components.dart';
import 'components/window_frame.dart';
import 'foundation/app.dart';
import 'foundation/appdata.dart';
import 'headless.dart';
import 'init.dart';
import 'pages/follow_updates_page.dart';

/// 全局滚动行为：把 Android 越界辉光颜色从强调色改为中性灰，
/// 避免选了绿/蓝等强调色时列表四边泛绿。iOS 橡皮筋回弹手感保持不变。
class _NeutralOverscrollScrollBehavior extends MaterialScrollBehavior {
  const _NeutralOverscrollScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      // 注意：不能用 colorScheme.outlineVariant —— SeedColorScheme.fromSeeds
      // 整套配色都从主色种子派生，选绿/蓝等强调色时 outlineVariant 也带色相，
      // 越界辉光会泛绿。这里用无色相的纯灰，暗色/亮色下都是中性辉光。
      return GlowingOverscrollIndicator(
        axisDirection: details.direction,
        color: Colors.grey,
        child: child,
      );
    }
    return super.buildOverscrollIndicator(context, child, details);
  }
}

void main(List<String> args) {
  if (args.contains('--headless')) {
    runHeadlessMode(args);
    return;
  }
  if (runWebViewTitleBarWidget(args)) return;
  overrideIO(() {
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await init();
      runApp(const MyApp());
      if (App.isDesktop) {
        await windowManager.ensureInitialized();
        windowManager.waitUntilReadyToShow().then((_) async {
          await windowManager.setTitleBarStyle(
            TitleBarStyle.hidden,
            windowButtonVisibility: App.isMacOS,
          );
          if (App.isLinux) {
            await windowManager.setBackgroundColor(Colors.transparent);
          }
          await windowManager.setMinimumSize(const Size(500, 600));
          var placement = await WindowPlacement.loadFromFile();
          if (App.isLinux) {
            await windowManager.show();
            await placement.applyToWindow();
          } else {
            await placement.applyToWindow();
            await windowManager.show();
          }

          WindowPlacement.loop();
        });
      }
    }, (error, stack) {
      Log.error("Unhandled Exception", error, stack);
    });
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    App.registerForceRebuild(forceRebuild);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    checkUpdates();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FollowUpdatesService.disposeChecker();
    WindowPlacement.dispose();
    cancelHeartbeatTimer();
    super.dispose();
  }

  bool isAuthPageActive = false;

  OverlayEntry? hideContentOverlay;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!App.isMobile || !appdata.settings['authorizationRequired']) {
      return;
    }
    if (state == AppLifecycleState.inactive && hideContentOverlay == null) {
      hideContentOverlay = OverlayEntry(
        builder: (context) {
          return Positioned.fill(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: App.rootContext.colorScheme.surface,
            ),
          );
        },
      );
      Overlay.of(App.rootContext).insert(hideContentOverlay!);
    } else if (hideContentOverlay != null &&
        state == AppLifecycleState.resumed) {
      hideContentOverlay!.remove();
      hideContentOverlay = null;
    }
    if (state == AppLifecycleState.hidden &&
        !isAuthPageActive &&
        !IO.isSelectingFiles) {
      isAuthPageActive = true;
      App.rootContext.to(
        () => AuthPage(
          onSuccessfulAuth: () {
            App.rootContext.pop();
            isAuthPageActive = false;
          },
        ),
      );
    }
    super.didChangeAppLifecycleState(state);
  }

  void forceRebuild() {
    setState(() {});
  }

  /// 各主题色的种子色。
  ///
  /// 各主题色的种子色。
  ///
  /// - [red] 使用 Kong Coral 品牌色 #E5402A，保留唯一暖红主题。
  /// - 删除 [orange] 主题：与 red 在色相环上过于接近，造成「双红重复」。
  /// - secondary 统一采用互补/冷暖对比色，让同一主题内的 primary 与 secondary
  ///   拉开层次，避免整体看起来「一个颜色」。
  /// 返回 (primary, secondary) 配色对。
  (Color, Color) translateColorSetting() {
    return switch (appdata.settings['color']) {
      'red' => (const Color(0xFFE5402A), const Color(0xFF0EA5E9)), // 珊瑚红 + 冰蓝
      'pink' => (const Color(0xFFE1468C), const Color(0xFF8B5CF6)), // 玫红 + 雾紫
      'purple' => (const Color(0xFF7C5CFC), const Color(0xFFF97316)), // 罗兰紫 + 暖橘
      'green' => (const Color(0xFF1FA971), const Color(0xFFF59E0B)), // 翠绿 + 琥珀
      'blue' => (const Color(0xFF2D7FF9), const Color(0xFFF97316)), // 蔚蓝 + 暖橘
      'yellow' => (const Color(0xFFF5B400), const Color(0xFF0EA5E9)), // 琥珀黄 + 冰蓝
      'cyan' => (const Color(0xFF13B5C9), const Color(0xFF8B5CF6)), // 青蓝 + 雾紫
      'system' => (const Color(0xFF2D7FF9), const Color(0xFFF97316)),
      _ => (const Color(0xFF2D7FF9), const Color(0xFFF97316)),
    };
  }

  ThemeData getTheme(
    Color primary,
    Color? secondary,
    Color? tertiary,
    Brightness brightness, {
    bool amoled = false,
  }) {
    String? font;
    List<String>? fallback;
    if (App.isLinux || App.isWindows) {
      font = 'Noto Sans SC';
      fallback = [
        'Segoe UI',
        'Noto Sans SC',
        'Noto Sans TC',
        'Noto Sans',
        'Microsoft YaHei',
        'PingFang SC',
        'Arial',
        'sans-serif'
      ];
    } else {
      // 移动端也提供 CJK 字体回退栈，保证跨设备字形一致
      fallback = [
        'PingFang SC',
        'Noto Sans SC',
        'Noto Sans TC',
        'Microsoft YaHei',
        'sans-serif'
      ];
    }
    final bool isDark = brightness == Brightness.dark;
    final Color bg = isDark
        ? (amoled ? const Color(0xFF000000) : const Color(0xFF141013))
        : const Color(0xFFFBF7F4);
    return ThemeData(
      colorScheme: SeedColorScheme.fromSeeds(
        primaryKey: primary,
        secondaryKey: secondary,
        tertiaryKey: tertiary,
        brightness: brightness,
        tones: FlexTones.soft(brightness),
      ).copyWith(
        surfaceTint: Colors.transparent,
        surface: amoled && isDark ? const Color(0xFF0A0A0A) : null,
        surfaceContainerLowest: amoled && isDark ? const Color(0xFF000000) : null,
        surfaceContainerLow: amoled && isDark ? const Color(0xFF0F0F0F) : null,
        surfaceContainer: amoled && isDark ? const Color(0xFF161616) : null,
        surfaceContainerHigh: amoled && isDark ? const Color(0xFF1E1E1E) : null,
        surfaceContainerHighest: amoled && isDark ? const Color(0xFF242424) : null,
      ),
      // Material 默认底色统一为页面背景色，避免各页顶栏/tab栏出现白条
      canvasColor: bg,
      scaffoldBackgroundColor: bg,
      fontFamily: font,
      fontFamilyFallback: fallback,
      // 中文行高：默认 1.0 偏挤，全局抬到舒适区间，长阅读不累
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.copyWith(
        displayLarge: const TextStyle(height: 1.3),
        displayMedium: const TextStyle(height: 1.3),
        displaySmall: const TextStyle(height: 1.35),
        headlineLarge: const TextStyle(height: 1.3),
        headlineMedium: const TextStyle(height: 1.35),
        headlineSmall: const TextStyle(height: 1.4),
        titleLarge: const TextStyle(height: 1.35),
        titleMedium: const TextStyle(height: 1.4),
        titleSmall: const TextStyle(height: 1.4),
        bodyLarge: const TextStyle(height: 1.5),
        bodyMedium: const TextStyle(height: 1.45),
        bodySmall: const TextStyle(height: 1.4),
        labelLarge: const TextStyle(height: 1.4),
        labelMedium: const TextStyle(height: 1.4),
        labelSmall: const TextStyle(height: 1.4),
      ),
      // AppBar 标题统一降到 20px（仅 AppBar，不影响其它 titleLarge 用途）
      appBarTheme: AppBarTheme(
        titleTextStyle: TextStyle(
          fontSize: kcTitleLarge,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
      ),
      // 滚动条滑块用中性灰，避免跟随强调色（如选"绿"时右边缘出现绿条）
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          isDark
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.2),
        ),
        thickness: const WidgetStatePropertyAll(4.0),
        radius: const Radius.circular(2),
        interactive: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (appdata.settings['authorizationRequired']) {
      home = AuthPage(
        onSuccessfulAuth: () {
          App.rootContext.toReplacement(() => const MainPage());
        },
      );
    } else {
      home = const MainPage();
    }
    return DynamicColorBuilder(builder: (light, dark) {
      Color? primary, secondary, tertiary;
      if (appdata.settings['color'] != 'system' ||
          light == null ||
          dark == null) {
        final scheme = translateColorSetting();
        primary = scheme.$1;
        secondary = scheme.$2;
      } else {
        primary = light.primary;
        secondary = light.secondary;
        tertiary = light.tertiary;
      }
      return MaterialApp(
        key: ValueKey(appdata.settings['language'] ?? 'system'),
        title: "KongComic".tl,
        home: home,
        scrollBehavior: const _NeutralOverscrollScrollBehavior(),
        debugShowCheckedModeBanner: false,
        theme: getTheme(primary, secondary, tertiary, Brightness.light),
        navigatorKey: App.rootNavigatorKey,
        darkTheme: getTheme(primary, secondary, tertiary, Brightness.dark,
            amoled: appdata.settings['theme_mode'] == 'amoled'),
        themeMode: switch (appdata.settings['theme_mode']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          'amoled' => ThemeMode.dark,
          _ => ThemeMode.system
        },
        color: Colors.transparent,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        locale: () {
          var lang = appdata.settings['language'];
          if (lang == 'system') {
            return null;
          }
          return switch (lang) {
            'zh-CN' => const Locale('zh', 'CN'),
            'zh-TW' => const Locale('zh', 'TW'),
            'en-US' => const Locale('en'),
            _ => null
          };
        }(),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
          Locale('en'),
        ],
        builder: (context, widget) {
          ErrorWidget.builder = (details) {
            Log.error("Unhandled Exception",
                "${details.exception}\n${details.stack}");
            return Material(
              child: Center(
                child: Text(details.exception.toString()),
              ),
            );
          };
          if (widget != null) {
            /// 如果无法检测到状态栏高度设定指定高度
            /// https://github.com/flutter/flutter/issues/161086
            var isPaddingCheckError =
                MediaQuery.of(context).viewPadding.top <= 0 ||
                MediaQuery.of(context).viewPadding.top > 200;

            if (isPaddingCheckError && Platform.isAndroid) {
              widget = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    viewPadding: const EdgeInsets.only(
                      top: 15,
                      bottom: 15,
                    ),
                    padding: const EdgeInsets.only(
                      top: 15,
                      bottom: 15,
                    ),
                  ),
                  child: widget);
            }

            widget = OverlayWidget(widget);
            if (App.isDesktop) {
              widget = Shortcuts(
                shortcuts: {
                  LogicalKeySet(LogicalKeyboardKey.escape): VoidCallbackIntent(
                    App.pop,
                  ),
                },
                child: MouseBackDetector(
                  onTapDown: App.pop,
                  child: WindowFrame(widget),
                ),
              );
            }
            return _SystemUiProvider(Material(
              color: App.isLinux ? Colors.transparent : null,
              child: widget,
            ));
          }
          throw ('widget is null');
        },
      );
    });
  }
}

class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var brightness = Theme.of(context).brightness;
    SystemUiOverlayStyle systemUiStyle;
    if (brightness == Brightness.light) {
      systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
      );
    } else {
      systemUiStyle = SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}
