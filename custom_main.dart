import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TidalAmoledApp());
}

class TidalAmoledApp extends StatelessWidget {
  const TidalAmoledApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tidal Hi-Fi',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF121212),
          primary: Colors.white,
          secondary: Colors.grey,
        ),
      ),
      home: const MusicPlayerScreen(),
    );
  }
}

class Song {
  final String title;
  final String artist;
  final String url;
  final String albumArt;

  Song({
    required this.title,
    required this.artist,
    required this.url,
    required this.albumArt,
  });
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  late final AudioPlayer _audioPlayer;
  
  // High fidelity public domain streams that will never break
  final List<Song> _playlist = [
    Song(
      title: 'Symphony No. 9 (Ode to Joy)',
      artist: 'Ludwig van Beethoven',
      url: 'https://upload.wikimedia.org/wikipedia/commons/b/b4/Beethoven_Symphony_9_1_Allegro_ma_non_troppo_Furtw%C3%A4ngler.ogg',
      albumArt: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=600&q=80',
    ),
    Song(
      title: 'The Goldberg Variations, BWV 988',
      artist: 'Johann Sebastian Bach',
      url: 'https://upload.wikimedia.org/wikipedia/commons/e/e8/JS_Bach_Goldberg_Variations_BWV_988_Marina_Milstein.ogg',
      albumArt: 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?auto=format&fit=crop&w=600&q=80',
    ),
    Song(
      title: 'Moonlight Sonata (Adagio sostenuto)',
      artist: 'Ludwig van Beethoven',
      url: 'https://upload.wikimedia.org/wikipedia/commons/3/32/Beethoven_Moonlight_1st_movement.ogg',
      albumArt: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=600&q=80',
    ),
  ];

  int _currentIndex = 0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _audioPlayer.setUrl(_playlist[_currentIndex].url);
      _audioPlayer.playerStateStream.listen((state) {
        setState(() {
          _isPlaying = state.playing;
        });
      });
    } catch (e) {
      debugPrint("Error loading track: $e");
    }
  }

  void _playSong(int index) async {
    setState(() {
      _currentIndex = index;
    });
    await _audioPlayer.setUrl(_playlist[_currentIndex].url);
    await _audioPlayer.play();
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = _playlist[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'T I D A L   H I - F I',
          style: TextStyle(
            color: Colors.white,
            letterSpacing: 3,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Square Album Art 1:1 Tidal style
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.05),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      currentSong.albumArt,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // Title and Artist
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentSong.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          currentSong.artist,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'MAX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: () {
                      int newIndex = (_currentIndex - 1) % _playlist.length;
                      if (newIndex < 0) newIndex = _playlist.length - 1;
                      _playSong(newIndex);
                    },
                  ),
                  const SizedBox(width: 30),
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 48,
                      color: Colors.black,
                      icon: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                  ),
                  const SizedBox(width: 30),
                  IconButton(
                    iconSize: 36,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: () {
                      int newIndex = (_currentIndex + 1) % _playlist.length;
                      _playSong(newIndex);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'QUEUE / MASTER TRACKS',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _playlist.length,
                  itemBuilder: (context, index) {
                    final song = _playlist[index];
                    final isSelected = index == _currentIndex;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          song.albumArt,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[300],
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                      ),
                      subtitle: Text(
                        song.artist,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.bar_chart_rounded, color: Colors.white)
                          : null,
                      onTap: () => _playSong(index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
