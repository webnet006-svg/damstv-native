import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DamsTvApp());
}

/// Modèle pour représenter une chaîne TV ou une station Radio.
class Channel {
  final String id;
  final String name;
  final String url;
  final String? logo;
  final String? group;
  final bool isRadio;

  Channel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.isRadio = false,
    String? id,
  }) : id = id ?? url;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'logo': logo,
        'group': group,
        'isRadio': isRadio,
      };

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Chaîne',
        url: json['url'] as String? ?? '',
        logo: json['logo'] as String?,
        group: json['group'] as String?,
        isRadio: json['isRadio'] as bool? ?? false,
      );
}

class DamsTvApp extends StatelessWidget {
  const DamsTvApp({super.key});

  static const Color bgDark = Color(0xFF060B18);
  static const Color surfaceDark = Color(0xFF151B28);
  static const Color surfaceCard = Color(0xFF1E2636);
  static const Color primaryBlue = Color(0xFF2F6BFF);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color textLight = Color(0xFFF1F5F9);
  static const Color textMuted = Color(0xFF8B97AD);
  static const Color borderDark = Color(0xFF26304A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAMS TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        primaryColor: accentCyan,
        colorScheme: const ColorScheme.dark(
          primary: accentCyan,
          secondary: primaryBlue,
          surface: surfaceDark,
          background: bgDark,
          onPrimary: bgDark,
          onSecondary: Colors.white,
          onSurface: textLight,
          onBackground: textLight,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1220),
          foregroundColor: textLight,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surfaceDark,
          selectedItemColor: accentCyan,
          unselectedItemColor: textMuted,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        cardTheme: CardTheme(
          color: surfaceDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: borderDark, width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceDark,
          hintStyle: const TextStyle(color: textMuted, fontSize: 14),
          prefixIconColor: accentCyan,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderDark),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderDark),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accentCyan, width: 1.5),
          ),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final Map<String, Channel> _favorites = {};

  // Contrôleurs & données onglet TV
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tvSearchController = TextEditingController();
  bool _isLoadingTv = false;
  String? _tvErrorMessage;
  List<Channel> _allTvChannels = [];
  List<Channel> _filteredTvChannels = [];
  bool _showM3uPanel = true;

  // Contrôleurs & données onglet Radio
  final TextEditingController _radioSearchController = TextEditingController();
  bool _isLoadingRadio = false;
  String? _radioErrorMessage;
  List<Channel> _allRadios = [];
  List<Channel> _filteredRadios = [];
  String _radioFilter = 'top'; // 'top', 'fr', 'afrique'

  // Filtre Favoris
  String _favFilter = 'all'; // 'all', 'tv', 'radio'

  @override
  void initState() {
    super.initState();
    _loadStoredData();
    _tvSearchController.addListener(_filterTvChannels);
    _radioSearchController.addListener(_filterRadioChannels);
    _fetchDefaultRadios();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tvSearchController.dispose();
    _radioSearchController.dispose();
    super.dispose();
  }

  /// Chargement des favoris et de la dernière playlist stockés dans SharedPreferences
  Future<void> _loadStoredData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Charger les favoris
      final favsString = prefs.getString('damstv_favorites');
      if (favsString != null && favsString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(favsString);
        setState(() {
          for (var item in decoded) {
            final channel = Channel.fromJson(item as Map<String, dynamic>);
            _favorites[channel.url] = channel;
          }
        });
      }

      // Charger la dernière URL M3U
      final lastUrl = prefs.getString('damstv_last_m3u_url');
      if (lastUrl != null && lastUrl.isNotEmpty) {
        _urlController.text = lastUrl;
      }

      // Charger le cache des chaînes TV
      final cachedChannels = prefs.getString('damstv_cached_channels');
      if (cachedChannels != null && cachedChannels.isNotEmpty) {
        final List<dynamic> decodedChannels = jsonDecode(cachedChannels);
        final list = decodedChannels
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _allTvChannels = list;
          _filterTvChannels();
          if (_allTvChannels.isNotEmpty) {
            _showM3uPanel = false;
          }
        });
      }
    } catch (_) {}
  }

  /// Sauvegarde des favoris dans SharedPreferences
  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _favorites.values.map((c) => c.toJson()).toList();
      await prefs.setString('damstv_favorites', jsonEncode(list));
    } catch (_) {}
  }

  /// Basculer l'état de favori pour une chaîne / radio
  void _toggleFavorite(Channel channel) {
    setState(() {
      if (_favorites.containsKey(channel.url)) {
        _favorites.remove(channel.url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${channel.name} retiré des favoris'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        _favorites[channel.url] = channel;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${channel.name} ajouté aux favoris !'),
            backgroundColor: const Color(0xFF0C4A6E),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
    _saveFavorites();
  }

  bool _isFavorite(Channel channel) => _favorites.containsKey(channel.url);

  /* ================= GESTION TV & M3U ================= */

  void _filterTvChannels() {
    final query = _tvSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredTvChannels = List.from(_allTvChannels);
      } else {
        _filteredTvChannels = _allTvChannels.where((c) {
          final matchesName = c.name.toLowerCase().contains(query);
          final matchesGroup = c.group?.toLowerCase().contains(query) ?? false;
          return matchesName || matchesGroup;
        }).toList();
      }
    });
  }

  List<Channel> _parseM3U(String content) {
    final List<Channel> channels = [];
    final lines = content.split('\n');

    String? currentName;
    String? currentLogo;
    String? currentGroup;

    final logoRegex = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);
    final groupRegex = RegExp(r'group-title="([^"]*)"', caseSensitive: false);

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final commaIndex = line.lastIndexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = null;
        }

        final logoMatch = logoRegex.firstMatch(line);
        currentLogo = logoMatch?.group(1);

        final groupMatch = groupRegex.firstMatch(line);
        currentGroup = groupMatch?.group(1);
      } else if (!line.startsWith('#')) {
        if (line.startsWith('http://') ||
            line.startsWith('https://') ||
            line.startsWith('rtmp://') ||
            line.startsWith('rtsp://') ||
            line.startsWith('mms://')) {
          final resolvedName = (currentName != null && currentName.isNotEmpty)
              ? currentName
              : 'Chaîne ${channels.length + 1}';

          channels.add(Channel(
            name: resolvedName,
            url: line,
            logo: currentLogo,
            group: currentGroup,
            isRadio: false,
          ));
        }
        currentName = null;
        currentLogo = null;
        currentGroup = null;
      }
    }
    return channels;
  }

  Future<void> _fetchPlaylist() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer une URL M3U valide.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoadingTv = true;
      _tvErrorMessage = null;
    });

    try {
      final uri = Uri.parse(rawUrl);
      final response = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.google.com/',
          'Accept': '*/*',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final content = utf8.decode(response.bodyBytes, allowMalformed: true);
        final parsed = _parseM3U(content);

        if (parsed.isEmpty) {
          setState(() {
            _tvErrorMessage =
                'Aucune chaîne trouvée dans cette playlist. Vérifiez le format M3U.';
            _allTvChannels = [];
            _filteredTvChannels = [];
          });
        } else {
          setState(() {
            _allTvChannels = parsed;
            _filterTvChannels();
            _showM3uPanel = false;
          });

          // Enregistrer en cache local
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('damstv_last_m3u_url', rawUrl);
          await prefs.setString(
            'damstv_cached_channels',
            jsonEncode(parsed.map((c) => c.toJson()).toList()),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${parsed.length} chaînes chargées avec succès !'),
                backgroundColor: const Color(0xFF059669),
              ),
            );
          }
        }
      } else {
        setState(() {
          _tvErrorMessage =
              'Erreur de téléchargement: Code HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _tvErrorMessage = 'Erreur lors du chargement : $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTv = false;
        });
      }
    }
  }

  /* ================= GESTION RADIO ================= */

  void _filterRadioChannels() {
    final query = _radioSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredRadios = List.from(_allRadios);
      } else {
        _filteredRadios = _allRadios.where((r) {
          final matchesName = r.name.toLowerCase().contains(query);
          final matchesGroup = r.group?.toLowerCase().contains(query) ?? false;
          return matchesName || matchesGroup;
        }).toList();
      }
    });
  }

  Future<void> _fetchDefaultRadios() async {
    setState(() {
      _isLoadingRadio = true;
      _radioErrorMessage = null;
    });

    final radioServers = [
      'https://de1.api.radio-browser.info',
      'https://nl1.api.radio-browser.info',
      'https://at1.api.radio-browser.info',
    ];

    String path;
    if (_radioFilter == 'fr') {
      path = '/json/stations/bycountrycodeexact/FR?limit=60&order=clickcount&reverse=true';
    } else if (_radioFilter == 'afrique') {
      path = '/json/stations/search?tag=african&limit=60&order=clickcount&reverse=true';
    } else {
      path = '/json/stations/topvote/60';
    }

    bool success = false;
    for (var server in radioServers) {
      try {
        final uri = Uri.parse('$server$path');
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);
          final List<Channel> list = [];
          for (var item in data) {
            final urlResolved = (item['url_resolved'] ?? item['url'] ?? '').toString();
            final name = (item['name'] ?? 'Radio').toString().trim();
            final favicon = (item['favicon'] ?? '').toString();
            final country = (item['country'] ?? 'Radio').toString();
            final bitrate = item['bitrate'] != null ? '${item['bitrate']} kbps' : '';

            if (urlResolved.startsWith('http://') || urlResolved.startsWith('https://')) {
              list.add(Channel(
                id: item['stationuuid']?.toString(),
                name: name,
                url: urlResolved,
                logo: favicon.isNotEmpty ? favicon : null,
                group: '$country ${bitrate.isNotEmpty ? "• $bitrate" : ""}'.trim(),
                isRadio: true,
              ));
            }
          }
          if (mounted) {
            setState(() {
              _allRadios = list;
              _filterRadioChannels();
              _isLoadingRadio = false;
            });
          }
          success = true;
          break;
        }
      } catch (_) {}
    }

    if (!success && mounted) {
      // Liste de secours des radios francophones principales
      final fallbackRadios = [
        Channel(name: 'France Inter', url: 'https://stream.radiofrance.fr/franceinter/franceinter_hifi.m3u8', group: 'France • Actualités', isRadio: true),
        Channel(name: 'France Info', url: 'https://stream.radiofrance.fr/franceinfo/franceinfo_hifi.m3u8', group: 'France • Information', isRadio: true),
        Channel(name: 'FIP Radio', url: 'https://stream.radiofrance.fr/fip/fip_hifi.m3u8', group: 'France • Éclectique', isRadio: true),
        Channel(name: 'NRJ France', url: 'https://scdn.nrjaudio.fm/audio1/fr/30001/aac_64.mp3', group: 'France • Pop / Hits', isRadio: true),
        Channel(name: 'RTL', url: 'https://streamer-02.rtl.fr/rtl-1-44-128', group: 'France • Généraliste', isRadio: true),
        Channel(name: 'Skyrock', url: 'https://icecast.skyrock.net/s/natio_aac_96k', group: 'France • Rap / RnB', isRadio: true),
        Channel(name: 'Europe 1', url: 'https://stream.europe1.fr/europe1.mp3', group: 'France • Information', isRadio: true),
        Channel(name: 'RFI Monde', url: 'https://rfienfrancais64k.stream.liveradio.fr/rfienfrancais-64.mp3', group: 'Monde • Actualités', isRadio: true),
        Channel(name: 'Nostalgie', url: 'https://scdn.nrjaudio.fm/audio1/fr/30601/aac_64.mp3', group: 'France • Rétro', isRadio: true),
        Channel(name: 'Fun Radio', url: 'https://streamer-02.rtl.fr/fun-1-44-128', group: 'France • Dance / Electro', isRadio: true),
      ];
      setState(() {
        _allRadios = fallbackRadios;
        _filterRadioChannels();
        _isLoadingRadio = false;
      });
    }
  }

  /* ================= NAVIGATION & LECTURE ================= */

  void _openPlayer(Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          channel: channel,
          isFavorite: _isFavorite(channel),
          onToggleFavorite: () => _toggleFavorite(channel),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            RichText(
              text: const TextSpan(
                text: 'DAMS',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2F6BFF), Color(0xFF22D3EE)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            'TV',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: Icon(
                _showM3uPanel ? Icons.expand_less : Icons.add_link,
                color: const Color(0xFF22D3EE),
              ),
              tooltip: _showM3uPanel ? 'Masquer URL M3U' : 'Charger URL M3U',
              onPressed: () => setState(() => _showM3uPanel = !_showM3uPanel),
            ),
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF22D3EE)),
              tooltip: 'Actualiser les radios',
              onPressed: _fetchDefaultRadios,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildTvTab(),
          _buildRadioTab(),
          _buildFavoritesTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF26304A), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.live_tv_rounded),
              label: 'TV',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.radio_rounded),
              label: 'Radio',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: _favorites.isNotEmpty,
                label: Text('${_favorites.length}'),
                backgroundColor: const Color(0xFF22D3EE),
                textColor: const Color(0xFF060B18),
                child: const Icon(Icons.favorite_rounded),
              ),
              label: 'Favoris',
            ),
          ],
        ),
      ),
    );
  }

  /* ================= WIDGETS ONGLET TV ================= */

  Widget _buildTvTab() {
    return Column(
      children: [
        if (_showM3uPanel)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF151B28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF26304A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'URL de la playlist M3U',
                    labelStyle: const TextStyle(color: Color(0xFF8B97AD)),
                    hintText: 'https://exemple.com/playlist.m3u',
                    prefixIcon: const Icon(Icons.link, color: Color(0xFF22D3EE)),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _urlController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _isLoadingTv ? null : _fetchPlaylist,
                  icon: _isLoadingTv
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF060B18),
                          ),
                        )
                      : const Icon(Icons.download_rounded, color: Color(0xFF060B18)),
                  label: Text(
                    _isLoadingTv ? 'Téléchargement...' : 'Télécharger la playlist',
                    style: const TextStyle(
                      color: Color(0xFF060B18),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22D3EE),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_tvErrorMessage != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.shade400),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tvErrorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (_allTvChannels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tvSearchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher une chaîne ou un groupe...',
                      prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF22D3EE)),
                      suffixIcon: _tvSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _tvSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2636),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF26304A)),
                  ),
                  child: Text(
                    '${_filteredTvChannels.length} / ${_allTvChannels.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xFF22D3EE),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _isLoadingTv
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF22D3EE)),
                )
              : _filteredTvChannels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _allTvChannels.isEmpty ? Icons.live_tv_rounded : Icons.search_off,
                            size: 60,
                            color: const Color(0xFF8B97AD).withOpacity(0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _allTvChannels.isEmpty
                                ? 'Téléchargez une playlist M3U pour commencer'
                                : 'Aucune chaîne trouvée',
                            style: const TextStyle(color: Color(0xFF8B97AD)),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: _filteredTvChannels.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final channel = _filteredTvChannels[index];
                        return _buildChannelTile(channel);
                      },
                    ),
        ),
      ],
    );
  }

  /* ================= WIDGETS ONGLET RADIO ================= */

  Widget _buildRadioTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _radioSearchController,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une radio...',
                    prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF22D3EE)),
                    suffixIcon: _radioSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _radioSearchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Filtres par catégorie de radio
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('Populaires', 'top'),
              const SizedBox(width: 8),
              _buildFilterChip('France', 'fr'),
              const SizedBox(width: 8),
              _buildFilterChip('Afrique', 'afrique'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _isLoadingRadio
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF22D3EE)),
                )
              : _filteredRadios.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.radio_rounded, size: 60, color: Color(0xFF8B97AD)),
                          SizedBox(height: 12),
                          Text('Aucune radio disponible', style: TextStyle(color: Color(0xFF8B97AD))),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: _filteredRadios.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final radio = _filteredRadios[index];
                        return _buildChannelTile(radio);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _radioFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF060B18) : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF22D3EE),
      backgroundColor: const Color(0xFF1E2636),
      side: const BorderSide(color: Color(0xFF26304A)),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _radioFilter = value;
          });
          _fetchDefaultRadios();
        }
      },
    );
  }

  Widget _buildFavChip(String label, String value) {
    final isSelected = _favFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF060B18) : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 11,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF22D3EE),
      backgroundColor: const Color(0xFF1E2636),
      side: const BorderSide(color: Color(0xFF26304A)),
      visualDensity: VisualDensity.compact,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _favFilter = value;
          });
        }
      },
    );
  }

  /* ================= WIDGETS ONGLET FAVORIS ================= */

  Widget _buildFavoritesTab() {
    final allFavList = _favorites.values.toList();
    final displayedFavs = _favFilter == 'all'
        ? allFavList
        : _favFilter == 'tv'
            ? allFavList.where((c) => !c.isRadio).toList()
            : allFavList.where((c) => c.isRadio).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.favorite_rounded, color: Color(0xFF22D3EE), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Mes Favoris (${allFavList.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              if (allFavList.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFavChip('Tous', 'all'),
                    const SizedBox(width: 6),
                    _buildFavChip('TV', 'tv'),
                    const SizedBox(width: 6),
                    _buildFavChip('Radio', 'radio'),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: displayedFavs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.favorite_border_rounded,
                        size: 64,
                        color: Color(0xFF8B97AD),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Aucun favori enregistré',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Touchez le cœur ♡ à côté d\'une chaîne ou d\'une radio pour la retrouver ici.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8B97AD), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: displayedFavs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = displayedFavs[index];
                    return _buildChannelTile(item);
                  },
                ),
        ),
      ],
    );
  }

  /* ================= TILE CANAL / RADIO ================= */

  Widget _buildChannelTile(Channel channel) {
    final isFav = _isFavorite(channel);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151B28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF26304A)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 48,
            height: 48,
            color: const Color(0xFF1E2636),
            child: channel.logo != null && channel.logo!.isNotEmpty
                ? Image.network(
                    channel.logo!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      channel.isRadio ? Icons.radio_rounded : Icons.live_tv_rounded,
                      color: const Color(0xFF22D3EE),
                      size: 26,
                    ),
                  )
                : Icon(
                    channel.isRadio ? Icons.radio_rounded : Icons.live_tv_rounded,
                    color: const Color(0xFF22D3EE),
                    size: 26,
                  ),
          ),
        ),
        title: Text(
          channel.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          channel.group != null && channel.group!.isNotEmpty
              ? channel.group!
              : (channel.isRadio ? 'Radio' : 'TV Direct'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF8B97AD),
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bouton Cœur Favori
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? const Color(0xFF22D3EE) : const Color(0xFF8B97AD),
                size: 24,
              ),
              tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
              onPressed: () => _toggleFavorite(channel),
            ),
            // Bouton Lecture
            IconButton(
              icon: const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFF22D3EE),
                size: 34,
              ),
              tooltip: 'Lire le flux',
              onPressed: () => _openPlayer(channel),
            ),
          ],
        ),
        onTap: () => _openPlayer(channel),
      ),
    );
  }
}

/// Écran du lecteur VLC natif avec en-têtes User-Agent / Referer et gestion anti-403
class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const PlayerScreen({
    super.key,
    required this.channel,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VlcPlayerController _vlcViewController;
  bool _isPlaying = true;
  bool _hasError = false;
  late bool _favState;
  String _statusText = 'Connexion au flux...';

  @override
  void initState() {
    super.initState();
    _favState = widget.isFavorite;

    // Configuration VLC avec accélération matérielle complète et options anti-403
    _vlcViewController = VlcPlayerController.network(
      widget.channel.url,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([
          VlcAdvancedOptions.networkCaching(3000),
          VlcAdvancedOptions.liveCaching(3000),
        ]),
        http: VlcHttpOptions([
          ':http-user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          ':http-referrer=https://www.google.com/',
          ':http-reconnect=true',
        ]),
      ),
    );

    _vlcViewController.addListener(_onVlcStatusChange);
  }

  void _onVlcStatusChange() {
    if (!mounted) return;

    final value = _vlcViewController.value;
    setState(() {
      _isPlaying = value.isPlaying;
      _hasError = value.hasError;

      if (value.hasError) {
        _statusText = 'Erreur lors de la lecture du flux';
      } else if (value.isPlaying) {
        _statusText = widget.channel.isRadio ? 'Diffusion Radio en direct' : 'En direct';
      } else if (value.isBuffering) {
        _statusText = 'Mise en mémoire tampon...';
      } else {
        _statusText = 'En pause';
      }
    });
  }

  @override
  void dispose() {
    _vlcViewController.removeListener(_onVlcStatusChange);
    _vlcViewController.stopRendererScanning();
    _vlcViewController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _vlcViewController.pause();
    } else {
      _vlcViewController.play();
    }
  }

  void _restartStream() {
    _vlcViewController.stop();
    _vlcViewController.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.channel.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.channel.group != null)
              Text(
                widget.channel.group!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF22D3EE)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _favState ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _favState ? const Color(0xFF22D3EE) : Colors.white70,
            ),
            onPressed: () {
              widget.onToggleFavorite();
              setState(() {
                _favState = !_favState;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Recharger le flux',
            onPressed: _restartStream,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: widget.channel.isRadio
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151B28),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF22D3EE), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF22D3EE).withOpacity(0.3),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: widget.channel.logo != null && widget.channel.logo!.isNotEmpty
                                      ? ClipOval(
                                          child: Image.network(
                                            widget.channel.logo!,
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.radio_rounded,
                                              size: 60,
                                              color: Color(0xFF22D3EE),
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.radio_rounded,
                                          size: 60,
                                          color: Color(0xFF22D3EE),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                widget.channel.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.channel.group ?? 'Flux audio en direct',
                                style: const TextStyle(color: Color(0xFF8B97AD), fontSize: 13),
                              ),
                              // VLC Player invisible ou minimal en arrière plan audio
                              Opacity(
                                opacity: 0.01,
                                child: SizedBox(
                                  width: 1,
                                  height: 1,
                                  child: VlcPlayer(
                                    controller: _vlcViewController,
                                    aspectRatio: 16 / 9,
                                    placeholder: const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : VlcPlayer(
                            controller: _vlcViewController,
                            aspectRatio: 16 / 9,
                            placeholder: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF22D3EE)),
                                  SizedBox(height: 16),
                                  Text(
                                    'Chargement du flux vidéo VLC...',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  if (_hasError)
                    Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Impossible de lire ce flux',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.channel.url,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _restartStream,
                            icon: const Icon(Icons.refresh, color: Color(0xFF060B18)),
                            label: const Text(
                              'Réessayer',
                              style: TextStyle(color: Color(0xFF060B18), fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22D3EE),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              color: const Color(0xFF0B1220),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _isPlaying
                              ? const Color(0xFF34D399)
                              : (_hasError ? Colors.redAccent : Colors.orangeAccent),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'VLC HW: Full',
                        style: TextStyle(
                          color: Color(0xFF22D3EE),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        onPressed: () async {
                          final pos = await _vlcViewController.getPosition();
                          _vlcViewController.setTime(
                            (pos.inMilliseconds - 10000).clamp(0, double.infinity).toInt(),
                          );
                        },
                      ),
                      IconButton(
                        iconSize: 48,
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                          color: const Color(0xFF22D3EE),
                        ),
                        onPressed: _togglePlayPause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        onPressed: () async {
                          final pos = await _vlcViewController.getPosition();
                          _vlcViewController.setTime(pos.inMilliseconds + 10000);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70),
                        tooltip: 'Recharger',
                        onPressed: _restartStream,
                      ),
                    ],
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
