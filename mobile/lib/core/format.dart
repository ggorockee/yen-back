import 'package:intl/intl.dart';

final _int = NumberFormat.decimalPattern('ko_KR');
final _usd = NumberFormat('#,##0.00', 'en_US');

String yen(int v) => '¥${_int.format(v)}';
String won(int v) => '${_int.format(v)}원';
String usd(double v) => '\$${_usd.format(v)}';
String number(int v) => _int.format(v);

String dateLabel(DateTime d) => DateFormat('M월 d일 (E)', 'ko_KR').format(d);
String dateTimeLabel(DateTime d) => DateFormat('M월 d일 (E) HH:mm', 'ko_KR').format(d);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
