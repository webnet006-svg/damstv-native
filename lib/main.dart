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

  // Couleurs exactes du projet web DAMS TV v2.2
  static const Color cBackground = Color(0xFF060B18); // #060b18 (bleu très sombre)
  static const Color cSurface = Color(0xFF151B28); // #151b28 (surface barres & cartes)
  static const Color cSurface2 = Color(0xFF1E2636); // #1e2636 (surface secondaire)
  static const Color cPrimary = Color(0xFF2F6BFF); // #2f6bff (bleu bouton)
  static const Color cCyan = Color(0xFF22D3EE); // #22d3ee (cyan accent & actif)
  static const Color cText = Color(0xFFF1F5F9); // #f1f5f9 (texte blanc cassé)
  static const Color cMuted = Color(0xFF8B97AD); // #8b97ad (texte gris)
  static const Color cBorder = Color(0xFF26304A); // #26304a (lignes & bordures)

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAMS TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: cBackground,
        primaryColor: cCyan,
        colorScheme: const ColorScheme.dark(
          primary: cCyan,
          secondary: cPrimary,
          surface: cSurface,
          background: cBackground,
          onPrimary: cBackground,
          onSecondary: Colors.white,
          onSurface: cText,
          onBackground: cText,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: cSurface,
          foregroundColor: cText,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: cSurface,
          selectedItemColor: cCyan,
          unselectedItemColor: cMuted,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
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

  // Données et contrôleurs onglet TV
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tvSearchController = TextEditingController();
  bool _isLoadingTv = false;
  String? _tvErrorMessage;
  List<Channel> _allTvChannels = [];
  List<Channel> _filteredTvChannels = [];
  bool _showM3uPanel = true;

  // Données et contrôleurs onglet Radio
  final TextEditingController _radioSearchController = TextEditingController();
  bool _isLoadingRadio = false;
  List<Channel> _allRadios = [];
  List<Channel> _filteredRadios = [];
  String _radioFilter = 'top';

  // Filtres onglet Favoris
  String _favFilter = 'all';

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

  /* ================= PERSISTANCE AVEC SHARED_PREFERENCES ================= */

  Future<void> _loadStoredData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Charger les favoris permanents
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

      // Charger les chaînes TV mises en cache
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

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _favorites.values.map((c) => c.toJson()).toList();
      await prefs.setString('damstv_favorites', jsonEncode(list));
    } catch (_) {}
  }

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

  /* ================= PARSEUR ET TÉLÉCHARGEMENT M3U ================= */

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
      backgroundColor: DamsTvApp.cBackground,
      appBar: AppBar(
        title: Row(
          children: [
            RichText(
              text: const TextSpan(
                text: 'DAMS',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: DamsTvApp.cText,
                  letterSpacing: -0.5,
                ),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [DamsTvApp.cPrimary, DamsTvApp.cCyan],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                _showM3uPanel ? Icons.expand_less_rounded : Icons.add_link_rounded,
                color: DamsTvApp.cCyan,
              ),
              tooltip: _showM3uPanel ? 'Masquer URL' : 'Ajouter playlist M3U',
              onPressed: () => setState(() => _showM3uPanel = !_showM3uPanel),
            ),
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: DamsTvApp.cCyan),
              tooltip: 'Actualiser',
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
          color: DamsTvApp.cSurface,
          border: Border(
            top: BorderSide(color: DamsTvApp.cBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: DamsTvApp.cSurface,
          selectedItemColor: DamsTvApp.cCyan,
          unselectedItemColor: DamsTvApp.cMuted,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.live_tv_rounded),
              label: 'TV',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radio_rounded),
              label: 'Radio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_rounded),
              label: 'Favoris',
            ),
          ],
        ),
      ),
    );
  }

  /* ================= ONGLET 1: TV ================= */

  Widget _buildTvTab() {
    return Column(
      children: [
        // Champ de texte en haut avec le bouton "Télécharger la playlist"
        if (_showM3uPanel)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DamsTvApp.cSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DamsTvApp.cBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  style: const TextStyle(color: DamsTvApp.cText),
                  decoration: InputDecoration(
                    labelText: 'URL de la playlist M3U',
                    labelStyle: const TextStyle(color: DamsTvApp.cMuted),
                    hintText: 'https://exemple.com/playlist.m3u',
                    hintStyle: TextStyle(color: DamsTvApp.cMuted.withOpacity(0.6)),
                    prefixIcon: const Icon(Icons.link_rounded, color: DamsTvApp.cCyan),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20, color: DamsTvApp.cMuted),
                            onPressed: () {
                              _urlController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: DamsTvApp.cSurface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: DamsTvApp.cBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: DamsTvApp.cBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: DamsTvApp.cCyan, width: 1.5),
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isLoadingTv ? null : _fetchPlaylist,
                  icon: _isLoadingTv
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, color: Colors.white),
                  label: Text(
                    _isLoadingTv ? 'Téléchargement...' : 'Télécharger la playlist',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DamsTvApp.cPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
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
              color: Colors.red.shade900.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tvErrorMessage!,
                    style: const TextStyle(color: DamsTvApp.cText, fontSize: 13),
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
                    style: const TextStyle(color: DamsTvApp.cText, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une chaîne...',
                      hintStyle: const TextStyle(color: DamsTvApp.cMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: DamsTvApp.cCyan),
                      suffixIcon: _tvSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: DamsTvApp.cMuted),
                              onPressed: () {
                                _tvSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      filled: true,
                      fillColor: DamsTvApp.cSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DamsTvApp.cBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DamsTvApp.cBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DamsTvApp.cCyan),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: DamsTvApp.cSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DamsTvApp.cBorder),
                  ),
                  child: Text(
                    '${_filteredTvChannels.length} / ${_allTvChannels.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: DamsTvApp.cCyan,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Liste de cartes sombres
        Expanded(
          child: _isLoadingTv
              ? const Center(
                  child: CircularProgressIndicator(color: DamsTvApp.cCyan),
                )
              : _filteredTvChannels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _allTvChannels.isEmpty ? Icons.live_tv_rounded : Icons.search_off_rounded,
                            size: 64,
                            color: DamsTvApp.cMuted.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _allTvChannels.isEmpty
                                ? 'Téléchargez une playlist M3U pour charger les chaînes'
                                : 'Aucune chaîne ne correspond à la recherche',
                            style: const TextStyle(color: DamsTvApp.cMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _filteredTvChannels.length,
                      itemBuilder: (context, index) {
                        final channel = _filteredTvChannels[index];
                        return _buildCardItem(channel);
                      },
                    ),
        ),
      ],
    );
  }

  /* ================= ONGLET 2: RADIO ================= */

  Widget _buildRadioTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: _radioSearchController,
            style: const TextStyle(color: DamsTvApp.cText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Rechercher une radio...',
              hintStyle: const TextStyle(color: DamsTvApp.cMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: DamsTvApp.cCyan),
              suffixIcon: _radioSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: DamsTvApp.cMuted),
                      onPressed: () {
                        _radioSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              filled: true,
              fillColor: DamsTvApp.cSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DamsTvApp.cBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DamsTvApp.cBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DamsTvApp.cCyan),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              _buildRadioChip('Populaires', 'top'),
              const SizedBox(width: 8),
              _buildRadioChip('France', 'fr'),
              const SizedBox(width: 8),
              _buildRadioChip('Afrique', 'afrique'),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingRadio
              ? const Center(
                  child: CircularProgressIndicator(color: DamsTvApp.cCyan),
                )
              : _filteredRadios.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.radio_rounded, size: 64, color: DamsTvApp.cMuted),
                          SizedBox(height: 12),
                          Text('Aucune radio trouvée', style: TextStyle(color: DamsTvApp.cMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _filteredRadios.length,
                      itemBuilder: (context, index) {
                        final radio = _filteredRadios[index];
                        return _buildCardItem(radio);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRadioChip(String label, String value) {
    final isSelected = _radioFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? DamsTvApp.cBackground : DamsTvApp.cText,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: DamsTvApp.cCyan,
      backgroundColor: DamsTvApp.cSurface,
      side: const BorderSide(color: DamsTvApp.cBorder),
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

  /* ================= ONGLET 3: FAVORIS ================= */

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
                  const Icon(Icons.favorite_rounded, color: DamsTvApp.cCyan, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Mes Favoris (${allFavList.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: DamsTvApp.cText,
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
                    children: const [
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 64,
                        color: DamsTvApp.cMuted,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Aucun favori enregistré',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: DamsTvApp.cText,
                        ),
                      ),
                      SizedBox(height: 6),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Touchez le cœur sur une carte de chaîne ou de radio pour l\'ajouter aux favoris.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: DamsTvApp.cMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: displayedFavs.length,
                  itemBuilder: (context, index) {
                    final item = displayedFavs[index];
                    return _buildCardItem(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFavChip(String label, String value) {
    final isSelected = _favFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? DamsTvApp.cBackground : DamsTvApp.cText,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 11,
        ),
      ),
      selected: isSelected,
      selectedColor: DamsTvApp.cCyan,
      backgroundColor: DamsTvApp.cSurface,
      side: const BorderSide(color: DamsTvApp.cBorder),
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

  /* ================= CARTE SOMBRE (TV / RADIO) ================= */

  Widget _buildCardItem(Channel channel) {
    final isFav = _isFavorite(channel);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: DamsTvApp.cSurface, // Surface #151b28
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DamsTvApp.cBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            offset: const Offset(0, 3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openPlayer(channel),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Vignette logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: DamsTvApp.cSurface2,
                    child: channel.logo != null && channel.logo!.isNotEmpty
                        ? Image.network(
                            channel.logo!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              channel.isRadio ? Icons.radio_rounded : Icons.live_tv_rounded,
                              color: DamsTvApp.cCyan,
                              size: 26,
                            ),
                          )
                        : Icon(
                            channel.isRadio ? Icons.radio_rounded : Icons.live_tv_rounded,
                            color: DamsTvApp.cCyan,
                            size: 26,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Nom de chaîne en blanc (#f1f5f9) & groupe en gris (#8b97ad)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DamsTvApp.cText, // Nom en blanc
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (channel.group != null && channel.group!.isNotEmpty)
                            ? channel.group!
                            : (channel.isRadio ? 'Radio' : 'TV Direct'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DamsTvApp.cMuted, // Groupe en gris
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Bouton Cœur pour ajouter aux favoris
                IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? DamsTvApp.cCyan : DamsTvApp.cMuted,
                    size: 24,
                  ),
                  tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  onPressed: () => _toggleFavorite(channel),
                ),
                // Icône "Play" cyan (#22d3ee) à droite
                IconButton(
                  icon: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: DamsTvApp.cCyan, // Play cyan
                    size: 36,
                  ),
                  tooltip: 'Regarder',
                  onPressed: () => _openPlayer(channel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Écran du lecteur PlayerScreen avec VLC, en-têtes User-Agent/Referer,
/// boutons Plein écran et Fermer en haut.
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
  bool _isFullscreen = false;
  late bool _favState;
  String _statusText = 'Connexion au flux...';

  @override
  void initState() {
    super.initState();
    _favState = widget.isFavorite;

    // Initialisation VLC avec User-Agent, Referer et accélération matérielle
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
        _statusText = widget.channel.isRadio ? 'Radio en direct' : 'En direct';
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

    // Restaurer l'interface normale et orientation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: Column(
          children: [
            // Barre supérieure avec boutons Plein écran et Fermer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF060B18).withOpacity(0.95),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channel.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF1F5F9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.channel.group != null && widget.channel.group!.isNotEmpty)
                          Text(
                            widget.channel.group!,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF22D3EE)),
                          ),
                      ],
                    ),
                  ),
                  // Bouton Cœur
                  IconButton(
                    icon: Icon(
                      _favState ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _favState ? const Color(0xFF22D3EE) : const Color(0xFF8B97AD),
                      size: 22,
                    ),
                    onPressed: () {
                      widget.onToggleFavorite();
                      setState(() {
                        _favState = !_favState;
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  // Bouton Plein écran
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF22D3EE),
                      backgroundColor: const Color(0xFF1E2636),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFF26304A)),
                      ),
                    ),
                    icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _isFullscreen ? 'Fenêtré' : 'Plein écran',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _toggleFullscreen,
                  ),
                  const SizedBox(width: 8),
                  // Bouton Fermer
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF060B18),
                      backgroundColor: const Color(0xFFE8EEFB),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF060B18)),
                    label: const Text(
                      'Fermer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF060B18),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Zone de visualisation du lecteur VLC
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
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151B28),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF22D3EE), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF22D3EE).withOpacity(0.35),
                                      blurRadius: 26,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: widget.channel.logo != null && widget.channel.logo!.isNotEmpty
                                      ? ClipOval(
                                          child: Image.network(
                                            widget.channel.logo!,
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.radio_rounded,
                                              size: 54,
                                              color: Color(0xFF22D3EE),
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.radio_rounded,
                                          size: 54,
                                          color: Color(0xFF22D3EE),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                widget.channel.name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFF1F5F9),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.channel.group ?? 'Flux audio en direct',
                                style: const TextStyle(color: Color(0xFF8B97AD), fontSize: 13),
                              ),
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
                                    style: TextStyle(color: Color(0xFF8B97AD)),
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
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
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
                              color: Color(0xFF8B97AD),
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _restartStream,
                            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF060B18)),
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
            // Barre de commandes inférieure
            Container(
              color: const Color(0xFF060B18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          color: Color(0xFF8B97AD),
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
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
                        icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                        onPressed: () async {
                          final pos = await _vlcViewController.getPosition();
                          _vlcViewController.setTime(pos.inMilliseconds + 10000);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Color(0xFF8B97AD)),
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
