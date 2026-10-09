class SearchResultPodcast {
  final String title;
  final String author;
  final String rssUrl;
  final String imageUrl;
  final String description;
  final String websiteUrl;
  final List<String> categories;
  final int? episodeCount;
  final String? language;
  final String providerId;

  const SearchResultPodcast({
    required this.title,
    required this.author,
    required this.rssUrl,
    required this.imageUrl,
    required this.description,
    required this.websiteUrl,
    this.categories = const [],
    this.episodeCount,
    this.language,
    required this.providerId,
  });


  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      'rssUrl': rssUrl,
      'imageUrl': imageUrl,
      'description': description,
      'websiteUrl': websiteUrl,
      'categories': categories,
      'episodeCount': episodeCount,
      'language': language,
      'providerId': providerId,
    };
  }
}
