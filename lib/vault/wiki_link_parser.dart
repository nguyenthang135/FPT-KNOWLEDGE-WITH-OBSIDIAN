class WikiLinkParser {
  static List<String> extractWikiLinks(String content) {
    final regex = RegExp(r'\[\[([^\]]+)\]\]');

    return regex.allMatches(content).map((match) => match.group(1)!).toList();
  }
}
