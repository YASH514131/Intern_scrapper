import 'dart:io';

import 'package:shelf/shelf_io.dart';
import 'package:nexus_api/nexus_api.dart';

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;
  final api = NexusApi();

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(api.handler, ip, port);
  print('Server listening on port ${server.port}');
}
