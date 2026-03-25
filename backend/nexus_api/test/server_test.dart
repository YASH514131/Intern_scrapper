import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  final port = '8080';
  final host = 'http://127.0.0.1:$port';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );
    // Wait for server to start and print to stdout.
    await p.stdout.first;
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
