import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/main.dart';

void main() {
  testWidgets('hiển thị giao diện FPTU SE Brain', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FptuSeBrainApp());

    expect(find.text('FPTU SE Brain'), findsOneWidget);
    expect(find.text('Chọn Vault'), findsOneWidget);
    expect(find.text('Trợ lý AI'), findsOneWidget);
  });

  testWidgets('chọn ghi chú sẽ cập nhật phần nội dung', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FptuSeBrainApp());

    await tester.tap(find.text('Quản lý State'));
    await tester.pump();

    expect(
      find.text(
        'State là dữ liệu có thể thay đổi trong quá trình ứng dụng hoạt động. '
        'Khi state thay đổi, Flutter sẽ cập nhật phần giao diện liên quan.',
      ),
      findsOneWidget,
    );
  });
}
