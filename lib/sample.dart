/// A built-in example report for a fictional community, so the app can be
/// tried without documents or an API key.
const Map<String, dynamic> kSampleReport = {
  'community': 'Riverbend Lakes Village (example)',
  'site': '58',
  'operator': 'Riverbend Lakes Operations Pty Ltd (fictional)',
  'buyer': 'Pat Example',
  'documents_reviewed': [
    {'name': 'Disclosure Statement', 'date': '3 November 2026', 'notes': 'Given by email'},
    {'name': 'Residential Site Agreement', 'date': 'Draft, undated', 'notes': '24 pages including additional terms 34-70'},
    {'name': 'Community Rules', 'date': 'March 2025', 'notes': '9 pages'},
  ],
  'documents_missing': ['Site condition report', 'Contract for sale of the home'],
  'overall_rating': 'Moderate',
  'overall_reason': 'The fee is higher than the outgoing owner pays and rises 5% a year, and several additional terms shift costs or limit your rights.',
  'summary':
      'You would own the home and rent the site for \$248.00 a week, rising 5% every July for three years, then by notice. '
          'That is \$31 a week more than the current owner pays. Several extra terms make you responsible for the driveway, slab and pipes, '
          'and one clause stops you commenting on the village. The village is in a bush fire prone area and a 40-home expansion is planned next to your site. '
          'Sort out the items in red before you sign, and do not sign before 17 November 2026.',
  'costs': {
    'proposed_fee': '\$248.00 a week',
    'current_fee': '\$217.10 a week (outgoing owner)',
    'community_range': '\$198.40 to \$248.00 a week',
    'increase_method': 'Fixed: 5% each 1 July for 3 years, then notice (non-fixed) method',
    'first_increase': '1 July 2027 (about 7 months after you start)',
    'projection': [
      {'when': 'Start (Dec 2026)', 'weekly': '\$248.00'},
      {'when': '1 July 2027', 'weekly': '\$260.40'},
      {'when': '1 July 2028', 'weekly': '\$273.42'},
      {'when': '1 July 2029', 'weekly': '\$287.09'},
      {'when': 'After 2029', 'weekly': 'By notice — can be challenged'},
    ],
    'other_costs': [
      'Electricity from the operator (embedded network) — capped at the IPART comparable market offer; rates not given',
      'Water usage plus up to \$50 a year availability charge',
      'Boat and caravan storage \$20 a week (waiting list)',
      'Key and gate remote deposit \$25',
    ],
  },
  'key_dates': [
    {'date': '3 Nov 2026', 'what': 'Disclosure Statement given to you'},
    {'date': '17 Nov 2026', 'what': 'Earliest date you can sign the site agreement (14 days)'},
    {'date': '14 days after signing', 'what': 'End of cooling-off — lost if you move in earlier'},
    {'date': '1 Dec 2026', 'what': 'Proposed start of site fees'},
    {'date': '1 Jul 2027', 'what': 'First 5% increase'},
  ],
  'red': [
    {
      'title': 'You would pay \$31 a week more than the current owner',
      'detail': 'The site fee resets from \$217.10 to \$248.00 — the top of the range in the village (about \$1,600 a year more).',
      'where': 'Disclosure Statement, section 3',
      'ask': 'Why is my fee higher than the current owner\'s? Will you agree to the current fee?',
    },
    {
      'title': 'You would own and repair the driveway, slab and service pipes',
      'detail': 'Extra terms say anything built on the site, including the plumbing and wiring that connect to the village services, is yours to maintain "in a condition satisfactory to us", and to remove at your cost when you leave.',
      'where': 'Site Agreement, clauses 58, 60 and 61',
      'ask': 'Please limit these to items I install, and to a reasonable standard.',
    },
    {
      'title': '"Social media" clause stops you criticising the village',
      'detail': 'You must not do anything that "negatively impacts on the reputation" of the business. This could be used against genuine complaints and may not be enforceable.',
      'where': 'Site Agreement, clause 45',
      'ask': 'Please delete clause 45.',
    },
    {
      'title': 'Two increase methods are ticked',
      'detail': 'On the site fee page both "Fixed method" and "Notice method" have ticks. Only one can apply.',
      'where': 'Site Agreement, page 3',
      'ask': 'Please correct the page so only the fixed 5% method (then notice) is ticked, matching the Disclosure Statement.',
    },
  ],
  'amber': [
    {
      'title': 'Expansion planned next to your site',
      'detail': 'A development application for 40 more homes on the eastern paddock has been approved; works over 3 years.',
      'where': 'Disclosure Statement, section 1',
      'ask': 'How close is the work to site 58, what hours, and when will it finish?',
    },
    {
      'title': 'Bush fire prone area',
      'detail': 'The village is in a declared bush fire prone area. The bushfire attack level (BAL) for your site is not given.',
      'where': 'Disclosure Statement, section 8',
      'ask': 'What is the BAL for site 58? Get insurance quotes before signing.',
    },
    {
      'title': 'Only one vehicle without permission',
      'detail': 'The agreement allows one vehicle, boat or trailer on site; the rules say two cars if there is room.',
      'where': 'Site Agreement cl 53; Rules 7.4',
      'ask': 'Which applies to site 58?',
    },
    {
      'title': 'Pets need approval',
      'detail': 'One small dog is allowed; cats and larger dogs need written approval.',
      'where': 'Community Rules, rule 9',
      'ask': 'If you have a pet, get approval in writing before you sign.',
    },
  ],
  'green': [
    {'title': 'Standard site agreement form used', 'detail': 'Standard terms 1-33 match the prescribed form.'},
    {'title': 'No exit fee', 'detail': 'There is no deferred fee or share of sale price.'},
    {'title': 'Residents committee', 'detail': 'There is an active residents committee — talk to them before you buy.'},
    {'title': 'Not flood prone', 'detail': 'The operator says the land is not flood prone and has not flooded in 5 years.'},
  ],
  'blanks': [
    {'field': 'Key deposit amount', 'document': 'Site Agreement, clause 12.1'},
    {'field': 'Number of trees on the site', 'document': 'Site condition report (not provided)'},
    {'field': 'Start date of site fees', 'document': 'Site Agreement, page 2'},
  ],
  'questions': [
    'Why is my site fee \$31 a week more than the current owner pays?',
    'Will you correct the site fee page so only one increase method is ticked?',
    'Will you delete clause 45 and limit clauses 58, 60 and 61?',
    'What are the current electricity and water charges?',
    'How will the expansion affect site 58, and when?',
    'What is the bushfire attack level for site 58?',
    'May I see the site condition report before I sign?',
  ],
};
