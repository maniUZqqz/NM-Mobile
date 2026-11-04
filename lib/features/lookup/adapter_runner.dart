import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'lookup_models.dart';
import 'platforms.dart';

/// Runs ONE adapter for ONE number in a messenger's web client. The real implementation uses
/// a hidden WebView that shares cookies / storage with the visible login WebView, so the lookup
/// uses the session the OWNER created by logging in himself. Tests use a fake.
abstract class AdapterRunner {
  Future<AdapterResult> lookup(PlatformSpec spec, String digits, {Duration timeout});

  /// Is the owner logged into this messenger's web client right now?
  Future<LoginProbe> probe(PlatformSpec spec);

  /// Forgets the web session of this messenger on this phone (local only).
  Future<void> clearSession(PlatformSpec spec);
}

/// flutter_inappwebview based runner. Compiled and analysed in CI; its behaviour against the
/// real messengers is NOT verified (see docs/lookup.md).
class WebViewAdapterRunner implements AdapterRunner {
  WebViewAdapterRunner({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  Future<String> _asset(String name) => _bundle.loadString('assets/lookup/$name');

  static InAppWebViewSettings webSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: kDesktopUserAgent,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
      );

  Future<HeadlessInAppWebView> _open(PlatformSpec spec, Duration loadTimeout) async {
    final loaded = Completer<void>();
    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(spec.webUrl)),
      initialSize: const Size(1280, 900),
      initialSettings: webSettings(),
      onLoadStop: (controller, url) {
        if (!loaded.isCompleted) loaded.complete();
      },
      onReceivedError: (controller, request, error) {
        if ((request.isForMainFrame ?? false) && !loaded.isCompleted) {
          loaded.completeError(StateError('page_load_failed'));
        }
      },
    );
    await headless.run();
    try {
      await loaded.future.timeout(loadTimeout);
    } catch (_) {
      await headless.dispose();
      rethrow;
    }
    return headless;
  }

  Future<void> _inject(InAppWebViewController c, PlatformSpec spec) async {
    await c.evaluateJavascript(source: await _asset('common.js'));
    await c.evaluateJavascript(source: await _asset(spec.assetName));
  }

  @override
  Future<AdapterResult> lookup(PlatformSpec spec, String digits, {Duration timeout = const Duration(seconds: 70)}) async {
    HeadlessInAppWebView? headless;
    try {
      headless = await _open(spec, const Duration(seconds: 30));
      final c = headless.webViewController;
      if (c == null) return AdapterResult.error('webview_unavailable');
      await _inject(c, spec);
      final args = jsonEncode(<String, dynamic>{'digits': digits});
      await c.evaluateJavascript(
        source: 'window.__NM_RESULT = null;'
            '(async () => { try { window.__NM_RESULT = JSON.stringify(await window.__NM_LOOKUP($args)); }'
            ' catch (e) { window.__NM_RESULT = JSON.stringify({status:"error", error:"js_exception: " + String((e && e.message) || e)}); } })();'
            'true;',
      );
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final v = await c.evaluateJavascript(source: 'window.__NM_RESULT');
        if (v is String && v.isNotEmpty) return AdapterResult.fromJsonString(v);
      }
      return AdapterResult.error('timeout');
    } catch (e) {
      return AdapterResult.error('webview_error: $e');
    } finally {
      await headless?.dispose();
    }
  }

  /// Probe on an already open controller (the visible login page uses this too).
  Future<LoginProbe> probeWith(InAppWebViewController c, PlatformSpec spec) async {
    await _inject(c, spec);
    var last = const LoginProbe(loggedIn: false, stage: 'unknown');
    for (var i = 0; i < 20; i++) {
      final v = await c.evaluateJavascript(source: 'JSON.stringify(window.__NM_PROBE())');
      if (v is String && v.isNotEmpty) {
        last = LoginProbe.fromJsonString(v);
        if (last.loggedIn || last.stage != 'loading') return last;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return last;
  }

  @override
  Future<LoginProbe> probe(PlatformSpec spec) async {
    HeadlessInAppWebView? headless;
    try {
      headless = await _open(spec, const Duration(seconds: 30));
      final c = headless.webViewController;
      if (c == null) return const LoginProbe(loggedIn: false, stage: 'unknown');
      return await probeWith(c, spec);
    } catch (_) {
      return const LoginProbe(loggedIn: false, stage: 'error');
    } finally {
      await headless?.dispose();
    }
  }

  @override
  Future<void> clearSession(PlatformSpec spec) async {
    HeadlessInAppWebView? headless;
    try {
      headless = await _open(spec, const Duration(seconds: 30));
      final c = headless.webViewController;
      if (c != null) {
        await c.evaluateJavascript(
          source: '(async () => { try { localStorage.clear(); sessionStorage.clear();'
              ' if (indexedDB.databases) { const dbs = await indexedDB.databases(); dbs.forEach((d) => d.name && indexedDB.deleteDatabase(d.name)); }'
              ' if (navigator.serviceWorker) { const regs = await navigator.serviceWorker.getRegistrations(); regs.forEach((r) => r.unregister()); }'
              ' if (window.caches) { const ks = await caches.keys(); ks.forEach((k) => caches.delete(k)); } } catch (e) {} })(); true;',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      final cm = CookieManager.instance();
      final url = WebUri(spec.webUrl);
      final cookies = await cm.getCookies(url: url);
      for (final cookie in cookies) {
        await cm.deleteCookie(url: url, name: cookie.name, domain: cookie.domain, path: cookie.path ?? '/');
      }
    } finally {
      await headless?.dispose();
    }
  }
}
