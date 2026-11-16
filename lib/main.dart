import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DamsTvApp());
}

class DamsTvApp extends StatelessWidget {
  const DamsTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAMS TV Native',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class Channel {
  final String name;
  final String url;
  final String? logo;
  final String? group;

  Channel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  List<Channel> _allChannels = [];
  List<Channel> _filteredChannels = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterChannels);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterChannels() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredChannels = List.from(_allChannels);
      } else {
        _filteredChannels = _allChannels.where((c) {
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
        // Extract channel name after the last comma
        final commaIndex = line.lastIndexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = null;
        }

        // Extract metadata if available
        final logoMatch = logoRegex.firstMatch(line);
        currentLogo = logoMatch?.group(1);

        final groupMatch = groupRegex.firstMatch(line);
        currentGroup = groupMatch?.group(1);
      } else if (!line.startsWith('#')) {
        // Line is a stream URL
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
          ));
        }

        // Reset for the next entry
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
      _isLoading = true;
      _errorMessage = null;
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
            _errorMessage =
                'Aucune chaîne trouvée dans cette playlist. Vérifiez le format M3U.';
            _allChannels = [];
            _filteredChannels = [];
          });
        } else {
          setState(() {
            _allChannels = parsed;
            _filterChannels();
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${parsed.length} chaînes chargées avec succès !'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        }
      } else {
        setState(() {
          _errorMessage =
              'Erreur de téléchargement: Code HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors du chargement : $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openPlayer(Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.live_tv, color: Colors.cyanAccent),
            SizedBox(width: 10),
            Text('DAMS TV Native', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'URL de la playlist M3U',
                    hintText: 'https://exemple.com/playlist.m3u',
                    prefixIcon: const Icon(Icons.link, color: Colors.cyanAccent),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _urlController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _fetchPlaylist,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isLoading
                        ? 'Téléchargement...'
                        : 'Télécharger la playlist',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          if (_allChannels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Rechercher une chaîne ou un groupe...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Chip(
                    label: Text(
                      '${_filteredChannels.length} / ${_allChannels.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  )
                : _filteredChannels.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _allChannels.isEmpty
                                  ? Icons.tv
                                  : Icons.search_off,
                              size: 64,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _allChannels.isEmpty
                                  ? 'Collez une URL M3U pour charger des chaînes'
                                  : 'Aucune chaîne ne correspond à votre recherche',
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filteredChannels.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: Color(0xFF1E293B),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final channel = _filteredChannels[index];
                          return ListTile(
                            leading: channel.logo != null &&
                                    channel.logo!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      channel.logo!,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const CircleAvatar(
                                        backgroundColor: Color(0xFF334155),
                                        child: Icon(Icons.tv,
                                            color: Colors.cyanAccent),
                                      ),
                                    ),
                                  )
                                : const CircleAvatar(
                                    backgroundColor: Color(0xFF334155),
                                    child:
                                        Icon(Icons.tv, color: Colors.cyanAccent),
                                  ),
                            title: Text(
                              channel.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            subtitle: channel.group != null &&
                                    channel.group!.isNotEmpty
                                ? Text(
                                    channel.group!,
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                    ),
                                  )
                                : Text(
                                    channel.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                    ),
                                  ),
                            trailing: const Icon(
                              Icons.play_circle_fill,
                              color: Colors.cyanAccent,
                              size: 32,
                            ),
                            onTap: () => _openPlayer(channel),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final Channel channel;

  const PlayerScreen({super.key, required this.channel});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VlcPlayerController _vlcViewController;
  bool _isPlaying = true;
  bool _hasError = false;
  String _statusText = 'Connexion au flux...';

  @override
  void initState() {
    super.initState();

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
        _statusText = 'En direct';
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
        backgroundColor: Colors.black.withOpacity(0.8),
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
                style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: VlcPlayer(
                      controller: _vlcViewController,
                      aspectRatio: 16 / 9,
                      placeholder: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.cyanAccent),
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
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 48),
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
                            icon: const Icon(Icons.refresh),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              color: const Color(0xFF0F172A),
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
                              ? Colors.greenAccent
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
                      Text(
                        'HW: Full',
                        style: TextStyle(
                          color: Colors.cyanAccent.shade200,
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
                        iconSize: 42,
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: Colors.cyanAccent,
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
                        tooltip: 'Recharger le flux',
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
