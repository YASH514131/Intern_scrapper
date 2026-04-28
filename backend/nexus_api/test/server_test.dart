import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  late String port;
  late String host;
  late Process p;

  setUp(() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port.toString();
    await probe.close();
    host = 'http://127.0.0.1:$port';

    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );

    var ready = false;
    for (var i = 0; i < 50; i++) {
      final exitProbe = await p.exitCode.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => -1,
      );
      if (exitProbe != -1) break;
      try {
        final response = await get(Uri.parse('$host/health'));
        if (response.statusCode == 200) {
          ready = true;
          break;
        }
      } catch (_) {
        // Server is still booting.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (!ready) {
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      fail('Server did not become ready. stdout=$out stderr=$err');
    }
  });

  tearDown(() => p.kill());

  test('Health endpoint', () async {
    final response = await get(Uri.parse('$host/health'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['ok'], true);
    expect(body['service'], 'nexus_api');
  });

  test('404', () async {
    final response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });
}
