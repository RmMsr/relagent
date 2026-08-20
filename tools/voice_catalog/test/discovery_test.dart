import 'package:test/test.dart';
import 'package:voice_catalog/catalog_index.dart';
import 'package:voice_catalog/discovery.dart';

Map<String, dynamic> _untestedEntry(String id) => {
  'id': id,
  'displayName': '',
  'type': 'asr',
  'architecture': 'unknown',
  'languages': <String>[],
  'downloadUrl': 'https://example.com/$id.tar.bz2',
  'downloadSizeMb': 10,
  'fileStructure': <String, String>{},
  'origin': '',
  'sourceUrl': '',
  'speakerCount': 0,
  'releaseDate': '',
  'status': 'untested',
  'recommended': false,
  'notes': '',
};

void main() {
  group('VoiceCatalogDiscovery.classify — NeMo transducer routing', () {
    late VoiceCatalogDiscovery discovery;

    setUp(() {
      discovery = VoiceCatalogDiscovery(CatalogIndex('unused.json'));
    });

    test('cache-aware streaming NeMo transducer is routed to the '
        'catalog-only label, not offlineNemoTransducer', () {
      final entries = [
        _untestedEntry(
          'sherpa-onnx-nemo-streaming-fast-conformer-transducer-en-80ms-int8',
        ),
      ];

      discovery.classify(entries);

      expect(
        entries.single['architecture'],
        'nemoCacheAwareStreamingTransducer',
      );
    });

    test('"non-streaming" NeMo transducer export is NOT caught by the '
        'streaming-substring check — regression test for a false positive '
        'found while fixing the streaming case above', () {
      final entries = [
        _untestedEntry(
          'sherpa-onnx-nemo-parakeet-unified-en-0-6b-int8-non-streaming',
        ),
      ];

      discovery.classify(entries);

      expect(entries.single['architecture'], 'offlineNemoTransducer');
    });

    test('plain offline NeMo transducer export is unaffected', () {
      final entries = [
        _untestedEntry('sherpa-onnx-nemo-parakeet-tdt-0-6b-v2-int8'),
      ];

      discovery.classify(entries);

      expect(entries.single['architecture'], 'offlineNemoTransducer');
    });
  });
}
