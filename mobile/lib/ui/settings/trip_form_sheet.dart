import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../services/analytics.dart';
import '../../state/providers.dart';
import '../widgets.dart';

/// Edits departure date/time and airport; reschedules reminders on save.
Future<void> showTripFormSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _TripFormSheet(),
);

class _TripFormSheet extends ConsumerStatefulWidget {
  const _TripFormSheet();

  @override
  ConsumerState<_TripFormSheet> createState() => _TripFormSheetState();
}

class _TripFormSheetState extends ConsumerState<_TripFormSheet> {
  DateTime? _departure;
  late final TextEditingController _airport;

  @override
  void initState() {
    super.initState();
    final trip = ref.read(tripProvider).value;
    _departure = trip?.departureAt;
    _airport = TextEditingController(text: trip?.airport ?? '');
  }

  @override
  void dispose() {
    _airport.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _departure ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure ?? DateTime(2000, 1, 1, 12)),
      helpText: '비행기 출발 시각',
    );
    if (time == null) return;
    setState(() => _departure = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final trip = ref.read(tripProvider).value;
    if (trip == null) return;
    if (_departure != null) await ref.read(notificationsProvider).requestPermission();
    await ref
        .read(tripProvider.notifier)
        .save(
          trip.copyWith(departureAt: _departure, clearDeparture: _departure == null, airport: _airport.text.trim()),
        );
    if (_departure != null) ref.read(analyticsProvider).track(AppEvent.departureSet);
    if (!mounted) return;
    Navigator.pop(context);
    if (_departure != null) showSnack(context, '출국 전날 저녁과 출발 3시간 전에 알려드릴게요.');
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('출국 정보', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(_departure == null ? '출국 일시 선택' : dateTimeLabel(_departure!)),
          trailing: _departure == null
              ? null
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _departure = null)),
          onTap: _pick,
        ),
        TextField(
          controller: _airport,
          decoration: const InputDecoration(labelText: '출국 공항 (선택)', hintText: '예: 간사이공항 T1'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _save,
          child: const Text('저장'),
        ),
      ],
    ),
  );
}
