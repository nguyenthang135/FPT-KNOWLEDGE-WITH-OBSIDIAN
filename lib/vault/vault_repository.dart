import 'note_file.dart';

abstract class VaultRepository {
  Future<VaultSnapshot> scan(String directoryPath);
  Future<NoteFile> readNote(NoteFile note);
}
