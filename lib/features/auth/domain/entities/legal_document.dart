/// A titled section of a legal document (Terms of Service / Privacy Policy).
class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

/// Static legal copy shown before sign-up and from Profile ▸ Support.
///
/// This is a starting draft written from what Rootsphere actually does
/// (family tree data, uploaded records + OCR, the AI research assistant,
/// donations via Paystack, community/cross-tree search, multi-user tree
/// collaboration) — not a substitute for review by a lawyer before this ships
/// to real users, particularly for jurisdiction-specific requirements
/// (GDPR/CCPA, payment regulation, minors' data).
abstract class LegalDocuments {
  LegalDocuments._();

  static const String lastUpdated = '24 July 2026';

  static const String termsOfServiceIntro =
      'These Terms of Service ("Terms") govern your use of Rootsphere '
      '(the "App"). By creating an account or using the App, you agree to '
      'these Terms. If you do not agree, do not use the App.';

  static const List<LegalSection> termsOfService = <LegalSection>[
    LegalSection(
      '1. What Rootsphere Is',
      'Rootsphere is a family-history app that lets you build a family tree; '
          'store records, photos, videos, and voice notes; search historical '
          'and community-contributed records; get AI-assisted research '
          'suggestions; collaborate with other members on a shared tree; and '
          'support other users\' research through one-time donations.',
    ),
    LegalSection(
      '2. Eligibility and Accounts',
      'You must be at least 13 years old to create an account. If you are '
          'under the age of majority where you live, you should have a '
          'parent or guardian\'s permission. You are responsible for keeping '
          'your login credentials secure and for all activity under your '
          'account. Tell us right away if you suspect unauthorized access.',
    ),
    LegalSection(
      '3. Your Content, and Content About Other People',
      'You keep ownership of what you submit — person records, photos, '
          'documents, notes, and research. By submitting it, you grant '
          'Rootsphere a licence to store, process, and display it back to '
          'you and to anyone you\'ve shared a tree with, so the App can '
          'function.\n\n'
          'Family history inherently involves information about other '
          'people — living relatives, ancestors, and people who never '
          'consented to being in an app. You are responsible for having a '
          'reasonable basis to add information about someone else (e.g. '
          'they\'re family, or the information is already a matter of '
          'public/historical record), for keeping it accurate, and for '
          'removing it if a living person you\'ve added asks you to. Don\'t '
          'add sensitive information about a living person (health, '
          'immigration status, financial details) without their consent.',
    ),
    LegalSection(
      '4. Community Records and Cross-Tree Search',
      'A record you attach to people in your own tree stays visible only to '
          'you and the members of that tree. If you upload a record without '
          'linking it to anyone, it becomes a community record: any '
          'signed-in user can find it through search and copy it into their '
          'own tree. Don\'t upload a document as an unattached community '
          'record unless you\'re comfortable with any other member finding '
          'and reusing it.\n\n'
          'Separately, a limited, privacy-safe summary of people in your '
          'tree (name, birth/death years, birthplace) can be found by other '
          'members through cross-tree search, so relatives researching the '
          'same family line can discover and request to join your tree. '
          'This never includes your notes, photos, or contact details.',
    ),
    LegalSection(
      '5. Shared Trees and Collaboration',
      'A tree can have more than one member. Anyone you invite (or who '
          'joins via a shared tree code) can view, and depending on their '
          'role, edit the people and records in that tree. Choose who you '
          'share a tree with accordingly. The collaboration board '
          '("Opportunities") lets members ask the community for research '
          'help and lets others claim and submit that work — submissions '
          'are visible to the person who posted the request so they can '
          'verify them.\n\n'
          'Finder and Indexer are qualified roles: applying requires '
          'submitting verification information (including a '
          'government-issued ID) for review by Rootsphere admins, and only '
          'approved applicants can claim opportunities requiring that '
          'role. To support that review, and platform moderation '
          'generally, Rootsphere admins and users approved as a Finder or '
          'Indexer can see records across every tree, not just their own.',
    ),
    LegalSection(
      '6. AI Research Assistant',
      'Some features (suggested ancestors, generated timelines, research '
          'recommendations) are produced by an AI model processing the '
          'relevant person\'s data. AI suggestions can be wrong or '
          'incomplete — they\'re a research aid, not a verified genealogical '
          'record. Always check a suggestion against a real source before '
          'relying on it.',
    ),
    LegalSection(
      '7. Donations',
      'Donations are one-time payments to support another user\'s research '
          'request, processed by Paystack. Rootsphere does not store your '
          'card details. Your name (or "Anonymous", if you choose) is shown '
          'publicly alongside the research request you support. Donations '
          'are voluntary contributions to another user\'s research effort, '
          'not a purchase of goods or services, and are non-refundable '
          'except as required by law or at our discretion.',
    ),
    LegalSection(
      '8. Acceptable Use',
      'Don\'t use Rootsphere to harass, defame, or endanger anyone; upload '
          'content you don\'t have the right to share; misrepresent your '
          'identity; scrape or bulk-extract other users\' data; or interfere '
          'with the App\'s normal operation.',
    ),
    LegalSection(
      '9. Termination',
      'You can delete your account at any time from Profile ▸ Account. We '
          'may suspend or terminate an account that violates these Terms. '
          'Deleting your account removes your personal profile; records or '
          'people you\'ve contributed to a shared tree may remain if other '
          'members still rely on that tree.',
    ),
    LegalSection(
      '10. Disclaimers and Liability',
      'Rootsphere is provided "as is." Historical and community-contributed '
          'records may be inaccurate, incomplete, or contributed by other '
          'users we haven\'t independently verified. To the fullest extent '
          'the law allows, Rootsphere isn\'t liable for indirect, '
          'incidental, or consequential damages arising from your use of '
          'the App.',
    ),
    LegalSection(
      '11. Changes to These Terms',
      'We may update these Terms as the App changes. We\'ll update the '
          '"last updated" date above; continuing to use the App after '
          'changes take effect means you accept the revised Terms.',
    ),
    LegalSection(
      '12. Contact',
      'Questions about these Terms: contact.us@rootsphere.ink.',
    ),
  ];

  static const String privacyPolicyIntro =
      'This Privacy Policy explains what information Rootsphere collects, '
      'how it\'s used, and the choices you have. It applies to your account '
      'and to the family-history data you add to the App.';

  static const List<LegalSection> privacyPolicy = <LegalSection>[
    LegalSection(
      '1. Information We Collect',
      '• Account information: email address and authentication data '
          '(including via Google or Apple sign-in, if you use it).\n'
          '• Family-tree data you add: names, dates, places, relationships, '
          'notes, photos, videos, and voice recordings — about yourself and '
          'about other people (living or deceased) you choose to add.\n'
          '• Uploaded records: documents/images you upload, plus text '
          'extracted from them via OCR.\n'
          '• Usage data: activity within the App needed to make features '
          'work (e.g. edit history, collaboration board activity).\n'
          '• Payment data: if you make a donation, Paystack processes your '
          'payment details directly — Rootsphere receives only the '
          'transaction result (amount, status), never your card number.\n'
          '• Role verification data: if you apply to become a Finder or '
          'Indexer, we collect your name, email, phone number, a '
          'government-issued ID, and any supporting certificates you '
          'choose to attach, for Rootsphere admins to review.',
    ),
    LegalSection(
      '2. How We Use Information',
      'To operate the App\'s core features: building your tree, storing and '
          'displaying your records and media, generating AI research '
          'suggestions, running searches, processing donations, reviewing '
          'Finder/Indexer applications, and enabling collaboration between '
          'members of a shared tree.',
    ),
    LegalSection(
      '3. What Other Users Can See',
      '• Members of a tree you belong to can see everything in that tree.\n'
          '• Any signed-in user can find a limited, privacy-safe summary of '
          'people in your tree through cross-tree search (name, birth/death '
          'years, birthplace, and which tree they\'re in) — never your '
          'notes, photos, or contact details — so relatives researching the '
          'same family can find and request to join your tree.\n'
          '• If you upload a record without linking it to anyone, it '
          'becomes findable by any signed-in user through search; who '
          'uploaded it is not shown.\n'
          '• Donation and collaboration-board activity you choose to post '
          '(e.g. a research request, a submitted result) is visible to '
          'other members as part of that feature working.\n'
          '• A completed donation shows your name (or "Anonymous", if you '
          'choose) publicly alongside the research request it supports.\n'
          '• Rootsphere admins can see Finder/Indexer applications, '
          'including submitted ID and supporting documents, to review and '
          'approve them. Admins and users approved as a Finder or Indexer '
          'can also see records across every tree on Rootsphere, not just '
          'their own, so they can find and work on opportunities.',
    ),
    LegalSection(
      '4. Third-Party Service Providers',
      'Rootsphere runs on Supabase (authentication, database, and file '
          'storage) and uses: Anthropic\'s Claude for AI-assisted research '
          'features; Paystack for donation payment processing; FamilySearch '
          '(via a server-side integration) for historical-record search; '
          'and a geocoding service to resolve place names on the map. Each '
          'only receives the data needed to perform its specific function.',
    ),
    LegalSection(
      '5. Data About Other People',
      'Genealogy inherently involves data about people other than you. If '
          'you are a living person who has been added to someone else\'s '
          'tree and want information about you removed, contact us at the '
          'email below and we\'ll work with the tree owner to address it.',
    ),
    LegalSection(
      '6. Data Retention and Deletion',
      'We keep your data while your account is active. Deleting your '
          'account (Profile ▸ Account ▸ Delete account) removes your '
          'personal profile and credentials; content you contributed to a '
          'tree shared with other members may remain if they still rely on '
          'it, consistent with the Terms of Service. Role-verification '
          'documents (including any government ID) are deleted if your '
          'application is withdrawn or your account is deleted.',
    ),
    LegalSection(
      '7. Your Rights and Choices',
      'You can access and edit most of your data directly in the App '
          '(person records, uploaded files, account settings). You can '
          'request a copy of your data or its deletion by emailing us. '
          'Depending on where you live, you may have additional rights '
          'under laws like the GDPR or CCPA.',
    ),
    LegalSection(
      '8. Children\'s Privacy',
      'Rootsphere isn\'t directed at children under 13, and we don\'t '
          'knowingly collect account information from them.',
    ),
    LegalSection(
      '9. Security',
      'We use industry-standard measures (encryption in transit, '
          'row-level access controls on your data) to protect your '
          'information, but no system is 100% secure. Government ID '
          'documents submitted for role verification are stored in '
          'access-controlled storage and used only for verification '
          'purposes.',
    ),
    LegalSection(
      '10. Changes to This Policy',
      'We may update this Policy as the App changes. We\'ll update the '
          '"last updated" date above when we do.',
    ),
    LegalSection(
      '11. Contact',
      'Questions about this Policy or your data: contact.us@rootsphere.ink.',
    ),
  ];

  static const String ourFoundationIntro =
      'Discover Your Roots • Preserve Your Story • Connect Generations\n\n'
      'RootSphere Family History Foundation is a nonprofit initiative '
      'dedicated to helping individuals, families, and communities '
      'discover, document, preserve, and share their family histories, '
      'genealogy, cultural heritage, and memories.\n\n'
      'We believe every person has a story, every family has a history, '
      'and every community has a heritage worth preserving.\n\n'
      'Across Africa and other parts of the world, much of our family '
      'history exists not only in written records but also in oral '
      'traditions, photographs, family documents, community records, '
      'cemeteries, religious records, traditional institutions, and the '
      'memories of elders. As generations pass, valuable information can '
      'be lost if it is not intentionally documented and preserved.\n\n'
      'RootSphere combines technology, genealogical research, education, '
      'oral history, record preservation, and community participation to '
      'make family history more accessible. Through the RootSphere App '
      'and our wider programs, we seek to provide individuals and '
      'families with practical tools to build family trees, preserve '
      'memories, document important life events, record oral histories, '
      'organize family records, and pass their heritage to future '
      'generations.\n\n'
      'While RootSphere has a strong commitment to African family history '
      'and the preservation of underrepresented histories, our vision is '
      'inclusive and global. Everyone deserves the opportunity to know '
      'where they come from and preserve that knowledge for those who '
      'come after them.';

  static const List<LegalSection> ourFoundation = <LegalSection>[
    LegalSection(
      'Our Mission',
      'Our mission is to empower individuals, families, and communities to '
          'discover, document, preserve, and share their family history and '
          'heritage through accessible technology, genealogical research, '
          'education, community engagement, and responsible record '
          'preservation.\n\n'
          'We work to make family history understandable and accessible, '
          'particularly in communities where historical information may be '
          'scattered, undocumented, difficult to access, or primarily '
          'preserved through oral tradition.',
    ),
    LegalSection(
      'Our Vision',
      'Our vision is a world where every person has the opportunity to '
          'discover their roots, understand their heritage, preserve their '
          'family story, and connect generations through family history.\n\n'
          'We envision families and communities in which photographs, '
          'documents, oral histories, cultural traditions, and ancestral '
          'knowledge are preserved rather than forgotten and made '
          'available responsibly to future generations.',
    ),
    LegalSection(
      'Our Values',
      '• Family — Understanding our families can strengthen identity, '
          'belonging, relationships, and connections across generations.\n'
          '• Preservation — Protecting family stories, photographs, '
          'documents, oral histories, cultural knowledge, and historical '
          'records from being permanently lost.\n'
          '• Accuracy — Evidence-based family history, responsible '
          'documentation, proper sourcing, and honest distinction between '
          'established facts, family traditions, and information that '
          'still requires verification.\n'
          '• Respect — Approaching every family and community\'s history, '
          'traditions, beliefs, and experiences with dignity and '
          'sensitivity.\n'
          '• Privacy — Responsible collection, storage, use, and sharing '
          'of genealogical information, respecting privacy, consent, and '
          'applicable data-protection requirements.\n'
          '• Inclusion — Making genealogy accessible regardless of '
          'nationality, ethnicity, social background, education, age, or '
          'economic circumstances.\n'
          '• Education — Helping people learn how to discover and '
          'preserve their own histories, not just receive information.\n'
          '• Innovation — Embracing appropriate technology that makes '
          'research, preservation, collaboration, and education easier '
          'and more accessible.\n'
          '• Community — Encouraging community participation in '
          'preserving the collective history of villages, towns, '
          'institutions, migrations, occupations, and faith communities.',
    ),
    LegalSection(
      'What We Do',
      '• Family Tree Building — helping families create, organize, and '
          'preserve family trees connecting parents, children, '
          'grandparents, ancestors, descendants, and extended family.\n'
          '• Genealogical Research — supporting research using available '
          'sources to discover ancestors, establish relationships, and '
          'document genealogical conclusions.\n'
          '• Oral History Preservation — encouraging families to '
          'interview elders and traditional leaders so their memories and '
          'experiences can be recorded before they are lost.\n'
          '• Memories and Family Stories — preserving photographs, '
          'biographies, personal experiences, and family traditions so '
          'future generations understand the lives behind the names.\n'
          '• Records and Document Preservation — encouraging the '
          'identification, digitization, and preservation of birth, '
          'marriage, death, school, religious, military, migration, land, '
          'cemetery, and other historical records, where lawfully '
          'accessible.\n'
          '• Genealogy Education and Training — workshops, tutorials, and '
          'guidance that teach people how to begin and improve their '
          'family history research.\n'
          '• Community Heritage Projects — encouraging communities to '
          'document their settlements, migrations, traditional '
          'leadership, and cultural practices.\n'
          '• Digital Preservation — using the RootSphere App and related '
          'technology to organize and preserve genealogical information, '
          'photographs, documents, stories, and recordings digitally.\n'
          '• Research Collaboration — encouraging relatives, researchers, '
          'volunteers, institutions, and communities to work together '
          'responsibly to solve genealogical questions.',
    ),
    LegalSection(
      'Our Objectives',
      '• Promote family history awareness and encourage people to '
          'understand the importance of discovering and preserving their '
          'ancestry.\n'
          '• Make genealogy more accessible, particularly in African '
          'communities and other places where traditional genealogical '
          'resources may be limited.\n'
          '• Support family tree development with tools and guidance for '
          'documenting relationships across generations.\n'
          '• Preserve oral histories by encouraging the recording of '
          'elders, family members, and other custodians of historical '
          'knowledge.\n'
          '• Promote responsible genealogical research based on evidence, '
          'documentation, and source evaluation.\n'
          '• Preserve family records and memories, including photographs, '
          'documents, stories, and interviews.\n'
          '• Support the digitization of vulnerable records where '
          'appropriate and with the permission of their owners or '
          'custodians.\n'
          '• Provide genealogy education and training for individuals, '
          'families, students, volunteers, researchers, and communities.\n'
          '• Encourage young people to participate in family history so '
          'heritage preservation continues across generations.\n'
          '• Support community history projects documenting local '
          'histories, families, migrations, and traditions.\n'
          '• Encourage collaboration among families, genealogists, '
          'archives, libraries, educational and religious institutions, '
          'and historical societies.\n'
          '• Promote ethical genealogy, including privacy, informed '
          'consent, and cultural sensitivity.\n'
          '• Use technology to make research, documentation, '
          'preservation, education, and family connections more '
          'accessible.\n'
          '• Contribute to the preservation of African genealogical '
          'heritage while building connections with the wider '
          'international family-history community.',
    ),
    LegalSection(
      'Why RootSphere?',
      'The name RootSphere represents two ideas: Roots and Sphere. Roots '
          'represent ancestry, origin, identity, family connections, '
          'heritage, and the generations that came before us. Sphere '
          'represents the wider circle of human connection — the '
          'families, communities, cultures, countries, and generations '
          'that together form our shared human story.\n\n'
          'Family history is more than discovering names and dates. It is '
          'about understanding the people behind those names — their '
          'experiences, relationships, migrations, occupations, '
          'sacrifices, traditions, challenges, achievements, and '
          'contributions.\n\n'
          'RootSphere exists because valuable family histories are '
          'disappearing every day. Elders pass away, photographs '
          'deteriorate, documents are damaged, memories fade, and '
          'information that was never recorded can disappear permanently. '
          'Technology gives us an opportunity to change that — RootSphere '
          'seeks to create a bridge between the wisdom of the past, the '
          'technology of the present, and the generations of the future.',
    ),
    LegalSection(
      'Our Commitment',
      'We are committed to building a trusted family-history environment '
          'that respects individuals, families, cultures, communities, and '
          'the records entrusted to our care. We will continue to promote '
          'responsible research, accurate documentation, informed '
          'consent, privacy, collaboration, education, and long-term '
          'preservation.\n\n'
          'Our goal is not simply to build family trees. Our goal is to '
          'preserve lives, memories, relationships, and stories so that '
          'generations yet unborn can know those who came before them.',
    ),
    LegalSection(
      'Our Promise',
      'Discover the Past. Preserve the Present. Connect the Future.',
    ),
  ];
}
