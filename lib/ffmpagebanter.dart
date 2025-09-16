import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LeagueBanterPage extends StatefulWidget {
  const LeagueBanterPage({super.key});

  @override
  State<LeagueBanterPage> createState() => _LeagueBanterPageState();
}

class _LeagueBanterPageState extends State<LeagueBanterPage> {
  final TextEditingController _leagueIdController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _banterItems = [];
  Map<String, dynamic>? _leagueData;

  /// Fetch league standings from FPL API
  Future<Map<String, dynamic>> fetchLeagueStandings(int leagueId) async {
    final url = Uri.parse(
        "https://fantasy.premierleague.com/api/leagues-classic/$leagueId/standings/");
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          "Failed to fetch league standings: ${response.statusCode}");
    }
  }

  /// Send the standings to Qwen to get witty banter
  Future<List<Map<String, dynamic>>> getLeagueBanter(
    Map<String, dynamic> leagueData) async {
  final leagueName = leagueData["league"]["name"];
  final standings = leagueData["standings"]["results"] as List;

  // Build a text summary of teams for the AI prompt
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
    {"role":"system","content":"You are a savage, witty football pundit. For each team you’re given, output a JSON object with 'title' and 'description'. In 'title', write a funny, over-the-top nickname for the team (make it catchy). In 'description', write a long, detailed, trash-talking paragraph (at least 4–5 sentences) that roasts that team mercilessly, compares them to other teams/managers in the list, and especially humiliates the lowest-ranked clubs as if they’re allergic to winning. Make it heavy enough to sting. Return only a plain JSON array (no object wrapping, no markdown, no text before/after). Use only standard quotes. At most 5 items. Do not include code fences, commentary, or any non-JSON characters."},


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

    final parsed = _safeDecodeList(raw);
    return parsed;
  } else {
    return [
      {
        "title": "Error",
        "description": "AI returned error: ${res.statusCode}"
      }
    ];
  }
}

List<Map<String, dynamic>> _safeDecodeList(String raw) {
  // 1. Strip out <think> sections and similar hidden blocks
  String cleaned =
      raw.replaceAll(RegExp(r"<think>[\s\S]*?</think>", dotAll: true), "").trim();

  // 2. Strip markdown/code fences
  cleaned = cleaned
      .replaceAll(RegExp(r"^```json", multiLine: true), "")
      .replaceAll(RegExp(r"^```", multiLine: true), "")
      .replaceAll(RegExp(r"```$", multiLine: true), "")
      .trim();

  // 3. Normalise quotes/apostrophes and other weird punctuation
  cleaned = cleaned
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‟', '"')
      .replaceAll('„', '"')
      .replaceAll('’', "'")
      .replaceAll('`', "'");

  // 4. Remove BOM if present
  cleaned = cleaned.replaceAll(RegExp(r'^\uFEFF'), '');

  // 5. Strip trailing commas inside objects/arrays (very common LLM mistake)
  cleaned = cleaned.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');

  // 6. Fix known bad key patterns (double or spaced quotes)
  cleaned = cleaned.replaceAll(RegExp(r'""title"'), '"title"');
  cleaned = cleaned.replaceAll(RegExp(r'" "title"'), '"title"');
  cleaned = cleaned.replaceAll(RegExp(r'" "description"'), '"description"');

  // Debug print cleaned string if needed
  debugPrint('Cleaned AI output:\n$cleaned');

  // 7. Try full decode first
  try {
    final decoded = jsonDecode(cleaned);
    if (decoded is List) {
      return decoded
          .whereType<Map>() // only maps
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
  } catch (e) {
    debugPrint("Full decode failed, falling back: $e");
  }

  // 8. Fallback: extract each JSON object individually
  // Regex matches { ... } across multiple lines/nested braces
  final regex = RegExp(r'\{(?:[^{}]|(?R))*\}', dotAll: true, multiLine: true);
  final List<Map<String, dynamic>> items = [];

  for (final match in regex.allMatches(cleaned)) {
    final objText = match.group(0);
    if (objText != null) {
      try {
        final obj = jsonDecode(objText);
        if (obj is Map<String, dynamic>) {
          items.add(Map<String, dynamic>.from(obj));
        }
      } catch (e) {
        debugPrint("Skipping bad object: $e\n$objText");
      }
    }
  }

  // 9. Fallback if nothing worked
  if (items.isEmpty) {
    return [
      {
        'title': 'Error',
        'description':
            'Could not parse AI output into valid JSON. Cleaned string:\n$cleaned'
      }
    ];
  }

  return items;
}


  /// Button handler
  Future<void> _generateBanter() async {
    final text = _leagueIdController.text.trim();
    if (text.isEmpty) return;
    final id = int.tryParse(text);
    if (id == null) {
      setState(() => _error = "Please enter a valid number");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _banterItems = [];
      _leagueData = null;
    });

    try {
      final leagueData = await fetchLeagueStandings(id);
      final banter = await getLeagueBanter(leagueData);
      setState(() {
        _leagueData = leagueData;
        _banterItems = banter;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagueName = _leagueData?["league"]?["name"];
    final standings = _leagueData?["standings"]?["results"] as List?;

    return Scaffold(
  backgroundColor: Colors.grey[100],
  appBar: AppBar(
    backgroundColor: Colors.red[700],
    title: const Text(
      '⚽ League Banter',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    centerTitle: true,
    elevation: 0,
  ),
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // input card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter League ID',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _leagueIdController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g. 12345',
                    filled: true,
                    fillColor: Colors.grey[200],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loading ? null : _generateBanter,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            '🔥 Generate Banter',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Banter list
        if (_banterItems.isNotEmpty)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📰 Today’s Tabloid Banter',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _banterItems.length,
                    itemBuilder: (context, index) {
                      final item = _banterItems[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item["title"] ?? "",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[700],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item["description"] ?? "",
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  ),
);

  }
}
