import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math';

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
    systemNavigationBarColor: Colors.black,
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
  String _currentThemeKey = 'amoled';

  final Map<String, Color> themes = {
    'amoled': Colors.black,
    'indigo': const Color(0xFF14182E),
    'pink': const Color(0xFF2E1422),
  };

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentThemeKey = prefs.getString('app_theme') ?? 'amoled';
    });
  }

  Future<void> setTheme(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', key);
    setState(() {
      _currentThemeKey = key;
    });
  }

  Color get currentBackgroundColor => themes[_currentThemeKey] ?? Colors.black;

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
  final AudioPlayer audioPlayer = AudioPlayer();
  
  Song? currentSong;
  List<Song> queue = [];
  int queueIndex = 0;
  bool isPlaying = false;
  bool isLoadingTrack = false;
  String? errorMessage;

  List<Song> likedSongs = [];
  List<Song> recentSongs = [];
  List<Song> searchResults = [];
  List<Song> localSongs = [];
  bool isSearching = false;
  bool isScanningLocal = false;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissionsAndScan();
    audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          isPlaying = state.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? likedJson = prefs.getString('liked_songs');
    if (likedJson != null) {
      final List decoded = jsonDecode(likedJson);
      likedSongs = decoded.map((e) => Song.fromJson(e)).toList();
    }

    final String? recentJson = prefs.getString('recent_songs');
    if (recentJson != null) {
      final List decoded = jsonDecode(recentJson);
      recentSongs = decoded.map((e) => Song.fromJson(e)).toList();
    }
    setState(() {});
  }

  Future<void> saveLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(likedSongs.map((e) => e.toJson()).toList());
    await prefs.setString('liked_songs', encoded);
  }

  Future<void> saveRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(recentSongs.map((e) => e.toJson()).toList());
    await prefs.setString('recent_songs', encoded);
  }

  Future<void> _requestPermissionsAndScan() async {
    if (Platform.isAndroid) {
      PermissionStatus status = await Permission.audio.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    }
    _scanLocalFiles();
  }

  Future<void> _scanLocalFiles() async {
    setState(() => isScanningLocal = true);
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
                    author: 'Local Device',
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
          localSongs = foundSongs;
          isScanningLocal = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isScanningLocal = false);
    }
  }

  void _addToRecents(Song song) {
    setState(() {
      recentSongs.removeWhere((s) => s.videoId == song.videoId);
      recentSongs.insert(0, song);
      if (recentSongs.length > 20) recentSongs.removeLast();
    });
    saveRecentSongs();
  }

  bool isLiked(Song song) => likedSongs.any((s) => s.videoId == song.videoId);

  void toggleLike(Song song) {
    setState(() {
      if (isLiked(song)) {
        likedSongs.removeWhere((s) => s.videoId == song.videoId);
      } else {
        likedSongs.add(song);
      }
    });
    saveLikedSongs();
  }

  Future<void> playSong(Song song, {List<Song>? newQueue, int index = 0}) async {
    setState(() {
      currentSong = song;
      isLoadingTrack = true;
      errorMessage = null;
      if (newQueue != null) {
        queue = newQueue;
        queueIndex = index;
      }
    });

    _addToRecents(song);

    try {
      if (song.isLocal && song.filePath != null) {
        await audioPlayer.setFilePath(song.filePath!);
        await audioPlayer.play();
        if (mounted) setState(() => isLoadingTrack = false);
        return;
      }

      var yt = yt_explode.YoutubeExplode();
      var manifest = await yt.videos.streamsClient.getManifest(song.videoId);
      var audioStream = manifest.audioOnly.withHighestBitrate();
      var audioUrl = audioStream.url.toString();
      yt.close();

      await audioPlayer.setUrl(audioUrl);
      await audioPlayer.play();

      if (mounted) setState(() => isLoadingTrack = false);
    } catch (_) {
      try {
        var yt = yt_explode.YoutubeExplode();
        await yt.videos.get(song.videoId);
        yt.close();
        if (mounted) setState(() => isLoadingTrack = false);
      } catch (_) {}

      if (mounted) {
        setState(() {
          isLoadingTrack = false;
          errorMessage = "Stream unavailable. Try another track.";
        });
      }
    }
  }

  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      isSearching = true;
      searchResults = [];
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

    if (results.isEmpty) {
      try {
        var yt = yt_explode.YoutubeExplode();
        var ytResults = await yt.search.search(query);
        for (var video in ytResults) {
          results.add(Song(
            videoId: video.id.value,
            title: video.title,
            author: video.author,
            thumbnailUrl: video.thumbnails.highResUrl,
          ));
        }
        yt.close();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        searchResults = results;
        isSearching = false;
      });
    }
  }

  void openNowPlaying() {
    if (currentSong == null) return;
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
          if (currentSong != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 82,
              child: MiniPlayer(parent: this),
            ),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
          child: Container(
            color: Colors.black.withOpacity(0.8),
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

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.02),
                ],
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'OVERRIDE',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 26),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SettingsScreen(parent: parent)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            LiquidGlassCard(
              borderRadius: 32,
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 18),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        SizedBox(height: 4),
                        Text('High-Fidelity Audio Streaming', style: TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Recently Played',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: parent.recentSongs.isEmpty
                  ? const Center(
                      child: Text(
                        'No history yet. Search music or play local tracks!',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: parent.recentSongs.length,
                      itemBuilder: (context, index) {
                        final song = parent.recentSongs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: LiquidGlassCard(
                            borderRadius: 24,
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: song.thumbnailUrl.isNotEmpty
                                    ? Image.network(song.thumbnailUrl, width: 50, height: 50, fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(width: 50, height: 50, color: Colors.white24, child: const Icon(Icons.music_note)))
                                    : Container(width: 50, height: 50, color: Colors.white24, child: const Icon(Icons.audio_file)),
                              ),
                              title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              onTap: () => parent.playSong(song, newQueue: parent.recentSongs, index: index),
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

class SearchTab extends StatelessWidget {
  final _MainContainerState parent;
  const SearchTab({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            LiquidGlassCard(
              borderRadius: 24,
              child: TextField(
                controller: parent.searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search YouTube music catalog...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
                onSubmitted: (val) => parent.searchMusic(val),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: parent.isSearching
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : parent.searchResults.isEmpty
                      ? const Center(child: Text('Type a query above to stream music.', style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          itemCount: parent.searchResults.length,
                          itemBuilder: (context, index) {
                            final song = parent.searchResults[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: LiquidGlassCard(
                                borderRadius: 24,
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: song.thumbnailUrl.isNotEmpty
                                        ? Image.network(song.thumbnailUrl, width: 50, height: 50, fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => Container(width: 50, height: 50, color: Colors.white24))
                                        : Container(width: 50, height: 50, color: Colors.white24, child: const Icon(Icons.music_note)),
                                  ),
                                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                  subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  onTap: () => parent.playSong(song, newQueue: parent.searchResults, index: index),
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

class LibraryTab extends StatelessWidget {
  final _MainContainerState parent;
  const LibraryTab({super.key, required this.parent});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Library',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: parent._scanLocalFiles,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  const Text('Local Files', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  parent.localSongs.isEmpty
                      ? LiquidGlassCard(
                          borderRadius: 24,
                          child: const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text('Scanning local device storage...', style: TextStyle(color: Colors.white54)),
                          ),
                        )
                      : Column(
                          children: parent.localSongs.map((song) => Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: LiquidGlassCard(
                              borderRadius: 22,
                              child: ListTile(
                                leading: Container(
                                  width: 46, height: 46,
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.music_note, color: Colors.white, size: 22),
                                ),
                                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                onTap: () => parent.playSong(song, newQueue: parent.localSongs, index: parent.localSongs.indexOf(song)),
                              ),
                            ),
                          )).toList(),
                        ),
                  const SizedBox(height: 24),
                  const Text('Liked Songs', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  parent.likedSongs.isEmpty
                      ? LiquidGlassCard(
                          borderRadius: 24,
                          child: const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text('No favorite tracks saved yet.', style: TextStyle(color: Colors.white54)),
                          ),
                        )
                      : Column(
                          children: parent.likedSongs.map((song) => Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: LiquidGlassCard(
                              borderRadius: 22,
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: song.thumbnailUrl.isNotEmpty
                                      ? Image.network(song.thumbnailUrl, width: 46, height: 46, fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(width: 46, height: 46, color: Colors.white24))
                                      : Container(width: 46, height: 46, color: Colors.white24, child: const Icon(Icons.music_note)),
                                ),
                                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.favorite, color: Colors.white),
                                  onPressed: () => parent.toggleLike(song),
                                ),
                                onTap: () => parent.playSong(song, newQueue: parent.likedSongs, index: parent.likedSongs.indexOf(song)),
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
    final currentKey = appState?._currentThemeKey ?? 'amoled';

    return Scaffold(
      backgroundColor: appState?.currentBackgroundColor ?? Colors.black,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            const Text('Appearance & Theme', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LiquidGlassCard(
              borderRadius: 24,
              child: ListTile(
                title: const Text('Color Theme', style: TextStyle(color: Colors.white)),
                subtitle: Text('Current: ${currentKey.toUpperCase()}', style: const TextStyle(color: Colors.white54)),
                trailing: DropdownButton<String>(
                  value: currentKey,
                  dropdownColor: const Color(0xFF141414),
                  style: const TextStyle(color: Colors.white),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'amoled', child: Text('Pure AMOLED Black')),
                    DropdownMenuItem(value: 'indigo', child: Text('Pixel 10 Indigo')),
                    DropdownMenuItem(value: 'pink', child: Text('Neon Pink')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      appState?.setTheme(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Storage & Data', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LiquidGlassCard(
              borderRadius: 24,
              child: ListTile(
                title: const Text('Clear Recently Played History', style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onTap: () {
                  parent.recentSongs.clear();
                  parent.saveRecentSongs();
                  parent.setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History cleared successfully')),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text('Extras', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LiquidGlassCard(
              borderRadius: 24,
              child: ListTile(
                leading: const Icon(Icons.sports_esports_rounded, color: Colors.white),
                title: const Text('Secret Game Arcade', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Launch mini game', style: TextStyle(color: Colors.white54, fontSize: 11)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SecretGameScreen()),
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

class SecretGameScreen extends StatefulWidget {
  const SecretGameScreen({super.key});

  @override
  State<SecretGameScreen> createState() => _SecretGameScreenState();
}

class _SecretGameScreenState extends State<SecretGameScreen> {
  int _score = 0;
  int _timeLeft = 25;
  bool _isPlaying = false;
  Timer? _gameTimer;
  Timer? _targetTimer;
  double _targetX = 0.5;
  double _targetY = 0.5;
  bool _targetVisible = false;

  void _startGame() {
    setState(() {
      _score = 0;
      _timeLeft = 25;
      _isPlaying = true;
      _spawnTarget();
    });

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          _stopGame();
        }
      });
    });
  }

  void _spawnTarget() {
    if (!_isPlaying) return;
    final random = Random();
    setState(() {
      _targetX = 0.15 + random.nextDouble() * 0.7;
      _targetY = 0.2 + random.nextDouble() * 0.6;
      _targetVisible = true;
    });

    _targetTimer?.cancel();
    _targetTimer = Timer(const Duration(milliseconds: 1100), () {
      if (_isPlaying) _spawnTarget();
    });
  }

  void _shootTarget() {
    if (!_isPlaying || !_targetVisible) return;
    setState(() {
      _score += 100;
      _targetVisible = false;
    });
    _targetTimer?.cancel();
    _spawnTarget();
  }

  void _stopGame() {
    _gameTimer?.cancel();
    _targetTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _targetVisible = false;
    });
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _targetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Arcade Zone', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Time: ${_timeLeft}s', style: const TextStyle(fontSize: 18, color: Colors.white54)),
                  Text('Score: $_score', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                ],
              ),
              const SizedBox(height: 16),
              if (!_isPlaying)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                  onPressed: _startGame,
                  child: const Text('Start Game', style: TextStyle(color: Colors.white)),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: LiquidGlassCard(
                  borderRadius: 32,
                  child: Stack(
                    children: [
                      const Center(child: Icon(Icons.add, color: Colors.white24, size: 40)),
                      if (_isPlaying && _targetVisible)
                        Positioned(
                          left: MediaQuery.of(context).size.width * _targetX - 40,
                          top: 350 * _targetY - 40,
                          child: GestureDetector(
                            onTap: _shootTarget,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.pinkAccent,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [BoxShadow(color: Colors.pink, blurRadius: 15)],
                              ),
                              child: const Center(
                                child: CircleAvatar(radius: 10, backgroundColor: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      if (!_isPlaying)
                        Center(
                          child: Text(
                            _score > 0 ? 'Game Over!\nFinal Score: $_score' : 'Tap Start to Play!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, color: Colors.white54),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    final song = parent.currentSong!;
    return GestureDetector(
      onTap: parent.openNowPlaying,
      child: LiquidGlassCard(
        borderRadius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: song.thumbnailUrl.isNotEmpty
                  ? Image.network(song.thumbnailUrl, width: 50, height: 50, fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(width: 50, height: 50, color: Colors.white24))
                  : Container(width: 50, height: 50, color: Colors.white24, child: const Icon(Icons.music_note, size: 22)),
            ),
            const SizedBox(width: 14),
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
              icon: Icon(parent.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
              onPressed: () {
                if (parent.isPlaying) {
                  parent.audioPlayer.pause();
                } else {
                  parent.audioPlayer.play();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 1-to-1 Tidal-inspired Full Screen Player
class FullPlayerSheet extends StatelessWidget {
  final _MainContainerState parent;
  const FullPlayerSheet({super.key, required this.parent});

  String _formatDuration(Duration position, Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(position.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(position.inSeconds.remainder(60));
    String posStr = "$twoDigitMinutes:$twoDigitSeconds";

    String durMinutes = twoDigits(duration.inMinutes.remainder(60));
    String durSeconds = twoDigits(duration.inSeconds.remainder(60));
    String durStr = "$durMinutes:$durSeconds";

    return "$posStr / $durStr";
  }

  @override
  Widget build(BuildContext context) {
    final song = parent.currentSong!;
    final isLiked = parent.isLiked(song);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Blurred ambient background artwork layer inspired by Tidal
          if (song.thumbnailUrl.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.35,
                child: Image.network(
                  song.thumbnailUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.black.withOpacity(0.65)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top Header with close arrow and streaming badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 34),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('PLAYING FROM STREAM', style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Hi-Fi Master', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 26),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Massive centered album artwork card with Tidal proportions and shadow glow
                  Container(
                    width: MediaQuery.of(context).size.width * 0.82,
                    height: MediaQuery.of(context).size.width * 0.82,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 35,
                          spreadRadius: 5,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: song.thumbnailUrl.isNotEmpty
                          ? Image.network(song.thumbnailUrl, fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(color: Colors.white10, child: const Icon(Icons.music_note, size: 80, color: Colors.white54)))
                          : Container(color: Colors.white10, child: const Icon(Icons.music_note, size: 80, color: Colors.white54)),
                    ),
                  ),
                  const Spacer(),
                  // Track metadata row with favorite toggle
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 6),
                            Text(song.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, color: Colors.white54, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isLiked ? Colors.white : Colors.white54, size: 30),
                        onPressed: () => parent.toggleLike(song),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Audio progress stream builder (Tidal style slider & timestamps)
                  StreamBuilder<Duration?>(
                    stream: parent.audioPlayer.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = parent.audioPlayer.duration ?? const Duration(seconds: 1);
                      double sliderVal = position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble());

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: sliderVal,
                              min: 0.0,
                              max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                              onChanged: (val) {
                                parent.audioPlayer.seek(Duration(milliseconds: val.toInt()));
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(position, duration).split(' / ')[0], style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                Text(_formatDuration(position, duration).split(' / ')[1], style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  if (parent.isLoadingTrack)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(color: Colors.white))
                  else if (parent.errorMessage != null)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(parent.errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                  const SizedBox(height: 10),
                  // Master Control Row (Shuffle, Prev, Play/Pause, Next, Repeat)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shuffle_rounded, color: Colors.white54, size: 24),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 42),
                        onPressed: parent.queue.isNotEmpty
                            ? () {
                                int newIndex = (parent.queueIndex - 1) % parent.queue.length;
                                parent.playSong(parent.queue[newIndex], newQueue: parent.queue, index: newIndex);
                              }
                            : null,
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: IconButton(
                          icon: Icon(parent.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 40),
                          onPressed: () {
                            if (parent.isPlaying) {
                              parent.audioPlayer.pause();
                            } else {
                              parent.audioPlayer.play();
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 42),
                        onPressed: parent.queue.isNotEmpty
                            ? () {
                                int newIndex = (parent.queueIndex + 1) % parent.queue.length;
                                parent.playSong(parent.queue[newIndex], newQueue: parent.queue, index: newIndex);
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.repeat_rounded, color: Colors.white54, size: 24),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Bottom Tidal-style audio quality badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('FLAC • 24-bit / 96kHz', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
