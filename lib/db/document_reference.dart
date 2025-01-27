part of "../scientisst_db.dart";

class DocumentReference {
  late String objectId;
  final CollectionReference parent;
  late String _filePath;
  late String _collectionsPath;
  late _MetadataReference _metadata;

  DocumentReference._({required this.parent, required String path}) {
    assert(path.isNotEmpty && !path.contains(".") && !path.contains("/"));

    objectId = path;

    _filePath = ScientISSTdb._joinPaths(parent._documentsPath, path);
    _collectionsPath = ScientISSTdb._joinPaths(parent._collectionsPath, path);

    final metadataPath = ScientISSTdb._joinPaths(parent._metadataPath, path);
    _metadata = _MetadataReference(parent: this, path: metadataPath);
  }

  Future<File> get _file async => await ScientISSTdb._getFile(_filePath);
  Future<Directory> get _collections async =>
      await ScientISSTdb._getDirectory(_collectionsPath);

  CollectionReference collection(String path) {
    assert(!path.contains("/") && !path.contains("."));
    return CollectionReference._(parent: this, path: path);
  }

  Future<List<String>> listCollections() async {
    final Directory collections = await _collections;
    try {
      return List<String>.from(
        collections.listSync().where((file) => file is Directory).map(
              (file) async => file.path.split("/").last,
            ),
      );
    } on FileSystemException catch (e) {
      if (e.osError!.errorCode != 2)
        throw e; // if error is not "No such file or directory"
      else
        return [];
    }
  }

  Future<List<CollectionReference>?> getCollections() async {
    final collections = await listCollections();
    return List<CollectionReference>.from(
      collections.map(
        (String path) async => CollectionReference._(parent: this, path: path),
      ),
    );
  }

  Future<void> set(Map<String, dynamic>? data, {bool merge: false}) async {
    if (!(await _file).existsSync()) await _init();
    if (data == null || data.isEmpty) {
      await delete();
    } else {
      if (merge) {
        await update(data);
      } else {
        await _write(data);
      }
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    await _metadata.setFieldTypes(data);
    await (await _file).writeAsString(
      jsonEncode(data, toEncodable: _myEncode),
    );
  }

  dynamic _myEncode(dynamic item) {
    if (item is DateTime) {
      return item.toIso8601String();
    } else if (item is List<DateTime>) {
      return List<dynamic>.from(
        item.map(
          (DateTime i) => i.toIso8601String(),
        ),
      );
    } else if (item is List) {
      return List<dynamic>.from(item);
    }
    return item;
  }

  Future<void> update(Map<String, dynamic> data) async {
    Map<String, dynamic> _data = await _read();
    _data.addAll(data);
    await _write(_data);
  }

  Future<void> _init() async {
    if (parent.parent != null) await parent.parent!._init();
    await _metadata.init();
    (await _collections).createSync(recursive: true);
    (await _file).createSync(recursive: true);
  }

  Future<void> delete() async {
    (await _file).deleteSync();
    (await _collections).deleteSync(recursive: true);
    await _metadata.delete();
    await parent._deleteEmpty();
  }

  String get id => objectId;

  Future<Map<String, dynamic>> _read() async {
    try {
      final Map<String, String> fieldsType = (await _metadata.get()).fieldsType;
      return jsonDecode(
        (await _file).readAsStringSync(),
        reviver: fieldsType.isEmpty
            ? null
            : (key, value) {
                if (key is String) {
                  return _convertToType(
                    value,
                    fieldsType[key],
                  );
                }
                return value;
              },
      );
    } on FormatException catch (_) {
      return {};
    } on FileSystemException catch (e) {
      throw e;
    }
  }

  Future<DocumentSnapshot> get() async {
    final MetadataSnapshot metadata = await _metadata.get();
    return DocumentSnapshot(this, await _read(), metadata);
  }

  Stream<DocumentSnapshot> watch() async* {
    DocumentSnapshot doc = await get();
    yield doc;
    await for (WatchEvent _ in FileWatcher(await _absolutePath).events) {
      doc = await get();
      yield doc;
    }
  }

  static dynamic _convertToType(dynamic value, String? type) {
    if (type == "num" ||
        type == "double" ||
        type == "int" ||
        type == "bool" ||
        type == "String")
      return value;
    else if (type == "List") {
      return value;
    } else if (type == "DateTime")
      return DateTime.parse(value);
    else if (type == "List<DateTime>")
      return List<DateTime>.from(
        (value as List<dynamic>).map(
          (dynamic item) => DateTime.parse(item),
        ),
      );
    else if (type == "Null")
      return null;
    else
      throw Exception(
          "scientisst_db cannot cast this type of object - Value: $value, Type: ${value.runtimeType.toString()} - into $type");
  }

  Future<String> get _absolutePath async =>
      ScientISSTdb._joinPaths(await ScientISSTdb._dbDirPath, _filePath);
}
