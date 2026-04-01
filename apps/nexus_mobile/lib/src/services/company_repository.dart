import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/default_companies.dart';

class CompanyRepository {
  static const String _companyMapKey = 'company_url_map';

  Future<Map<String, String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureSeeded(prefs);
    final raw = prefs.getString(_companyMapKey) ?? '{}';
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final mapped = <String, String>{};
    for (final entry in decoded.entries) {
      final key = entry.key.trim();
      final value = entry.value.toString().trim();
      if (key.isEmpty || value.isEmpty) continue;
      mapped[key] = value;
    }
    return mapped;
  }

  Future<Map<String, String>> merge(Map<String, String> newEntries) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureSeeded(prefs);
    final current = await getAll();

    for (final entry in newEntries.entries) {
      final k = entry.key.trim();
      final v = entry.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      current[k] = v;
    }

    await prefs.setString(_companyMapKey, jsonEncode(current));
    return current;
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_companyMapKey, jsonEncode(defaultCompanyUrls));
  }

  Future<void> _ensureSeeded(SharedPreferences prefs) async {
    if (prefs.containsKey(_companyMapKey)) return;
    await prefs.setString(_companyMapKey, jsonEncode(defaultCompanyUrls));
  }
}
