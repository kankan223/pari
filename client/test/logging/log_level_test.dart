import 'package:civic_commons/logging/domain/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogLevel - Task 13.1', () {
    test('enum has 4 values in correct order', () {
      expect(LogLevel.values.length, 4);
      expect(LogLevel.debug.index, 0);
      expect(LogLevel.info.index, 1);
      expect(LogLevel.warning.index, 2);
      expect(LogLevel.error.index, 3);
    });

    test('debug is least severe', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.debug.index, lessThan(LogLevel.warning.index));
      expect(LogLevel.debug.index, lessThan(LogLevel.error.index));
    });

    test('error is most severe', () {
      expect(LogLevel.error.index, greaterThan(LogLevel.debug.index));
      expect(LogLevel.error.index, greaterThan(LogLevel.info.index));
      expect(LogLevel.error.index, greaterThan(LogLevel.warning.index));
    });
  });

  group('LogLevelConfig - Task 13.1', () {
    test('development config emits all levels', () {
      const config = LogLevelConfig.development;
      expect(config.environment, 'development');
      expect(config.minimumLevel, LogLevel.debug);
      expect(config.shouldEmit(LogLevel.debug), isTrue);
      expect(config.shouldEmit(LogLevel.info), isTrue);
      expect(config.shouldEmit(LogLevel.warning), isTrue);
      expect(config.shouldEmit(LogLevel.error), isTrue);
    });

    test('production config excludes debug', () {
      const config = LogLevelConfig.production;
      expect(config.environment, 'production');
      expect(config.minimumLevel, LogLevel.info);
      expect(config.shouldEmit(LogLevel.debug), isFalse);
      expect(config.shouldEmit(LogLevel.info), isTrue);
      expect(config.shouldEmit(LogLevel.warning), isTrue);
      expect(config.shouldEmit(LogLevel.error), isTrue);
    });

    test('custom config with warning minimum', () {
      const config = LogLevelConfig(
        environment: 'staging',
        minimumLevel: LogLevel.warning,
      );
      expect(config.shouldEmit(LogLevel.debug), isFalse);
      expect(config.shouldEmit(LogLevel.info), isFalse);
      expect(config.shouldEmit(LogLevel.warning), isTrue);
      expect(config.shouldEmit(LogLevel.error), isTrue);
    });

    test('custom config with error minimum', () {
      const config = LogLevelConfig(
        environment: 'minimal',
        minimumLevel: LogLevel.error,
      );
      expect(config.shouldEmit(LogLevel.debug), isFalse);
      expect(config.shouldEmit(LogLevel.info), isFalse);
      expect(config.shouldEmit(LogLevel.warning), isFalse);
      expect(config.shouldEmit(LogLevel.error), isTrue);
    });
  });
}
