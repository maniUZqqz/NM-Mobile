import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/assistant/assistant_models.dart';
import 'package:nm_mobile/features/assistant/messenger_links.dart';
import 'package:nm_mobile/features/assistant/product_card.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// دستیارِ فروشِ حینِ تماس: شناسایی تماس‌گیرنده، جست‌وجوی سریع محصول (قیمت، موجودی،
/// سود، کمترین قیمتِ بی‌ضرر)، پیشنهادِ پاسخ با هوش مصنوعی، و دکمه‌های باز کردن شماره
/// در پیام‌رسان‌ها. هیچ صدایی ضبط یا شنیده نمی‌شود.
class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.number,
    this.callUid,
    this.direction = 'in',
    this.api,
    this.facade,
    this.messengers,
  });

  final String number;
  final String? callUid;
  final String direction;

  /// برای تست
  final AssistantApi? api;
  final LookupFacade? facade;
  final List<MessengerDef>? messengers;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  AssistantApi? _api;
  LookupFacade? _facade;

  CallerId? _caller;
  String? _callerError;

  final _searchCtrl = TextEditingController();
  List<ProductInfo> _products = const [];
  bool _searching = false;
  String? _searchError;
  final Set<int> _picked = <int>{};

  final _askCtrl = TextEditingController();
  AiReply? _reply;
  bool _asking = false;
  String? _askError;

  List<MessengerDef> _messengers = const [];
  final Map<String, String?> _installed = <String, String?>{};

  @override
  void initState() {
    super.initState();
    final client = NmSession.instance.client;
    _api = widget.api ?? (client == null ? null : AssistantApi(client));
    _facade = widget.facade ?? (client == null ? null : LookupFacade(client));
    _loadCaller();
    _loadMessengers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _askCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCaller() async {
    final api = _api;
    if (api == null || widget.number.isEmpty) return;
    try {
      final c = await api.callerId(widget.number);
      if (mounted) setState(() => _caller = c);
    } on NmHttpException catch (e) {
      if (mounted) setState(() => _callerError = e.message);
    }
  }

  Future<void> _loadMessengers() async {
    var found0 = widget.messengers;
    if (found0 == null) {
      try {
        found0 = parseMessengers(await rootBundle.loadString('assets/messengers.json'));
      } catch (_) {
        found0 = const <MessengerDef>[];
      }
    }
    final loaded = found0;
    final installed = <String, String?>{};
    for (final m in loaded) {
      String? found;
      for (final pkg in m.packages) {
        if (await SmsBridge.isInstalled(pkg)) {
          found = pkg;
          break;
        }
      }
      installed[m.key] = found;
    }
    if (!mounted) return;
    setState(() {
      _messengers = loaded;
      _installed
        ..clear()
        ..addAll(installed);
    });
  }

  Future<void> _search() async {
    final api = _api;
    final q = _searchCtrl.text.trim();
    if (api == null || q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await api.searchProducts(q);
      if (mounted) setState(() => _products = r);
    } on NmHttpException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _ask() async {
    final api = _api;
    final q = _askCtrl.text.trim();
    if (api == null || q.isEmpty) return;
    setState(() {
      _asking = true;
      _askError = null;
    });
    try {
      final r = await api.ask(q, number: widget.number, productIds: _picked.toList(), callUid: widget.callUid);
      if (mounted) setState(() => _reply = r);
    } on NmHttpException catch (e) {
      if (mounted) setState(() => _askError = e.message);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _openMessenger(MessengerDef m) async {
    final link = buildPhoneLink(m, _caller?.normalized.isNotEmpty == true ? _caller!.normalized : widget.number);
    if (link == null) return;
    final ok = await SmsBridge.openUrl(link, package: _installed[m.key]);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('باز کردن لینک ممکن نشد.')));
    }
  }

  Future<void> _saveContact() async {
    final ok = await SmsBridge.insertContact(name: _caller?.display ?? '', number: widget.number);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صفحهٔ ذخیرهٔ مخاطب باز نشد.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caller = _caller;
    final noNumber = widget.number.isEmpty;
    final title = noNumber
        ? 'دستیار فروش'
        : (caller?.display ?? (widget.direction == 'out' ? 'تماس خروجی' : 'تماس ورودی'));
    return Scaffold(
      appBar: AppBar(title: const Text('دستیار تماس')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!noNumber) ...[
            _headerCard(theme, title, caller),
            const SizedBox(height: 12),
            _messengerCard(),
            const SizedBox(height: 12),
          ],
          if (_facade != null && !noNumber)
            ProfilesCard(
              facade: _facade!,
              number: widget.number,
              callUid: widget.callUid,
              manual: widget.callUid == null || widget.callUid!.isEmpty,
            ),
          const SizedBox(height: 12),
          _productCard(),
          const SizedBox(height: 12),
          _askCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _headerCard(ThemeData theme, String title, CallerId? c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.direction == 'out' ? Icons.call_made_rounded : Icons.call_received_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                ),
                if (c != null)
                  Chip(
                    label: Text(c.known ? 'می‌شناسیم' : 'ناشناس'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: c.known ? AppColors.success : AppColors.warning),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(widget.number, style: const TextStyle(color: AppColors.textSecondary)),
            ),
            if (_callerError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_callerError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            if (c != null) ...[
              for (final m in c.matches)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${m.sourceLabel}: ${m.name}${m.detail.isEmpty ? '' : ' — ${m.detail}'}',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              if (c.matches.isEmpty && c.known == false)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'این شماره در داده‌های NM (مشتری، سرنخ، لید، تماس و پیامک قبلی) نیست.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'سابقه: ${faDigits('${c.calls}')} تماس · ${faDigits('${c.smsOut}')} پیامک ارسالی · ${faDigits('${c.smsIn}')} پیامک دریافتی',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saveContact,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('ذخیره به‌عنوان مخاطب گوشی'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messengerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('باز کردن در پیام‌رسان', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'همان چیزی را می‌بینید که خودِ آن شخص در پیام‌رسان نشان داده است. اگر او اجازه نداده باشد، چیزی باز نمی‌شود.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _messengers)
                  if (m.hasPhoneLink)
                    FilledButton.tonalIcon(
                      onPressed: () => _openMessenger(m),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(m.labelFa + (_installed[m.key] == null ? ' (نصب نیست)' : '')),
                    )
                  else
                    Tooltip(
                      message: 'این پیام‌رسان لینک باز کردن چت با شماره ندارد',
                      child: Chip(
                        label: Text('${m.labelFa}: لینک شماره ندارد'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'برای پیام‌رسان‌های بدون لینک، شماره را به‌عنوان مخاطب گوشی ذخیره کنید تا خودِ برنامه پروفایل را (اگر ثبت‌نام کرده باشد) نشان بدهد.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('جست‌وجوی سریع محصول', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(hintText: 'نام، برند یا کد محصول', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('جست‌وجو'),
                ),
              ],
            ),
            if (_searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_searchError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            for (final p in _products)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ProductCard(
                  product: p,
                  selected: _picked.contains(p.id),
                  onTap: () => setState(() {
                    if (!_picked.add(p.id)) _picked.remove(p.id);
                  }),
                ),
              ),
            if (_picked.isNotEmpty)
              Text(
                '${faDigits('${_picked.length}')} محصول برای پیشنهادِ هوش مصنوعی انتخاب شد.',
                style: const TextStyle(color: AppColors.primary, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _askCard() {
    final r = _reply;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('پیشنهاد پاسخ (هوش مصنوعی)', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'سؤال مشتری را تایپ کنید؛ پیشنهادها فقط برای شماست و قیمتِ تمام‌شده و سود به مشتری گفته نمی‌شود.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _askCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'مثلاً: «تخفیف بیشتری می‌دهید؟»', isDense: true),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _asking ? null : _ask,
              icon: _asking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('پیشنهاد بده'),
            ),
            if (_askError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_askError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            if (r != null) ...[
              const SizedBox(height: 8),
              for (final t in r.replies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(t, style: const TextStyle(height: 1.6))),
                        IconButton(
                          tooltip: 'کپی',
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () => Clipboard.setData(ClipboardData(text: t)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (r.notes.isNotEmpty)
                Text(r.notes, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}
