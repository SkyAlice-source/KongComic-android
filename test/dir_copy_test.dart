import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/utils/dir_copy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Directory src;
  late Directory dst;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kcdircopy');
    src = Directory(p.join(tmp.path, 'src'))..createSync();
    dst = Directory(p.join(tmp.path, 'dst'))..createSync();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void writeSrc(String rel, String content) {
    final file = File(p.join(src.path, rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  test('递归复制嵌套目录，返回真实复制的文件数', () {
    writeSrc('a.txt', 'A');
    writeSrc(p.join('vol01', '1.txt'), 'one');
    writeSrc(p.join('vol01', 'sub', '2.txt'), 'two');

    final copied = copyDirectoryContentsSync(src.path, dst.path);

    expect(copied, 3);
    expect(File(p.join(dst.path, 'a.txt')).readAsStringSync(), 'A');
    expect(File(p.join(dst.path, 'vol01', '1.txt')).readAsStringSync(), 'one');
    expect(
      File(p.join(dst.path, 'vol01', 'sub', '2.txt')).readAsStringSync(),
      'two',
    );
  });

  test('默认不覆盖目标里已有的同名文件，且不计入复制数', () {
    writeSrc('a.txt', 'new');
    File(p.join(dst.path, 'a.txt')).writeAsStringSync('old');

    final copied = copyDirectoryContentsSync(src.path, dst.path);

    expect(copied, 0);
    expect(File(p.join(dst.path, 'a.txt')).readAsStringSync(), 'old');
  });

  test('overwrite 为 true 时用源文件覆盖目标', () {
    writeSrc('a.txt', 'new');
    File(p.join(dst.path, 'a.txt')).writeAsStringSync('old');

    final copied = copyDirectoryContentsSync(
      src.path,
      dst.path,
      overwrite: true,
    );

    expect(copied, 1);
    expect(File(p.join(dst.path, 'a.txt')).readAsStringSync(), 'new');
  });

  test('空源目录返回 0（调用方据此判定「什么都没搬」）', () {
    expect(copyDirectoryContentsSync(src.path, dst.path), 0);
  });

  test('只有空子目录时也返回 0，但目标会建出同名目录', () {
    Directory(p.join(src.path, 'empty')).createSync(recursive: true);

    final copied = copyDirectoryContentsSync(src.path, dst.path);

    expect(copied, 0);
    expect(Directory(p.join(dst.path, 'empty')).existsSync(), isTrue);
  });

  test('findMissingFiles：复制完整时为空', () {
    writeSrc('a.txt', 'A');
    writeSrc(p.join('vol01', '1.txt'), 'one');

    copyDirectoryContentsSync(src.path, dst.path);

    expect(findMissingFiles(src.path, dst.path), isEmpty);
  });

  test('findMissingFiles：目标里被跳过但已存在的同名文件不算缺失', () {
    // overwrite=false 时现存的同名文件会被跳过，copied 为 0，
    // 但文件其实在目标里 —— 这正是不能用「写了几个」判成败的原因。
    writeSrc('a.txt', 'new');
    File(p.join(dst.path, 'a.txt')).writeAsStringSync('old');

    final copied = copyDirectoryContentsSync(src.path, dst.path);

    expect(copied, 0);
    expect(findMissingFiles(src.path, dst.path), isEmpty);
  });

  test('findMissingFiles：能报出没写进去的文件（模拟静默失败）', () {
    writeSrc('a.txt', 'A');
    writeSrc(p.join('vol01', '1.txt'), 'one');

    // 一个都不复制，等价于「兼容层静默跳过」的后果。
    final missing = findMissingFiles(src.path, dst.path);

    expect(missing, containsAll(<String>['a.txt', p.join('vol01', '1.txt')]));
  });

  test('countFilesSync：递归统计文件数，不含空目录', () {
    writeSrc('a.txt', 'A');
    writeSrc(p.join('vol01', '1.txt'), 'one');
    Directory(p.join(src.path, 'empty')).createSync(recursive: true);

    expect(countFilesSync(src.path), 2);
  });
}
