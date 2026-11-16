// @id PROVGUID-RGLR-PROV-VULC-EDUVULCANAPI
// @name eduVULCAN / UONET+
// @version 1.2.3
// @lang pl
// @author Ogaku
// @icon https://eduvulcan.pl/Content/images/favicon/apple-touch-icon.png
// @banner https://eduvulcan.pl/Content/images/favicon/apple-touch-icon.png
// @baseUrl https://lekcjaplus.vulcan.net.pl
// @loginType 20
// @description /Providers/Vulcan/Description

import 'dart:convert';
import 'package:oshi/bridge_lib.dart';

class EduVulcanExtension extends OProvider {
  EduVulcanExtension({required this.source}) : _http = OHttpClient();

  final OSource source;
  final OHttpClient _http;
  OProtocolDriver? _sampleDriver;

  static const String _hebeceAppName = 'DzienniczekPlus 3.0';
  static const String _hebeceAppVersion = '26.04.01 (G)';
  static const String _hebeceVersionCode = '946';
  static const String _hebeAppName = 'DzienniczekPlus 2.0';
  static const String _hebeAppVersion = '26.04.00 (G)';
  static const String _hebeVersionCode = '941';
  static const String _userAgent = 'Dart/3.3 (dart:io)';
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const String _deviceOs = 'Android';
  static const String _deviceModel = 'Oshi Mobile';
  static const String _defaultHebeBaseUrl = 'https://lekcjaplus.vulcan.net.pl';
  static const String _canonicalPattern = r'(api/mobile/.+)';

  static const Map<String, String> _tokenPrefixes = {
    '3S1': 'https://lekcjaplus.vulcan.net.pl',
    'TA1': 'https://uonetplus-komunikacja.umt.tarnow.pl',
    'OP1': 'https://uonetplus-komunikacja.eszkola.opolskie.pl',
    'RZ1': 'https://uonetplus-komunikacja.resman.pl',
    'GD1': 'https://uonetplus-komunikacja.edu.gdansk.pl',
    'KA1': 'https://uonetplus-komunikacja.mcuw.katowice.eu',
    'KA2': 'https://uonetplus-komunikacja-test.mcuw.katowice.eu',
    'LU1': 'https://uonetplus-komunikacja.edu.lublin.eu',
    'LU2': 'https://test-uonetplus-komunikacja.edu.lublin.eu',
    'KO1': 'https://uonetplus-komunikacja.eduportal.koszalin.pl',
    'FK1': 'http://api.fakelog.tk',
  };

  Map<String, String>? _keyPair;
  String _deviceId = uuidV4();
  String? _restUrl;
  Map<String, dynamic>? _activeStudentRaw;
  bool _isHebeCe = true;
  String _proxyUrl = '';
  String _savedUsername = '';
  String _savedPassword = '';
  final Map<String, dynamic> _registerData = <String, dynamic>{};

  @override
  String get providerName => source.name;

  @override
  String get providerDescription => source.description;

  @override
  String get providerBannerUrl => source.bannerUrl ?? source.iconUrl;

  String get _topLevelPartition {
    final active = _activeStudentRaw;
    if (active != null) {
      final top = active['TopLevelPartition']?.toString() ?? '';
      if (top.isNotEmpty) return top;
      final links = active['Links'];
      if (links is Map) {
        final group = links['Group']?.toString() ?? '';
        if (group.isNotEmpty) return group;
      }
      final part = active['Partition']?.toString() ?? '';
      if (part.isNotEmpty) {
        return part.split('-').first;
      }
    }
    return '';
  }

  String _errStr(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }

  String _twoDigits(int n) => n < 10 ? '0$n' : '$n';

  String _ymd(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${_twoDigits(dt.month)}-${_twoDigits(dt.day)}';
  }

  String _hms(DateTime dt) {
    return '${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}:${_twoDigits(dt.second)}';
  }

  String _formatTimestamp(DateTime utc) {
    return '${_ymd(utc)} ${_hms(utc)}';
  }

  String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  int _int(dynamic v, [int fallback = -1]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  int? _intOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  double _double(dynamic v, [double fallback = 0.0]) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  String _str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    return v.toString();
  }

  String _normalizeGradeValue(String raw) {
    var v = raw.trim();
    if (v.startsWith('+') && v.length > 1) {
      return '${v.substring(1)}+';
    }
    if (v.startsWith('-') && v.length > 1) {
      return '${v.substring(1)}-';
    }
    return v;
  }

  String _cleanHtml(String html) {
    if (html.isEmpty) return html;
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\u2022 ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&ndash;', '\u2013')
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&oacute;', '\u00F3')
        .replaceAll('&Oacute;', '\u00D3')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '');
          return code != null ? String.fromCharCode(code) : (m.group(0) ?? '');
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '', radix: 16);
          return code != null ? String.fromCharCode(code) : (m.group(0) ?? '');
        })
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _solvePow({
    required String challenge,
    required int difficulty,
    required int rounds,
  }) {
    if (rounds <= 0) return '';
    var currentPrefix = challenge;
    final results = <int>[];

    for (var r = 0; r < rounds; r++) {
      var nonce = 1;
      while (true) {
        final candidate = '$currentPrefix$nonce';
        final digest = sha256Bytes(candidate);
        final value = ((digest[0] & 0xff) * 16777216) +
            ((digest[1] & 0xff) << 16) +
            ((digest[2] & 0xff) << 8) +
            (digest[3] & 0xff);
        if (value < difficulty) {
          results.add(nonce);
          currentPrefix = candidate;
          break;
        }
        nonce++;
        if (nonce > 50000000) {
          throw Exception('eduVULCAN PoW captcha exceeded max iterations');
        }
      }
    }
    return results.join(';');
  }

  DateTime? _tryParseVulcanDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is num) {
      final intVal = value.toInt();
      if (intVal <= 0) return null;
      if (intVal < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(intVal * 1000).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(intVal).toLocal();
    }
    if (value is String) {
      final str = value.trim();
      if (str.isEmpty) return null;

      final dotNetMatch = RegExp(r'/Date\((-?\d+)').firstMatch(str);
      if (dotNetMatch != null) {
        final ms = int.tryParse(dotNetMatch.group(1) ?? '');
        if (ms != null && ms > 0) {
          return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
        }
      }

      final numVal = num.tryParse(str);
      if (numVal != null && numVal > 100000000) {
        return _tryParseVulcanDate(numVal);
      }

      final isoParsed = DateTime.tryParse(str);
      if (isoParsed != null) return isoParsed.toLocal();

      final ymMatch = RegExp(
        r'(\d{4})[./-](\d{1,2})[./-](\d{1,2})(?:[,\sT]+(?:godz\.?\s*)?(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
        caseSensitive: false,
      ).firstMatch(str);
      if (ymMatch != null) {
        final y = int.parse(ymMatch.group(1)!);
        final m = int.parse(ymMatch.group(2)!);
        final d = int.parse(ymMatch.group(3)!);
        final h = ymMatch.group(4) != null ? int.parse(ymMatch.group(4)!) : 0;
        final min = ymMatch.group(5) != null ? int.parse(ymMatch.group(5)!) : 0;
        final s = ymMatch.group(6) != null ? int.parse(ymMatch.group(6)!) : 0;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(y, m, d, h, min, s);
        }
      }

      final dmMatch = RegExp(
        r'(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?:\s*r\.?)?(?:[,\sT]+(?:godz\.?\s*)?(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
        caseSensitive: false,
      ).firstMatch(str);
      if (dmMatch != null) {
        final d = int.parse(dmMatch.group(1)!);
        final m = int.parse(dmMatch.group(2)!);
        final y = int.parse(dmMatch.group(3)!);
        final h = dmMatch.group(4) != null ? int.parse(dmMatch.group(4)!) : 0;
        final min = dmMatch.group(5) != null ? int.parse(dmMatch.group(5)!) : 0;
        final s = dmMatch.group(6) != null ? int.parse(dmMatch.group(6)!) : 0;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(y, m, d, h, min, s);
        }
      }

      const plMonths = <String, int>{
        'stycz': 1, 'sty': 1,
        'lut': 2,
        'mar': 3,
        'kwiet': 4, 'kwi': 4,
        'maj': 5,
        'czerw': 6, 'cze': 6,
        'lip': 7,
        'sierp': 8, 'sie': 8,
        'wrze': 9, 'wrz': 9,
        'pa\u017adz': 10, 'pazdz': 10, 'pa\u017a': 10, 'paz': 10,
        'listop': 11, 'lis': 11,
        'grud': 12, 'gru': 12,
      };
      final lower = str.toLowerCase();
      for (final entry in plMonths.entries) {
        final plMatch = RegExp(
          '(\\d{1,2})\\s+${entry.key}[a-z\\u0105\\u0107\\u0119\\u0142\\u0144\\u00f3\\u015b\\u017a\\u017c.]*(?:\\s+(\\d{4}))?(?:[,\\s]+(?:godz\\.?\\s*)?(\\d{1,2}):(\\d{1,2}))?',
        ).firstMatch(lower);
        if (plMatch != null) {
          final d = int.parse(plMatch.group(1)!);
          final m = entry.value;
          final now = DateTime.now();
          var y = plMatch.group(2) != null ? int.parse(plMatch.group(2)!) : now.year;
          if (plMatch.group(2) == null &&
              DateTime(y, m, d).isAfter(now.add(const Duration(days: 1)))) {
            y -= 1;
          }
          final h = plMatch.group(3) != null ? int.parse(plMatch.group(3)!) : 0;
          final min = plMatch.group(4) != null ? int.parse(plMatch.group(4)!) : 0;
          return DateTime(y, m, d, h, min);
        }
      }

      final timeOnly = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(str);
      if (timeOnly != null) {
        final now = DateTime.now();
        final h = int.parse(timeOnly.group(1)!);
        final min = int.parse(timeOnly.group(2)!);
        final s = timeOnly.group(3) != null ? int.parse(timeOnly.group(3)!) : 0;
        if (h >= 0 && h < 24 && min >= 0 && min < 60) {
          return DateTime(now.year, now.month, now.day, h, min, s);
        }
      }

      return null;
    }
    if (value is Map) {
      for (final tsKey in ['Timestamp', 'timestamp', 'Time', 'time', 'Epoch', 'epoch']) {
        final ts = value[tsKey];
        if (ts is num && ts > 100000000) {
          return _tryParseVulcanDate(ts);
        }
        if (ts is String) {
          final tsNum = num.tryParse(ts.trim());
          if (tsNum != null && tsNum > 100000000) {
            return _tryParseVulcanDate(tsNum);
          }
        }
      }
      for (final dateKey in [
        'Date', 'date',
        'DateDisplay', 'dateDisplay',
        'DateAt', 'dateAt',
        'DayAt', 'dayAt',
        'DeadlineAt', 'deadlineAt',
        'SentAt', 'sentAt',
        'ReadAt', 'readAt',
        'CreatedAt', 'createdAt',
        'ModifiedAt', 'modifiedAt',
        'DateTime', 'dateTime',
        'Value', 'value',
        'Day', 'day',
        'DateFormatted', 'dateFormatted',
        'Deadline', 'deadline',
      ]) {
        final inner = value[dateKey];
        if (inner != null) {
          final res = _tryParseVulcanDate(inner);
          if (res != null) {
            final timePart = value['Time'] ?? value['time'];
            if (timePart is String && timePart.contains(':')) {
              final tp = timePart.trim().split(':');
              final h = int.tryParse(tp[0]) ?? res.hour;
              final m = int.tryParse(tp.length > 1 ? tp[1] : '0') ?? res.minute;
              final s = int.tryParse(tp.length > 2 ? tp[2] : '0') ?? res.second;
              return DateTime(res.year, res.month, res.day, h, m, s);
            }
            return res;
          }
        }
      }
    }
    return null;
  }

  DateTime _parseVulcanDate(dynamic value, [DateTime? fallback]) {
    return _tryParseVulcanDate(value) ?? fallback ?? DateTime.now();
  }

  String _cleanPersonName(String rawName) {
    var cleaned = rawName.trim();
    if (cleaned.isEmpty) return '';
    if (cleaned.contains(' - ')) {
      cleaned = cleaned.split(' - ').first.trim();
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[[^\]]*\]\s*$'), '').trim();
    return cleaned;
  }

  Map<String, String> _splitPersonName(String rawName) {
    final cleaned = _cleanPersonName(rawName);
    if (cleaned.isEmpty) {
      return const {'firstName': '', 'lastName': ''};
    }
    final rawParts = cleaned.replaceAll(RegExp(r'\s+'), ' ').split(' ');
    final parts = <String>[];
    for (final p in rawParts) {
      if (p.isNotEmpty) parts.add(p);
    }
    if (parts.isEmpty) {
      return const {'firstName': '', 'lastName': ''};
    }
    if (parts.length == 1) {
      return {'firstName': '', 'lastName': parts.first};
    }
    return {
      'firstName': parts.first,
      'lastName': parts.sublist(1).join(' '),
    };
  }

  bool _hasTeacherName(dynamic teacher) {
    if (teacher is! Map) return false;
    return _str(teacher['firstName']).trim().isNotEmpty ||
        _str(teacher['lastName']).trim().isNotEmpty;
  }

  int _stablePositiveId(dynamic rawId, String seed) {
    final parsed = _int(rawId);
    if (parsed > 0) return parsed;
    var hash = 0x811c9dc5;
    for (var i = 0; i < seed.length; i++) {
      hash ^= seed.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash > 0 ? hash : 1;
  }

  Map<String, dynamic> _teacherToJson(dynamic raw, {bool? isHomeTeacher}) {
    if (raw is! Map) {
      return <String, dynamic>{
        'id': -1,
        'url': '',
        'firstName': '',
        'lastName': '',
        if (isHomeTeacher != null) 'isHomeTeacher': isHomeTeacher,
      };
    }
    var firstName = _str(raw['FirstName'] ?? raw['Name']).trim();
    var lastName = _str(raw['Surname'] ?? raw['LastName']).trim();
    final display = _str(raw['DisplayName']).trim();
    if (firstName.isEmpty && lastName.isEmpty && display.isNotEmpty) {
      final split = _splitPersonName(display);
      firstName = split['firstName'] ?? '';
      lastName = split['lastName'] ?? '';
    } else if (lastName.isEmpty && firstName.contains(' ')) {
      final split = _splitPersonName(firstName);
      firstName = split['firstName'] ?? '';
      lastName = split['lastName'] ?? '';
    } else {
      if (firstName.isNotEmpty) firstName = _cleanPersonName(firstName);
      if (lastName.isNotEmpty) lastName = _cleanPersonName(lastName);
    }
    return <String, dynamic>{
      'id': _int(raw['Id']),
      'url': _str(raw['BoxId'] ?? raw['AddressHash'] ?? raw['GlobalKey']),
      'firstName': firstName,
      'lastName': lastName,
      if (isHomeTeacher != null) 'isHomeTeacher': isHomeTeacher,
    };
  }

  Future<dynamic> _webRequest(
    OHttpClient webClient,
    String url, {
    required String method,
    Map<String, String>? formData,
    Map<String, String>? cookies,
  }) async {
    if (_proxyUrl.isNotEmpty) {
      final reqHeaders = <String, String>{
        'User-Agent': _browserUserAgent,
      };
      if (formData != null) {
        reqHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
      }
      final payload = <String, dynamic>{
        'uri': url,
        'method': method,
        'headers': reqHeaders,
        'data': formData != null ? _encodeForm(formData) : null,
      };
      if (cookies != null) {
        payload['cookies'] = cookies;
      }
      final proxyRes = await _http.post(
        _proxyUrl,
        body: jsonEncode(payload),
        headers: const {'Content-Type': 'application/json'},
      );
      final parsed = proxyRes.json;
      if (parsed is Map) {
        final rawCookies = parsed['cookies'];
        if (cookies != null && rawCookies is Map) {
          rawCookies.forEach((k, v) {
            cookies[k.toString()] = v.toString();
          });
        }
        final inner = parsed['data'];
        if (inner is Map && inner.length == 1 && inner['text'] is String) {
          return inner['text'] as String;
        }
        return inner ?? parsed;
      }
      return proxyRes.body;
    }

    OHttpResponse res;
    if (method == 'POST') {
      res = await webClient.post(
        url,
        body: formData != null ? _encodeForm(formData) : null,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        followRedirects: false,
      );
    } else {
      res = await webClient.get(
        url,
        followRedirects: false,
      );
    }

    var currentBase = res.url.isNotEmpty ? res.url : url;
    var nextLoc = res.location;
    var hops = 0;
    while (nextLoc != null && nextLoc.isNotEmpty && hops < 6) {
      final resolvedUrl = Uri.parse(currentBase).resolve(nextLoc).toString();
      res = await webClient.get(resolvedUrl, followRedirects: false);
      currentBase = res.url.isNotEmpty ? res.url : resolvedUrl;
      nextLoc = res.location;
      hops++;
    }
    return res.json ?? res.body;
  }

  Future<dynamic> _hebeRequest({
    required String method,
    required String restUrl,
    required String endpoint,
    Map<String, String>? query,
    Object? payload,
    int? pupilId,
  }) async {
    final kp = _keyPair;
    if (kp == null) {
      throw Exception('VULCAN session is not initialized');
    }

    var fullUrl = '$restUrl/$endpoint';
    if (query != null && query.isNotEmpty) {
      final q = query.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      fullUrl = '$fullUrl?$q';
    }

    final now = DateTime.now().toUtc();
    String? bodyJson;
    if (payload != null) {
      final envelopeBody = <String, dynamic>{
        'AppName': _isHebeCe ? _hebeceAppName : _hebeAppName,
        'AppVersion': _isHebeCe ? _hebeceAppVersion : _hebeAppVersion,
        'CertificateId': kp['fingerprint'],
        'FirebaseToken': '',
        'NotificationToken': '',
        'API': 1,
        'RequestId': uuidV4(),
        'Timestamp': now.millisecondsSinceEpoch,
        'TimestampFormatted': _formatTimestamp(now),
        'Envelope': payload,
      };
      bodyJson = jsonEncode(envelopeBody);
    }

    final sigHeaders = getRsaSignatureHeaders(
      keyId: kp['fingerprint'] ?? '',
      privateKeyJson: kp['privateKey'] ?? '',
      body: bodyJson,
      requestPath: fullUrl,
      canonicalPattern: _canonicalPattern,
    );

    final headers = <String, String>{
      'User-Agent': _userAgent,
      'vOS': _deviceOs,
      'vDeviceModel': _deviceModel,
      'vVersionCode': _isHebeCe ? _hebeceVersionCode : _hebeVersionCode,
      'vAPI': '1',
      'Content-Type': bodyJson != null ? 'application/json; charset=utf-8' : 'application/json',
    };
    if (pupilId != null) {
      headers['vHint'] = pupilId.toString();
    }
    sigHeaders.forEach((k, v) {
      headers[k] = v;
    });

    dynamic rawResponse;
    if (_proxyUrl.isNotEmpty) {
      final proxyRes = await _http.post(
        _proxyUrl,
        body: jsonEncode({
          'uri': fullUrl,
          'method': method,
          'headers': headers,
          'data': bodyJson,
        }),
        headers: const {'Content-Type': 'application/json'},
      );
      final parsed = proxyRes.json;
      rawResponse = parsed is Map ? (parsed['data'] ?? parsed) : proxyRes.body;
    } else {
      final res = method == 'POST'
          ? await _http.post(fullUrl, body: bodyJson, headers: headers)
          : await _http.get(fullUrl, headers: headers);
      rawResponse = res.json ?? res.body;
    }

    if (rawResponse is Map && rawResponse.length == 1 && rawResponse['text'] is String) {
      rawResponse = rawResponse['text'];
    }

    final Map<String, dynamic> decoded = rawResponse is String
        ? Map<String, dynamic>.from(jsonDecode(rawResponse) as Map)
        : Map<String, dynamic>.from(rawResponse as Map);
    final status = decoded['Status'] as Map?;
    final code = _int(status?['Code'], 0);
    if (code != 0) {
      throw Exception('VULCAN API error ($code): ${status?['Message'] ?? 'Unknown'}');
    }
    return decoded['Envelope'];
  }

  Future<List<String>> _loginEduVulcanPrometheus(String login, String password) async {
    final webCookies = <String, String>{};
    final webClient = OHttpClient(
      defaultHeaders: const {'User-Agent': _browserUserAgent},
    );

    if (_proxyUrl.isNotEmpty) {
      try {
        final fastRes = await _http.post(
          _proxyUrl,
          body: jsonEncode({
            'action': 'eduvulcan_login',
            'login': login,
            'password': password,
          }),
          headers: const {'Content-Type': 'application/json'},
        );
        final fastData = fastRes.json;
        if (fastRes.statusCode == 401 && fastData is Map) {
          final innerData = fastData['data'];
          final errMsg = fastData['error'] ??
              (innerData is Map ? innerData['error'] : null) ??
              'Nieprawid\u0142owy login lub has\u0142o eduVULCAN.';
          throw Exception(errMsg.toString());
        }
        if (fastRes.statusCode == 200 && fastData is Map) {
          final inner = fastData['data'];
          final text = inner is Map ? (inner['text'] ?? inner) : inner;
          if (text != null) {
            return await _extractTokensFromAp(text);
          }
        }
      } catch (e) {
        if (e.toString().contains('Nieprawid')) {
          rethrow;
        }
      }
    }

    const loginUrl = 'https://eduvulcan.pl/logowanie?ReturnUrl=%2fapi%2fap';

    final loginRes = await _webRequest(
      webClient,
      loginUrl,
      method: 'GET',
      cookies: webCookies,
    );
    final loginHtml = loginRes.toString();
    final csrfMatch =
        RegExp(r'name="__RequestVerificationToken"[^>]*value="([^"]+)"').firstMatch(loginHtml) ??
            RegExp(r'value="([^"]+)"[^>]*name="__RequestVerificationToken"').firstMatch(loginHtml);
    if (csrfMatch == null) {
      throw Exception('Failed to extract CSRF token from eduvulcan.pl/logowanie');
    }
    final csrfToken = csrfMatch.group(1)!;

    var showCaptcha = true;
    try {
      final infoRes = await _webRequest(
        webClient,
        'https://eduvulcan.pl/Account/QueryUserInfo',
        method: 'POST',
        formData: {
          'alias': login,
          '__RequestVerificationToken': csrfToken,
        },
        cookies: webCookies,
      );
      final decoded = infoRes is Map ? infoRes : jsonDecode(infoRes.toString());
      if (decoded is Map && decoded['data'] is Map) {
        final flag = decoded['data']['ShowCaptcha'];
        showCaptcha = flag == true || flag?.toString().toLowerCase() == 'true';
      }
    } catch (_) {
      showCaptcha = true;
    }

    var captchaResponse = '';
    if (showCaptcha) {
      final challengeMatch = RegExp(r'data-challenge="([^"]+)"').firstMatch(loginHtml);
      final difficultyMatch = RegExp(r'data-difficulty="(\d+)"').firstMatch(loginHtml);
      final roundsMatch = RegExp(r'data-rounds="(\d+)"').firstMatch(loginHtml);
      if (challengeMatch != null && difficultyMatch != null && roundsMatch != null) {
        captchaResponse = _solvePow(
          challenge: challengeMatch.group(1)!,
          difficulty: int.parse(difficultyMatch.group(1)!),
          rounds: int.parse(roundsMatch.group(1)!),
        );
      }
    }

    final postRes = await _webRequest(
      webClient,
      loginUrl,
      method: 'POST',
      formData: {
        'Alias': login,
        'UserName': login,
        'Password': password,
        'captcha-response': captchaResponse,
        '__RequestVerificationToken': csrfToken,
      },
      cookies: webCookies,
    );

    final bodyText = postRes.toString();
    if (bodyText.contains('id="ap"') || bodyText.contains("id='ap'") || bodyText.contains('"Tokens"')) {
      return await _extractTokensFromAp(
        postRes,
        webClient: webClient,
        webCookies: webCookies,
        csrfToken: csrfToken,
      );
    }
    if (bodyText.toLowerCase().contains('robot') || bodyText.toLowerCase().contains('robak')) {
      throw Exception('eduVULCAN anti-bot verification failed');
    }
    if (bodyText.contains('id="form1"')) {
      final errMatches =
          RegExp(r'<div[^>]*class="[^"]*message-error[^"]*"[^>]*>([\s\S]*?)</div>').allMatches(bodyText);
      for (final m in errMatches) {
        final cleaned = (m.group(1) ?? '')
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (cleaned.isNotEmpty) {
          throw Exception(cleaned);
        }
      }
      throw Exception('Nieprawid\u0142owy login lub has\u0142o eduVULCAN.');
    }

    final apRes = await _webRequest(
      webClient,
      'https://eduvulcan.pl/api/ap',
      method: 'GET',
      cookies: webCookies,
    );
    return await _extractTokensFromAp(
      apRes,
      webClient: webClient,
      webCookies: webCookies,
      csrfToken: csrfToken,
    );
  }

  Future<List<String>> _extractTokensFromAp(
    dynamic rawInput, {
    OHttpClient? webClient,
    Map<String, String>? webCookies,
    String? csrfToken,
  }) async {
    if (rawInput is Map) {
      if (rawInput['Tokens'] is List) {
        final list = (rawInput['Tokens'] as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) return list;
      }
      if (rawInput['tokens'] is List) {
        final list = (rawInput['tokens'] as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) return list;
      }
      if (rawInput['text'] is String) {
        return await _extractTokensFromAp(
          rawInput['text'] as String,
          webClient: webClient,
          webCookies: webCookies,
          csrfToken: csrfToken,
        );
      }
    }

    final trimmed = rawInput.toString().trim();
    var jsonStr = trimmed;
    final match =
        RegExp("id=['\"]ap['\"][^>]*value=(['\"])([\\s\\S]*?)\\1").firstMatch(trimmed) ??
            RegExp("value=(['\"])([\\s\\S]*?)\\1[^>]*id=['\"]ap['\"]").firstMatch(trimmed);
    if (match != null) {
      jsonStr = (match.group(2) ?? '')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&amp;', '&');
    }

    final decoded = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    if (decoded['Success'] == false || decoded['success'] == false) {
      throw Exception(
          'eduVULCAN /api/ap error: ${decoded['ErrorMessage'] ?? decoded['errorMessage'] ?? 'Unknown error'}');
    }

    final rawTokens = (decoded['Tokens'] ?? decoded['tokens']) as List?;
    final tokens = rawTokens != null ? rawTokens.map((e) => e.toString()).toList() : <String>[];

    if (tokens.isEmpty &&
        webClient != null &&
        (decoded['IsConsentAccepted'] == false || decoded['isConsentAccepted'] == false)) {
      try {
        final consentForm = <String, String>{
          'Consent[0].Key': '4',
          'Consent[0].Value': 'true',
        };
        if (csrfToken != null) {
          consentForm['__RequestVerificationToken'] = csrfToken;
        }
        await _webRequest(
          webClient,
          'https://eduvulcan.pl/konto/zgody',
          method: 'POST',
          formData: consentForm,
          cookies: webCookies,
        );
        final reAp = await _webRequest(
          webClient,
          'https://eduvulcan.pl/api/ap',
          method: 'GET',
          cookies: webCookies,
        );
        return await _extractTokensFromAp(reAp);
      } catch (_) {}
    }

    if (tokens.isEmpty) {
      throw Exception('No student tokens found in eduVULCAN account');
    }
    return tokens;
  }

  String _decodeJwtTenant(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) throw Exception('Invalid JWT format');
    final normalized = base64Url.normalize(parts[1]);
    final payload = Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map);
    final tenant = (payload['tenant'] ?? payload['Tenant'])?.toString() ?? '';
    if (tenant.isEmpty) {
      throw Exception('JWT token missing tenant claim');
    }
    return tenant;
  }

  Future<void> _registerWithJwtTokens(List<String> tokens) async {
    final tenants = tokens.map(_decodeJwtTenant).toSet().toList();
    Map<String, dynamic>? selectedStudent;
    String? selectedBaseRestUrl;
    final kp = _keyPair!;

    for (final tenant in tenants) {
      final host = tenant.toLowerCase() == 'lublin'
          ? 'https://uonetplus-komunikacja.edu.lublin.eu'
          : _defaultHebeBaseUrl;
      final tenantApiUrl = '$host/$tenant/api';

      try {
        await _hebeRequest(
          method: 'POST',
          restUrl: tenantApiUrl,
          endpoint: 'mobile/register/jwt',
          payload: {
            'OS': _deviceOs,
            'Certificate': kp['certificate'],
            'CertificateType': 'RSA_PEM',
            'DeviceModel': _deviceModel,
            'SelfIdentifier': _deviceId,
            'CertificateThumbprint': kp['fingerprint'],
            'Tokens': tokens,
          },
        );
      } catch (ex) {
        if (!ex.toString().contains('205')) {
          rethrow;
        }
      }

      final pupils = await _hebeRequest(
        method: 'GET',
        restUrl: tenantApiUrl,
        endpoint: 'mobile/register/hebe',
        query: const {'mode': '2'},
      );

      if (pupils is List && pupils.isNotEmpty) {
        selectedStudent = Map<String, dynamic>.from(pupils.first as Map);
        final unitMap = selectedStudent['Unit'];
        final unitRestUrl = (unitMap is Map ? unitMap['RestURL']?.toString() : null) ?? '';
        final unitSymbol = (unitMap is Map ? unitMap['Symbol']?.toString() : null) ?? '';
        if (unitRestUrl.isNotEmpty) {
          final cleaned =
              unitRestUrl.endsWith('/') ? unitRestUrl.substring(0, unitRestUrl.length - 1) : unitRestUrl;
          selectedBaseRestUrl = cleaned.endsWith('/api') ? cleaned : '$cleaned/api';
        } else {
          selectedBaseRestUrl = unitSymbol.isNotEmpty ? '$host/$tenant/$unitSymbol/api' : tenantApiUrl;
        }
        break;
      }
    }

    if (selectedStudent == null || selectedBaseRestUrl == null) {
      throw Exception('No active student profile returned by eduVULCAN');
    }

    _activeStudentRaw = selectedStudent;
    _restUrl = selectedBaseRestUrl;
  }

  Future<void> _registerWithMobileToken(String loginInput, String passwordInput) async {
    var token = loginInput.trim().toUpperCase();
    var symbol = 'default';
    var pin = passwordInput.trim();

    if (loginInput.contains(':')) {
      final parts = loginInput.split(':');
      token = parts[0].trim().toUpperCase();
      symbol = parts[1].trim().toLowerCase();
    } else if (passwordInput.contains(':')) {
      final parts = passwordInput.split(':');
      symbol = parts[0].trim().toLowerCase();
      pin = parts[1].trim();
    }

    final prefix = token.length >= 3 ? token.substring(0, 3) : '';
    final host = _tokenPrefixes[prefix] ?? _defaultHebeBaseUrl;
    final tenantApiUrl = '$host/$symbol/api';
    final kp = _keyPair!;

    try {
      await _hebeRequest(
        method: 'POST',
        restUrl: tenantApiUrl,
        endpoint: 'mobile/register/token',
        payload: {
          'OS': _deviceOs,
          'Certificate': kp['certificate'],
          'CertificateType': 'RSA_PEM',
          'DeviceModel': _deviceModel,
          'SelfIdentifier': _deviceId,
          'CertificateThumbprint': kp['fingerprint'],
          'SecurityToken': token,
          'PIN': pin,
        },
      );
    } catch (ex) {
      if (!ex.toString().contains('205')) {
        rethrow;
      }
    }

    final pupils = await _hebeRequest(
      method: 'GET',
      restUrl: tenantApiUrl,
      endpoint: 'mobile/register/hebe',
      query: const {'mode': '2'},
    );

    if (pupils is! List || pupils.isEmpty) {
      throw Exception('No student profile returned after token registration');
    }

    _activeStudentRaw = Map<String, dynamic>.from(pupils.first as Map);
    final unitMap = _activeStudentRaw!['Unit'];
    final unitRestUrl = (unitMap is Map ? unitMap['RestURL']?.toString() : null) ?? '';
    final unitSymbol = (unitMap is Map ? unitMap['Symbol']?.toString() : null) ?? '';
    if (unitRestUrl.isNotEmpty) {
      final cleaned = unitRestUrl.endsWith('/') ? unitRestUrl.substring(0, unitRestUrl.length - 1) : unitRestUrl;
      _restUrl = cleaned.endsWith('/api') ? cleaned : '$cleaned/api';
    } else {
      _restUrl = unitSymbol.isNotEmpty ? '$host/$symbol/$unitSymbol/api' : tenantApiUrl;
    }
  }

  DateTime _extractMessageSendDate(Map m) {
    for (final key in [
      'SentAt', 'DateSent', 'SendAt', 'DateSend', 'SentDate', 'SendDate',
      'CreatedAt', 'DateCreated', 'DateAt', 'Date', 'DayAt', 'Day',
      'data', 'Data', 'dataWyslania', 'DataWyslania',
      'dataNadania', 'DataNadania', 'dataOtrzymania', 'DataOtrzymania',
      'dataUtworzenia', 'DataUtworzenia',
      'date', 'sendDate', 'sentAt', 'dateSent', 'createdAt', 'dateCreated',
      'ModifiedAt', 'DateModify', 'modifiedAt', 'dateModify',
    ]) {
      final parsed = _tryParseVulcanDate(m[key]);
      if (parsed != null) return parsed;
    }

    final sender = m['Sender'] ?? m['nadawca'];
    if (sender is Map) {
      for (final key in ['SentAt', 'DateSent', 'CreatedAt', 'DateCreated', 'Date', 'data']) {
        final parsed = _tryParseVulcanDate(sender[key]);
        if (parsed != null) return parsed;
      }
    }

    for (final entry in m.entries) {
      final k = entry.key.toString().toLowerCase();
      if (k.contains('read') ||
          k.contains('przeczyt') ||
          k.contains('odczyt') ||
          k.contains('wycof') ||
          k.contains('withdraw') ||
          k == 'id' ||
          k.contains('key') ||
          k.contains('subject') ||
          k.contains('temat') ||
          k.contains('content') ||
          k.contains('tresc') ||
          k.contains('status')) {
        continue;
      }
      final v = entry.value;
      if (v is Map ||
          (v is String &&
              (k.contains('dat') || k.contains('sent') || k.contains('send') || k.contains('time') || k.contains('at')))) {
        final parsed = _tryParseVulcanDate(v);
        if (parsed != null) return parsed;
      }
    }

    return DateTime.now();
  }

  bool? _isTruthyFlag(dynamic val) {
    if (val == null) return null;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final s = val.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'tak' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'nie' || s == 'no') return false;
    }
    return null;
  }

  DateTime? _extractMessageReadDate(
    Map m, {
    required DateTime sendDate,
    required bool sent,
    required String boxKey,
  }) {
    for (final key in [
      'ReadAt', 'DateRead', 'ReadDate', 'readAt', 'dateRead', 'readDate',
      'dataPrzeczytania', 'DataPrzeczytania', 'dataOdczytania', 'DataOdczytania',
    ]) {
      final parsed = _tryParseVulcanDate(m[key]);
      if (parsed != null) return parsed;
    }

    for (final entry in m.entries) {
      final k = entry.key.toString().toLowerCase();
      if ((k.contains('read') || k.contains('przeczyt') || k.contains('odczyt')) &&
          !k.contains('unread') &&
          !k.contains('nieprzeczyt')) {
        final parsed = _tryParseVulcanDate(entry.value);
        if (parsed != null) return parsed;
      }
    }

    if (sent) return sendDate;

    final recRaw = m['Receiver'] ?? m['Receivers'] ?? m['odbiorcy'] ?? m['Odbiorcy'];
    if (recRaw is List && recRaw.isNotEmpty) {
      final mb = _activeStudentRaw?['MessageBox'];
      final boxName = (mb is Map ? mb['Name']?.toString() : null)?.toLowerCase() ?? '';
      final recMaps = recRaw.whereType<Map>().toList();
      if (recMaps.isNotEmpty) {
        var matchingRecs = recMaps.where((r) {
          final gk = r['GlobalKey']?.toString() ?? r['apiGlobalKey']?.toString() ?? '';
          if (boxKey.isNotEmpty && gk.isNotEmpty && gk.toLowerCase() == boxKey.toLowerCase()) {
            return true;
          }
          final rName = r['Name']?.toString().toLowerCase() ?? '';
          if (boxName.isNotEmpty && rName.isNotEmpty && rName == boxName) {
            return true;
          }
          return false;
        }).toList();

        if (matchingRecs.isEmpty) {
          matchingRecs = recMaps;
        }

        for (final r in matchingRecs) {
          for (final rk in ['ReadAt', 'DateRead', 'ReadDate', 'readAt', 'dateRead', 'dataPrzeczytania', 'dataOdczytania']) {
            final parsed = _tryParseVulcanDate(r[rk]);
            if (parsed != null) return parsed;
          }
          for (final rk in ['HasRead', 'IsRead', 'Read', 'hasRead', 'isRead', 'read', 'przeczytana', 'odczytana', 'czyPrzeczytana']) {
            if (_isTruthyFlag(r[rk]) == true) return sendDate;
          }
          for (final uk in ['Unread', 'IsUnread', 'unread', 'nieprzeczytane', 'nieprzeczytana']) {
            if (_isTruthyFlag(r[uk]) == false) return sendDate;
          }
        }
      }
    } else if (recRaw is Map) {
      for (final rk in ['ReadAt', 'DateRead', 'ReadDate', 'readAt', 'dateRead', 'dataPrzeczytania', 'dataOdczytania']) {
        final parsed = _tryParseVulcanDate(recRaw[rk]);
        if (parsed != null) return parsed;
      }
      for (final rk in ['HasRead', 'IsRead', 'Read', 'hasRead', 'isRead', 'read', 'przeczytana', 'odczytana', 'czyPrzeczytana']) {
        if (_isTruthyFlag(recRaw[rk]) == true) return sendDate;
      }
    }

    for (final rk in [
      'HasRead', 'IsRead', 'Read', 'ByMe', 'hasRead', 'isRead', 'read',
      'przeczytana', 'Przeczytana', 'przeczytane', 'Przeczytane',
      'odczytana', 'Odczytana', 'odczytane', 'Odczytane',
      'czyPrzeczytana', 'CzyPrzeczytana', 'czyOdczytana', 'CzyOdczytana',
    ]) {
      if (_isTruthyFlag(m[rk]) == true) return sendDate;
    }

    for (final uk in [
      'Unread', 'IsUnread', 'unread', 'isUnread',
      'nieprzeczytane', 'Nieprzeczytane', 'nieprzeczytana', 'Nieprzeczytana',
    ]) {
      if (_isTruthyFlag(m[uk]) == false) return sendDate;
    }

    final ratio = m['nieprzeczytanePrzeczytanePrzez']?.toString().trim() ?? '';
    if (ratio.startsWith('0/')) {
      return sendDate;
    }

    return null;
  }

  @override
  Future<Map<String, dynamic>> login(Map<String, String> credentials) async {
    try {
      reportProgress(0.1, localized('D870CFEB-F16B-4091-9084-9620E5BACE22'));

      final username = (credentials['login'] ?? credentials['username'] ?? '').trim();
      final password = credentials['pass'] ?? credentials['password'] ?? '';
      final hasProxyField = credentials.containsKey('proxy');
      var resolvedProxy = (credentials['proxy'] ?? '').trim();

      if ((username.toLowerCase() == 'test' && password == 'test') ||
          (username.toLowerCase() == 'demo' && password == 'demo')) {
        _sampleDriver ??= OProtocolDriver('sample');
        return await _sampleDriver!.login(credentials);
      }
      _sampleDriver = null;

      if (hasProxyField) {
        if (resolvedProxy.isEmpty ||
            resolvedProxy.toLowerCase().contains('librus.pl') ||
            resolvedProxy.toLowerCase().contains('eduvulcan.pl') ||
            resolvedProxy.toLowerCase().contains('vulcan.net.pl')) {
          resolvedProxy = 'http://127.0.0.1:5000';
        }
        if (Uri.tryParse(resolvedProxy) == null) {
          return {'success': false, 'message': localized('1DBA54DA-C4D2-4D21-B072-89AAFCC4758D')};
        }
      } else {
        resolvedProxy = '';
      }
      _proxyUrl = resolvedProxy;
      _savedUsername = username;
      _savedPassword = password;

      if (username.isEmpty || (password.isEmpty && !username.contains('Tokens'))) {
        return {'success': false, 'message': localized('E15B042C-B7C1-43AB-9557-EA1B1F08CE9C')};
      }

      _keyPair = generateRsaKeyPair();
      _deviceId = uuidV4();

      reportProgress(0.25, localized('440FA18A-AD7D-47B4-B4FF-C2FE934479DA'));

      if (username.contains('Tokens') || username.contains('id="ap"') || username.contains("id='ap'")) {
        _isHebeCe = true;
        final tokens = await _extractTokensFromAp(username);
        await _registerWithJwtTokens(tokens);
        return {'success': true};
      }

      final upperLogin = username.toUpperCase();
      if (_tokenPrefixes.keys.any((prefix) => upperLogin.startsWith(prefix)) && !username.contains('@')) {
        _isHebeCe = false;
        await _registerWithMobileToken(username, password);
        return {'success': true};
      }

      _isHebeCe = true;
      reportProgress(0.35, localized('395B01AF-19EE-43BE-880D-1EAE925B33C2'));
      final tokens = await _loginEduVulcanPrometheus(username, password);
      await _registerWithJwtTokens(tokens);

      return {'success': true};
    } catch (ex) {
      return {'success': false, 'message': _errStr(ex)};
    }
  }

  @override
  Future<Map<String, dynamic>> refresh(String? weekStartIso) async {
    if (_sampleDriver != null) {
      return await _sampleDriver!.refresh(weekStartIso);
    }
    if (_restUrl == null || _activeStudentRaw == null) {
      return {'success': false, 'message': localized('C5FDD0D8-771D-4DCE-8FCE-62D1BA4A6C93')};
    }

    try {
      reportProgress(0.1, localized('9395EE9D-253E-4795-9F7D-DFA49D161EA8'));

      final studentRaw = _activeStudentRaw!;
      final pupilRaw = Map<String, dynamic>.from((studentRaw['Pupil'] as Map?) ?? {});
      final unitRaw = Map<String, dynamic>.from((studentRaw['Unit'] as Map?) ?? {});
      final constituentRaw = Map<String, dynamic>.from((studentRaw['ConstituentUnit'] as Map?) ?? {});
      final journalRaw = Map<String, dynamic>.from((studentRaw['Journal'] as Map?) ?? {});
      final periodsRaw = <Map<String, dynamic>>[];
      if (studentRaw['Periods'] is List) {
        for (final p in studentRaw['Periods'] as List) {
          if (p is Map) periodsRaw.add(Map<String, dynamic>.from(p));
        }
      }

      final pupilId = _int(pupilRaw['Id']);
      final unitId = _int(unitRaw['Id']);
      final constituentId = _int(constituentRaw['Id'], unitId);

      Map<String, dynamic>? currentPeriod;
      for (final p in periodsRaw) {
        if (p['Current'] == true) {
          currentPeriod = p;
          break;
        }
      }
      if (currentPeriod == null && periodsRaw.isNotEmpty) {
        currentPeriod = periodsRaw.first;
      }
      final periodId = _int(currentPeriod?['Id']);
      final periodNumber = _int(currentPeriod?['Number'], 1);

      final defaultStartYear = DateTime(DateTime.now().month >= 9 ? DateTime.now().year : DateTime.now().year - 1, 9, 1);
      final firstPeriod = periodsRaw.isNotEmpty ? periodsRaw.first : null;
      final lastPeriod = periodsRaw.isNotEmpty ? periodsRaw.last : null;
      final beginSchoolYear = _parseVulcanDate(
        journalRaw['StartAt'] ?? firstPeriod?['StartAt'] ?? firstPeriod?['Start'],
        defaultStartYear,
      );

      Map<String, dynamic>? sem1Period;
      for (final p in periodsRaw) {
        if (_int(p['Number']) == 1) {
          sem1Period = p;
          break;
        }
      }
      final endFirstSemester = _parseVulcanDate(
        sem1Period?['EndAt'] ?? sem1Period?['End'],
        DateTime(beginSchoolYear.year + 1, 1, 31),
      );
      final endSchoolYear = _parseVulcanDate(
        journalRaw['EndAt'] ?? lastPeriod?['EndAt'] ?? lastPeriod?['End'],
        DateTime(beginSchoolYear.year + 1, 6, 25),
      );

      int? luckyNumber;
      try {
        final luckyEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/school/lucky',
          pupilId: pupilId,
          query: {
            'pupilId': pupilId.toString(),
            'constituentId': constituentId.toString(),
            'day': _ymd(DateTime.now()),
          },
        );
        if (luckyEnv is Map) {
          final numVal = _intOrNull(luckyEnv['Number']);
          if (numVal != null && numVal > 0) luckyNumber = numVal;
        }
      } catch (_) {}

      final lessonRangesJson = <Map<String, dynamic>>[];
      try {
        final slotsEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/dictionary/timeslot',
          pupilId: pupilId,
          query: {'pupilId': pupilId.toString()},
        );
        if (slotsEnv is List) {
          for (final s in slotsEnv) {
            if (s is Map) {
              final startParts = (s['Start']?.toString() ?? '08:00').split(':');
              final endParts = (s['End']?.toString() ?? '08:45').split(':');
              final sfh = int.tryParse(startParts[0]) ?? 8;
              final sfm = int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0;
              final sth = int.tryParse(endParts[0]) ?? 8;
              final stm = int.tryParse(endParts.length > 1 ? endParts[1] : '45') ?? 45;
              lessonRangesJson.add({
                'from': DateTime(2000, 1, 1, sfh, sfm).toIso8601String(),
                'to': DateTime(2000, 1, 1, sth, stm).toIso8601String(),
              });
            }
          }
        }
      } catch (_) {}

      final announcementsJson = <Map<String, dynamic>>[];
      try {
        final annEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/announcement/byPupil',
          pupilId: pupilId,
          query: {
            'unitId': unitId.toString(),
            'pupilId': pupilId.toString(),
            'view': '6',
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
        if (annEnv is List) {
          for (final a in annEnv) {
            if (a is Map) {
              announcementsJson.add({
                'id': _int(a['Id']),
                'url': '',
                'subject': _str(a['Title']),
                'content': _cleanHtml(_str(a['Content'])),
                'startDate': _parseVulcanDate(a['From'] ?? a['CreatedAt'] ?? a['DateCreated']).toIso8601String(),
                'endDate': _parseVulcanDate(a['To'] ?? a['ModifiedAt'] ?? a['DateModify']).toIso8601String(),
                'contact': _teacherToJson(a['Sender']),
                'read': a['Read'] == true ||
                    a['HasRead'] == 1 ||
                    a['HasRead'] == true ||
                    a['ReadAt'] != null ||
                    a['DateRead'] != null,
              });
            }
          }
        }
      } catch (_) {}

      var homeTeacherJson = _teacherToJson(null, isHomeTeacher: true);
      var principalName = '';
      var principalIsVice = false;
      void setPrincipal(String rawCandidate, {bool isVice = false}) {
        final cleaned = _cleanPersonName(rawCandidate);
        if (cleaned.isEmpty) return;
        if (!isVice) {
          principalName = cleaned;
          principalIsVice = false;
        } else if (principalName.isEmpty || principalIsVice) {
          principalName = cleaned;
          principalIsVice = true;
        }
      }

      final educatorsListRaw = studentRaw['EducatorsList'];
      if (educatorsListRaw is List) {
        for (final e in educatorsListRaw) {
          if (e is! Map) continue;
          final group = _str(e['Group']).toLowerCase();
          final rawName = _str(e['Name'] ?? e['DisplayName']);
          if (group.contains('dyrektor')) {
            setPrincipal(rawName, isVice: group.contains('wicedyrektor'));
          } else if (!_hasTeacherName(homeTeacherJson)) {
            final candidate = _teacherToJson(e, isHomeTeacher: true);
            if (_hasTeacherName(candidate)) {
              homeTeacherJson = candidate;
            }
          }
        }
      }

      final educatorsRaw = studentRaw['Educators'];
      if (educatorsRaw is List) {
        for (final e in educatorsRaw) {
          if (e is! Map) continue;
          final roles = e['Roles'];
          var roleMatchedHome = false;
          if (roles is List && roles.isNotEmpty) {
            for (final r in roles) {
              if (r is! Map) continue;
              final roleName = _str(r['RoleName']).toLowerCase();
              final roleTeacher = _hasTeacherName(_teacherToJson(e))
                  ? e
                  : <String, dynamic>{
                      'Id': e['Id'],
                      'Name': r['Name'] ?? e['Name'],
                      'Surname': r['Surname'] ?? e['Surname'],
                      'DisplayName': r['DisplayName'] ?? e['DisplayName'],
                      'AddressHash': r['AddressHash'] ?? e['AddressHash'],
                    };
              final personName = _str(roleTeacher['DisplayName']).trim().isNotEmpty
                  ? _str(roleTeacher['DisplayName']).trim()
                  : '${_str(roleTeacher['Name'])} ${_str(roleTeacher['Surname'])}'.trim();
              if (roleName.contains('dyrektor')) {
                setPrincipal(personName, isVice: roleName.contains('wicedyrektor'));
              } else if (roleName.contains('wychowawc') || _int(r['RoleOrder']) == 1) {
                roleMatchedHome = true;
                final candidate = _teacherToJson(roleTeacher, isHomeTeacher: true);
                if (_hasTeacherName(candidate)) {
                  homeTeacherJson = candidate;
                }
              }
            }
          }
          if (!roleMatchedHome && !_hasTeacherName(homeTeacherJson)) {
            final candidate = _teacherToJson(e, isHomeTeacher: true);
            if (_hasTeacherName(candidate)) {
              homeTeacherJson = candidate;
            }
          }
        }
      }

      final subjectTeachersByName = <String, Map<String, dynamic>>{};
      final teacherPeriodId = _int(currentPeriod?['Id'], periodId);
      if (teacherPeriodId != -1) {
        try {
          final teachersEnv = await _hebeRequest(
            method: 'GET',
            restUrl: _restUrl!,
            endpoint: 'mobile/teacher/byPeriod',
            pupilId: pupilId,
            query: {
              'periodId': teacherPeriodId.toString(),
              'pupilId': pupilId.toString(),
              'unitId': unitId.toString(),
              'lastId': '-2147483648',
              'pageSize': '500',
              'lastSyncDate': '1970-01-01 01:00:00',
            },
          );
          if (teachersEnv is List) {
            for (final t in teachersEnv) {
              if (t is! Map) continue;
              final pos = _intOrNull(t['Position']);
              final desc = _str(t['Description']).trim();
              final descLower = desc.toLowerCase();
              final first = _cleanPersonName(_str(t['FirstName'] ?? t['Name']));
              final last = _cleanPersonName(_str(t['Surname'] ?? t['LastName']));
              final full = '$first $last'.trim();
              final display = _cleanPersonName(_str(t['DisplayName']));
              final bestName = full.isNotEmpty ? full : display;

              if (pos == 0 || descLower.contains('wychowawca')) {
                final candidate = _teacherToJson(t, isHomeTeacher: true);
                if (_hasTeacherName(candidate) &&
                    (descLower.contains('wychowawca') || !_hasTeacherName(homeTeacherJson))) {
                  homeTeacherJson = candidate;
                }
              }
              if (pos == 2 || descLower.contains('dyrektor')) {
                setPrincipal(bestName, isVice: descLower.contains('wicedyrektor'));
              }
              if (descLower.isNotEmpty &&
                  pos != 0 &&
                  pos != 2 &&
                  !descLower.contains('wychowawca') &&
                  !descLower.contains('dyrektor')) {
                final subjectTeacher = _teacherToJson(t);
                if (_hasTeacherName(subjectTeacher)) {
                  subjectTeachersByName.putIfAbsent(descLower, () => subjectTeacher);
                }
              }
            }
          }
        } catch (_) {}
      }

      if (!_hasTeacherName(homeTeacherJson)) {
        try {
          final kgEnv = await _hebeRequest(
            method: 'GET',
            restUrl: _restUrl!,
            endpoint: 'mobile/teacher/kindergarten/byPupil',
            pupilId: pupilId,
            query: {
              'pupilId': pupilId.toString(),
              'unitId': unitId.toString(),
              'lastId': '-2147483648',
              'pageSize': '500',
              'lastSyncDate': '1970-01-01 01:00:00',
            },
          );
          if (kgEnv is List) {
            for (final t in kgEnv) {
              if (t is! Map) continue;
              final candidate = _teacherToJson(t, isHomeTeacher: true);
              if (_hasTeacherName(candidate)) {
                homeTeacherJson = candidate;
                break;
              }
            }
          }
        } catch (_) {}
      }

      final rawConstituentName = _str(constituentRaw['Name']).trim();
      final rawUnitName = _str(unitRaw['Name']).trim();
      final rawDisplayName = _str(unitRaw['DisplayName']).trim();
      final patron = _str(constituentRaw['Patron'] ?? unitRaw['Patron']).trim();
      var unitFullName = rawConstituentName.isNotEmpty
          ? rawConstituentName
          : (rawUnitName.isNotEmpty
              ? rawUnitName
              : (rawDisplayName.isNotEmpty ? rawDisplayName : 'Szko\u0142a VULCAN'));
      if (patron.isNotEmpty && !unitFullName.toLowerCase().contains(patron.toLowerCase())) {
        unitFullName = '$unitFullName im. $patron';
      }
      final unitName = _str(
        unitRaw['DisplayName'],
        unitFullName.isNotEmpty ? unitFullName : _str(unitRaw['Short'], 'VULCAN'),
      );
      var unitAddress = _str(
        unitRaw['Address'],
        _str(constituentRaw['Address']),
      );
      var unitTown = _str(
        constituentRaw['City'] ?? constituentRaw['Town'],
        _str(unitRaw['City'] ?? unitRaw['Town']),
      );
      var unitPhone = _str(
        constituentRaw['Phone'] ?? constituentRaw['Telephone'],
        _str(unitRaw['Phone'] ?? unitRaw['Telephone']),
      );
      var unitEmail = _str(
        constituentRaw['Email'] ?? constituentRaw['Mail'],
        _str(unitRaw['Email'] ?? unitRaw['Mail']),
      );
      if (principalName.isEmpty) {
        setPrincipal(_str(
          constituentRaw['Director'] ?? constituentRaw['Principal'],
          _str(unitRaw['Director'] ?? unitRaw['Principal']),
        ));
      }

      try {
        final infoEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/school/info',
          pupilId: pupilId,
          query: {
            'pupilId': pupilId.toString(),
            'lastSyncDate': '1970-01-01 01:00:00',
          },
        );
        if (infoEnv is List) {
          for (final item in infoEnv) {
            if (item is! Map) continue;
            final topic = _str(item['Topic']).trim().toLowerCase();
            final content = _str(item['Content'])
                .replaceAll(RegExp(r'<[^>]*>'), ' ')
                .replaceAll('&nbsp;', ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            if (content.isEmpty) continue;
            if (topic.contains('dyrektor')) {
              setPrincipal(content, isVice: topic.contains('wicedyrektor'));
            }
            if (unitEmail.isEmpty) {
              final emailMatch = RegExp(
                r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
              ).firstMatch(content);
              if (emailMatch != null) {
                unitEmail = emailMatch.group(0) ?? '';
              }
            }
            if (unitPhone.isEmpty &&
                (topic.contains('tel') ||
                    topic.contains('phone') ||
                    topic.contains('kontakt') ||
                    topic.contains('dane'))) {
              final phoneMatch = RegExp(r'(\+?\d[\d\s\-()]{6,}\d)').firstMatch(content);
              if (phoneMatch != null) {
                unitPhone = (phoneMatch.group(1) ?? '').trim();
              } else if (topic.contains('telefon') && content.length <= 40) {
                unitPhone = content;
              }
            }
            if (unitAddress.isEmpty && (topic.contains('adres') || topic.contains('address'))) {
              unitAddress = content;
            }
          }
        }
      } catch (_) {}

      if (unitTown.isEmpty && unitAddress.isNotEmpty) {
        final townMatch = RegExp(r'\b\d{2}-\d{3}\s+([^,\n]+)').firstMatch(unitAddress);
        if (townMatch != null) {
          unitTown = (townMatch.group(1) ?? '').trim();
        }
      }

      final unitJson = <String, dynamic>{
        'id': unitId,
        'url': '',
        if (luckyNumber != null) 'luckyNumber': luckyNumber,
        'luckyNumberTomorrow': false,
        'name': unitName.isNotEmpty ? unitName : 'VULCAN',
        'fullName': unitFullName.isNotEmpty ? unitFullName : 'Szko\u0142a VULCAN',
        'address': unitAddress,
        'town': unitTown,
        'principalName': principalName,
        'phone': unitPhone,
        'email': unitEmail,
        'lessonsRange': lessonRangesJson,
        'announcements': announcementsJson,
      };

      final classDisplay = _str(studentRaw['ClassDisplay']);
      final mainClassLightJson = <String, dynamic>{
        'id': unitId,
        'number': _int(currentPeriod?['Level'], 1),
        'symbol': classDisplay,
        'name': classDisplay,
        'beginSchoolYear': beginSchoolYear.toIso8601String(),
        'endFirstSemester': endFirstSemester.toIso8601String(),
        'endSchoolYear': endSchoolYear.toIso8601String(),
        'unit': unitJson,
        'classTutor': homeTeacherJson,
        'events': <Map<String, dynamic>>[],
        'averages': <String, dynamic>{},
      };

      reportProgress(0.35, localized('7526392B-307D-4306-B5E7-D9627277B257'));

      final subjectsById = <int, Map<String, dynamic>>{};
      Map<String, dynamic> ensureSubject(dynamic rawSub, [Map<String, dynamic>? fallbackTeacher]) {
        if (rawSub is! Map) {
          return subjectsById.putIfAbsent(
            -1,
            () => {
              'id': -1,
              'url': '',
              'name': 'Przedmiot',
              'short': '',
              'no': -1,
              'isExtracurricular': false,
              'isBlockLesson': false,
              'hostClass': mainClassLightJson,
              'teacher': _teacherToJson(null),
              'grades': <Map<String, dynamic>>[],
            },
          );
        }
        final id = _int(rawSub['Id']);
        final subName = _str(rawSub['Name'], 'Przedmiot');
        final candidateTeacher = _hasTeacherName(fallbackTeacher)
            ? fallbackTeacher!
            : (subjectTeachersByName[subName.toLowerCase().trim()] ?? _teacherToJson(null));
        final subject = subjectsById.putIfAbsent(
          id,
          () => {
            'id': id,
            'url': '',
            'name': subName,
            'short': _str(rawSub['Kod'] ?? rawSub['Code']),
            'no': _int(rawSub['Position'], id),
            'isExtracurricular': false,
            'isBlockLesson': false,
            'hostClass': mainClassLightJson,
            'teacher': candidateTeacher,
            'grades': <Map<String, dynamic>>[],
          },
        );
        if (!_hasTeacherName(subject['teacher']) &&
            _hasTeacherName(candidateTeacher)) {
          subject['teacher'] = candidateTeacher;
        }
        return subject;
      }

      var gradesSucceeded = false;
      var attendanceSucceeded = false;
      Object? coreFetchError;

      final periodsToQuery = periodsRaw.isNotEmpty ? periodsRaw : (currentPeriod != null ? [currentPeriod] : <Map<String, dynamic>>[]);
      for (final period in periodsToQuery) {
        final pId = _int(period['Id'], periodId);
        final pNum = _int(period['Number'], periodNumber);
        if (pId == -1) continue;

        try {
          final gradesEnv = await _hebeRequest(
            method: 'GET',
            restUrl: _restUrl!,
            endpoint: 'mobile/grade/byPupil',
            pupilId: pupilId,
            query: {
              'unitId': unitId.toString(),
              'pupilId': pupilId.toString(),
              'periodId': pId.toString(),
              'lastId': '-2147483648',
              'pageSize': '500',
            },
          );
          if (gradesEnv is List) {
            gradesSucceeded = true;
            for (final g in gradesEnv) {
              if (g is! Map) continue;
              final column = Map<String, dynamic>.from((g['Column'] as Map?) ?? {});
              final teacher = _teacherToJson(g['Creator'] ?? g['Modifier']);
              final subject = ensureSubject(column['Subject'], teacher);
              final gradeList = subject['grades'] as List<Map<String, dynamic>>;
              final comment = _str(g['Comment']);
              final rawVal = _str(g['Content'] ?? g['ContentRaw']);
              final normVal = _normalizeGradeValue(rawVal);
              final explicitNoAvg =
                  column['CountToAverage'] == false || column['CountsToAverage'] == false;
              final explicitAvg =
                  column['CountToAverage'] == true || column['CountsToAverage'] == true;
              final hasNumericGrade = g['Value'] != null || RegExp(r'^[1-6]').hasMatch(normVal);
              final rawWeight = _double(column['Weight'], hasNumericGrade ? 1.0 : 0.0);
              final countsToAvg = !explicitNoAvg && (explicitAvg || hasNumericGrade);
              var weight = rawWeight > 0 && rawWeight < 1.0 ? 1 : rawWeight.round();
              if (countsToAvg && weight <= 0) {
                weight = 1;
              }
              final colName = _str(column['Name']);
              final createdIso = _parseVulcanDate(g['CreatedAt'] ?? g['DateCreated']).toIso8601String();
              final gradeId = _stablePositiveId(
                g['Id'],
                '${subject['id']}:$pNum:$colName:$normVal:$createdIso',
              );
              final alreadyExists =
                  gradeId > 0 && gradeList.any((existing) => _int(existing['id']) == gradeId);
              if (!alreadyExists) {
                gradeList.add({
                  'id': gradeId,
                  'url': '',
                  'name': colName.isNotEmpty ? colName : _str(column['Code'], 'Ocena'),
                  'value': normVal,
                  'weight': weight,
                  'comments': comment.isNotEmpty ? [comment] : <String>[],
                  'countsToAverage': countsToAvg,
                  'date': createdIso,
                  'addDate': _parseVulcanDate(
                    g['ModifiedAt'] ?? g['DateModify'] ?? g['CreatedAt'] ?? g['DateCreated'],
                  ).toIso8601String(),
                  'addedBy': teacher,
                  'resitPart': false,
                  'semester': pNum,
                  'isConstituent': true,
                  'isSemester': false,
                  'isSemesterProposition': false,
                  'isFinal': false,
                  'isFinalProposition': false,
                });
              }
            }
          }
        } catch (ex) {
          coreFetchError ??= ex;
        }

        try {
          final sumEnv = await _hebeRequest(
            method: 'GET',
            restUrl: _restUrl!,
            endpoint: 'mobile/grade/summary/byPupil',
            pupilId: pupilId,
            query: {
              'unitId': unitId.toString(),
              'pupilId': pupilId.toString(),
              'periodId': pId.toString(),
              'lastId': '-2147483648',
              'pageSize': '500',
            },
          );
          if (sumEnv is List) {
            for (final s in sumEnv) {
              if (s is! Map) continue;
              final subject = ensureSubject(s['Subject']);
              final gradeList = subject['grades'] as List<Map<String, dynamic>>;
              final entry1 = _normalizeGradeValue(_str(s['Entry_1']).trim());
              final entry2 = _normalizeGradeValue(_str(s['Entry_2']).trim());
              final entry3 = _normalizeGradeValue(_str(s['Entry_3']).trim());
              final isLastPeriod = s['Last'] == true || period['Last'] == true || pNum >= 2;
              final baseSummaryId = _int(s['Id'], 0) * 10;
              final modIso = _parseVulcanDate(s['ModifiedAt']).toIso8601String();

              if (entry1.isNotEmpty &&
                  !gradeList.any((existing) => _int(existing['id']) == baseSummaryId + 1)) {
                gradeList.add({
                  'id': baseSummaryId + 1,
                  'url': '',
                  'name': isLastPeriod
                      ? 'Propozycja oceny rocznej'
                      : 'Propozycja oceny \u015br\u00f3drocznej',
                  'value': entry1,
                  'weight': 0,
                  'comments': <String>[],
                  'countsToAverage': false,
                  'date': modIso,
                  'addDate': modIso,
                  'resitPart': false,
                  'semester': pNum,
                  'isConstituent': false,
                  'isSemester': false,
                  'isSemesterProposition': !isLastPeriod,
                  'isFinal': false,
                  'isFinalProposition': isLastPeriod,
                });
              }
              if (entry2.isNotEmpty &&
                  !gradeList.any((existing) => _int(existing['id']) == baseSummaryId + 2)) {
                gradeList.add({
                  'id': baseSummaryId + 2,
                  'url': '',
                  'name': isLastPeriod ? 'Ocena roczna' : 'Ocena \u015br\u00f3droczna',
                  'value': entry2,
                  'weight': 0,
                  'comments': <String>[],
                  'countsToAverage': false,
                  'date': modIso,
                  'addDate': modIso,
                  'resitPart': false,
                  'semester': pNum,
                  'isConstituent': false,
                  'isSemester': !isLastPeriod,
                  'isSemesterProposition': false,
                  'isFinal': isLastPeriod,
                  'isFinalProposition': false,
                });
              }
              if (entry3.isNotEmpty &&
                  entry3 != entry2 &&
                  !gradeList.any((existing) => _int(existing['id']) == baseSummaryId + 3)) {
                gradeList.add({
                  'id': baseSummaryId + 3,
                  'url': '',
                  'name': isLastPeriod ? 'Ocena roczna (poprawkowa)' : 'Ocena \u015br\u00f3droczna',
                  'value': entry3,
                  'weight': 0,
                  'comments': <String>[],
                  'countsToAverage': false,
                  'date': modIso,
                  'addDate': modIso,
                  'resitPart': entry2.isNotEmpty,
                  'semester': pNum,
                  'isConstituent': false,
                  'isSemester': !isLastPeriod,
                  'isSemesterProposition': false,
                  'isFinal': isLastPeriod,
                  'isFinalProposition': false,
                });
              }
            }
          }
        } catch (_) {}

        try {
          final avgEnv = await _hebeRequest(
            method: 'GET',
            restUrl: _restUrl!,
            endpoint: 'mobile/grade/average/byPupil',
            pupilId: pupilId,
            query: {
              'unitId': unitId.toString(),
              'pupilId': pupilId.toString(),
              'periodId': pId.toString(),
              'lastId': '-2147483648',
              'pageSize': '500',
              'scope': 'auto',
            },
          );
          if (avgEnv is List) {
            for (final a in avgEnv) {
              if (a is! Map) continue;
              ensureSubject(a['Subject']);
            }
          }
        } catch (_) {}
      }

      reportProgress(0.6, localized('7344559E-3869-4BDA-AD38-266302B3D929'));

      final pivot = (weekStartIso != null && weekStartIso.isNotEmpty)
          ? (DateTime.tryParse(weekStartIso) ?? DateTime.now())
          : DateTime.now();
      final schedDateFrom = _ymd(pivot.subtract(const Duration(days: 35)));
      final schedDateTo = _ymd(pivot.add(const Duration(days: 42)));

      final timetableMap = <String, dynamic>{};
      final existingTimetables = _registerData['timetables'];
      if (existingTimetables is Map && existingTimetables['timetable'] is Map) {
        (existingTimetables['timetable'] as Map).forEach((k, v) {
          timetableMap[k.toString()] = v;
        });
      }

      try {
        final schedEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/schedule/withchanges/byPupil',
          pupilId: pupilId,
          query: {
            'pupilId': pupilId.toString(),
            'dateFrom': schedDateFrom,
            'dateTo': schedDateTo,
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
        if (schedEnv is List) {
          final byDay = <String, Map<int, List<Map<String, dynamic>>>>{};
          for (final item in schedEnv) {
            if (item is! Map) continue;
            if (item['Visible'] == false) continue;

            final rawDate = _parseVulcanDate(item['DateAt'] ?? item['Date']);
            final dayKey = DateTime(rawDate.year, rawDate.month, rawDate.day);
            final dayIso = dayKey.toIso8601String();

            final slot = Map<String, dynamic>.from((item['TimeSlot'] as Map?) ?? {});
            final lessonNo = _int(slot['Position'], 1);
            final startParts = _str(slot['Start'], '08:00').split(':');
            final endParts = _str(slot['End'], '08:45').split(':');
            final hourFrom = DateTime(
              dayKey.year,
              dayKey.month,
              dayKey.day,
              int.tryParse(startParts[0]) ?? 8,
              int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0,
            );
            final hourTo = DateTime(
              dayKey.year,
              dayKey.month,
              dayKey.day,
              int.tryParse(endParts[0]) ?? 8,
              int.tryParse(endParts.length > 1 ? endParts[1] : '45') ?? 45,
            );

            final sub = item['Substitution'] as Map?;
            final change = (sub?['Change'] ?? item['Change']) as Map?;
            final changeType = _intOrNull(change?['Type']);
            final isCanceled = changeType == 1 || changeType == 4 || sub?['ClassAbsence'] == true;
            final modifiedSchedule = sub != null || change != null;

            final effectiveSubjectMap = sub?['Subject'] ?? item['Subject'];
            final effectiveTeacherMap = sub?['TeacherPrimary'] ?? item['TeacherPrimary'];
            final effectiveRoomMap = sub?['Room'] ?? item['Room'];

            final teacherJson = _teacherToJson(effectiveTeacherMap);
            final subjectJson = ensureSubject(effectiveSubjectMap, teacherJson);
            final roomCode = (effectiveRoomMap is Map) ? _str(effectiveRoomMap['Code']) : '';

            Map<String, dynamic>? subDetails;
            if (modifiedSchedule) {
              subDetails = {
                'originalUrl': '',
                'originalLessonNo': lessonNo,
                'originalDate': dayIso,
                'originalSubject': ensureSubject(item['Subject']),
                'originalTeacher': _teacherToJson(item['TeacherPrimary']),
              };
            }

            final subNote = sub?['Reason']?.toString() ??
                sub?['PupilNote']?.toString() ??
                item['Event']?.toString();

            final lessonObj = <String, dynamic>{
              'url': '',
              'lessonNo': lessonNo,
              'isCanceled': isCanceled,
              'lessonClass': mainClassLightJson,
              'subject': subjectJson,
              'teacher': teacherJson,
              'classroom': {
                'id': -1,
                'url': '',
                'name': roomCode,
                'symbol': roomCode,
              },
              'modifiedSchedule': modifiedSchedule,
              if (subNote != null) 'substitutionNote': subNote,
              if (subDetails != null) 'substitutionDetails': subDetails,
              'date': dayIso,
              'hourFrom': hourFrom.toIso8601String(),
              'hourTo': hourTo.toIso8601String(),
            };

            final daySlots = byDay.putIfAbsent(dayIso, () => <int, List<Map<String, dynamic>>>{});
            daySlots.putIfAbsent(lessonNo, () => <Map<String, dynamic>>[]).add(lessonObj);
          }

          byDay.forEach((dayIso, slotsMap) {
            var maxSlot = 0;
            slotsMap.forEach((k, _) {
              if (k > maxSlot) maxSlot = k;
            });
            final list = List<List<Map<String, dynamic>>?>.generate(
              maxSlot + 1,
              (idx) => slotsMap[idx],
            );
            timetableMap[dayIso] = {'lessons': list};
          });
        }
      } catch (_) {}

      reportProgress(0.8, localized('10B640EC-6CBF-42CF-A20B-7CA5E97E8AFE'));

      final attendancesJson = <Map<String, dynamic>>[];
      try {
        final attEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/lesson/byPupil',
          pupilId: pupilId,
          query: {
            'pupilId': pupilId.toString(),
            'dateFrom': _ymd(beginSchoolYear),
            'dateTo': _ymd(DateTime.now().add(const Duration(days: 2))),
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
        if (attEnv is List) {
          attendanceSucceeded = true;
          for (final a in attEnv) {
            if (a is! Map) continue;
            final presence = a['PresenceType'] as Map?;
            if (presence == null || presence['Removed'] == true) continue;

            var attType = 'other';
            if (presence['Presence'] == true) {
              attType = 'present';
            } else if (presence['Late'] == true) {
              attType = 'late';
            } else if (presence['AbsenceJustified'] == true) {
              attType = 'excused';
            } else if (presence['LegalAbsence'] == true) {
              attType = 'duty';
            } else if (presence['Absence'] == true) {
              attType = 'absent';
            }

            final date = _tryParseVulcanDate(a['DayAt']) ??
                _tryParseVulcanDate(a['Date']) ??
                _tryParseVulcanDate(a['DateAt']) ??
                _tryParseVulcanDate(a['Day']) ??
                _tryParseVulcanDate(a['LessonDate']) ??
                DateTime.now();
            final dayOnly = DateTime(date.year, date.month, date.day);
            final dayIso = dayOnly.toIso8601String();
            final addDate = _tryParseVulcanDate(a['ModifiedAt']) ??
                _tryParseVulcanDate(a['DateModify']) ??
                _tryParseVulcanDate(a['Date']) ??
                date;
            final lessonNo = _int(a['LessonNumber'], 1);
            final teacherJson = _teacherToJson(a['TeacherPrimary']);
            final subjectJson = ensureSubject(a['Subject'], teacherJson);
            final attId = _stablePositiveId(
              a['Id'] ?? a['LessonId'],
              '$dayIso:$lessonNo:$attType:${subjectJson['id']}',
            );

            attendancesJson.add({
              'id': attId,
              'lessonNo': lessonNo,
              'date': dayIso,
              'addDate': addDate.toIso8601String(),
              'type': attType,
              'teacher': teacherJson,
              'lesson': {
                'url': '',
                'lessonNo': lessonNo,
                'isCanceled': false,
                'modifiedSchedule': false,
                'subject': subjectJson,
                'teacher': teacherJson,
                'date': dayIso,
              },
            });
          }
        }
      } catch (ex) {
        coreFetchError ??= ex;
      }

      final eventsDateFrom = _ymd(beginSchoolYear);
      final eventsDateTo = _ymd(endSchoolYear.add(const Duration(days: 14)));
      final eventsJson = <Map<String, dynamic>>[];

      try {
        final examsEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/exam/byPupil',
          pupilId: pupilId,
          query: {
            'pupilId': pupilId.toString(),
            'dateFrom': eventsDateFrom,
            'dateTo': eventsDateTo,
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
        if (examsEnv is List) {
          for (final ex in examsEnv) {
            if (ex is! Map) continue;
            final typeStr = _str(ex['Type'], 'Sprawdzian');
            final deadline = _tryParseVulcanDate(ex['DeadlineAt']) ??
                _tryParseVulcanDate(ex['Deadline']) ??
                _tryParseVulcanDate(ex['Date']) ??
                _tryParseVulcanDate(ex['DateAt']) ??
                _tryParseVulcanDate(ex['DayAt']) ??
                _tryParseVulcanDate(ex['Day']) ??
                _tryParseVulcanDate(ex['CreatedAt']) ??
                _tryParseVulcanDate(ex['DateCreated']) ??
                beginSchoolYear;
            final created = _tryParseVulcanDate(ex['CreatedAt']) ??
                _tryParseVulcanDate(ex['DateCreated']) ??
                _tryParseVulcanDate(ex['ModifiedAt']) ??
                _tryParseVulcanDate(ex['DateModify']) ??
                deadline;
            final subject = ensureSubject(ex['Subject']);
            final lowType = typeStr.toLowerCase();
            final cat = lowType.contains('kartk')
                ? 'shortTest'
                : lowType.contains('klasow')
                    ? 'classWork'
                    : 'test';
            eventsJson.add({
              'id': _int(ex['Id']),
              'date': DateTime(deadline.year, deadline.month, deadline.day).toIso8601String(),
              'addDate': created.toIso8601String(),
              'timeFrom': deadline.toIso8601String(),
              'title': '${subject['name']} \u2022 $typeStr',
              'content': _str(ex['Content'], typeStr),
              'categoryName': typeStr,
              'category': cat,
              'done': false,
              'sender': _teacherToJson(ex['Creator']),
            });
          }
        }
      } catch (_) {}

      try {
        final hwEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/homework/byPupil',
          pupilId: pupilId,
          query: {
            'pupilId': pupilId.toString(),
            'dateFrom': eventsDateFrom,
            'dateTo': eventsDateTo,
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
        if (hwEnv is List) {
          for (final hw in hwEnv) {
            if (hw is! Map) continue;
            final deadline = _tryParseVulcanDate(hw['DeadlineAt']) ??
                _tryParseVulcanDate(hw['Deadline']) ??
                _tryParseVulcanDate(hw['DateAt']) ??
                _tryParseVulcanDate(hw['Date']) ??
                _tryParseVulcanDate(hw['AnswerAt']) ??
                _tryParseVulcanDate(hw['AnswerDeadline']) ??
                _tryParseVulcanDate(hw['DayAt']) ??
                _tryParseVulcanDate(hw['Day']) ??
                _tryParseVulcanDate(hw['CreatedAt']) ??
                _tryParseVulcanDate(hw['DateCreated']) ??
                beginSchoolYear;
            final created = _tryParseVulcanDate(hw['DateAt']) ??
                _tryParseVulcanDate(hw['CreatedAt']) ??
                _tryParseVulcanDate(hw['DateCreated']) ??
                _tryParseVulcanDate(hw['ModifiedAt']) ??
                _tryParseVulcanDate(hw['DateModify']) ??
                deadline;
            final subject = ensureSubject(hw['Subject']);
            eventsJson.add({
              'id': _int(hw['Id']),
              'date': DateTime(deadline.year, deadline.month, deadline.day).toIso8601String(),
              'addDate': created.toIso8601String(),
              'timeFrom': deadline.toIso8601String(),
              'timeTo': deadline.toIso8601String(),
              'title': subject['name'],
              'content': _str(hw['Content']),
              'categoryName': 'Zadanie domowe',
              'category': 'homework',
              'done': hw['AnswerDate'] != null,
              'sender': _teacherToJson(hw['Creator']),
            });
          }
        }
      } catch (_) {}

      if (!_hasTeacherName(homeTeacherJson)) {
        for (final sub in subjectsById.values) {
          final subNameLower = _str(sub['name']).toLowerCase();
          if (subNameLower.contains('wychowawc') ||
              subNameLower.contains('edukacja wczesnoszkolna')) {
            final subTeacher = sub['teacher'];
            if (subTeacher is Map && _hasTeacherName(subTeacher)) {
              homeTeacherJson = <String, dynamic>{
                'id': _int(subTeacher['id']),
                'url': _str(subTeacher['url']),
                'firstName': _str(subTeacher['firstName']),
                'lastName': _str(subTeacher['lastName']),
                'isHomeTeacher': true,
              };
              mainClassLightJson['classTutor'] = homeTeacherJson;
              break;
            }
          }
        }
      }

      final mainClassFullJson = <String, dynamic>{
        'id': mainClassLightJson['id'],
        'number': mainClassLightJson['number'],
        'symbol': mainClassLightJson['symbol'],
        'name': mainClassLightJson['name'],
        'beginSchoolYear': mainClassLightJson['beginSchoolYear'],
        'endFirstSemester': mainClassLightJson['endFirstSemester'],
        'endSchoolYear': mainClassLightJson['endSchoolYear'],
        'unit': unitJson,
        'classTutor': homeTeacherJson,
        'events': eventsJson,
        'averages': <String, dynamic>{},
      };

      var firstName = _str(pupilRaw['FirstName']);
      var lastName = _str(pupilRaw['Surname'] ?? pupilRaw['LastName']);
      if (firstName.isEmpty && pupilRaw['DisplayName'] != null) {
        final parts = pupilRaw['DisplayName'].toString().trim().split(' ');
        if (parts.isNotEmpty) firstName = parts.first;
        if (parts.length > 1) lastName = parts.sublist(1).join(' ');
      }
      if (firstName.isEmpty) firstName = _str(pupilRaw['Name'], 'Ucze\u0144');

      final pupilNumber = _intOrNull(journalRaw['PupilNumber']) ??
          _intOrNull(studentRaw['PupilNumber']) ??
          _intOrNull(pupilRaw['Number']) ??
          _intOrNull(pupilRaw['PupilNumber']) ??
          1;

      if (!gradesSucceeded && !attendanceSucceeded && coreFetchError != null) {
        return {'success': false, 'message': _errStr(coreFetchError)};
      }

      final prevStudent = _registerData['student'];
      var finalSubjects = subjectsById.values.toList();
      if (!gradesSucceeded && prevStudent is Map && prevStudent['subjects'] is List) {
        finalSubjects = (prevStudent['subjects'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      var finalAttendances = attendancesJson;
      if (!attendanceSucceeded && prevStudent is Map && prevStudent['attendances'] is List) {
        finalAttendances = (prevStudent['attendances'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      final studentJson = <String, dynamic>{
        'account': {
          'id': pupilId,
          'userId': _int(pupilRaw['LoginId'], pupilId),
          'number': pupilNumber,
          'firstName': firstName,
          'lastName': lastName,
        },
        'mainClass': mainClassFullJson,
        'subjects': finalSubjects,
        'attendances': finalAttendances,
      };

      final timetablesJson = <String, dynamic>{
        'timetable': timetableMap,
      };

      _registerData['student'] = studentJson;
      _registerData['timetables'] = timetablesJson;
      setRegisterDataJson({
        'student': studentJson,
        'timetables': timetablesJson,
      });

      return {'success': true};
    } catch (ex) {
      return {'success': false, 'message': _errStr(ex)};
    }
  }

  @override
  Future<Map<String, dynamic>> refreshMessages() async {
    if (_sampleDriver != null) {
      return await _sampleDriver!.refreshMessages();
    }
    if (_restUrl == null || _activeStudentRaw == null) {
      return {'success': false, 'message': localized('C5FDD0D8-771D-4DCE-8FCE-62D1BA4A6C93')};
    }

    try {
      reportProgress(0.2, localized('135991AA-5B53-42EA-8A2B-5406B249CC40'));
      final active = _activeStudentRaw!;
      final pupilMap = active['Pupil'];
      final pupilId = pupilMap is Map ? _int(pupilMap['Id']) : -1;
      final mb = active['MessageBox'];
      final boxKey = mb is Map ? _str(mb['GlobalKey']) : '';
      if (boxKey.isEmpty && _topLevelPartition.isEmpty) {
        final emptyMessages = <String, dynamic>{
          'receivers': <Map<String, dynamic>>[],
          'received': <Map<String, dynamic>>[],
          'sent': <Map<String, dynamic>>[],
        };
        _registerData['messages'] = emptyMessages;
        setRegisterDataJson({'messages': emptyMessages});
        return {'success': true};
      }

      final receiversJson = <Map<String, dynamic>>[];
      try {
        final addrEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/addressbook',
          pupilId: pupilId,
          query: {'box': boxKey},
        );
        if (addrEnv is List) {
          for (var i = 0; i < addrEnv.length; i++) {
            final entry = addrEnv[i];
            if (entry is Map) {
              receiversJson.add({
                'id': i + 1,
                'url': _str(entry['GlobalKey']),
                'firstName': _str(entry['Name']),
                'lastName': _str(entry['Group']),
              });
            }
          }
        }
      } catch (_) {}

      final prevMessages = _registerData['messages'] is Map
          ? _registerData['messages'] as Map
          : <String, dynamic>{};
      final prevReceived = <Map<String, dynamic>>[];
      if (prevMessages['received'] is List) {
        for (final x in prevMessages['received'] as List) {
          if (x is Map) prevReceived.add(Map<String, dynamic>.from(x));
        }
      }
      final prevSent = <Map<String, dynamic>>[];
      if (prevMessages['sent'] is List) {
        for (final x in prevMessages['sent'] as List) {
          if (x is Map) prevSent.add(Map<String, dynamic>.from(x));
        }
      }

      Map<String, dynamic>? findPrevMsg(List<Map<String, dynamic>> prevList, int msgId, String msgUrl) {
        for (final ex in prevList) {
          final exUrl = _str(ex['url']);
          if ((msgUrl.isNotEmpty && exUrl == msgUrl) || (msgId != -1 && _int(ex['id']) == msgId)) {
            return ex;
          }
        }
        return null;
      }

      List<Map<String, dynamic>> mapMessages(dynamic env, {required bool sent}) {
        if (env is! List) return <Map<String, dynamic>>[];
        final out = <Map<String, dynamic>>[];
        for (final m in env) {
          if (m is! Map) continue;
          final senderMap = m['Sender'] as Map?;
          final recList = (m['Receiver'] as List?) ?? <dynamic>[];
          final attachmentsRaw = (m['Attachments'] as List?) ?? <dynamic>[];
          final content = _cleanHtml(_str(m['Content']));
          final sendDate = _extractMessageSendDate(m);
          final readDate = _extractMessageReadDate(
            m,
            sendDate: sendDate,
            sent: sent,
            boxKey: boxKey,
          );
          final msgId = (m['Id'] is num)
              ? (m['Id'] as num).toInt()
              : (m['Id']?.toString().hashCode ?? m['GlobalKey']?.toString().hashCode ?? -1);
          final msgUrl = _str(m['GlobalKey']);
          final existingMsg = sent ? null : findPrevMsg(prevReceived, msgId, msgUrl);
          final effectiveReadIso = readDate?.toIso8601String() ?? existingMsg?['readDate']?.toString();

          final attachmentsJson = <Map<String, dynamic>>[];
          for (final a in attachmentsRaw) {
            if (a is Map) {
              attachmentsJson.add({
                'name': _str(a['Name'], 'Za\u0142\u0105cznik'),
                'location': _str(a['Link']),
              });
            }
          }

          final receiversOut = <Map<String, dynamic>>[];
          if (sent) {
            for (final r in recList) {
              if (r is Map) {
                receiversOut.add({
                  'id': -1,
                  'url': _str(r['GlobalKey']),
                  'firstName': _str(r['Name']),
                  'lastName': '',
                });
              }
            }
          }

          out.add({
            'id': msgId,
            'url': msgUrl,
            'topic': _str(m['Subject']),
            'content': content,
            'preview': content,
            'sendDate': sendDate.toIso8601String(),
            if (effectiveReadIso != null) 'readDate': effectiveReadIso,
            'hasAttachments': attachmentsRaw.isNotEmpty,
            'attachments': attachmentsJson,
            if (!sent)
              'sender': {
                'id': -1,
                'url': _str(senderMap?['GlobalKey']),
                'firstName': _str(senderMap?['Name'], 'Nadawca'),
                'lastName': '',
              },
            if (sent) 'receivers': receiversOut,
          });
        }
        return out;
      }

      dynamic inboxEnv;
      try {
        inboxEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/messages/received/byBox',
          pupilId: pupilId,
          query: {
            'box': boxKey,
            'pupilId': pupilId.toString(),
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
      } catch (_) {}

      dynamic sentEnv;
      try {
        sentEnv = await _hebeRequest(
          method: 'GET',
          restUrl: _restUrl!,
          endpoint: 'mobile/messages/sent/byBox',
          pupilId: pupilId,
          query: {
            'box': boxKey,
            'pupilId': pupilId.toString(),
            'lastId': '-2147483648',
            'pageSize': '500',
          },
        );
      } catch (_) {}

      var received = mapMessages(inboxEnv, sent: false);
      var sent = mapMessages(sentEnv, sent: true);

      if (received.isEmpty && _proxyUrl.isNotEmpty && _topLevelPartition.isNotEmpty) {
        try {
          final webInboxRes = await _http.post(
            _proxyUrl,
            body: jsonEncode({
              'action': 'eduvulcan_fetch_messages',
              'login': _savedUsername,
              'password': _savedPassword,
              'partition': _topLevelPartition,
              'mailboxKey': boxKey,
              'folder': 'Odebrane',
              'idLastWiadomosc': 0,
              'pageSize': 50,
            }),
            headers: const {'Content-Type': 'application/json'},
          );
          final parsed = webInboxRes.json;
          final rawData = parsed is Map ? (parsed['data'] ?? parsed) : webInboxRes.body;
          final rawList = rawData is List
              ? rawData
              : (rawData is Map && rawData['data'] is List ? rawData['data'] as List : null);
          if (rawList != null) {
            final webReceived = <Map<String, dynamic>>[];
            for (final m in rawList) {
              if (m is! Map) continue;
              final msgId = (m['id'] is num)
                  ? (m['id'] as num).toInt()
                  : (m['apiGlobalKey']?.toString().hashCode ?? -1);
              final msgUrl = _str(m['apiGlobalKey'], msgId.toString());
              final dateParsed = _extractMessageSendDate(m);
              final readDateParsed = _extractMessageReadDate(
                m,
                sendDate: dateParsed,
                sent: false,
                boxKey: boxKey,
              );
              final existingMsg = findPrevMsg(prevReceived, msgId, msgUrl);
              final rawBody = _str(m['tresc'] ?? m['content'] ?? m['trescHtml']);
              final cleanedBody = _cleanHtml(rawBody);
              final existingBody = _cleanHtml(_str(existingMsg?['content']));
              final effectiveContent = cleanedBody.isNotEmpty ? cleanedBody : existingBody;
              final topicStr = _str(m['temat'], '(Bez tematu)');
              final effectiveReadIso = readDateParsed?.toIso8601String() ?? existingMsg?['readDate']?.toString();
              webReceived.add({
                'id': msgId,
                'url': msgUrl,
                'topic': topicStr,
                'content': effectiveContent,
                'preview': effectiveContent.isNotEmpty ? effectiveContent : topicStr,
                'sendDate': dateParsed.toIso8601String(),
                if (effectiveReadIso != null) 'readDate': effectiveReadIso,
                'hasAttachments': m['hasZalaczniki'] == true || m['czyZalaczniki'] == true,
                if (existingMsg?['attachments'] != null) 'attachments': existingMsg!['attachments'],
                'sender': {
                  'id': -1,
                  'url': _str(m['apiGlobalKey']),
                  'firstName': _str(m['korespondenci'] ?? m['nadawca'], 'Nadawca'),
                  'lastName': '',
                },
              });
            }
            if (webReceived.isNotEmpty) {
              received = webReceived;
            }
          }
        } catch (_) {}

        try {
          final webSentRes = await _http.post(
            _proxyUrl,
            body: jsonEncode({
              'action': 'eduvulcan_fetch_messages',
              'login': _savedUsername,
              'password': _savedPassword,
              'partition': _topLevelPartition,
              'mailboxKey': boxKey,
              'folder': 'Wyslane',
              'idLastWiadomosc': 0,
              'pageSize': 50,
            }),
            headers: const {'Content-Type': 'application/json'},
          );
          final parsed = webSentRes.json;
          final rawData = parsed is Map ? (parsed['data'] ?? parsed) : webSentRes.body;
          final rawList = rawData is List
              ? rawData
              : (rawData is Map && rawData['data'] is List ? rawData['data'] as List : null);
          if (rawList != null) {
            final webSent = <Map<String, dynamic>>[];
            for (final m in rawList) {
              if (m is! Map) continue;
              final msgId = (m['id'] is num)
                  ? (m['id'] as num).toInt()
                  : (m['apiGlobalKey']?.toString().hashCode ?? -1);
              final msgUrl = _str(m['apiGlobalKey'], msgId.toString());
              final dateParsed = _extractMessageSendDate(m);
              final existingMsg = findPrevMsg(prevSent, msgId, msgUrl);
              final rawBody = _str(m['tresc'] ?? m['content'] ?? m['trescHtml']);
              final cleanedBody = _cleanHtml(rawBody);
              final existingBody = _cleanHtml(_str(existingMsg?['content']));
              final effectiveContent = cleanedBody.isNotEmpty ? cleanedBody : existingBody;
              final topicStr = _str(m['temat'], '(Bez tematu)');
              webSent.add({
                'id': msgId,
                'url': msgUrl,
                'topic': topicStr,
                'content': effectiveContent,
                'preview': effectiveContent.isNotEmpty ? effectiveContent : topicStr,
                'sendDate': dateParsed.toIso8601String(),
                'readDate': dateParsed.toIso8601String(),
                'hasAttachments': m['hasZalaczniki'] == true || m['czyZalaczniki'] == true,
                if (existingMsg?['attachments'] != null) 'attachments': existingMsg!['attachments'],
                'receivers': [
                  {
                    'id': -1,
                    'url': _str(m['apiGlobalKey']),
                    'firstName': _str(m['korespondenci'] ?? m['adresaci'], 'Odbiorca'),
                    'lastName': '',
                  }
                ],
              });
            }
            if (webSent.isNotEmpty) {
              sent = webSent;
            }
          }
        } catch (_) {}
      }

      if (received.isEmpty && prevReceived.isNotEmpty) {
        received = prevReceived;
      }
      if (sent.isEmpty && prevSent.isNotEmpty) {
        sent = prevSent;
      }

      if (receiversJson.isEmpty) {
        final seenNames = <String>{};
        for (final m in received) {
          final sender = m['sender'];
          if (sender is Map) {
            final name = '${_str(sender['firstName'])} ${_str(sender['lastName'])}'.trim();
            if (name.isNotEmpty && seenNames.add(name)) {
              receiversJson.add(Map<String, dynamic>.from(sender));
            }
          }
        }
      }

      final messagesJson = <String, dynamic>{
        'receivers': receiversJson,
        'received': received,
        'sent': sent,
      };
      _registerData['messages'] = messagesJson;
      setRegisterDataJson({'messages': messagesJson});

      return {'success': true};
    } catch (_) {
      if (_registerData['messages'] == null) {
        final emptyMessages = <String, dynamic>{
          'receivers': <Map<String, dynamic>>[],
          'received': <Map<String, dynamic>>[],
          'sent': <Map<String, dynamic>>[],
        };
        _registerData['messages'] = emptyMessages;
        setRegisterDataJson({'messages': emptyMessages});
      }
      return {'success': true};
    }
  }

  @override
  Future<Map<String, dynamic>> sendMessage(
    List<Map<String, dynamic>> receivers,
    String topic,
    String content,
  ) async {
    if (_sampleDriver != null) {
      return await _sampleDriver!.sendMessage(receivers, topic, content);
    }

    try {
      final active = _activeStudentRaw;
      final pupilMap = active?['Pupil'];
      final pupilId = pupilMap is Map ? _intOrNull(pupilMap['Id']) : null;
      final mb = active?['MessageBox'];
      final boxKey = mb is Map ? _str(mb['GlobalKey']) : '';
      final senderName = (mb is Map ? _str(mb['Name']) : '').isNotEmpty
          ? _str(mb['Name'])
          : 'Ucze\u0144';
      final now = DateTime.now();

      await _hebeRequest(
        method: 'POST',
        restUrl: _restUrl!,
        endpoint: 'mobile/messages',
        pupilId: pupilId,
        payload: {
          'Id': uuidV4(),
          'GlobalKey': uuidV4(),
          'ThreadKey': uuidV4(),
          'Sender': {
            'GlobalKey': boxKey,
            'Name': senderName,
            'HasRead': 1,
          },
          'Receiver': receivers
              .map((r) => {
                    'GlobalKey': _str(r['url']),
                    'Name': '${_str(r['firstName'])} ${_str(r['lastName'])}'.trim(),
                    'HasRead': 0,
                  })
              .toList(),
          'Subject': topic,
          'Content': content,
          'DateSent': {
            'Date': _ymd(now),
            'Time': _hms(now),
            'Timestamp': now.millisecondsSinceEpoch,
          },
          'Status': 1,
          'Attachments': <dynamic>[],
        },
      );
      return {'success': true};
    } catch (ex) {
      return {'success': false, 'message': _errStr(ex)};
    }
  }

  @override
  Future<Map<String, dynamic>> fetchMessageContent(Map<String, dynamic> parent, bool byMe) async {
    if (_sampleDriver != null) {
      return await _sampleDriver!.fetchMessageContent(parent, byMe);
    }

    try {
      final hasReadDate = parent['readDate'] != null &&
          parent['readDate'].toString().isNotEmpty &&
          !parent['readDate'].toString().startsWith('2000-01-01');
      final isRead = byMe || hasReadDate;
      final parentUrl = _str(parent['url']);

      if (!byMe && !isRead && parentUrl.isNotEmpty && _restUrl != null) {
        try {
          final active = _activeStudentRaw;
          final pupilMap = active?['Pupil'];
          final pupilId = pupilMap is Map ? _intOrNull(pupilMap['Id']) : null;
          final mb = active?['MessageBox'];
          final boxKey = mb is Map ? _str(mb['GlobalKey']) : '';
          await _hebeRequest(
            method: 'POST',
            restUrl: _restUrl!,
            endpoint: 'mobile/messages/status',
            pupilId: pupilId,
            payload: {
              'BoxKey': boxKey,
              'MessageKey': parentUrl,
              'Status': 1,
            },
          );
        } catch (_) {}
      }

      var effectiveContent = _cleanHtml(_str(parent['content']));
      var effectiveAttachments = parent['attachments'] is List
          ? List<dynamic>.from(parent['attachments'] as List)
          : null;

      if (effectiveContent.isEmpty && _proxyUrl.isNotEmpty && _topLevelPartition.isNotEmpty) {
        try {
          final detRes = await _http.post(
            _proxyUrl,
            body: jsonEncode({
              'action': 'eduvulcan_fetch_message_content',
              'login': _savedUsername,
              'password': _savedPassword,
              'partition': _topLevelPartition,
              'id': _int(parent['id']),
              'apiGlobalKey': parentUrl,
            }),
            headers: const {'Content-Type': 'application/json'},
          );
          final parsed = detRes.json;
          final d = parsed is Map ? (parsed['data'] ?? parsed) : detRes.body;
          if (d is Map) {
            final rawBody = _str(d['tresc'] ?? d['content'] ?? d['trescHtml']);
            if (rawBody.isNotEmpty) {
              effectiveContent = _cleanHtml(rawBody);
            }
            final attachmentsRaw = (d['zalaczniki'] ?? d['Attachments']) as List?;
            if (attachmentsRaw != null && attachmentsRaw.isNotEmpty) {
              final mapped = <Map<String, dynamic>>[];
              for (final a in attachmentsRaw) {
                if (a is Map) {
                  mapped.add({
                    'name': _str(a['nazwaPliku'] ?? a['nazwa'] ?? a['Name'], 'Za\u0142\u0105cznik'),
                    'location': _str(a['url'] ?? a['Link']),
                  });
                }
              }
              effectiveAttachments = mapped;
            }
          }
        } catch (_) {}
      }

      if (effectiveContent.isEmpty) {
        final preview = _str(parent['preview']);
        effectiveContent = preview.isNotEmpty ? _cleanHtml(preview) : _str(parent['topic']);
      }

      final updated = Map<String, dynamic>.from(parent);
      updated['content'] = effectiveContent;
      if (updated['readDate'] == null) {
        updated['readDate'] = DateTime.now().toIso8601String();
      }
      if (effectiveAttachments != null) {
        updated['attachments'] = effectiveAttachments;
        updated['hasAttachments'] = effectiveAttachments.isNotEmpty || parent['hasAttachments'] == true;
      }

      return {'success': true, 'result': updated};
    } catch (ex) {
      return {'success': false, 'message': _errStr(ex), 'result': parent};
    }
  }

  @override
  Future<Map<String, dynamic>> moveMessageToTrash(Map<String, dynamic> parent, bool byMe) async {
    if (_sampleDriver != null) {
      return await _sampleDriver!.moveMessageToTrash(parent, byMe);
    }

    try {
      final active = _activeStudentRaw;
      final pupilMap = active?['Pupil'];
      final pupilId = pupilMap is Map ? _intOrNull(pupilMap['Id']) : null;
      final mb = active?['MessageBox'];
      final boxKey = mb is Map ? _str(mb['GlobalKey']) : '';
      await _hebeRequest(
        method: 'POST',
        restUrl: _restUrl!,
        endpoint: 'mobile/messages/status',
        pupilId: pupilId,
        payload: {
          'BoxKey': boxKey,
          'MessageKey': _str(parent['url']),
          'Status': 2,
        },
      );
      return {'success': true};
    } catch (ex) {
      return {'success': false, 'message': _errStr(ex)};
    }
  }

  @override
  Future<Map<String, dynamic>> markEventAsViewed(Map<String, dynamic> parent) async {
    if (_sampleDriver != null) return await _sampleDriver!.markEventAsViewed(parent);
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> markEventAsDone(Map<String, dynamic> parent) async {
    if (_sampleDriver != null) return await _sampleDriver!.markEventAsDone(parent);
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> markAnnouncementAsViewed(Map<String, dynamic> parent) async {
    if (_sampleDriver != null) return await _sampleDriver!.markAnnouncementAsViewed(parent);
    return {'success': true};
  }

  @override
  Map<String, dynamic> getRegisterDataJson() => _registerData;
}

EduVulcanExtension main(dynamic source) {
  return EduVulcanExtension(source: source as OSource);
}
