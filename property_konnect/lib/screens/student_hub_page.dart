import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'hostels_page.dart';
import 'roommate_posting_finding_page.dart';
import 'student_services_page.dart';
import 'campus_communities_page.dart';
import 'comrade_marketplace_page.dart';

class StudentHubPage extends StatelessWidget {
  const StudentHubPage({super.key});

  // ---- Translation helper (English / Kiswahili) ----
  static String _tr(BuildContext context, String en, String sw) {
    return AppSettings.of(context).languageCode == 'sw' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.of(context).isDark;
    final brand = isDark ? kBrandGreenOnDark : kBrandGreen;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(context, 'Student Hub', 'Kituo cha Wanafunzi'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHero(context, isDark),
                  const SizedBox(height: 22),
                  _sectionTitle(
                    context,
                    _tr(context, 'What are you looking for?',
                        'Unatafuta nini?'),
                  ),
                  const SizedBox(height: 12),
                  _hubButton(
                    context,
                    icon: Icons.apartment_rounded,
                    title: _tr(context, 'Find Your Hostel',
                        'Tafuta Hosteli Yako'),
                    subtitle: _tr(
                      context,
                      'Browse student-friendly hostels near your campus.',
                      'Vinjari hosteli rafiki kwa wanafunzi karibu na chuo chako.',
                    ),
                    page: const HostelsPage(),
                  ),
                  _hubButton(
                    context,
                    icon: Icons.people_alt_rounded,
                    title: _tr(context, 'Find Roommate',
                        'Tafuta Mwenzi wa Chumba'),
                    subtitle: _tr(
                      context,
                      'Post or find students looking to share a room.',
                      'Tangaza au tafuta wanafunzi wanaotaka kushiriki chumba.',
                    ),
                    page: const RoommatePostingFindingPage(),
                  ),
                  _hubButton(
                    context,
                    icon: Icons.miscellaneous_services_rounded,
                    title: _tr(context, 'Student Services',
                        'Huduma za Wanafunzi'),
                    subtitle: _tr(
                      context,
                      'Laundry, moving, printing, study spaces and more.',
                      'Ufuaji, uhamishaji, uchapishaji, maeneo ya kusomea na zaidi.',
                    ),
                    page: const StudentServicesPage(),
                  ),
                  _hubButton(
                    context,
                    icon: Icons.groups_rounded,
                    title: _tr(context, 'Campus Communities',
                        'Jamii za Chuoni'),
                    subtitle: _tr(
                      context,
                      'Join groups, clubs and communities on your campus.',
                      'Jiunge na vikundi, vilabu na jamii za chuo chako.',
                    ),
                    page: const CampusCommunitiesPage(),
                  ),
                  _hubButton(
                    context,
                    icon: Icons.storefront_rounded,
                    title: _tr(context, 'Comrade Marketplace',
                        'Soko la Wanafunzi'),
                    subtitle: _tr(
                      context,
                      'Buy and sell items from fellow students on campus.',
                      'Nunua na uza bidhaa kutoka kwa wanafunzi wenzako chuoni.',
                    ),
                    page: const ComradeMarketplacePage(),
                  ),
                  const SizedBox(height: 18),
                  _buildAbout(context, isDark, brand),
                  const SizedBox(height: 16),
                  _buildHowItWorks(context, isDark, brand),
                  const SizedBox(height: 16),
                  _buildSafety(context, isDark),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // HERO
  // ------------------------------------------------------------
  Widget _buildHero(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0E3D2A), Color(0xFF126B45)]
              : const [kBrandGreen, Color(0xFF2E9E6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.school_rounded, color: Colors.white, size: 52),
          const SizedBox(height: 12),
          Text(
            _tr(context, 'Welcome to Student Hub',
                'Karibu Kituo cha Wanafunzi'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _tr(
              context,
              'Find student-friendly accommodation, connect with potential '
                  'roommates and discover useful student services, communities '
                  'and a marketplace to buy and sell.',
              'Pata makazi rafiki kwa wanafunzi, unganika na wenzi wa chumba '
                  'watarajiwa na gundua huduma, jamii na soko la kununua na '
                  'kuuza kwa wanafunzi.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .92),
              height: 1.5,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }

  // ------------------------------------------------------------
  // NAVIGATION BUTTON
  // ------------------------------------------------------------
  Widget _hubButton(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required Widget page,
      }) {
    final isDark = AppSettings.of(context).isDark;
    final brand = isDark ? kBrandGreenOnDark : kBrandGreen;
    final cardColor = isDark ? const Color(0xFF1A241D) : Colors.white;
    final border = isDark ? const Color(0xFF2A3A2F) : Colors.grey.shade200;
    final subtle = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: .68);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: brand.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: brand, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subtle,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: brand),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ABOUT
  // ------------------------------------------------------------
  Widget _buildAbout(BuildContext context, bool isDark, Color brand) {
    final bg = isDark ? const Color(0xFF16201A) : const Color(0xFFEFF7F2);
    final subtle = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: .78);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr(context, 'About Student Hub', 'Kuhusu Kituo cha Wanafunzi'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _tr(
              context,
              'Student Hub is the part of PropertyKonnect made for students. '
                  'It brings together everything you need to settle in near campus: '
                  'verified hostels, a roommate board where you can post or find '
                  'someone to share with, everyday student services, campus '
                  'communities where you can meet people with similar interests, '
                  'and the Comrade Marketplace where you can buy and sell items '
                  'with fellow students. '
                  'You do not need an account to browse.',
              'Kituo cha Wanafunzi ni sehemu ya PropertyKonnect iliyoundwa kwa '
                  'ajili ya wanafunzi. Kinakusanya kila kitu unachohitaji ili '
                  'kutulia karibu na chuo: hosteli zilizothibitishwa, ubao wa '
                  'wenzi wa chumba ambapo unaweza kutangaza au kutafuta mtu wa '
                  'kushiriki naye, huduma za kila siku za wanafunzi, jamii za '
                  'chuoni ambapo unaweza kukutana na watu wenye mapendezi sawa, '
                  'na Soko la Wanafunzi ambapo unaweza kununua na kuuza bidhaa '
                  'na wanafunzi wenzako. '
                  'Huhitaji akaunti ili kuvinjari.',
            ),
            style: TextStyle(color: subtle, height: 1.55, fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // HOW IT WORKS
  // ------------------------------------------------------------
  Widget _buildHowItWorks(BuildContext context, bool isDark, Color brand) {
    final cardColor = isDark ? const Color(0xFF1A241D) : Colors.white;
    final border = isDark ? const Color(0xFF2A3A2F) : Colors.grey.shade200;

    final steps = <List<String>>[
      [
        'Search for a hostel near your campus.',
        'Tafuta hosteli karibu na chuo chako.'
      ],
      [
        'Post or browse roommate requests.',
        'Tangaza au vinjari maombi ya wenzi wa chumba.'
      ],
      [
        'Use student services to settle in.',
        'Tumia huduma za wanafunzi ili kutulia.'
      ],
      [
        'Join communities and meet other students.',
        'Jiunge na jamii na ukutane na wanafunzi wengine.'
      ],
      [
        'Buy or sell items in the Comrade Marketplace.',
        'Nunua au uza bidhaa kwenye Soko la Wanafunzi.'
      ],
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr(context, 'How it works', 'Jinsi inavyofanya kazi'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: brand,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _tr(context, steps[i][0], steps[i][1]),
                        style: const TextStyle(fontSize: 13.5, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // SAFETY
  // ------------------------------------------------------------
  Widget _buildSafety(BuildContext context, bool isDark) {
    final bg = isDark ? const Color(0xFF2A2412) : const Color(0xFFFFF8E1);
    final border = isDark ? const Color(0xFF5C4E1C) : const Color(0xFFFFE082);
    final accent = isDark ? const Color(0xFFFFCA28) : const Color(0xFF8D6E00);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr(context, 'Student safety', 'Usalama wa wanafunzi'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _tr(
              context,
              'When looking for accommodation, personally view the property '
                  'before sending money. Be careful with requests for urgent '
                  'payments and report suspicious listings through the property '
                  'details page. When buying items, meet in a public place on '
                  'campus and inspect the item before paying.',
              'Unapotafuta makazi, tembelea mali mwenyewe kabla ya kutuma pesa. '
                  'Jihadhari na maombi ya malipo ya haraka na uripoti matangazo '
                  'yanayotia shaka kupitia ukurasa wa maelezo ya mali. Unaponunua '
                  'bidhaa, kutana katika eneo la wazi chuoni na ukague bidhaa '
                  'kabla ya kulipa.',
            ),
            style: const TextStyle(height: 1.5, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}