import 'dart:convert';

import '../models/models.dart';

/// پارس ساب‌لینک: بدنه ساب‌لینک base64 است و هر خط یک کانفیگ
/// vless:// ،ss:// ،trojan:// یا vmess:// است.
///
/// vmess لینک base64 از یک JSON است؛ بقیه لینک‌های URI معمولی‌اند.
class SublinkParser {
  /// بدنه خام ساب‌لینک (base64 یا متن ساده) را به لیست کانفیگ تبدیل می‌کند.
  static List<VpnConfig> parseBody(String body) {
    var text = body.trim();
    if (text.isEmpty) return [];
    // اگر کل بدنه base64 بود، دیکدش کن؛ اگر نه، خودش متن ساده است.
    final decoded = _tryBase64Decode(text);
    if (decoded != null && decoded.contains('://')) text = decoded;
    final configs = <VpnConfig>[];
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final cfg = parseLink(line);
      if (cfg != null) configs.add(cfg);
    }
    return configs;
  }

  /// یک لینک تکی را پارس می‌کند؛ اگر ناشناخته/خراب بود null.
  static VpnConfig? parseLink(String link) {
    final trimmed = link.trim();
    if (trimmed.startsWith('vless://')) return _parseVless(trimmed);
    if (trimmed.startsWith('trojan://')) return _parseTrojan(trimmed);
    if (trimmed.startsWith('ss://')) return _parseShadowsocks(trimmed);
    if (trimmed.startsWith('vmess://')) return _parseVmess(trimmed);
    return null;
  }

  static String? _tryBase64Decode(String s) {
    try {
      final normalized = s.replaceAll(RegExp(r'\s'), '');
      final padded = normalized +
          '=' * ((4 - normalized.length % 4) % 4);
      final bytes = base64Decode(padded);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _b64UrlDecode(String s) {
    var normalized = s.replaceAll('-', '+').replaceAll('_', '/');
    normalized += '=' * ((4 - normalized.length % 4) % 4);
    return utf8.decode(base64Decode(normalized));
  }

  static VpnConfig? _parseVless(String link) {
    try {
      final uri = Uri.parse(link);
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '${uri.host}:${uri.port}';
      return VpnConfig(
        link: link,
        name: name,
        protocol: 'vless',
        host: uri.host,
        port: uri.hasPort ? uri.port : 443,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnConfig? _parseTrojan(String link) {
    try {
      final uri = Uri.parse(link);
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '${uri.host}:${uri.port}';
      return VpnConfig(
        link: link,
        name: name,
        protocol: 'trojan',
        host: uri.host,
        port: uri.hasPort ? uri.port : 443,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnConfig? _parseShadowsocks(String link) {
    try {
      var rest = link.substring('ss://'.length);
      var name = '';
      final hashIdx = rest.indexOf('#');
      if (hashIdx >= 0) {
        name = Uri.decodeComponent(rest.substring(hashIdx + 1));
        rest = rest.substring(0, hashIdx);
      }
      // شکل ss://base64(method:password@host:port) یا
      // ss://base64(method:password)@host:port
      String host;
      int port;
      if (rest.contains('@')) {
        final atIdx = rest.lastIndexOf('@');
        final hostPort = rest.substring(atIdx + 1);
        final hp = hostPort.split(':');
        host = hp.first;
        port = hp.length > 1 ? int.tryParse(hp[1]) ?? 0 : 0;
        if (port == 0) return null;
      } else {
        final decoded = _b64UrlDecode(rest);
        final atIdx = decoded.lastIndexOf('@');
        if (atIdx < 0) return null;
        final hostPort = decoded.substring(atIdx + 1);
        final hp = hostPort.split(':');
        host = hp.first;
        port = hp.length > 1 ? int.tryParse(hp[1]) ?? 0 : 0;
        if (port == 0) return null;
      }
      return VpnConfig(
        link: link,
        name: name.isNotEmpty ? name : '$host:$port',
        protocol: 'ss',
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnConfig? _parseVmess(String link) {
    try {
      final payload = link.substring('vmess://'.length).trim();
      final jsonStr = _b64UrlDecode(payload);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final host = (data['add'] as String?) ?? '';
      final port = int.tryParse('${data['port'] ?? ''}') ?? 0;
      if (host.isEmpty || port == 0) return null;
      final name = (data['ps'] as String?) ?? '$host:$port';
      return VpnConfig(
        link: link,
        name: name,
        protocol: 'vmess',
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  /// توکن اشتراک را از آدرس ساب‌لینک بیرون می‌کشد:
  /// https://panel17.rovikvpn.shop/sub/<token>
  static String? extractToken(String subUrl) {
    try {
      final uri = Uri.parse(subUrl.trim());
      if ((uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        return null;
      }
      final segments = uri.pathSegments;
      if (segments.isEmpty) return null;
      final last = segments.last;
      return last.isEmpty ? null : last;
    } catch (_) {
      return null;
    }
  }
}
