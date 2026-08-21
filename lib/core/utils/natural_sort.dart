int naturalCompare(String a, String b) {
  final RegExp regex = RegExp(r'(\d+)|(\D+)');
  final Iterable<RegExpMatch> matchesA = regex.allMatches(a);
  final Iterable<RegExpMatch> matchesB = regex.allMatches(b);

  final List<String> chunksA = matchesA.map((m) => m.group(0)!).toList();
  final List<String> chunksB = matchesB.map((m) => m.group(0)!).toList();

  final int minLength = chunksA.length < chunksB.length ? chunksA.length : chunksB.length;

  for (int i = 0; i < minLength; i++) {
    final String chunkA = chunksA[i];
    final String chunkB = chunksB[i];

    final BigInt? numA = BigInt.tryParse(chunkA);
    final BigInt? numB = BigInt.tryParse(chunkB);

    if (numA != null && numB != null) {
      final int comp = numA.compareTo(numB);
      if (comp != 0) return comp;
    } else {
      final int comp = chunkA.toLowerCase().compareTo(chunkB.toLowerCase());
      if (comp != 0) return comp;
    }
  }

  return chunksA.length.compareTo(chunksB.length);
}
