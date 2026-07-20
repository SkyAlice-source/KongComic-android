/// 全局字号 token —— 排版字号的唯一事实来源（single source of truth）。
///
/// - 非 const 场景：优先用 [StyledText] 的 `.sNN` 简写（它们委托到这里的常量）。
/// - const 场景（`const TextStyle(...)`）：直接引用本类常量，不要裸写数字。
///
/// 字阶覆盖当前实际在用的全部尺寸，按展示/标题/正文/辅助分层。
/// 新增字号时请先在此登记，避免再次出现散落的魔法数字。
class AppFontSizes {
  // 展示层
  static const double s40 = 40;
  static const double s36 = 36;
  static const double s32 = 32;
  static const double s28 = 28;
  static const double s24 = 24;

  // 标题层
  static const double s22 = 22;
  static const double s20 = 20;
  static const double s18 = 18;

  // 正文层
  static const double s16 = 16;
  static const double s15 = 15;
  static const double s14 = 14;

  // 辅助层
  static const double s13 = 13;
  static const double s12 = 12;
  static const double s11 = 11;
  static const double s10 = 10;
  static const double s9 = 9;
  static const double s8 = 8;
}
