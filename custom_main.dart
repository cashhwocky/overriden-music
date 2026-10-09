import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF101322),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const OverrideMusicApp());
}

class OverrideMusicApp extends StatefulWidget {
  const OverrideMusicApp({super.key});

  @override
  State<OverrideMusicApp> createState() => _OverrideMusicAppState();

  static _OverrideMusicAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_OverrideMusicAppState>();
}

class _OverrideMusicAppState extends State<OverrideMusicApp> {
  String _currentThemeKey = 'indigo';

  final Map<String, Color> themes = {
    'indigo': const Color(0xFF181C32), // Pixel 10 Indigo Base
    'black': const Color(0xFF0A0A0A),  // Pure Obsidian
    'midnight': const Color(0xFF0F172A),// Deep Slate Blue
  };

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentThemeKey = prefs.getString('app_theme') ?? 'indigo';
    });
  }

  Future<void> setTheme(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', key);
    setState(() {
      _currentThemeKey = key;
    });
  }

  Color get currentBackgroundColor => themes[_currentThemeKey] ?? const Color(0xFF181C32);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Override Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: currentBackgroundColor,
        canvasColor: currentBackgroundColor,
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white24,
          surface: currentBackgroundColor,
        ),
      ),
      home: const MainContainer(),
    );
  }
}

class Song {
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final bool isLocal;
  final String? filePath;

  Song({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.isLocal = false,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'isLocal': isLocal,
        'filePath': filePath,
      };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        videoId: json['videoId'],
        title: json['title'],
        author: json['author'],
        thumbnailUrl: json['thumbnailUrl'],
        isLocal: json['isLocal'] ?? false,
        filePath: json['filePath'],
      );
}

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Song? _currentSong;
  List<Song> _queue = [];
  int _queueIndex = 0;
  bool _isPlaying = false;
  bool _isLoadingTrack = false;
  String? _errorMessage;

  List<Song> _likedSongs = [];
  List<Song> _recentSongs = [];
  List<Song> _searchResults = [];
  List<Song> _localSongs = [];
  bool _isSearching = false;
  bool _isScanningLocal = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissionsAndScan();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? likedJson = prefs.getString('liked_songs');
    if (likedJson != null) {
      final List decoded = jsonDecode(likedJson);
      _likedSongs = decoded.map((e) => Song.fromJson(e)).toList();
    }

    final String? recentJson = prefs.getString('recent_songs');
    if (recentJson != null) {
      final List decoded = jsonDecode(recentJson);
      _recentSongs = decoded.map((e) => Song.fromJson(e)).toList();
    }
    setState(() {});
  }

  Future<void> _saveLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_likedSongs.map((e) => e.toJson()).toList());
    await prefs.setString('liked_songs', encoded);
  }

  Future<void> _saveRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_recentSongs.map((e) => e.toJson()).toList());
    await prefs.setString('recent_songs', encoded);
  }

  void clearRecentHistory() {
    setState(() {
      _recentSongs.clear();
    });
    _saveRecentSongs();
  }

  Future<void> _requestPermissionsAndScan() async {
    if (Platform.isAndroid) {
      PermissionStatus status;
      if (await Permission.audio.isGranted) {
        status = PermissionStatus.granted;
      } else if (await Permission.storage.isGranted) {
        status = PermissionStatus.granted;
      } else {
        status = await Permission.audio.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      }

      if (status.isGranted) {
        _scanLocalFiles();
      }
    } else {
      _scanLocalFiles();
    }
  }

  Future<void> _scanLocalFiles() async {
    setState(() => _isScanningLocal = true);
    try {
      List<Song> foundSongs = [];
      List<Directory> directories = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Music'),
        Directory('/storage/emulated/0/Documents'),
      ];

      for (var dir in directories) {
        if (await dir.exists()) {
          try {
            await for (var entity in dir.list(recursive: true, followLinks: false)) {
              if (entity is File) {
                String path = entity.path.toLowerCase();
                if (path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.wav') || path.endsWith('.aac') || path.endsWith('.flac')) {
                  String fileName = entity.uri.pathSegments.last;
                  foundSongs.add(Song(
                    videoId: 'local_${path.hashCode}',
                    title: fileName.replaceAll(RegExp(r'\.[^\\]*$'), ''),
                    author: 'Local Storage',
                    thumbnailUrl: '',
                    isLocal: true,
                    filePath: entity.path,
                  ));
                }
              }
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _localSongs = foundSongs;
          _isScanningLocal = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isScanningLocal = false);
    }
  }

  void _addToRecents(Song song) {
    setState(() {
      _recentSongs.removeWhere((s) => s.videoId == song.videoId);
      _recentSongs.insert(0, song);
      if (_recentSongs.length > 25) {
        _recentSongs.removeLast();
      }
    });
    _saveRecentSongs();
  }

  bool _isLiked(Song song) {
    return _likedSongs.any((s) => s.videoId == song.videoId);
  }

  void _toggleLike(Song song) {
    setState(() {
      if (_isLiked(song)) {
        _likedSongs.removeWhere((s) => s.videoId == song.videoId);
      } else {
        _likedSongs.add(song);
      }
    });
    _saveLikedSongs();
  }

  Future<void> _playSong(Song song, {List<Song>? newQueue, int index = 0}) async {
    setState(() {
      _currentSong = song;
      _isLoadingTrack = true;
      _errorMessage = null;
      if (newQueue != null) {
        _queue = newQueue;
        _queueIndex = index;
      }
    });

    _addToRecents(song);

    try {
      if (song.isLocal && song.filePath != null) {
        await _audioPlayer.setFilePath(song.filePath!);
        await _audioPlayer.play();
        if (mounted) setState(() => _isLoadingTrack = false);
        return;
      }

      var yt = yt_explode.YoutubeExplode();
      var manifest = await yt.videos.streamsClient.getManifest(song.videoId);
      var audioStream = manifest.audioOnly.withHighestBitrate();
      var audioUrl = audioStream.url.toString();
      yt.close();

      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();

      if (mounted) {
        setState(() {
          _isLoadingTrack = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingTrack = false;
          _errorMessage = "Could not load track. Tap to retry.";
        });
      }
    }
  }

  Future<void> _searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    List<Song> results = [];
    final instances = [
      'https://pipedapi.kavin.rocks',
      'https://pipedapi.adminforge.de',
      'https://pipedapi.privacy.com.de',
    ];

    for (var instance in instances) {
      try {
        final response = await http.get(
          Uri.parse('$instance/search?q=${Uri.encodeComponent(query)}&filter=videos'),
        ).timeout(const Duration(seconds: 4));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = data['items'] as List?;
          if (items != null && items.isNotEmpty) {
            for (var item in items) {
              String url = item['url'] ?? '';
              String videoId = url.contains('?v=') ? url.split('?v=').last : '';
              if (videoId.isNotEmpty) {
                results.add(Song(
                  videoId: videoId,
                  title: item['title'] ?? 'Unknown Title',
                  author: item['uploaderName'] ?? 'Unknown Artist',
                  thumbnailUrl: item['thumbnail'] ?? '',
                ));
              }
            }
            break;
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _openNowPlaying() {
    if (_currentSong == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FullPlayerSheet(parent: this),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              HomeTab(parent: this),
              SearchTab(parent: this),
              LibraryTab(parent: this),
            ],
          ),
          if (_currentSong != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 74,
              child: MiniPlayer(parent: this),
            ),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: const Color(0xFF101322).withOpacity(0.75),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white54,
              type: BottomNavigationBarType.fixed,
              onTap: (index) => setState(() => _currentIndex = index),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Library'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  final _MainContainerState parent;
  const HomeTab({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'OVERRIDE',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SettingsScreen(parent: parent)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hi, Alexander', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        SizedBox(height: 2),
                        Text('Ready for high-fidelity audio.', style: TextStyle(fontSize: 13, color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Recently Played',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: parent._recentSongs.isEmpty
                  ? const Center(
                      child: Text(
                        'No history yet. Search online or play local music!',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: parent._recentSongs.length,
                      itemBuilder: (context, index) {
                        final song = parent._recentSongs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: GlassContainer(
                            borderRadius: 12,
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: song.thumbnailUrl.isNotEmpty
                                    ? Image.network(song.thumbnailUrl, width: 45, height: 45, fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(width: 45, height: 45, color: Colors.white24, child: const Icon(Icons.music_note)))
                                    : Container(width: 45, height: 45, color: Colors.white24, child: const Icon(Icons.audio_file)),
                              ),
                              title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              onTap: () => parent._playSong(song, newQueue: parent._recentSongs, index: index),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchTab extends StatefulWidget {
  final _MainContainerState parent;
  const SearchTab({super.key, required this.parent});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            GlassContainer(
              borderRadius: 14,
              child: TextField(
                controller: widget.parent._searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search online streaming music...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onSubmitted: (val) => widget.parent._searchMusic(val),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withOpacity(0.15),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Online Stream'),
                  Tab(text: 'Local Device'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Online Search Results
                  widget.parent._isSearching
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : widget.parent._searchResults.isEmpty
                          ? const Center(child: Text('Type a query and search online.', style: TextStyle(color: Colors.white54)))
                          : ListView.builder(
                              itemCount: widget.parent._searchResults.length,
                              itemBuilder: (context, index) {
                                final song = widget.parent._searchResults[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: GlassContainer(
                                    borderRadius: 12,
                                    child: ListTile(
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(song.thumbnailUrl, width: 45, height: 45, fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(width: 45, height: 45, color: Colors.white24),
                                        ),
                                      ),
                                      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                      subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                      onTap: () => widget.parent._playSong(song, newQueue: widget.parent._searchResults, index: index),
                                    ),
                                  ),
                                );
                              },
                            ),
                  // Local Device Search / Filter
                  widget.parent._isScanningLocal
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : widget.parent._localSongs.isEmpty
                          ? const Center(child: Text('No local audio files detected.', style: TextStyle(color: Colors.white54)))
                          : ListView.builder(
                              itemCount: widget.parent._localSongs.length,
                              itemBuilder: (context, index) {
                                final song = widget.parent._localSongs[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: GlassContainer(
                                    borderRadius: 12,
                                    child: ListTile(
                                      leading: Container(
                                        width: 45,
                                        height: 45,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.audio_file_rounded, color: Colors.white),
                                      ),
                                      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                      subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                      onTap: () => widget.parent._playSong(song, newQueue: widget.parent._localSongs, index: index),
                                    ),
                                  ),
                                );
                              },
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

class LibraryTab extends StatelessWidget {
  final _MainContainerState parent;
  const LibraryTab({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Library & Local',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: parent._scanLocalFiles,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const Text('Local Files on Device', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  parent._isScanningLocal
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white)))
                      : parent._localSongs.isEmpty
                          ? GlassContainer(
                              borderRadius: 12,
                              child: const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No local audio files found in Music or Downloads.', style: TextStyle(color: Colors.white54)),
                              ),
                            )
                          : Column(
                              children: parent._localSongs.map((song) => Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: GlassContainer(
                                  borderRadius: 12,
                                  child: ListTile(
                                    leading: Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.music_note, color: Colors.white, size: 20),
                                    ),
                                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                    onTap: () => parent._playSong(song, newQueue: parent._localSongs, index: parent._localSongs.indexOf(song)),
                                  ),
                                ),
                              )).toList(),
                            ),
                  const SizedBox(height: 20),
                  const Text('Liked Songs', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  parent._likedSongs.isEmpty
                      ? GlassContainer(
                          borderRadius: 12,
                          child: const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('No liked songs saved yet.', style: TextStyle(color: Colors.white54)),
                          ),
                        )
                      : Column(
                          children: parent._likedSongs.map((song) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: GlassContainer(
                              borderRadius: 12,
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: song.thumbnailUrl.isNotEmpty
                                      ? Image.network(song.thumbnailUrl, width: 40, height: 40, fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(width: 40, height: 40, color: Colors.white24))
                                      : Container(width: 40, height: 40, color: Colors.white24, child: const Icon(Icons.music_note)),
                                ),
                                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.favorite, color: Colors.white),
                                  onPressed: () => parent._toggleLike(song),
                                ),
                                onTap: () => parent._playSong(song, newQueue: parent._likedSongs, index: parent._likedSongs.indexOf(song)),
                              ),
                            ),
                          )).toList(),
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

class SettingsScreen extends StatelessWidget {
  final _MainContainerState parent;
  const SettingsScreen({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    final appState = OverrideMusicApp.of(context);
    final currentKey = appState?._currentThemeKey ?? 'indigo';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text('Appearance & Theme', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GlassContainer(
              borderRadius: 14,
              child: ListTile(
                title: const Text('Color Theme', style: TextStyle(color: Colors.white)),
                subtitle: Text('Current: ${currentKey.toUpperCase()}', style: const TextStyle(color: Colors.white54)),
                trailing: DropdownButton<String>(
                  value: currentKey,
                  dropdownColor: const Color(0xFF181C32),
                  style: const TextStyle(color: Colors.white),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'indigo', child: Text('Pixel 10 Indigo')),
                    DropdownMenuItem(value: 'black', child: Text('Pure Obsidian')),
                    DropdownMenuItem(value: 'midnight', child: Text('Midnight Slate')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      appState?.setTheme(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Storage & Data', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GlassContainer(
              borderRadius: 14,
              child: ListTile(
                title: const Text('Clear Recently Played History', style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onTap: () {
                  parent.clearRecentHistory();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History cleared')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  final _MainContainerState parent;
  const MiniPlayer({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    final song = parent._currentSong!;
    return GestureDetector(
      onTap: parent._openNowPlaying,
      child: GlassContainer(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: song.thumbnailUrl.isNotEmpty
                  ? Image.network(song.thumbnailUrl, width: 44, height: 44, fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(width: 44, height: 44, color: Colors.white24))
                  : Container(width: 44, height: 44, color: Colors.white24, child: const Icon(Icons.music_note, size: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(parent._isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
              onPressed: () {
                if (parent._isPlaying) {
                  parent._audioPlayer.pause();
                } else {
                  parent._audioPlayer.play();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class FullPlayerSheet extends StatelessWidget {
  final _MainContainerState parent;
  const FullPlayerSheet({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    final song = parent._currentSong!;
    final isLiked = parent._isLiked(song);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141728),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
              const Text('NOW PLAYING', style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 30),
            ],
          ),
          const SizedBox(height: 30),
          GlassContainer(
            borderRadius: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: song.thumbnailUrl.isNotEmpty
                  ? Image.network(song.thumbnailUrl, width: 280, height: 280, fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(width: 280, height: 280, color: Colors.white24, child: const Icon(Icons.music_note, size: 80)))
                  : Container(width: 280, height: 280, color: Colors.white24, child: const Icon(Icons.music_note, size: 80)),
            ),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Colors.white54)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border_rounded, color: isLiked ? Colors.white : Colors.white54, size: 28),
                onPressed: () => parent._toggleLike(song),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (parent._isLoadingTrack)
            const CircularProgressIndicator(color: Colors.white)
          else if (parent._errorMessage != null)
            Text(parent._errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 40),
                onPressed: parent._queue.isNotEmpty
                    ? () {
                        int newIndex = (parent._queueIndex - 1) % parent._queue.length;
                        parent._playSong(parent._queue[newIndex], newQueue: parent._queue, index: newIndex);
                      }
                    : null,
              ),
              const SizedBox(width: 30),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15),
                  border: Border.all(color: Colors.white24),
                ),
                child: IconButton(
                  icon: Icon(parent._isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 40),
                  onPressed: () {
                    if (parent._isPlaying) {
                      parent._audioPlayer.pause();
                    } else {
                      parent._audioPlayer.play();
                    }
                  },
                ),
              ),
              const SizedBox(width: 30),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 40),
                onPressed: parent._queue.isNotEmpty
                    ? () {
                        int newIndex = (parent._queueIndex + 1) % parent._queue.length;
                        parent._playSong(parent._queue[newIndex], newQueue: parent._queue, index: newIndex);
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
