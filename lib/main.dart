import 'dart:async';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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

/// 初始化 Sentry 崩溃上报。
///
/// DSN 通过 `--dart-define=SENTRY_DSN=xxx` 在构建时传入，未配置时静默跳过
/// （本地开发/无 DSN 的构建不受影响）。发版 CI 需在 build 命令加该 define。
Future<void> _initSentry() async {
  const dsn = String.fromEnvironment('SENTRY_DSN');
  if (dsn.isEmpty) return;
  await SentryFlutter.init((options) {
    options.dsn = dsn;
    options.tracesSampleRate = 1.0;
    options.release = 'kong_comic@${App.appVersion}';
    options.attachThreads = true;
  });
}

void main(List<String> args) {
  if (args.contains('--headless')) {
    runHeadlessMode(args);
    return;
  }
  if (runWebViewTitleBarWidget(args)) return;
  overrideIO(() {
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();
        await Workmanager().initialize(backupCallbackDispatcher);
        await _initSentry();
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
      },
      (error, stack) {
        Log.error("Unhandled Exception", error, stack);
        Sentry.captureException(error, stackTrace: stack);
      },
    );
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
      'red' => (
        const Color(0xFFFF453A),
        const Color(0xFF0EA5E9),
      ), // 高饱和珊瑚红 + 鲜天蓝
      'pink' => (
        const Color(0xFFFF2D55),
        const Color(0xFF8B5CF6),
      ), // 高饱和玫红 + 电光紫
      'purple' => (
        const Color(0xFFBF5AF2),
        const Color(0xFFFF9F0A),
      ), // 高饱和紫 + 鲜橙
      'green' => (
        const Color(0xFF30D158),
        const Color(0xFFFF9F0A),
      ), // 高饱和草绿 + 鲜橙
      'blue' => (const Color(0xFF0A84FF), const Color(0xFFFF9F0A)), // 高饱和蓝 + 鲜橙
      'yellow' => (
        const Color(0xFFFFD60A),
        const Color(0xFF0EA5E9),
      ), // 高饱和黄 + 鲜天蓝
      'cyan' => (
        const Color(0xFF5AC8FA),
        const Color(0xFF8B5CF6),
      ), // 高饱和青 + 电光紫
      // 默认（system）不再跟壁纸动态色，直接落到品牌红 + 同族珊瑚红：
      // 浅色下的选中胶囊、次级按钮、勾选框才会和主 CTA 是同一套红。
      'system' => (kcBrandColor, kcBrandColorOnDark),
      _ => (kcBrandColor, kcBrandColorOnDark),
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
        'sans-serif',
      ];
    } else {
      // 移动端也提供 CJK 字体回退栈，保证跨设备字形一致
      fallback = [
        'PingFang SC',
        'Noto Sans SC',
        'Noto Sans TC',
        'Microsoft YaHei',
        'sans-serif',
      ];
    }
    final bool isDark = brightness == Brightness.dark;
    // 三套外观，互不串味：
    // · 浅色：用户所选强调色（蓝/红/绿…）的鲜艳配色；
    // · 深色（含「跟随系统」落到暗色）：品牌红 + 暖近黑底，彩色只在强调处出现；
    // · AMOLED：纯黑 + 纯灰阶，全站零彩色。
    final bool grayscale = isDark && amoled;
    final Color bg = isDark
        ? (amoled ? const Color(0xFF0A0A0A) : const Color(0xFF100D0F))
        : Colors.white;

    final ColorScheme scheme;
    if (grayscale) {
      // 灰度深色：所有表面/容器/容器高都中性化，选中态、开关、CTA 等由组件层用
      // cs.surfaceContainerHigh 等灰阶表达，绝不冒出主题色。
      final surface = amoled
          ? const Color(0xFF0F0F0F)
          : const Color(0xFF171717);
      final low = amoled ? const Color(0xFF141414) : const Color(0xFF1C1C1C);
      final container = amoled
          ? const Color(0xFF191919)
          : const Color(0xFF242424);
      final high = amoled ? const Color(0xFF212121) : const Color(0xFF2E2E2E);
      final highest = amoled
          ? const Color(0xFF2A2A2A)
          : const Color(0xFF383838);
      scheme =
          SeedColorScheme.fromSeeds(
            primaryKey: Colors.white,
            secondaryKey: const Color(0xFFB0B0B0),
            tertiaryKey: const Color(0xFF808080),
            brightness: brightness,
            tones: FlexTones.soft(brightness),
          ).copyWith(
            surfaceTint: Colors.transparent,
            // primary 取柔和浅灰，减少纯黑底上的刺眼感；暗色零彩色，任何 primary
            // 用法（Tab 文字、图标、计数徽标）都呈中性灰。
            primary: const Color(0xFFE0E0E0),
            onPrimary: Colors.black,
            secondary: const Color(0xFFB0B0B0),
            onSecondary: Colors.black,
            tertiary: const Color(0xFF808080),
            onTertiary: Colors.white,
            surface: surface,
            surfaceContainerLowest: amoled
                ? const Color(0xFF050505)
                : const Color(0xFF0E0E0E),
            // 层高阶梯：AMOLED 的 Low(#141414) 与底(#0A0A0A) 原只差 5，卡片贴成一片；
            // 拉开后 surfaceContainerLow 面才真正浮起。普通深灰(#121212) 同步等比抬高。
            surfaceContainerLow: low,
            surfaceContainer: container,
            surfaceContainerHigh: high,
            surfaceContainerHighest: highest,
            onSurface: const Color(0xFFEDEAEB),
            onSurfaceVariant: const Color(0xFFA9A6A7),
            outline: const Color(0xFF3A3A3A),
            outlineVariant: const Color(0xFF2A2A2A),
            // 派生容器色一并压成中性灰，确保任何使用 primaryContainer/
            // secondaryContainer/surfaceVariant 的组件（如主页计数徽标）在
            // 纯黑外观下都不会泄漏主题色。
        primaryContainer: highest,
        onPrimaryContainer: Colors.white,
        secondaryContainer: highest,
        onSecondaryContainer: Colors.white,
        tertiaryContainer: highest,
        onTertiaryContainer: Colors.white,
        // errorContainer 也必须压成灰：AppBadge 的 warning 类型（「需登录」
        // 「新版本」）正是用它做底，不覆盖就会在纯黑界面上冒出一块红。
        // 只收容器色，`error` 本身仍是红——删除类按钮按约定保留语义红。
        errorContainer: high,
        onErrorContainer: const Color(0xFFEDEAEB),
            inverseSurface: const Color(0xFFE0E0E0),
            inversePrimary: const Color(0xFFB0B0B0),
          );
    } else if (isDark) {
      // 深色（品牌红）：暖近黑底 + 红色强调。大面积仍是中性深灰，红只出现在
      // 主 CTA、开关 ON、当前章节、选中胶囊这些「落点」上，避免整屏泛红。
      scheme =
          SeedColorScheme.fromSeeds(
            primaryKey: kcBrandColor,
            secondaryKey: kcBrandColorOnDark,
            tertiaryKey: const Color(0xFFFF9F0A),
            brightness: brightness,
            tones: FlexTones.soft(brightness),
          ).copyWith(
            surfaceTint: Colors.transparent,
            // primary 用提亮一档的红（#E4553A）：它会落在图标、小字号文字上，
            // 在暖近黑底上的对比度才够；面与线由 kcAccentColor 取深一档的
            // #D4381B，配白字更稳。
            primary: kcBrandColorOnDark,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFF4A1810),
            onPrimaryContainer: const Color(0xFFFFDAD2),
            secondary: const Color(0xFFE8A38F),
            onSecondary: Colors.black,
            tertiary: const Color(0xFFFFB86B),
            onTertiary: Colors.black,
            // 暖近黑：比纯黑多一点红调，和品牌红同源，卡片浮起时不会发蓝发灰。
            surface: const Color(0xFF100D0F),
            surfaceContainerLowest: const Color(0xFF0A0809),
            surfaceContainerLow: const Color(0xFF181415),
            surfaceContainer: const Color(0xFF1F1A1C),
            surfaceContainerHigh: const Color(0xFF272123),
            surfaceContainerHighest: const Color(0xFF302A2C),
            onSurface: const Color(0xFFEDEAEB),
            onSurfaceVariant: const Color(0xFFA9A6A7),
            outline: const Color(0xFF4A4244),
            outlineVariant: const Color(0xFF352E30),
            secondaryContainer: const Color(0xFF2A2022),
            onSecondaryContainer: const Color(0xFFF0E7E8),
            tertiaryContainer: const Color(0xFF2A2022),
            onTertiaryContainer: const Color(0xFFF0E7E8),
            inverseSurface: const Color(0xFFE0E0E0),
            inversePrimary: kcBrandColor,
          );
    } else {
      // 浅色：品牌红（或用户显式选的颜色）作为 primary。容器色仍交给
      // FlexTones 派生，但 primary 取种子原色，避免 vivid 把它推到更亮的
      // tone 后与 kcAccentColor 的红对不上，出现「两种红」。
      final base = SeedColorScheme.fromSeeds(
        primaryKey: primary,
        secondaryKey: secondary,
        tertiaryKey: tertiary,
        brightness: Brightness.light,
        tones: FlexTones.vivid(Brightness.light),
      );
      scheme = base.copyWith(
        surfaceTint: Colors.transparent,
        primary: primary,
        onPrimary: Colors.white,
        // 表面层全部中性化：品牌红只做「强调」，不把卡片、弹窗、勾选行的底
        // 染成粉色。种子派生出的中性色带红相（弹窗看起来像一块浅粉），
        // 在城市白底上既不干净，也和「克制用色」的设计语汇相反。
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF7F7F8),
        surfaceContainer: const Color(0xFFF2F2F4),
        surfaceContainerHigh: const Color(0xFFEDEDEF),
        surfaceContainerHighest: const Color(0xFFE6E6E9),
        outline: const Color(0xFFC9C9CE),
        outlineVariant: const Color(0xFFE4E4E7),
      );
    }

    final theme = ThemeData(
      colorScheme: scheme,
      // Material 默认底色统一为页面背景色，避免各页顶栏/tab栏出现白条
      canvasColor: bg,
      scaffoldBackgroundColor: bg,
      fontFamily: font,
      fontFamilyFallback: fallback,
      // 中文行高：默认 1.0 偏挤，全局抬到舒适区间，长阅读不累
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme
          .copyWith(
            displayLarge: const TextStyle(height: 1.3),
            displayMedium: const TextStyle(height: 1.3),
            displaySmall: const TextStyle(
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
            headlineLarge: const TextStyle(
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
            headlineMedium: const TextStyle(
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
            headlineSmall: const TextStyle(
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: const TextStyle(
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
            titleMedium: const TextStyle(
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: const TextStyle(
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: const TextStyle(height: 1.5),
            bodyMedium: const TextStyle(height: 1.45),
            bodySmall: const TextStyle(height: 1.4),
            labelLarge: const TextStyle(height: 1.4),
            labelMedium: const TextStyle(height: 1.4),
            labelSmall: const TextStyle(height: 1.4),
          ),
      // AppBar 标题统一跟随 kcAppbarTitle（20），与 Appbar/SliverAppbar 自绘标题
      // 同尺寸，并与根页主标题（kcTitleMain 20）齐平；只作用于原生 AppBar。
      appBarTheme: AppBarTheme(
        titleTextStyle: TextStyle(
          fontSize: kcAppbarTitle,
          height: 1.35,
          fontWeight: FontWeight.w600,
          // ⚠️ 必须显式给 color：AppBarTheme.titleTextStyle 一旦定义，
          // 就会整体接管 AppBar 标题样式；color 为 null 时标题颜色会丢，
          // 在浅色背景上渲染成近乎白色（分享图片选择页因此看不清）。
          color: scheme.onSurface,
        ),
      ),
      // 弹窗菜单（右上角 ⋮ / 设置页下拉）统一语汇：
      // 默认 M2 菜单是 4dp 直角 + 重投影，和全站 16dp 圆角、发丝描边的扁平
      // 卡片完全不像一套东西。这里改成「白/深灰面 + 0.8 描边 + 16 圆角 +
      // 轻投影」，既有浮起的层级感，又不会像一块厚重的塑料片。
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? scheme.surfaceContainerHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.55 : 0.14),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcRadius16),
          side: BorderSide(
            color: isDark
                ? scheme.outlineVariant
                : scheme.outline.withValues(alpha: 0.45),
            width: 0.8,
          ),
        ),
        textStyle: TextStyle(
          fontSize: kcBody,
          height: 1.35,
          color: scheme.onSurface,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: kcBody,
            height: 1.35,
            color: states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : scheme.onSurface,
          ),
        ),
      ),
      // 对话框统一语汇：ContentDialog 是绝大多数弹窗的基座，但仍有少数地方
      // 直接构造原生 Dialog（删除章节、加载中）。这里把 Dialog 的默认表面也锁到
      // 与 ContentDialog 同一套「surfaceContainerHigh + 24 圆角 + 发丝描边 +
      // 轻投影」，避免它们退回 M2 默认的浅色方角 + 重阴影，与源仓库卡片的扁平
      // 语言（surfaceContainerLow + outlineVariant 描边）脱节。
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcSurfaceRadius),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
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

    // AMOLED 纯黑：去掉彩色按钮，改为黑灰底 + 白字 + 细描边，
    // 在纯黑背景上呈现「黑灰高对比」的精髓。
    if (grayscale) {
      const buttonBg = Color(0xFF242424);
      const buttonBorder = Color(0xFF3D3D3D);
      final overlay = WidgetStatePropertyAll(
        Colors.white.withValues(alpha: 0.08),
      );
      final shape = WidgetStatePropertyAll<OutlinedBorder>(
        const StadiumBorder(),
      );
      return theme.copyWith(
        // 勾选/单选在纯黑外观下也必须零彩色：用浅灰填充 + 深色勾，
        // 比深灰块更清楚，也不会比开关更抢眼。
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? scheme.primary : null,
          ),
          checkColor: const WidgetStatePropertyAll(Colors.black),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? scheme.primary : null,
          ),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: scheme.primary,
        ),
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
    // 浅色 / 深色：主按钮恒为品牌红 + 白字，次级按钮（取消、跳转说明等）走
    // 中性灰文字而不是主题强调色。否则浅色下默认「蓝」会在红色设计里突兀地
    // 冒出来（分页「前进」、弹窗「退出」都踩过这个坑）。
    final Color disabledBg = scheme.onSurface.withValues(alpha: 0.08);
    final Color disabledFg = scheme.onSurface.withValues(alpha: 0.38);
    return theme.copyWith(
      // 勾选 / 单选 / 进度条统一走品牌红：它们是最常出现「选中」语义的原生
      // 控件，若仍跟着用户选的强调色（默认蓝），会和红色按钮同屏打架。
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? kcBrandColor : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? kcBrandColor : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: kcBrandColor,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? disabledBg
                : kcBrandColor,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? disabledFg
                : Colors.white,
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.10),
          ),
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(scheme.onSurfaceVariant),
          overlayColor: WidgetStatePropertyAll(
            scheme.onSurfaceVariant.withValues(alpha: 0.08),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
        ),
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
    // 不再采用系统壁纸动态色（Android 12+）。动态色会把浅色主题的 primary
    // 染成壁纸的蓝/紫，分页「前进」、弹窗按钮、次级胶囊图标就跟着变蓝，和
    // 品牌红设计直接打架。「主题色」里显式选的颜色仍然生效，默认值落到品牌红。
    return DynamicColorBuilder(
      builder: (_, __) {
        final pair = translateColorSetting();
        final Color primary = pair.$1;
        final Color secondary = pair.$2;
        const Color? tertiary = null;
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
            _ => ThemeMode.system,
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
              _ => null,
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
              Log.error(
                "Unhandled Exception",
                "${details.exception}\n${details.stack}",
              );
              return Material(
                child: Center(child: Text(details.exception.toString())),
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
                    viewPadding: const EdgeInsets.only(top: 15, bottom: 15),
                    padding: const EdgeInsets.only(top: 15, bottom: 15),
                  ),
                  child: widget,
                );
              }

              widget = OverlayWidget(widget);
              if (App.isDesktop) {
                widget = Shortcuts(
                  shortcuts: {
                    LogicalKeySet(LogicalKeyboardKey.escape):
                        VoidCallbackIntent(App.pop),
                  },
                  child: MouseBackDetector(
                    onTapDown: App.pop,
                    child: WindowFrame(widget),
                  ),
                );
              }
              return _SystemUiProvider(
                Material(
                  color: App.isLinux ? Colors.transparent : null,
                  child: widget,
                ),
              );
            }
            throw ('widget is null');
          },
        );
      },
    );
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
