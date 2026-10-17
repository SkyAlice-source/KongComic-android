/// If window width is less than this value, it is considered as mobile.
const changePoint = 600;

/// If window width is less than this value, it is considered as tablet.
///
/// If it is more than this value, it is considered as desktop.
///
/// 改为 840 以对齐 Material 3 响应式断点：compact <600（悬浮底栏）、
/// 600–840 折叠导航栏（仅图标）、≥840 展开导航栏（图标+文字）。原 1300
/// 偏高，平板（约 800–1000dp 宽）迟迟不展开文字标签，观感偏「窄屏」。
const changePoint2 = 840;

/// Default user agent for http requests.
const webUA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36";

/// Pages for all comics is started from this value.
const firstPage = 1;

/// Chapters for all comics is started from this value.
const firstChapter = 1;