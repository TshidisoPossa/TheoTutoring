import 'package:dotenv/dotenv.dart';

/// Backend settings: the system environment plus theo_tutoring_backend/.env,
/// with values from .env taking priority.
///
/// Each developer keeps their own .env (it is gitignored), so passwords never
/// go into the code. Copy .env.example to .env and fill in your own values.
final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
