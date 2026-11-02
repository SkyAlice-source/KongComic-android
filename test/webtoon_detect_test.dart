import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/pages/reader/reader.dart';

/// 自动条漫识别的判定边界。
///
/// 这段逻辑决定「打开一章后是否自动切成竖向连续模式」，误判的代价是整章
/// 排版突变，所以阈值和「过半」的边界都钉死在测试里：以后有人调阈值或把
/// `>=` 写成 `>`，这里会立刻红。
void main() {
  group('looksLikeWebtoon', () {
    test('全是长条 -> 条漫', () {
      expect(looksLikeWebtoon([3.0, 2.5, 4.2]), isTrue);
    });

    test('全是常规页面 -> 非条漫', () {
      expect(looksLikeWebtoon([1.4, 1.5, 1.38]), isFalse);
    });

    test('恰好一半是长条 -> 条漫（边界取等）', () {
      expect(looksLikeWebtoon([2.0, 1.4]), isTrue);
    });

    test('少于一半是长条 -> 非条漫', () {
      expect(looksLikeWebtoon([2.0, 1.4, 1.5]), isFalse);
    });

    test('阈值 2.0 本身算长条，1.99 不算', () {
      expect(looksLikeWebtoon([2.0]), isTrue);
      expect(looksLikeWebtoon([1.99]), isFalse);
    });

    test('空输入（全部探测失败）-> 非条漫，不误切', () {
      expect(looksLikeWebtoon([]), isFalse);
    });
  });
}
