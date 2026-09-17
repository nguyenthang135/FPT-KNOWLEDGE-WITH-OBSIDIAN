import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/vault/local_vault_repository.dart';
import 'package:fptu_se_brain/vault/note_file.dart';

void main() {
  late Directory root;
  const repository = LocalVaultRepository();
  Future<File> write(String path, List<int> bytes) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }
  setUp(() async { root = await Directory.systemTemp.createTemp('vault_test_'); });
  tearDown(() async { await root.delete(recursive: true); });

  test('recursive scan, .MD, folders first and ignore .obsidian', () async {
    await write('z/tiếng Việt.MD', utf8.encode('# Xin chào'));
    await write('a.md', []);
    await write('.obsidian/private.md', []);
    await write('z/.obsidian/private.md', []);
    await write('ignore.txt', []);
    final vault = await repository.scan(root.path);
    expect(vault.notes.length, 2);
    expect(vault.root.children.first.name, 'z');
    expect(vault.root.children.last.name, 'a.md');
    expect(vault.notes.every((note) => note.content == null), isTrue);
    final note = await repository.readNote(vault.notes.last);
    expect(note.content, '# Xin chào');
    expect(note.sizeBytes, utf8.encode('# Xin chào').length);
    expect(note.modified, (await File(note.path).stat()).modified);
  });
  test('empty file and UTF-8 BOM', () async {
    await write('empty.md', []);
    await write('bom.md', [239, 187, 191, ...utf8.encode('Tiếng Việt')]);
    final vault = await repository.scan(root.path);
    expect((await repository.readNote(vault.notes.first)).content, 'Tiếng Việt');
    expect((await repository.readNote(vault.notes.last)).content, '');
  });
  test('invalid UTF-8 does not block other notes', () async {
    await write('bad.md', [0xff, 0xfe]);
    await write('good.md', utf8.encode('OK'));
    final vault = await repository.scan(root.path);
    await expectLater(repository.readNote(vault.notes.first),
      throwsA(isA<VaultException>()));
    expect((await repository.readNote(vault.notes.last)).content, 'OK');
  });
  test('deleted file, missing root and empty vault', () async {
    expect((await repository.scan(root.path)).notes, isEmpty);
    final file = await write('gone.md', []);
    final vault = await repository.scan(root.path);
    await file.delete();
    await expectLater(repository.readNote(vault.notes.single),
      throwsA(isA<VaultException>()));
    await expectLater(repository.scan('${root.path}/missing'),
      throwsA(isA<VaultException>()));
  });
  test('re-read returns modified content and size', () async {
    final file = await write('note.md', utf8.encode('old'));
    final note = (await repository.scan(root.path)).notes.single;
    await file.writeAsString('Nội dung mới');
    final current = await repository.readNote(note);
    expect(current.content, 'Nội dung mới');
    expect(current.sizeBytes, utf8.encode('Nội dung mới').length);
  });
  test('links are skipped instead of recursively following cycles', () async {
    if (Platform.isWindows) return; // Windows may require symlink privileges.
    await write('note.md', []);
    await Link('${root.path}/cycle').create(root.path);
    expect((await repository.scan(root.path)).notes.length, 1);
  });
}
