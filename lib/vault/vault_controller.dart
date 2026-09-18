import 'package:flutter/foundation.dart';
import 'note_file.dart';
import 'vault_repository.dart';

class VaultController extends ChangeNotifier {
  VaultController(this.repository);
  final VaultRepository repository;
  VaultSnapshot? snapshot;
  NoteFile? selectedNote;
  String? selectedPath;
  String? error;
  String? readError;
  bool scanning = false;
  bool reading = false;
  bool _disposed = false;
  int _scanId = 0;
  int _readId = 0;

  void _emit() { if (!_disposed) notifyListeners(); }

  Future<void> open(String path) async {
    final id = ++_scanId;
    ++_readId;
    scanning = true;
    reading = false;
    selectedNote = null;
    selectedPath = null;
    error = null;
    readError = null;
    _emit();
    try {
      final result = await repository.scan(path);
      if (_disposed || id != _scanId) return;
      snapshot = result;
    } catch (e) {
      if (_disposed || id != _scanId) return;
      snapshot = null;
      error = e is VaultException ? e.message : 'Không quét được Vault.';
    } finally {
      if (!_disposed && id == _scanId) { scanning = false; _emit(); }
    }
  }

  Future<void> select(NoteFile note) async {
    if (scanning) return;
    final id = ++_readId;
    selectedPath = note.path;
    selectedNote = null;
    readError = null;
    reading = true;
    _emit();
    try {
      final result = await repository.readNote(note);
      if (_disposed || id != _readId) return;
      selectedNote = result;
      if (snapshot != null) {
        final index = snapshot!.notes.indexWhere((n) => n.path == result.path);
        if (index != -1) {
          final updatedNotes = List<NoteFile>.from(snapshot!.notes);
          updatedNotes[index] = result;
          snapshot = VaultSnapshot(
            root: snapshot!.root,
            notes: List.unmodifiable(updatedNotes),
            warnings: snapshot!.warnings,
          );
        }
      }
    } catch (e) {
      if (_disposed || id != _readId) return;
      readError = e is VaultException ? e.message : 'Không đọc được ghi chú.';
    } finally {
      if (!_disposed && id == _readId) { reading = false; _emit(); }
    }
  }

  @override
  void dispose() { _disposed = true; ++_scanId; ++_readId; super.dispose(); }
}
