import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/record.dart';

/// "Search the web" — the same person search, run against outside sources
/// the way FamilySearch links out to other sites. Wikipedia matches load
/// inline (its public API allows browser requests without a key); every
/// other site opens in an in-app browser with the query pre-filled.
class WebSearchSection extends StatefulWidget {
  const WebSearchSection({
    super.key,
    required this.firstName,
    required this.lastName,
    this.year,
    this.place = '',
    this.country = '',
    this.type,
  });

  final String firstName;
  final String lastName;
  final int? year;

  /// State / province / town, if given.
  final String place;
  final String country;
  final RecordType? type;

  @override
  State<WebSearchSection> createState() => _WebSearchSectionState();
}

class _WikiHit {
  const _WikiHit(this.title, this.snippet);
  final String title;
  final String snippet;
}

class _WebSearchSectionState extends State<WebSearchSection> {
  List<_WikiHit>? _wiki;
  bool _wikiFailed = false;

  String get _name =>
      '${widget.firstName.trim()} ${widget.lastName.trim()}'.trim();

  /// Google-style query: the exact name in quotes plus only the details
  /// the user actually entered, e.g. `"Emeka Okafor" 1905 Nnewi birth record`.
  /// The country is deliberately left out — it's just the dropdown's
  /// pre-selected default, and adding it (or filler like "genealogy")
  /// narrows a name search to pages that happen to repeat those words.
  String get _webQuery {
    final List<String> parts = <String>[
      if (_name.contains(' ')) '"$_name"' else if (_name.isNotEmpty) _name,
      if (widget.year != null) '${widget.year}',
      if (widget.place.trim().isNotEmpty) widget.place.trim(),
      if (widget.type != null && widget.type != RecordType.other)
        '${widget.type!.label.toLowerCase()} record',
    ];
    return parts.join(' ');
  }

  /// Wikipedia's search works best with fewer, looser terms.
  String get _wikiQuery => <String>[
    _name,
    if (widget.place.trim().isNotEmpty) widget.place.trim(),
  ].join(' ');

  @override
  void initState() {
    super.initState();
    _loadWikipedia();
  }

  @override
  void didUpdateWidget(covariant WebSearchSection old) {
    super.didUpdateWidget(old);
    if (old.firstName != widget.firstName ||
        old.lastName != widget.lastName ||
        old.place != widget.place ||
        old.country != widget.country) {
      _loadWikipedia();
    }
  }

  Future<void> _loadWikipedia() async {
    setState(() {
      _wiki = null;
      _wikiFailed = false;
    });
    if (_name.isEmpty) {
      setState(() => _wiki = const <_WikiHit>[]);
      return;
    }
    final String query = _wikiQuery;
    try {
      final Uri uri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'srlimit': '5',
        'format': 'json',
        'origin': '*',
      });
      final http.Response res = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (!mounted || query != _wikiQuery) return;
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final List<dynamic> hits =
          ((jsonDecode(res.body) as Map<String, dynamic>)['query']
                  as Map<String, dynamic>?)?['search']
              as List<dynamic>? ??
          const <dynamic>[];
      setState(() {
        _wiki = hits.map((h) {
          final Map<String, dynamic> m = h as Map<String, dynamic>;
          return _WikiHit(
            m['title'] as String? ?? '',
            _stripHtml(m['snippet'] as String? ?? ''),
          );
        }).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _wikiFailed = true);
    }
  }

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  Future<void> _open(Uri uri) async {
    // In the iOS/Android app this is an in-app browser (Safari View
    // Controller / Chrome Custom Tab) layered over RootSphere with a Done
    // button. On the web, sites like Google refuse to be embedded in another
    // page, so a new tab is the closest equivalent.
    final bool ok = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  /// Given name(s) and surname for sites with separate fields. When only the
  /// first-name box was filled with a full name ("Abraham Nweze Eze-David"),
  /// its last word is taken as the surname — FamilySearch and Find a Grave
  /// match far better with a surname than with everything as given names.
  (String, String) get _splitName {
    final String first = widget.firstName.trim();
    final String last = widget.lastName.trim();
    if (last.isNotEmpty || !first.contains(' ')) return (first, last);
    final List<String> words = first.split(RegExp(r'\s+'));
    return (words.sublist(0, words.length - 1).join(' '), words.last);
  }

  List<(String, String, Uri)> get _sites {
    final String q = _webQuery;
    final (String given, String surname) = _splitName;
    // Country only qualifies a place the user actually picked (e.g.
    // "Enugu, Nigeria"); on its own it's just the dropdown default.
    final String place = widget.place.trim().isEmpty
        ? ''
        : <String>[
            widget.place.trim(),
            widget.country.trim(),
          ].where((s) => s.isNotEmpty).join(', ');
    return <(String, String, Uri)>[
      (
        'Google',
        'assets/images/site_logo_google.png',
        Uri.https('www.google.com', '/search', {'q': q}),
      ),
      (
        'Google Books',
        // books.google.com uses the plain Google "G" as its icon.
        'assets/images/site_logo_google.png',
        Uri.https('www.google.com', '/search', {'q': q, 'tbm': 'bks'}),
      ),
      (
        'Wikipedia',
        'assets/images/site_logo_wikipedia.png',
        Uri.https('en.wikipedia.org', '/w/index.php', {
          'search': _wikiQuery,
          'fulltext': '1',
        }),
      ),
      (
        'FamilySearch',
        'assets/images/site_logo_familysearch.png',
        Uri.https('www.familysearch.org', '/search/record/results', {
          if (given.isNotEmpty) 'q.givenName': given,
          if (surname.isNotEmpty) 'q.surname': surname,
          if (widget.year != null) ...<String, String>{
            'q.birthLikeDate.from': '${widget.year! - 2}',
            'q.birthLikeDate.to': '${widget.year! + 2}',
          },
          if (place.isNotEmpty) 'q.birthLikePlace': place,
        }),
      ),
      (
        'Find a Grave',
        'assets/images/site_logo_findagrave.png',
        Uri.https('www.findagrave.com', '/memorial/search', {
          if (given.isNotEmpty) 'firstname': given,
          if (surname.isNotEmpty) 'lastname': surname,
          if (widget.year != null) 'birthyear': '${widget.year}',
          if (place.isNotEmpty) 'location': place,
        }),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final Color muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('SEARCH THE WEB', style: text.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Search for “$_webQuery” on other sites.',
          style: text.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final (String label, String logo, Uri uri) in _sites)
              ActionChip(
                avatar: _SiteLogo(logo),
                label: Text(label),
                onPressed: () => _open(uri),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: <Widget>[
            const _SiteLogo('assets/images/site_logo_wikipedia.png'),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'From Wikipedia',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_wikiFailed)
          Text(
            "Couldn't reach Wikipedia right now.",
            style: text.bodySmall?.copyWith(color: muted),
          )
        else if (_wiki == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_wiki!.isEmpty)
          Text(
            'No Wikipedia articles mention this name.',
            style: text.bodySmall?.copyWith(color: muted),
          )
        else
          for (final _WikiHit hit in _wiki!)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                title: Text(
                  hit.title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${hit.snippet}…',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _open(
                  Uri.https(
                    'en.wikipedia.org',
                    '/wiki/${hit.title.replaceAll(' ', '_')}',
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// A site's logo on a small white tile, so dark marks (Wikipedia's "W",
/// Find a Grave's headstone) stay visible in dark mode.
class _SiteLogo extends StatelessWidget {
  const _SiteLogo(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}
