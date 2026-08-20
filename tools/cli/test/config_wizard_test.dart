import 'package:relagent_cli/config_wizard.dart';
import 'package:test/test.dart';

void main() {
  group('decideConfigWizardAnswers', () {
    test('blank URL answer keeps the current URL', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '',
        tokenInput: '',
      );

      expect(decision.engineUrl, 'http://localhost:8000');
      expect(decision.urlChanged, isFalse);
    });

    test('blank URL answer (whitespace only) keeps the current URL', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '   ',
        tokenInput: '',
      );

      expect(decision.engineUrl, 'http://localhost:8000');
      expect(decision.urlChanged, isFalse);
    });

    test('non-blank URL answer replaces the current URL', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: 'https://engine.example.com',
        tokenInput: '',
      );

      expect(decision.engineUrl, 'https://engine.example.com');
      expect(decision.urlChanged, isTrue);
    });

    test('re-entering the same URL is not reported as a change', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: 'http://localhost:8000',
        tokenInput: '',
      );

      expect(decision.urlChanged, isFalse);
    });

    test('blank token answer leaves the stored token unchanged', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '',
        tokenInput: '',
      );

      expect(decision.newToken, isNull);
    });

    test('non-blank token answer is surfaced as the new token', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '',
        tokenInput: 'sk-secret',
      );

      expect(decision.newToken, 'sk-secret');
    });

    test('blank purge-session answer keeps the current value', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '',
        tokenInput: '',
        currentAlwaysPurgeSession: true,
        alwaysPurgeSessionInput: '',
      );

      expect(decision.alwaysPurgeSession, isTrue);
    });

    test('"y" purge-session answer enables it', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '',
        tokenInput: '',
        currentAlwaysPurgeSession: false,
        alwaysPurgeSessionInput: 'y',
      );

      expect(decision.alwaysPurgeSession, isTrue);
    });

    test('non-"y" purge-session answer disables it', () {
      final decision = decideConfigWizardAnswers(
        currentUrl: 'http://localhost:8000',
        urlInput: '',
        tokenInput: '',
        currentAlwaysPurgeSession: true,
        alwaysPurgeSessionInput: 'n',
      );

      expect(decision.alwaysPurgeSession, isFalse);
    });
  });
}
