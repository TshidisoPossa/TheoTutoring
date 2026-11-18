// Splits a migration file the way the mysql command-line client does, so
// the database tests can run it through the driver: `DELIMITER x` lines
// change the statement terminator (they are client commands, not SQL), and
// comment-only lines between statements are dropped.

/// The statements of [script], without their terminators.
List<String> sqlScriptStatements(String script) {
  final statements = <String>[];
  var delimiter = ';';
  final current = StringBuffer();
  for (final raw in script.split('\n')) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (current.isEmpty && (trimmed.isEmpty || trimmed.startsWith('--'))) {
      continue;
    }
    if (current.isEmpty && trimmed.toUpperCase().startsWith('DELIMITER ')) {
      delimiter = trimmed.substring('DELIMITER '.length).trim();
      continue;
    }
    current.writeln(line);
    if (!trimmed.startsWith('--') && trimmed.endsWith(delimiter)) {
      final text = current.toString().trim();
      final statement = text
          .substring(0, text.length - delimiter.length)
          .trim();
      if (statement.isNotEmpty) statements.add(statement);
      current.clear();
    }
  }
  final rest = current.toString().trim();
  if (rest.isNotEmpty) statements.add(rest);
  return statements;
}
