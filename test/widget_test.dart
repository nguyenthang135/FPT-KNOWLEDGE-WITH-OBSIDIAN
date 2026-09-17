import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/main.dart';
import 'package:fptu_se_brain/vault/vault_picker.dart';

void main() {
  testWidgets('empty workspace and cancelled picker', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      VaultPicker.channel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(VaultPicker.channel, null));
    await tester.pumpWidget(const FptuSeBrainApp());
    expect(find.text('FPTU SE Brain'), findsOneWidget);
    await tester.tap(find.text('Chọn Vault'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn Vault để mở thư mục ghi chú.'), findsOneWidget);
  });
  testWidgets('picker -> real file tree -> UTF-8 content', (tester) async {
    final root = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('vault_widget_');
      await File('${directory.path}/hello.md').writeAsString('Xin chào từ file thật');
      return directory;
    }))!;
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      VaultPicker.channel, (MethodCall call) async => root.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(VaultPicker.channel, null));
    await tester.pumpWidget(const FptuSeBrainApp());
    await tester.runAsync(() async {
      await tester.tap(find.text('Chọn Vault'));
      // Allow real filesystem work to finish; pump outside fake async.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text('hello.md').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('hello.md'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.text('hello.md').first);
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text('Xin chào từ file thật').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Xin chào từ file thật'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
