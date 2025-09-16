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

  List<List<Map<String, dynamic>>> _chunkStandings(List standings, int size) {
  final chunks = <List<Map<String, dynamic>>>[];
  for (var i = 0; i < standings.length; i += size) {
    chunks.add(
      standings.sublist(i, i + size > standings.length ? standings.length : i + size)
          .cast<Map<String, dynamic>>(),
    );
  }
  return chunks;
}


  /// Send the standings to Qwen to get witty banter
  Future<List<Map<String, dynamic>>> getLeagueBanter(Map<String, dynamic> leagueData) async {
  final leagueName = leagueData["league"]["name"];
  final standings = leagueData["standings"]["results"] as List;

  // break into groups of 10 teams to keep AI fast
  final chunks = _chunkStandings(standings, 10);

  final futures = chunks.map((chunk) async {
    final teamsInfo = chunk
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
                "You are a savage, witty football pundit writing like a scandal-hungry tabloid. For each team you’re given, output one JSON object with 'title' and 'description'. In 'title', write a sensational headline about the club’s situation (no manager names). In 'description', write a vivid, multi-sentence roast (4–6 sentences) that mocks the manager and players by name, comparing them to other teams. Humiliate the lowest-ranked clubs while referencing the top team’s dominance. Make it read like a scandal article. Return only a plain JSON array, up to 10 items."
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
      return _safeDecodeList(raw);
    } else {
      return [
        {
          "title": "Error",
          "description": "AI returned error: ${res.statusCode}"
        }
      ];
    }
  }).toList();

  // run all chunk calls at once
  final results = await Future.wait(futures);

  // merge all arrays into one
  return results.expand((x) => x).toList();
}


List<Map<String, dynamic>> _safeDecodeList(String raw) {
  String cleaned =
      raw.replaceAll(RegExp(r"<think>[\s\S]*?</think>", dotAll: true), "").trim();
  cleaned = cleaned
      .replaceAll(RegExp(r"^```json", multiLine: true), "")
      .replaceAll(RegExp(r"^```", multiLine: true), "")
      .replaceAll(RegExp(r"```$", multiLine: true), "")
      .trim();
  cleaned = cleaned
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‟', '"')
      .replaceAll('„', '"')
      .replaceAll('’', "'")
      .replaceAll('`', "'");
  cleaned = cleaned.replaceAll(RegExp(r'^\uFEFF'), '');
  cleaned = cleaned.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
  cleaned = cleaned.replaceAll(RegExp(r'""title"'), '"title"');
  cleaned = cleaned.replaceAll(RegExp(r'" "title"'), '"title"');
  cleaned = cleaned.replaceAll(RegExp(r'" "description"'), '"description"');
  debugPrint('Cleaned AI output:\n$cleaned');
  try {
    final decoded = jsonDecode(cleaned);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
  } catch (e) {
    debugPrint("Full decode failed, falling back: $e");
  }
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
