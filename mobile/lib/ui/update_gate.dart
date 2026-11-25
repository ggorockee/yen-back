import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_version.dart';
import '../services/analytics.dart';
import '../state/providers.dart';

/// Asks the user to update when Remote Config says this version is old.
///
/// Forced: the dialog cannot be dismissed, also after returning from the store.
/// Optional: "나중에" silences it until the next release.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  static const _dismissedKey = 'update.dismissed_version';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final policy = (await ref.read(remoteSettingsProvider)).updatePolicy;
    if (!mounted) return;
    switch (policy.evaluate(ref.read(appVersionProvider))) {
      case UpdateRequirement.none:
        return;
      case UpdateRequirement.force:
        await _showForced(policy);
      case UpdateRequirement.optional:
        await _showOptional(policy);
    }
  }

  void _track(AppEvent e) => ref.read(analyticsProvider).track(e);

  Future<void> _showForced(UpdatePolicy policy) {
    _track(AppEvent.forceUpdateShown);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.system_update),
          title: const Text('업데이트가 필요해요'),
          content: Text(policy.message.isNotEmpty ? policy.message : '정확한 환급 정보를 위해 최신 버전으로 업데이트해 주세요.'),
          actions: [FilledButton(onPressed: () => _openStore(policy), child: const Text('업데이트'))],
        ),
      ),
    );
  }

  Future<void> _showOptional(UpdatePolicy policy) async {
    final prefs = ref.read(prefsProvider);
    final latest = policy.latestVersion.toString();
    if (prefs.getString(_dismissedKey) == latest) return;
    _track(AppEvent.updatePromptShown);
    final update = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('새 버전이 있어요'),
        content: Text(policy.message.isNotEmpty ? policy.message : '새 버전($latest)이 나왔어요. 지금 업데이트할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('나중에')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('업데이트')),
        ],
      ),
    );
    if (!mounted) return;
    if (update ?? false) {
      await _openStore(policy);
    } else {
      _track(AppEvent.updateDismissed);
      await prefs.setString(_dismissedKey, latest);
    }
  }

  Future<void> _openStore(UpdatePolicy policy) async {
    _track(AppEvent.updateAccepted);
    try {
      await launchUrl(Uri.parse(policy.storeUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[UpdateGate] store link failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
