import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/legal/cost_copy.dart';
import 'package:pillar_ai/legal/privacy_copy.dart';
import 'package:pillar_ai/legal/product_copy.dart';
import 'package:pillar_ai/models/analysis_models.dart';

void main() {
  group('CostCopy canonical strings', () {
    test('label and honesty lines stay exact', () {
      expect(CostCopy.shortLabel, 'Planning range');
      expect(
        CostCopy.inlineNote,
        'Directional only from photos — not a contractor bid or inspection price.',
      );
      expect(
        CostCopy.withheld,
        'Planning range withheld — weak photo evidence',
      );
      expect(
        CostCopy.footnote,
        'Ranges are screening ballparks for conversation only. A site visit sets real scope and price.',
      );
    });

    test('product display name is First Sign', () {
      expect(ProductCopy.displayName, 'First Sign');
      expect(ProductCopy.tagline, contains('First Sign'));
      expect(ProductCopy.companionLabel, 'First Sign AI');
      expect(PrivacyCopy.screeningDisclaimer, contains('First Sign'));
      expect(PrivacyCopy.screeningDisclaimer, isNot(contains('First Step')));
      expect(PrivacyCopy.body, contains('First Sign'));
    });

    test('privacy and quote copy reuse the same voice', () {
      expect(PrivacyCopy.planningRangeNote, CostCopy.footnote);
      expect(PrivacyCopy.quoteIntro, contains(CostCopy.inlineNote));
      expect(PrivacyCopy.quoteIntro.toLowerCase(), isNot(contains('ai estimate')));
      expect(PrivacyCopy.quoteIntro.toLowerCase(), isNot(contains('firm bid')));
    });

    test('withheld ranges never invent numbers', () {
      expect(CostCopy.isWithheldRange(''), isTrue);
      expect(CostCopy.isWithheldRange('TBD'), isTrue);
      expect(CostCopy.isWithheldRange('TBD — no exterior findings'), isTrue);
      expect(CostCopy.compact('TBD'), CostCopy.withheld);
      expect(CostCopy.labeled(''), CostCopy.withheld);
      expect(CostCopy.labeled(r'$1,200 – $3,200'), contains(CostCopy.shortLabel));
      expect(CostCopy.labeled(r'$1,200 – $3,200'), contains(r'$1,200'));
      expect(CostCopy.labeled(r'$1,200 – $3,200').toLowerCase(), isNot(contains('estimate')));
      expect(CostCopy.labeled(r'$1,200 – $3,200').toLowerCase(), isNot(contains('bid')));
    });
  });

  group('AnalysisIssue planning labels', () {
    test('weak evidence uses withheld line', () {
      const issue = AnalysisIssue(
        title: 'Possible surface wear',
        location: 'Wall',
        severity: 'Low',
        cost: 'TBD',
        confidence: 62,
        insight: 'Closer photo needed',
        needsCloserPhoto: true,
      );
      expect(issue.planningCostLabel, CostCopy.withheld);
      expect(issue.shortPlanningRange, CostCopy.withheld);
      expect(issue.storyInsightParagraph, contains(CostCopy.withheld));
    });

    test('strong finding is labeled as a planning range, not an estimate', () {
      const issue = AnalysisIssue(
        title: 'Missing / Damaged Shingles',
        location: 'Roof field',
        severity: 'High',
        cost: r'$1,800 – $4,000',
        confidence: 88,
        insight: 'Roof damage supported',
      );
      expect(issue.planningCostLabel, startsWith(CostCopy.shortLabel));
      expect(issue.planningCostLabel, contains(r'$1,800'));
      expect(issue.planningCostLabel.toLowerCase(), isNot(contains('estimate')));
      expect(issue.planningCostLabel.toLowerCase(), isNot(contains('bid')));
      expect(issue.shortPlanningRange, contains(r'$1,800'));
      expect(issue.storyInsightParagraph, contains(CostCopy.inlineNote));
    });
  });
}
