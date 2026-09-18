import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/search_result_podcast.dart';
import '../../../core/providers/app_providers.dart';
import '../../discovery/discovery_notifier.dart';
import '../../podcasts/rss_feed_parser.dart';
import '../widgets/bidi_text.dart';

class PodcastDiscoveryView extends ConsumerStatefulWidget {
  const PodcastDiscoveryView({super.key});

  @override
  ConsumerState<PodcastDiscoveryView> createState() => _PodcastDiscoveryViewState();
}

class _PodcastDiscoveryViewState extends ConsumerState<PodcastDiscoveryView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  final Set<String> _subscribingUrls = {};

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(discoveryNotifierProvider.notifier).search(query);
    });
  }

  Future<void> _subscribePodcast(SearchResultPodcast item) async {
    if (_subscribingUrls.contains(item.rssUrl)) return;
    setState(() {
      _subscribingUrls.add(item.rssUrl);
    });

    try {
      final success = await ref.read(podcastsNotifierProvider.notifier).addPodcastFeed(item.rssUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Subscribed to "${item.title}"'
                  : 'Failed to subscribe to "${item.title}"',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _subscribingUrls.remove(item.rssUrl);
        });
      }
    }
  }

  void _showPodcastDetails(SearchResultPodcast item, bool isSubscribed) {
    showDialog(
      context: context,
      builder: (context) {
        return _PodcastPreviewDialog(
          item: item,
          isSubscribed: isSubscribed,
          isSubscribing: _subscribingUrls.contains(item.rssUrl),
          onSubscribe: () => _subscribePodcast(item),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryNotifierProvider);
    final searchService = ref.watch(multisourceSearchServiceProvider);
    final podcastsAsync = ref.watch(podcastsNotifierProvider);

    final subscribedUrls = podcastsAsync.when(
      data: (list) => list.map((p) => p.rssUrl).toSet(),
      loading: () => <String>{},
      error: (_, _) => <String>{},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Podcasts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              if (discoveryState.currentQuery.isNotEmpty) {
                ref.read(discoveryNotifierProvider.notifier).search(discoveryState.currentQuery);
              } else {
                ref.read(discoveryNotifierProvider.notifier).loadTrending();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 540;
                final searchField = ListenableBuilder(
                  listenable: _searchController,
                  builder: (context, _) {
                    return TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) {
                        FocusScope.of(context).unfocus();
                      },
                      decoration: InputDecoration(
                        hintText: isNarrow
                            ? 'Search podcasts...'
                            : 'Search podcasts (e.g. Technology, News, Science)...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _debounceTimer?.cancel();
                                  _searchController.clear();
                                  ref.read(discoveryNotifierProvider.notifier).loadTrending();
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    );
                  },
                );

                final providerDropdown = (searchService.availableProviders.length > 1)
                    ? DropdownButton<String>(
                        value: discoveryState.activeProviderId,
                        onChanged: (newId) {
                          if (newId != null) {
                            ref.read(discoveryNotifierProvider.notifier).setActiveProvider(newId);
                          }
                        },
                        items: searchService.availableProviders.map((p) {
                          return DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(p.displayName),
                          );
                        }).toList(),
                      )
                    : null;

                if (isNarrow && providerDropdown != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('Source: ', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: 8),
                          providerDropdown,
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    if (providerDropdown != null) ...[
                      const SizedBox(width: 12),
                      providerDropdown,
                    ],
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Text(
                  discoveryState.isTrending
                      ? '🔥 Trending Podcasts'
                      : 'Search Results (${discoveryState.results.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildBody(discoveryState, subscribedUrls),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DiscoveryState discoveryState, Set<String> subscribedUrls) {
    if (discoveryState.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Searching podcast directories...'),
          ],
        ),
      );
    }

    if (discoveryState.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 56, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                discoveryState.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                onPressed: () {
                  if (discoveryState.currentQuery.isNotEmpty) {
                    ref.read(discoveryNotifierProvider.notifier).search(discoveryState.currentQuery);
                  } else {
                    ref.read(discoveryNotifierProvider.notifier).loadTrending();
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (discoveryState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              discoveryState.isTrending
                  ? 'No trending podcasts found.'
                  : 'No podcasts matched "${discoveryState.currentQuery}".',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1400
            ? 4
            : (constraints.maxWidth > 950 ? 3 : (constraints.maxWidth > 600 ? 2 : 1));

        if (crossAxisCount == 1) {
          return ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: discoveryState.results.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (context, index) {
              final item = discoveryState.results[index];
              final isSubscribed = subscribedUrls.contains(item.rssUrl);
              final isSubscribing = _subscribingUrls.contains(item.rssUrl);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Icon(Icons.podcasts, size: 40),
                          )
                        : const Icon(Icons.podcasts, size: 40),
                  ),
                  title: BidiText(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    item.author.isNotEmpty ? item.author : item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: isSubscribed
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : (isSubscribing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_circle_outline)),
                    onPressed: isSubscribed || isSubscribing
                        ? null
                        : () => _subscribePodcast(item),
                  ),
                  onTap: () => _showPodcastDetails(item, isSubscribed),
                ),
              );
            },
          );
        }

        return GridView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 3.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: discoveryState.results.length,
          itemBuilder: (context, index) {
            final item = discoveryState.results[index];
            final isSubscribed = subscribedUrls.contains(item.rssUrl);
            final isSubscribing = _subscribingUrls.contains(item.rssUrl);

            return Card(
              child: InkWell(
                onTap: () => _showPodcastDetails(item, isSubscribed),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(Icons.podcasts, size: 40),
                              )
                            : const Icon(Icons.podcasts, size: 40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            BidiText(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.author.isNotEmpty ? item.author : item.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: isSubscribed || isSubscribing
                            ? null
                            : () => _subscribePodcast(item),
                        child: isSubscribed
                            ? const Icon(Icons.check, size: 18)
                            : (isSubscribing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Subscribe')),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PodcastPreviewDialog extends ConsumerStatefulWidget {
  final SearchResultPodcast item;
  final bool isSubscribed;
  final bool isSubscribing;
  final VoidCallback onSubscribe;

  const _PodcastPreviewDialog({
    required this.item,
    required this.isSubscribed,
    required this.isSubscribing,
    required this.onSubscribe,
  });

  @override
  ConsumerState<_PodcastPreviewDialog> createState() => _PodcastPreviewDialogState();
}

class _PodcastPreviewDialogState extends ConsumerState<_PodcastPreviewDialog> {
  Future<RssFeedResult?>? _feedFuture;

  @override
  void initState() {
    super.initState();
    if (widget.item.rssUrl.isNotEmpty) {
      _feedFuture = RssFeedParser().parseFeedFromUrl(widget.item.rssUrl).catchError((_) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: widget.item.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.item.imageUrl,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Icon(Icons.podcasts, size: 48),
                          )
                        : const Icon(Icons.podcasts, size: 48),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BidiText(
                          widget.item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.item.author.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.item.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (widget.item.categories.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: widget.item.categories.take(3).map((c) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(c, style: const TextStyle(fontSize: 10)),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.item.description.isNotEmpty) ...[
                    Text(
                      'About',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    BidiText(
                      widget.item.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.item.websiteUrl.isNotEmpty) ...[
                    InkWell(
                      onTap: () async {
                        final uri = Uri.tryParse(widget.item.websiteUrl);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.language, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Visit Website',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Recent Episodes',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_feedFuture != null)
                    FutureBuilder<RssFeedResult?>(
                      future: _feedFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final feed = snapshot.data;
                        if (feed == null || feed.episodes.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Episode preview not available for this feed.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        final previewEpisodes = feed.episodes.take(5).toList();
                        return Column(
                          children: previewEpisodes.map((ep) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: BidiText(
                                ep.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: ep.duration > 0
                                  ? Text('${(ep.duration / 60).round()} min',
                                      style: const TextStyle(fontSize: 11))
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.play_circle_outline, size: 24),
                                tooltip: 'Preview Play',
                                onPressed: () {
                                  ref.read(audioHandlerProvider).playEpisode(ep);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Playing preview: ${ep.title}'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            );
                          }).toList(),
                        );
                      },
                    )
                  else
                    const Text('No episodes preview available.'),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: widget.isSubscribed
                        ? const Icon(Icons.check, size: 18)
                        : (widget.isSubscribing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add, size: 18)),
                    label: Text(widget.isSubscribed ? 'Subscribed' : 'Subscribe'),
                    onPressed: widget.isSubscribed || widget.isSubscribing
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.onSubscribe();
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
