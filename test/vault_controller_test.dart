import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/vault/note_file.dart';
import 'package:fptu_se_brain/vault/vault_controller.dart';
import 'package:fptu_se_brain/vault/vault_repository.dart';

NoteFile note(String name) => NoteFile(path: name, relativePath: name,
  name: name, modified: DateTime(2026), sizeBytes: 0, content: name);
class PendingRepository implements VaultRepository {
  final reads = <String, Completer<NoteFile>>{};
  @override
  Future<NoteFile> readNote(NoteFile note) =>
      (reads[note.path] = Completer<NoteFile>()).future;
  @override
  Future<VaultSnapshot> scan(String path) async => VaultSnapshot(
    root: VaultNode(name: path, path: path), notes: const []);
}
void main() {
  test('a slow previous read cannot overwrite the last selection', () async {
    final repository = PendingRepository();
    final controller = VaultController(repository);
    final first = controller.select(note('a.md'));
    final last = controller.select(note('b.md'));
    repository.reads['b.md']!.complete(note('b.md'));
    await last;
    repository.reads['a.md']!.complete(note('a.md'));
    await first;
    expect(controller.selectedNote!.path, 'b.md');
    controller.dispose();
  });
  test('changing vault discards an in-flight read', () async {
    final repository = PendingRepository();
    final controller = VaultController(repository);
    final reading = controller.select(note('a.md'));
    await controller.open('new vault');
    repository.reads['a.md']!.complete(note('a.md'));
    await reading;
    expect(controller.selectedNote, isNull);
    expect(controller.snapshot!.root.path, 'new vault');
    controller.dispose();
  });
}
