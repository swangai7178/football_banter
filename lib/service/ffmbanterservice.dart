import 'dart:convert';
import 'package:http/http.dart' as http;
class Ffmbanterservice {

Future<Map<String, dynamic>> fetchLeagueStandings(int leagueId) async {
  final url = Uri.parse("https://fantasy.premierleague.com/api/leagues-classic/$leagueId/standings/");
  final response = await http.get(url);
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to fetch league standings: ${response.statusCode}");
  }
}

Future<Map<String, dynamic>> fetchManagerEntry(int managerId) async {
  final url = Uri.parse("https://fantasy.premierleague.com/api/entry/$managerId/");
  final response = await http.get(url);
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to fetch manager entry: ${response.statusCode}");
  }
}

Future<List<Map<String, dynamic>>> getLeagueBanter(Map<String, dynamic> leagueData) async {
  final leagueName = leagueData["league"]["name"];
  final standings = leagueData["standings"]["results"] as List;

  final teamsInfo = standings
      .map((team) =>
          "${team["entry_name"]} managed by ${team["player_name"]} – ${team["total"]} pts (Rank ${team["rank"]})")
      .join("\n");

  final url = Uri.parse('http://127.0.0.1:11434/api/chat');

  final res = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      "model": "qwen3:8b",
      "messages": [
        {
          "role": "system",
          "content":
              "You're a witty football pundit. Respond ONLY in JSON. Output an array of banter items where each has 'title' and 'description'. Include jokes about the top and bottom teams."
        },
        {
          "role": "user",
          "content": "League: $leagueName\nTeams:\n$teamsInfo"
        }
      ],
      "stream": false
    }),
  );

  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    final raw = data["message"]?["content"] ?? '[]';

    // Remove <think> tags if Qwen adds them
    final cleaned =
        raw.replaceAll(RegExp(r"<think>[\s\S]*?</think>"), "").trim();

    dynamic parsed;
    try {
      parsed = jsonDecode(cleaned);
    } catch (e) {
      print("❌ JSON decode failed: $e");
      return [];
    }

    if (parsed is Map<String, dynamic>) parsed = [parsed];
    if (parsed is! List) return [];

    return parsed.map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item)).toList();
  } else {
    return [
      {
        "title": "Error",
        "description": "AI returned error: ${res.statusCode}"
      }
    ];
  }
}


}