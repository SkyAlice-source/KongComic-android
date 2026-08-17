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
import 'package:workmanager/workmanager.dart';
import 'package:kong_comic/utils/translations.dart';
import 'components/components.dart';
import 'components/window_frame.dart';
import 'foundation/app.dart';
import 'foundation/appdata.dart';
import 'headless.dart';
import 'init.dart';
import 'pages/follow_updates_page.dart';
import 'package:kong_comic/utils/auto_backup.dart';

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
      await Workmanager().initialize(backupCallbackDispatcher);
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

  @override
  void didChangePlatformBrightness() {
    // theme_mode='system' 时跟随系统明暗切换，OS 主题变化即时生效（无需重启）。
    setState(() {});
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
      'red' => (const Color(0xFFFF453A), const Color(0xFF0EA5E9)), // 高饱和珊瑚红 + 鲜天蓝
      'pink' => (const Color(0xFFFF2D55), const Color(0xFF8B5CF6)), // 高饱和玫红 + 电光紫
      'purple' => (const Color(0xFFBF5AF2), const Color(0xFFFF9F0A)), // 高饱和紫 + 鲜橙
      'green' => (const Color(0xFF30D158), const Color(0xFFFF9F0A)), // 高饱和草绿 + 鲜橙
      'blue' => (const Color(0xFF0A84FF), const Color(0xFFFF9F0A)), // 高饱和蓝 + 鲜橙
      'yellow' => (const Color(0xFFFFD60A), const Color(0xFF0EA5E9)), // 高饱和黄 + 鲜天蓝
      'cyan' => (const Color(0xFF5AC8FA), const Color(0xFF8B5CF6)), // 高饱和青 + 电光紫
      'system' => (const Color(0xFF0A84FF), const Color(0xFFFF9F0A)),
      _ => (const Color(0xFF0A84FF), const Color(0xFFFF9F0A)),
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
    // 暗色模式下（非 AMOLED）采用「暗彩」风格：提高主题色饱和度、压低亮度，
    // 得到比浅色更深更艳的暗彩观感（纯黑 AMOLED 分支另走中性灰）。
    final effectivePrimary = isDark && !amoled
        ? kcDarkColorful(primary)
        : primary;
    final effectiveSecondary = isDark && !amoled && secondary != null
        ? kcDarkColorful(secondary)
        : secondary;
    final effectiveTertiary = isDark && !amoled && tertiary != null
        ? kcDarkColorful(tertiary)
        : tertiary;
    // 浅色模式底色统一纯白，与 AppBar/导航栏/卡片保持一致，消除加载时底色割裂；
    // 暗彩（非 AMOLED）压到接近纯黑但保留一丝暖度，与纯黑 AMOLED 区分。
    final Color bg = isDark
        ? (amoled ? const Color(0xFF0A0A0A) : const Color(0xFF100D0F))
        : Colors.white;

    final ColorScheme scheme;
    if (amoled && isDark) {
      // AMOLED/纯黑外观：去掉所有彩色主题色，用中性灰阶，保证对比清晰。
      scheme = SeedColorScheme.fromSeeds(
        primaryKey: Colors.white,
        secondaryKey: const Color(0xFFB0B0B0),
        tertiaryKey: const Color(0xFF808080),
        brightness: brightness,
        tones: FlexTones.soft(brightness),
      ).copyWith(
        surfaceTint: Colors.transparent,
        // 纯黑外观下把 primary/secondary/tertiary 也压成中性灰白，
        // 避免 SeedColorScheme 处理白色种子时意外偏色。
        // 选中 tab/活跃图标用柔和浅灰而非纯白，减少纯黑底上的刺眼感。
        primary: const Color(0xFFE0E0E0),
        onPrimary: Colors.black,
        secondary: const Color(0xFFB0B0B0),
        onSecondary: Colors.black,
        tertiary: const Color(0xFF808080),
        onTertiary: Colors.white,
        surface: const Color(0xFF0F0F0F),
        surfaceContainerLowest: const Color(0xFF050505),
        surfaceContainerLow: const Color(0xFF0F0F0F),
        surfaceContainer: const Color(0xFF161616),
        surfaceContainerHigh: const Color(0xFF1E1E1E),
        surfaceContainerHighest: const Color(0xFF262626),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFB0B0B0),
        outline: const Color(0xFF3A3A3A),
        outlineVariant: const Color(0xFF2A2A2A),
        // 派生容器色一并压成中性灰，确保任何使用 primaryContainer/
        // secondaryContainer/surfaceVariant 的组件（如主页计数徽标）在
        // 纯黑外观下都不会泄漏主题色。
        primaryContainer: const Color(0xFF2A2A2A),
        onPrimaryContainer: Colors.white,
        secondaryContainer: const Color(0xFF2A2A2A),
        onSecondaryContainer: Colors.white,
        tertiaryContainer: const Color(0xFF2A2A2A),
        onTertiaryContainer: Colors.white,
        inverseSurface: const Color(0xFFE0E0E0),
        inversePrimary: const Color(0xFFB0B0B0),
      );
    } else {
      // 暗彩：刻意比浅色更深、更艳。
      // FlexTones.vivid 在暗色下会把 primary 映射到 tone 80（浅色），导致暗彩
      // accent 与浅色饱和度几乎一致、且偏浅（截图里按钮仍是浅蓝）。这里先生成
      // 同一套种子在浅色下的 vivid 配色，再把它逐个 accent 经 kcDarkColorful
      // 加深加饱和后覆盖到暗色彩色方案上，保证暗彩明显比浅色更深更艳且对比可读。
      final lightScheme = SeedColorScheme.fromSeeds(
        primaryKey: primary,
        secondaryKey: secondary,
        tertiaryKey: tertiary,
        brightness: Brightness.light,
        tones: FlexTones.vivid(Brightness.light),
      ).copyWith(surfaceTint: Colors.transparent);
      final darkBase = SeedColorScheme.fromSeeds(
        primaryKey: effectivePrimary,
        secondaryKey: effectiveSecondary,
        tertiaryKey: effectiveTertiary,
        brightness: brightness,
        tones: FlexTones.vivid(brightness),
      ).copyWith(surfaceTint: Colors.transparent);
      scheme = kcDarkColorfulFromLight(lightScheme, darkBase);
    }

    final theme = ThemeData(
      colorScheme: scheme,
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

    // AMOLED/纯黑外观：去掉彩色按钮，改为黑灰底 + 白字 + 细描边，
    // 在柔和纯黑背景上呈现「黑灰高对比」的精髓。
    if (amoled && isDark) {
      const buttonBg = Color(0xFF242424);
      const buttonBorder = Color(0xFF3D3D3D);
      final overlay = WidgetStatePropertyAll(
        Colors.white.withValues(alpha: 0.08),
      );
      final shape = WidgetStatePropertyAll<OutlinedBorder>(
        const StadiumBorder(),
      );
      return theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(buttonBg),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            side: const WidgetStatePropertyAll(
              BorderSide(color: buttonBorder, width: 1),
            ),
            overlayColor: overlay,
            shape: shape,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(buttonBg),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            side: const WidgetStatePropertyAll(
              BorderSide(color: buttonBorder, width: 1),
            ),
            overlayColor: overlay,
            shape: shape,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            side: const WidgetStatePropertyAll(
              BorderSide(color: buttonBorder, width: 1),
            ),
            overlayColor: overlay,
            shape: shape,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            overlayColor: overlay,
            shape: shape,
          ),
        ),
      );
    }
    return theme;
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
        darkTheme: getTheme(
          primary,
          secondary,
          tertiary,
          Brightness.dark,
          amoled: appdata.isAmoledMode,
        ),
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
            'ja-JP' => const Locale('ja', 'JP'),
            'en-US' => const Locale('en'),
            _ => null
          };
        }(),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
          Locale('ja', 'JP'),
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
