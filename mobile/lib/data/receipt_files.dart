import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Receipt photos live in the app's private documents directory and are
/// never uploaded. The database stores only the file name.
class ReceiptFiles {
  ReceiptFiles(this._dir);

  final Directory _dir;

  static Future<ReceiptFiles> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'receipts'));
    await dir.create(recursive: true);
    return ReceiptFiles(dir);
  }

  File file(String name) => File(p.join(_dir.path, name));

  /// Copies a picked image into storage and returns its file name.
  Future<String> import(String sourcePath) async {
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final name = 'receipt_${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(sourcePath).copy(file(name).path);
    return name;
  }

  Future<void> delete(Iterable<String> names) async {
    for (final n in names) {
      final f = file(n);
      if (await f.exists()) await f.delete();
    }
  }
}
