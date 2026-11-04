import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'lookup_facade.dart';

const Map<String, String> _kFieldFa = <String, String>{
  'display_name': 'نام',
  'username': 'نام کاربری',
  'bio': 'بیو',
  'avatar': 'عکس',
};

const Map<String, String> _kStateFa = <String, String>{
  'queued': 'در صف',
  'authorizing': 'گرفتن مجوز…',
  'running': 'در حال جستجو…',
  'login_required': 'ورود لازم است',
  'done': 'انجام شد',
  'skipped': 'رد شد',
  'failed': 'ناموفق',
};

String _platformLabel(String key) {
  if (key == 'telegram') return 'تلگرام';
  return platformSpecFor(key)?.label ?? key;
}

String profileStatusText(ProfileView p) {
  switch (p.status) {
    case 'found':
      return p.onPlatform == false ? 'در ${p.label} نیست' : 'در ${p.label} هست';
    case 'not_found':
      return 'در ${p.label} پیدا نشد (یا حساب پنهان است)';
    case 'hidden':
      return 'پروفایل در ${p.label} پنهان است';
    case 'login_required':
      return 'برای ${p.label} ورود لازم بود';
    default:
      return 'جستجو در ${p.label} انجام نشد';
  }
}

String profileAgeText(ProfileView p) {
  final d = p.ageDays;
  if (d == null) return '';
  if (d <= 0) return 'امروز';
  return '$d روز پیش';
}

/// Card for the in-call screen and the call detail: latest profiles with the source of
/// each field, «جستجو» and «تازه‌سازی» buttons. A lookup is only ever started for the ONE
/// number of this card.
class ProfilesCard extends StatefulWidget {
  const ProfilesCard({
    super.key,
    required this.facade,
    required this.number,
    this.callUid,
    this.manual = false,
  });

  final LookupFacade facade;
  final String number;
  final String? callUid;
  final bool manual;

  @override
  State<ProfilesCard> createState() => _ProfilesCardState();
}

class _ProfilesCardState extends State<ProfilesCard> {
  List<ProfileView> _profiles = const <ProfileView>[];
  bool _loading = true;
  bool _running = false;
  String? _error;
  String? _notice;
  final Map<String, LookupProgress> _progress = <String, LookupProgress>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfilesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.number != widget.number) {
      _progress.clear();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.facade.latest(widget.number);
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _loading = false;
      });
    } on NmHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = lookupMessage(e.code, e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'خواندن پروفایل‌ها ممکن نشد.';
      });
    }
  }

  Future<void> _run({required bool refresh}) async {
    if (_running) return;
    setState(() {
      _running = true;
      _notice = null;
      _error = null;
      _progress.clear();
    });
    try {
      final result = await widget.facade.runAllDetailed(
        number: widget.number,
        callUid: widget.callUid,
        manual: widget.manual,
        refresh: refresh,
        onProgress: (p) {
          if (mounted) setState(() => _progress[p.platform] = p);
        },
      );
      if (!mounted) return;
      setState(() => _notice = result.stopped ? result.stopMessage : null);
    } on NmHttpException catch (e) {
      if (mounted) setState(() => _error = lookupMessage(e.code, e.message));
    } catch (e) {
      if (mounted) setState(() => _error = 'جستجو انجام نشد.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.badge_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('پروفایل پیام‌رسان‌ها', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('lookup-run'),
                  onPressed: _running ? null : () => _run(refresh: false),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('جستجو'),
                ),
                OutlinedButton.icon(
                  key: const Key('lookup-refresh'),
                  onPressed: _running ? null : () => _run(refresh: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تازه‌سازی'),
                ),
              ],
            ),
            if (_progress.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              for (final p in _progress.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${_platformLabel(p.platform)}: ${_kStateFa[p.state] ?? p.state}'
                    '${p.message.isEmpty ? '' : ' — ${p.message}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (_notice != null && _notice!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(_notice!, key: const Key('lookup-notice'), style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, key: const Key('lookup-error'), style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else if (_profiles.isEmpty)
              Text('هنوز پروفایلی ذخیره نشده است.', style: theme.textTheme.bodySmall)
            else
              for (final p in _profiles) _ProfileTile(facade: widget.facade, profile: p),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.facade, required this.profile});

  final LookupFacade facade;
  final ProfileView profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final name = p.displayName ?? p.label;
    final sources = p.fieldSources.entries.map((e) => '${_kFieldFa[e.key] ?? e.key} ← ${e.value}').toList();
    final age = profileAgeText(p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(http: facade.http, path: p.avatarPath, initials: name.isEmpty ? '?' : String.fromCharCode(name.runes.first)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: theme.textTheme.titleSmall),
                if (p.username != null) Text('@${p.username}', style: theme.textTheme.bodySmall),
                Text(profileStatusText(p), style: theme.textTheme.bodySmall),
                if (p.bio != null) Text(p.bio!, style: theme.textTheme.bodyMedium),
                if (sources.isNotEmpty)
                  Text('منبع: ${sources.join('؛ ')}', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                Row(
                  children: <Widget>[
                    if (age.isNotEmpty) Text(age, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                    if (p.stale) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        key: const Key('stale-badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.error),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('قدیمی', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatefulWidget {
  const _Avatar({required this.http, required this.path, required this.initials});

  final NmHttp http;
  final String? path;
  final String initials;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    final h = widget.http;
    final path = widget.path;
    if (path != null && path.isNotEmpty && h is NmBinaryHttp) {
      _future = (h as NmBinaryHttp).getBytes(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(radius: 22, child: Text(widget.initials));
    final f = _future;
    if (f == null) return fallback;
    return FutureBuilder<Uint8List>(
      future: f,
      builder: (context, snap) {
        if (snap.hasData && snap.data!.isNotEmpty) {
          return CircleAvatar(radius: 22, backgroundImage: MemoryImage(snap.data!));
        }
        return fallback;
      },
    );
  }
}
