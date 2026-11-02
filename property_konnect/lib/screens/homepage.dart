// ============================================================
// homepage.dart  (FULL UPDATED FILE)
//
// CHANGES IN THIS VERSION
//  1. CARD ORDER (top to bottom after the app bar):
//       1) Hero card (first card after the app bar)
//       2) "Are you a student?" card
//       3) Our Mission card
//       4) Who We Serve card
//       5) What You Can Find card (Rent / Buy categories)
//       6) Where We Cover card (county + subcounties)
//       7) Why Choose Us card
//       8) Safety Reminder card (LAST card)
//  2. REMOVED:
//     - the counties / subcounties / property-categories
//       counts card (_buildStats), and
//     - the "Your Property Journey" card (_buildJourney).
//   Their helper code was removed with them.
// Everything else (drawer, footer, county search sheet, theme,
// translations) is unchanged.
// ============================================================
import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import 'data.dart';
import 'services_page.dart';
import 'property_search_page.dart';
import 'student_hub_page.dart';
import 'hostels_page.dart';
import 'roommate_posting_finding_page.dart';
import 'student_services_page.dart';
import 'campus_communities_page.dart';
import 'registration_page.dart';
import 'favourites_page.dart';
import 'contact_page.dart';
import 'login_page.dart';
import 'faqs_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const String _appName = 'Property Konnect';
  static const String _appShort = 'PK';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final AnimationController _menuIconController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  String _purpose = 'Rent';
  String _selectedCounty = 'Nairobi';

  // ------------------------------------------------------------
  // THEME + LANGUAGE — ALL strings come from the central
  // catalog; the language is decided by AppSettings only.
  // ------------------------------------------------------------

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _brandSoft =>
      _isDark ? const Color(0xFF1F2B24) : const Color(0xFFEAF4EF);

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _borderColor =>
      _isDark ? Colors.grey.shade800 : Colors.grey.shade200;

  String _tr(String key) => AppLocalizations.tr(context, key);

  // ------------------------------------------------------------
  // DATA (from data.dart)
  // ------------------------------------------------------------

  List<String> _categoriesFor(String purpose) {
    final all = PropertyCategories.categoriesFor(purpose);
    if (purpose == 'Buy') {
      return all.where((c) => c != 'Short Stay').toList();
    }
    return all;
  }

  List<String> _subtypesFor(String purpose, String category) =>
      PropertyCategories.subtypesFor(purpose, category);

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Residential':
        return Icons.home_rounded;
      case 'Commercial':
        return Icons.storefront_rounded;
      case 'Short Stay':
        return Icons.luggage_outlined;
      case 'Land':
        return Icons.landscape_rounded;
      default:
        return Icons.apartment_rounded;
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'Residential':
        return _tr(AppStrings.residential);
      case 'Commercial':
        return _tr(AppStrings.commercial);
      case 'Short Stay':
        return _tr(AppStrings.shortStay);
      case 'Land':
        return _tr(AppStrings.land);
      default:
        return category;
    }
  }

  @override
  void initState() {
    super.initState();

    _menuIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _menuIconController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ServicesPage(),
      ),
    );
  }

  void _openProperties(
      String purpose, {
        String? category,
        String? subtype,
      }) {
    _push(
      PropertySearchPage(
        initialPurpose: purpose,
        initialCategory: category,
        initialSubtype: subtype,
      ),
    );
  }

  void _openStudentHub() => _push(const StudentHubPage());
  void _openHostels() => _push(const HostelsPage());
  void _openRoommates() => _push(const RoommatePostingFindingPage());
  void _openStudentServices() => _push(const StudentServicesPage());
  void _openCampusCommunities() => _push(const CampusCommunitiesPage());
  void _openRegistration() => _push(const RegistrationPage());
  void _openFavourites() => _push(const FavouritesPage());
  void _openAppSettings() => _push(const AppSettingsPage());
  void _openFAQs() => _push(const FAQsPage());
  void _openContact() => _push(const ContactPage());
  void _openLogin() => _push(const LoginPage());

  void _toggleDrawer() {
    final state = _scaffoldKey.currentState;
    if (state == null) return;
    if (state.isDrawerOpen) {
      state.closeDrawer();
    } else {
      state.openDrawer();
    }
  }

  void _drawerNavigate(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      onDrawerChanged: (isOpen) {
        if (isOpen) {
          _menuIconController.forward();
        } else {
          _menuIconController.reverse();
        }
      },
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 1,
              backgroundColor: _cardColor,
              titleSpacing: 0,
              leading: IconButton(
                tooltip: _tr(AppStrings.menu),
                icon: AnimatedIcon(
                  icon: AnimatedIcons.menu_close,
                  progress: _menuIconController,
                  color: _brand,
                ),
                onPressed: _toggleDrawer,
              ),
              title: Row(
                children: [
                  _brandLogo(),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _appName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _brand,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    // ---- NEW CARD ORDER ----
                    children: [
                      _buildHero(),          // 1. hero (first card)
                      _buildStudentSection(), // 2. are you a student?
                      _buildMission(),       // 3. our mission
                      _buildWhoWeServe(),    // 4. who we serve
                      _buildCategories(),    // 5. what you can find
                      _buildCoverage(),      // 6. where we cover
                      _buildWhyChoose(),     // 7. why choose us
                      _buildSafety(),        // 8. safety (last card)
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        ),
      ),
    );
  }

  Widget _brandLogo() {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _brand,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Text(
        _appShort,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SIDE MENU
  // ---------------------------------------------------------------------------

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: _cardColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  _brandLogo(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _appName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _brand,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _tr(AppStrings.collapseMenu),
                    icon: Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      color: _brand,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                children: [
                  _drawerItem(
                    icon: Icons.search_rounded,
                    label: _tr(AppStrings.findYourNextPlace),
                    onTap: () =>
                        _drawerNavigate(() => _openProperties('Rent')),
                  ),
                  _drawerItem(
                    icon: Icons.school_outlined,
                    label: _tr(AppStrings.studentHub),
                    onTap: () => _drawerNavigate(_openStudentHub),
                  ),
                  _drawerItem(
                    icon: Icons.favorite_border_rounded,
                    label: _tr(AppStrings.favourites),
                    onTap: () => _drawerNavigate(_openFavourites),
                  ),
                  _drawerItem(
                    icon: Icons.home_repair_service_outlined,
                    label: _tr(AppStrings.services),
                    onTap: () => _drawerNavigate(_openServices),
                  ),
                  _drawerItem(
                    icon: Icons.settings_outlined,
                    label: _tr(AppStrings.appSettings),
                    onTap: () => _drawerNavigate(_openAppSettings),
                  ),
                  _drawerItem(
                    icon: Icons.question_answer_outlined,
                    label: _tr(AppStrings.faqs),
                    onTap: () => _drawerNavigate(_openFAQs),
                  ),
                  _drawerItem(
                    icon: Icons.support_agent_rounded,
                    label: _tr(AppStrings.contactUs),
                    onTap: () => _drawerNavigate(_openContact),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _drawerNavigate(_openLogin),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brand,
                        side: BorderSide(color: _brand),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_tr(AppStrings.login)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _drawerNavigate(_openRegistration),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_tr(AppStrings.signUp)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _brandSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _brand, size: 22),
        ),
        title: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED SECTION HELPERS
  // ---------------------------------------------------------------------------

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: _brand, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _brand,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: _mutedText, fontSize: 13.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: _brandSoft,
            child: Icon(icon, color: _brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _brand,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style:
                  TextStyle(fontSize: 13, color: _bodyText, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. HERO (first card after the app bar)
  // ---------------------------------------------------------------------------

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B4A30), kBrandGreen, kBrandGreenOnDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.home_work_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _tr(AppStrings.aboutApp),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .85),
              fontSize: 12.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _tr(AppStrings.heroHeadline),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _tr(AppStrings.heroSub),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .9),
              height: 1.5,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          _verifiedBadge(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _heroButton(
                  label: _tr(AppStrings.rent),
                  icon: Icons.key_rounded,
                  onTap: () => _openProperties('Rent'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroButton(
                  label: _tr(AppStrings.buy),
                  icon: Icons.shopping_cart_outlined,
                  onTap: () => _openProperties('Buy'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verifiedBadge() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final v = _pulse.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10 + v * 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35 + v * 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_rounded,
                color: Colors.white.withValues(alpha: 0.70 + v * 0.30),
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _tr(AppStrings.verifiedListingsOnly),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _heroButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Transform.scale(
          scale: 1 + (_pulse.value * .025),
          child: ElevatedButton.icon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _brand,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. ARE YOU A STUDENT?
  // ---------------------------------------------------------------------------

  Widget _buildStudentSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _brandSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.school_rounded, size: 45, color: _brand),
          const SizedBox(height: 12),
          Text(
            _tr(AppStrings.areYouStudent),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(AppStrings.studentSectionBody),
            textAlign: TextAlign.center,
            style: TextStyle(color: _bodyText, height: 1.5, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _openStudentHub,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(_tr(AppStrings.openStudentHub)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. OUR MISSION
  // ---------------------------------------------------------------------------

  Widget _buildMission() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
      child: Column(
        children: [
          Text(
            _tr(AppStrings.ourMission),
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: _brand,
            ),
          ),
          Container(
            width: 46,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _brand,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Text(
            _tr(AppStrings.missionBody),
            textAlign: TextAlign.center,
            style: TextStyle(color: _bodyText, height: 1.6, fontSize: 14.5),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. WHO WE SERVE
  // ---------------------------------------------------------------------------

  Widget _buildWhoWeServe() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.groups_rounded,
            title: _tr(AppStrings.whoWeServe),
            subtitle: _tr(AppStrings.whoWeServeSub),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _infoCard(
                  icon: Icons.school,
                  title: _tr(AppStrings.students),
                  body: _tr(AppStrings.studentsBody),
                ),
                const SizedBox(height: 12),
                _infoCard(
                  icon: Icons.key,
                  title: _tr(AppStrings.tenantsBuyers),
                  body: _tr(AppStrings.tenantsBuyersBody),
                ),
                const SizedBox(height: 12),
                _infoCard(
                  icon: Icons.real_estate_agent,
                  title: _tr(AppStrings.propertyOwners),
                  body: _tr(AppStrings.propertyOwnersBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. WHAT YOU CAN FIND
  // ---------------------------------------------------------------------------

  Widget _buildCategories() {
    final categories = _categoriesFor(_purpose);

    Widget purposeChip(String value, String label) {
      final selected = _purpose == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: _brand,
        labelStyle: TextStyle(
          color: selected ? Colors.white : _bodyText,
          fontWeight: FontWeight.w700,
        ),
        onSelected: (_) => setState(() => _purpose = value),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.travel_explore_rounded,
            title: _tr(AppStrings.whatYouCanFind),
            subtitle: _tr(AppStrings.whatYouCanFindSub),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                purposeChip('Rent', _tr(AppStrings.rent)),
                const SizedBox(width: 10),
                purposeChip('Buy', _tr(AppStrings.buy)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final category in categories) ...[
                  _categoryCard(category),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryCard(String category) {
    final subtypes = _subtypesFor(_purpose, category);

    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openProperties(_purpose, category: category),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_categoryIcon(category), color: _brand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _categoryLabel(category),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _brand,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in subtypes)
                          Material(
                            color: _brandSoft,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _openProperties(
                                _purpose,
                                category: category,
                                subtype: s,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                child: Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _bodyText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 15, color: _brand),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. WHERE WE COVER
  // ---------------------------------------------------------------------------

  Widget _buildCoverage() {
    final subcounties = KenyaLocation.subcountiesOf(_selectedCounty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.map_rounded,
            title: _tr(AppStrings.whereWeCover),
            subtitle: _tr(AppStrings.whereWeCoverSub),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Tappable county selector: opens a searchable sheet ---
                Material(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _showCountySearchSheet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.place_outlined, color: _brand, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedCounty,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color:
                                _isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.expand_more_rounded,
                            color: _brand,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${subcounties.length} '
                      '${_tr(AppStrings.subcountiesIn)} '
                      '$_selectedCounty',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _brand,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in subcounties)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _brandSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.place_outlined,
                                size: 14, color: _brand),
                            const SizedBox(width: 4),
                            Text(
                              s,
                              style: TextStyle(
                                fontSize: 12,
                                color: _bodyText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Searchable county picker bottom sheet ---

  Future<void> _showCountySearchSheet() async {
    final controller = TextEditingController();
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final counties = KenyaLocation.counties;
            final filtered = query.trim().isEmpty
                ? counties
                : counties
                .where((c) =>
                c.toLowerCase().contains(query.trim().toLowerCase()))
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // --- Search bar ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search counties...',
                        prefixIcon: Icon(Icons.search_rounded, color: _brand),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: _mutedText),
                          onPressed: () {
                            controller.clear();
                            setSheetState(() => query = '');
                          },
                        ),
                        filled: true,
                        fillColor: _brandSoft,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _brand),
                        ),
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        color: _isDark ? Colors.white : Colors.black87,
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 40, color: _mutedText),
                          const SizedBox(height: 10),
                          Text(
                            'No counties found',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _mutedText,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    )
                        : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                          16, 4, 16, 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final county = filtered[index];
                        final selected = county == _selectedCounty;
                        return Padding(
                          padding:
                          const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
                            onTap: () {
                              setState(() => _selectedCounty = county);
                              Navigator.pop(sheetContext);
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: selected
                                    ? _brand
                                    : _brandSoft,
                                borderRadius:
                                BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.place_outlined,
                                color: selected
                                    ? Colors.white
                                    : _brand,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              county,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: _isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check_circle_rounded,
                                color: _brand)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 7. WHY CHOOSE US
  // ---------------------------------------------------------------------------

  Widget _buildWhyChoose() {
    final features = <Map<String, dynamic>>[
      {
        'icon': Icons.home,
        'title': _tr(AppStrings.whyWideTitle),
        'sub': _tr(AppStrings.whyWideSub),
      },
      {
        'icon': Icons.verified_user,
        'title': _tr(AppStrings.whyVerifiedTitle),
        'sub': _tr(AppStrings.whyVerifiedSub),
      },
      {
        'icon': Icons.mobile_friendly,
        'title': _tr(AppStrings.whyMobileTitle),
        'sub': _tr(AppStrings.whyMobileSub),
      },
      {
        'icon': Icons.search,
        'title': _tr(AppStrings.whySmartTitle),
        'sub': _tr(AppStrings.whySmartSub),
      },
      {
        'icon': Icons.security,
        'title': _tr(AppStrings.whySafeTitle),
        'sub': _tr(AppStrings.whySafeSub),
      },
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.star_rounded,
            title: _tr(AppStrings.whyChooseUs),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              children: [
                for (int i = 0; i < features.length; i++) ...[
                  ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: _brand.withValues(alpha: 0.15),
                      child: Icon(
                        features[i]['icon'] as IconData,
                        color: _brand,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      features[i]['title'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _brand,
                      ),
                    ),
                    subtitle: Text(
                      features[i]['sub'] as String,
                      style: TextStyle(fontSize: 12, color: _mutedText),
                    ),
                  ),
                  if (i != features.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 8. SAFETY REMINDER (LAST card)
  // ---------------------------------------------------------------------------

  Widget _buildSafety() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF2B2517) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isDark ? const Color(0xFF5C4E1E) : const Color(0xFFFFE082),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFF8D6E00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr(AppStrings.safetyReminder),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _tr(AppStrings.safetyBody1),
            style: const TextStyle(height: 1.5, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Text(
            _tr(AppStrings.safetyBody2),
            style: const TextStyle(height: 1.5, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER
  // ---------------------------------------------------------------------------

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 28),
      color: _isDark ? const Color(0xFF0B130E) : const Color(0xFF0D1B2A),
      child: Column(
        children: [
          const Icon(Icons.home_work_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 10),
          const Text(
            _appName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(AppStrings.copyright),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}