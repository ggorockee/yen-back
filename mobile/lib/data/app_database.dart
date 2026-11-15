import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../core/tax.dart';
import 'models.dart';

/// Local SQLite storage. Everything the user enters stays on the device.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// The MVP has one active trip with a fixed id.
  static const activeTripId = 1;

  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'yen_back.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final batch = db.batch()
            ..execute('''
              CREATE TABLE trips (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                departure_at TEXT,
                airport TEXT NOT NULL DEFAULT ''
              )''')
            ..execute('''
              CREATE TABLE shops (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                purchase_date TEXT NOT NULL,
                created_at TEXT NOT NULL
              )''')
            ..execute('''
              CREATE TABLE items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                shop_id INTEGER NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                unit_price_yen INTEGER NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 1,
                price_mode TEXT NOT NULL,
                tax_rate_pct INTEGER NOT NULL,
                category TEXT NOT NULL,
                created_at TEXT NOT NULL
              )''')
            ..execute('''
              CREATE TABLE receipts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                shop_id INTEGER NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
                image_file TEXT,
                total_incl_yen INTEGER NOT NULL,
                tax_yen INTEGER NOT NULL,
                created_at TEXT NOT NULL
              )''')
            ..execute('''
              CREATE TABLE checklist (
                trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                done INTEGER NOT NULL,
                PRIMARY KEY (trip_id, item_key)
              )''')
            ..execute('CREATE INDEX idx_items_shop ON items(shop_id)')
            ..execute('CREATE INDEX idx_receipts_shop ON receipts(shop_id)')
            ..insert('trips', {'id': activeTripId, 'name': '내 일본 여행', 'airport': ''});
          await batch.commit(noResult: true);
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();

  String _now() => DateTime.now().toIso8601String();

  // Trip

  Future<Trip> trip() async {
    final row = (await _db.query('trips', where: 'id = ?', whereArgs: [activeTripId])).first;
    return Trip(
      id: row['id'] as int,
      name: row['name'] as String,
      departureAt: DateTime.tryParse('${row['departure_at']}'),
      airport: row['airport'] as String,
    );
  }

  Future<void> saveTrip(Trip t) => _db.update(
    'trips',
    {'name': t.name, 'departure_at': t.departureAt?.toIso8601String(), 'airport': t.airport},
    where: 'id = ?',
    whereArgs: [t.id],
  );

  // Shops, items, receipts

  /// All shops of the active trip with their items and receipts, newest first.
  Future<List<ShopEntry>> entries() async {
    final shops = await _db.query(
      'shops',
      where: 'trip_id = ?',
      whereArgs: [activeTripId],
      orderBy: 'purchase_date DESC, id DESC',
    );
    if (shops.isEmpty) return const [];

    final ids = shops.map((s) => s['id'] as int).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final items = await _db.query('items', where: 'shop_id IN ($marks)', whereArgs: ids, orderBy: 'id');
    final receipts = await _db.query('receipts', where: 'shop_id IN ($marks)', whereArgs: ids, orderBy: 'id');

    final itemsByShop = <int, List<Item>>{};
    for (final r in items) {
      final it = Item(
        id: r['id'] as int,
        shopId: r['shop_id'] as int,
        name: r['name'] as String,
        unitPriceYen: r['unit_price_yen'] as int,
        quantity: r['quantity'] as int,
        priceMode: PriceMode.fromCode(r['price_mode'] as String),
        taxRatePct: r['tax_rate_pct'] as int,
        category: ItemCategory.fromCode(r['category'] as String),
      );
      (itemsByShop[it.shopId] ??= []).add(it);
    }
    final receiptsByShop = <int, List<Receipt>>{};
    for (final r in receipts) {
      final rc = Receipt(
        id: r['id'] as int,
        shopId: r['shop_id'] as int,
        imageFile: r['image_file'] as String?,
        totalInclYen: r['total_incl_yen'] as int,
        taxYen: r['tax_yen'] as int,
      );
      (receiptsByShop[rc.shopId] ??= []).add(rc);
    }

    return [
      for (final s in shops)
        ShopEntry(
          shop: Shop(
            id: s['id'] as int,
            tripId: s['trip_id'] as int,
            name: s['name'] as String,
            purchaseDate: DateTime.parse(s['purchase_date'] as String),
          ),
          items: itemsByShop[s['id']] ?? const [],
          receipts: receiptsByShop[s['id']] ?? const [],
        ),
    ];
  }

  Future<int> addShop(String name, DateTime purchaseDate) => _db.insert('shops', {
    'trip_id': activeTripId,
    'name': name,
    'purchase_date': isoDate(purchaseDate),
    'created_at': _now(),
  });

  Future<void> updateShop(int id, String name, DateTime purchaseDate) =>
      _db.update('shops', {'name': name, 'purchase_date': isoDate(purchaseDate)}, where: 'id = ?', whereArgs: [id]);

  /// Deletes the shop and, via cascade, its items and receipts. Returns the
  /// receipt image files so the caller can remove them from disk.
  Future<List<String>> deleteShop(int id) async {
    final files = await _db.query(
      'receipts',
      columns: ['image_file'],
      where: 'shop_id = ? AND image_file IS NOT NULL',
      whereArgs: [id],
    );
    await _db.delete('shops', where: 'id = ?', whereArgs: [id]);
    return [for (final f in files) f['image_file'] as String];
  }

  Future<int> addItem({
    required int shopId,
    required String name,
    required int unitPriceYen,
    required int quantity,
    required PriceMode priceMode,
    required int taxRatePct,
    required ItemCategory category,
  }) => _db.insert('items', {
    'shop_id': shopId,
    'name': name,
    'unit_price_yen': unitPriceYen,
    'quantity': quantity,
    'price_mode': priceMode.code,
    'tax_rate_pct': taxRatePct,
    'category': category.code,
    'created_at': _now(),
  });

  Future<void> deleteItem(int id) => _db.delete('items', where: 'id = ?', whereArgs: [id]);

  Future<int> addReceipt({required int shopId, required int totalInclYen, required int taxYen, String? imageFile}) =>
      _db.insert('receipts', {
        'shop_id': shopId,
        'image_file': imageFile,
        'total_incl_yen': totalInclYen,
        'tax_yen': taxYen,
        'created_at': _now(),
      });

  Future<void> deleteReceipt(int id) => _db.delete('receipts', where: 'id = ?', whereArgs: [id]);

  // Checklist

  Future<Set<String>> checkedItems() async {
    final rows = await _db.query(
      'checklist',
      columns: ['item_key'],
      where: 'trip_id = ? AND done = 1',
      whereArgs: [activeTripId],
    );
    return {for (final r in rows) r['item_key'] as String};
  }

  Future<void> setChecked(String key, bool done) => _db.insert('checklist', {
    'trip_id': activeTripId,
    'item_key': key,
    'done': done ? 1 : 0,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
