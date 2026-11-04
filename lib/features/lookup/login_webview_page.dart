import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adapter_runner.dart';
import 'lookup_models.dart';
import 'platforms.dart';

/// Full-screen web client of ONE messenger. THE OWNER logs in here, himself: types his phone
/// number and the code, or scans the QR with another phone. This app never reads, stores or
/// forwards a password, a code or a cookie; the web client keeps its own session inside this
/// WebView, which the hidden lookup WebView later reuses.
class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key, required this.spec, required this.runner});

  final PlatformSpec spec;
  final WebViewAdapterRunner runner;

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  InAppWebViewController? _controller;
  bool _checking = false;
  double _progress = 0;

  Future<void> _check() async {
    final c = _controller;
    if (c == null || _checking) return;
    setState(() => _checking = true);
    LoginProbe probe;
    try {
      probe = await widget.runner.probeWith(c, widget.spec);
    } catch (_) {
      probe = const LoginProbe(loggedIn: false, stage: 'error');
    }
    if (!mounted) return;
    setState(() => _checking = false);
    final text = probe.loggedIn
        ? 'وارد ${widget.spec.label} شده‌اید. می‌توانید برگردید.'
        : 'هنوز وارد نشده‌اید (مرحله: ${probe.stage}).';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return Scaffold(
      appBar: AppBar(
        title: Text('ورود به ${spec.label}'),
        actions: <Widget>[
          TextButton(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? 'در حال بررسی…' : 'بررسی ورود'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(10),
            child: Text(
              'ورود را خودتان انجام دهید؛ برنامه رمز یا کد شما را نمی‌بیند و نمی‌فرستد.\n${spec.loginHint}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_progress < 1) LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(spec.webUrl)),
              initialSettings: WebViewAdapterRunner.webSettings(),
              onWebViewCreated: (c) => _controller = c,
              onProgressChanged: (c, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
            ),
          ),
        ],
      ),
    );
  }
}
