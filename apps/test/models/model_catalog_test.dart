import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';

void main() {
  setUpAll(() async {
    final fixture = await File('test/fixtures/voice-models.json').readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  group('ModelCatalog', () {
    test('entries is not empty', () {
      expect(ModelCatalog.entries, isNotEmpty);
    });

    test('all entries have unique IDs', () {
      final ids = ModelCatalog.entries.map((e) => e.id).toSet();
      expect(ids.length, ModelCatalog.entries.length);
    });

    test('all entries have non-empty download URLs', () {
      for (final entry in ModelCatalog.entries) {
        expect(
          entry.downloadUrl,
          isNotEmpty,
          reason: '${entry.id} has empty URL',
        );
        expect(
          entry.downloadUrl,
          startsWith('https://'),
          reason: '${entry.id} URL does not start with https://',
        );
      }
    });

    test('all entries have at least one language', () {
      for (final entry in ModelCatalog.entries) {
        expect(
          entry.languages,
          isNotEmpty,
          reason: '${entry.id} has no languages',
        );
      }
    });

    test('all entries have non-empty fileStructure', () {
      for (final entry in ModelCatalog.entries) {
        expect(
          entry.fileStructure,
          isNotEmpty,
          reason: '${entry.id} has empty fileStructure',
        );
      }
    });

    group('byType', () {
      test('returns only ASR models', () {
        final asrModels = ModelCatalog.byType(ModelType.asr);
        expect(asrModels, isNotEmpty);
        for (final model in asrModels) {
          expect(model.type, ModelType.asr);
        }
      });

      test('returns only TTS models', () {
        final ttsModels = ModelCatalog.byType(ModelType.tts);
        expect(ttsModels, isNotEmpty);
        for (final model in ttsModels) {
          expect(model.type, ModelType.tts);
        }
      });

      test('ASR + TTS covers all entries', () {
        final asr = ModelCatalog.byType(ModelType.asr);
        final tts = ModelCatalog.byType(ModelType.tts);
        expect(asr.length + tts.length, ModelCatalog.entries.length);
      });
    });

    group('byLanguage', () {
      test('returns English models', () {
        final enModels = ModelCatalog.byLanguage('en');
        expect(enModels, isNotEmpty);
        for (final model in enModels) {
          expect(model.languages, anyOf(contains('en'), contains('multi')));
        }
      });

      test('returns only the multi-language wildcard for an unsupported code', () {
        final models = ModelCatalog.byLanguage('xx');
        expect(models.map((e) => e.id), ['omnilingual-asr-300m-ctc-int8']);
      });

      test('"multi" entry matches any language code', () {
        for (final code in ['en', 'de', 'fr', 'xx']) {
          expect(
            ModelCatalog.byLanguage(code).map((e) => e.id),
            contains('omnilingual-asr-300m-ctc-int8'),
          );
        }
      });
    });

    group('byTypeAndLanguage', () {
      test('returns English ASR models', () {
        final models = ModelCatalog.byTypeAndLanguage(ModelType.asr, 'en');
        expect(models, isNotEmpty);
        for (final model in models) {
          expect(model.type, ModelType.asr);
          expect(model.languages, anyOf(contains('en'), contains('multi')));
        }
      });

      test('returns German TTS models', () {
        final models = ModelCatalog.byTypeAndLanguage(ModelType.tts, 'de');
        expect(models, isNotEmpty);
        for (final model in models) {
          expect(model.type, ModelType.tts);
          expect(model.languages, contains('de'));
        }
      });

      test('excludes the multi-language ASR entry from TTS results', () {
        final models = ModelCatalog.byTypeAndLanguage(ModelType.tts, 'xx');
        expect(models, isEmpty);
      });
    });

    group('findById', () {
      test('finds existing model', () {
        final entry = ModelCatalog.findById('zipformer-en-kroko');
        expect(entry, isNotNull);
        expect(entry!.id, 'zipformer-en-kroko');
        expect(entry.type, ModelType.asr);
        expect(entry.architecture, ModelArchitecture.transducer);
      });

      test('returns null for non-existent ID', () {
        final entry = ModelCatalog.findById('non-existent');
        expect(entry, isNull);
      });
    });

    group('availableLanguages', () {
      test('contains expected languages', () {
        final languages = ModelCatalog.availableLanguages;
        expect(languages, containsAll(['en', 'de', 'fr', 'ru', 'sv']));
      });

      test('excludes the "multi" wildcard sentinel', () {
        expect(ModelCatalog.availableLanguages, isNot(contains('multi')));
      });
    });

    group('metadata fields', () {
      test('all entries have non-empty origin', () {
        for (final entry in ModelCatalog.entries) {
          expect(
            entry.origin,
            isNotEmpty,
            reason: '${entry.id} has empty origin',
          );
        }
      });

      test('all entries have non-empty sourceUrl', () {
        for (final entry in ModelCatalog.entries) {
          expect(
            entry.sourceUrl,
            isNotEmpty,
            reason: '${entry.id} has empty sourceUrl',
          );
        }
      });

      test('all entries have non-empty releaseDate', () {
        for (final entry in ModelCatalog.entries) {
          expect(
            entry.releaseDate,
            isNotEmpty,
            reason: '${entry.id} has empty releaseDate',
          );
        }
      });

      test('TTS models have positive speakerCount', () {
        for (final entry in ModelCatalog.byType(ModelType.tts)) {
          expect(
            entry.speakerCount,
            greaterThan(0),
            reason: '${entry.id} has speakerCount <= 0',
          );
        }
      });

      test('Kokoro has multiple speakers', () {
        final entry = ModelCatalog.findById('kokoro-en-v0_19-int8');
        expect(entry!.speakerCount, greaterThan(1));
      });

      test('Piper models have single speaker', () {
        final piperModels = ModelCatalog.byType(ModelType.tts).where(
          (e) => e.architecture == ModelArchitecture.vitsPiper,
        );
        for (final model in piperModels) {
          expect(
            model.speakerCount,
            1,
            reason: '${model.id} should have speakerCount 1',
          );
        }
      });
    });

    group('display name format', () {
      test('all display names use Language - Variant format', () {
        for (final entry in ModelCatalog.entries) {
          expect(
            entry.displayName,
            contains(' - '),
            reason: '${entry.id} displayName missing " - " separator',
          );
        }
      });

      test('entries are sorted alphabetically within each type', () {
        for (final type in ModelType.values) {
          final entries = ModelCatalog.byType(type);
          for (var i = 1; i < entries.length; i++) {
            expect(
              entries[i - 1].displayName.compareTo(entries[i].displayName),
              lessThanOrEqualTo(0),
              reason:
                  '${entries[i - 1].displayName} should come before ${entries[i].displayName}',
            );
          }
        }
      });
    });

    group('ASR model properties', () {
      test('zipformer transducer models have encoder/decoder/joiner', () {
        final entry = ModelCatalog.findById('zipformer-en-kroko');
        expect(entry!.architecture, ModelArchitecture.transducer);
        expect(entry.fileStructure, containsPair('encoder', 'encoder.onnx'));
        expect(entry.fileStructure, containsPair('decoder', 'decoder.onnx'));
        expect(entry.fileStructure, containsPair('joiner', 'joiner.onnx'));
        expect(entry.fileStructure, containsPair('tokens', 'tokens.txt'));
      });
    });

    group('TTS model properties', () {
      test('Kokoro model has voices.bin', () {
        final entry = ModelCatalog.findById('kokoro-en-v0_19-int8');
        expect(entry!.architecture, ModelArchitecture.kokoro);
        expect(entry.fileStructure, containsPair('voices', 'voices.bin'));
      });

      test('Piper models have dataDir for espeak-ng-data', () {
        final entry = ModelCatalog.findById('piper-de-thorsten-medium-int8');
        expect(entry!.architecture, ModelArchitecture.vitsPiper);
        expect(entry.fileStructure, containsPair('dataDir', 'espeak-ng-data'));
      });

      test('TTS models do not support streaming', () {
        final ttsModels = ModelCatalog.byType(ModelType.tts);
        for (final model in ttsModels) {
          expect(
            model.supportsStreaming,
            isFalse,
            reason: '${model.id} should not support streaming',
          );
        }
      });
    });

    group('recommended flag', () {
      test('all approved seed entries are recommended, except the '
          'multi-language wildcard entry', () {
        for (final entry in ModelCatalog.entries) {
          if (entry.id == 'omnilingual-asr-300m-ctc-int8') {
            expect(entry.recommended, isFalse, reason: '${entry.id} is the '
                'deliberate non-recommended fixture entry');
            continue;
          }
          expect(
            entry.recommended,
            isTrue,
            reason: '${entry.id} should be recommended',
          );
        }
      });

      test('recommended entries sort before non-recommended', () {
        // This is verified by the alphabetical sort test when all are
        // recommended. Verify that the sort comparator works correctly
        // by checking the entries list ordering is stable.
        for (final type in ModelType.values) {
          final entries = ModelCatalog.byType(type);
          var seenNonRecommended = false;
          for (final entry in entries) {
            if (!entry.recommended) seenNonRecommended = true;
            if (seenNonRecommended) {
              expect(entry.recommended, isFalse,
                  reason: 'Recommended entries must come before non-recommended');
            }
          }
        }
      });
    });
  });
}
