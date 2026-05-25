import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const MaterialApp(home: MovieSearchPage()));
}

class MovieSearchPage extends StatefulWidget {
  const MovieSearchPage({super.key});

  @override
  State<MovieSearchPage> createState() => _MovieSearchPageState();
}

class _MovieSearchPageState extends State<MovieSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;

  // 核心资源站配置
  final List<Map<String, String>> _sources = [
    {"name": "量子资源", "api": "https://cj.lziapi.com/api.php/provide/vod/"},
    {"name": "非凡资源", "api": "https://cj.ffzyapi.com/api.php/provide/vod/"},
    {"name": "极速资源", "api": "https://jszyapi.com/api.php/provide/vod/"},
  ];

  // 搜索逻辑
  Future<void> _handleSearch() async {
    if (_searchController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    for (var source in _sources) {
      try {
        final response = await _dio.get(
          source['api']!,
          queryParameters: {'ac': 'list', 'wd': _searchController.text},
        );
        if (response.data['list'] != null) {
          setState(() {
            _searchResults.addAll(response.data['list'].map((item) {
              item['source_name'] = source['name'];
              item['source_api'] = source['api'];
              return item;
            }));
          });
        }
      } catch (e) {
        debugPrint("Error searching ${source['name']}: $e");
      }
    }

    setState(() => _isLoading = false);
  }

  // 获取详情并播放
  Future<void> _playMovie(dynamic movie) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await _dio.get(
        movie['source_api'],
        queryParameters: {'ac': 'detail', 'ids': movie['vod_id']},
      );

      Navigator.pop(context); // 关闭加载框

      if (response.data['list'] != null && response.data['list'].isNotEmpty) {
        String playUrlData = response.data['list'][0]['vod_play_url'];
        // 简单逻辑：提取第一个 m3u8
        String? finalUrl;
        final parts = playUrlData.split('#');
        for (var part in parts) {
          if (part.contains('m3u8')) {
            finalUrl = part.split('\$')[1];
            break;
          }
        }

        if (finalUrl != null) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerPage(
                url: finalUrl!,
                title: movie['vod_name'],
                referer: movie['source_api'],
              ),
            ),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("解析失败: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("聚合影视搜索"),
        backgroundColor: Colors.indigo,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "输入电影/电视剧名称",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSearch,
                  child: const Text("搜索"),
                ),
              ],
            ),
          ),
          if (_isLoading && _searchResults.isEmpty)
            const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final movie = _searchResults[index];
                return ListTile(
                  title: Text(movie['vod_name']),
                  subtitle: Text("${movie['type_name']} - ${movie['source_name']}"),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => _playMovie(movie),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final String referer;

  const VideoPlayerPage({
    super.key,
    required this.url,
    required this.title,
    required this.referer,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      // 关键：注入 Referer 绕过防盗链
      httpHeaders: {
        'Referer': widget.referer,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    await _videoPlayerController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      errorBuilder: (context, errorMessage) {
        return Center(child: Text("播放失败: $errorMessage", style: const TextStyle(color: Colors.white)));
      },
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: _chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(),
      ),
    );
  }
}
