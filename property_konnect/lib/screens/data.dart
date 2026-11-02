// ============================================================
// KENYA LOCATIONS DATA
//
// All 47 counties with their subcounties.
//
// Usage:
//
//   import 'data.dart';
//
//   KenyaLocation.counties            -> all county names
//   KenyaLocation.subcountiesOf('Kisumu')
//                                     -> subcounties of Kisumu
//   KenyaLocation.countyMap           -> full map
// ============================================================

class KenyaLocation {
  KenyaLocation._();

  /// County name -> its subcounties.
  static const Map<String, List<String>> countyMap = {
    'Mombasa': [
      'Changamwe', 'Jomvu', 'Kisauni', 'Nyali', 'Mvita', 'Likoni',
    ],
    'Kwale': [
      'Msambweni', 'Matuga', 'Kinango', 'Lunga Lunga',
    ],
    'Kilifi': [
      'Kilifi North', 'Kilifi South', 'Rabai', 'Kaloleni',
      'Ganze', 'Malindi', 'Magarini',
    ],
    'Tana River': [
      'Garsen', 'Galole', 'Bura',
    ],
    'Lamu': [
      'Lamu East', 'Lamu West', 'Mpeketoni',
    ],
    'Taita Taveta': [
      'Taveta', 'Wundanyi', 'Mwatate', 'Voi',
    ],
    'Garissa': [
      'Garissa Township', 'Ijara', 'Dadaab', 'Balambala',
      'Lagdera', 'Fafi',
    ],
    'Wajir': [
      'Wajir North', 'Wajir East', 'Wajir South', 'Wajir West',
      'Tarbaj', 'Eldas',
    ],
    'Mandera': [
      'Mandera East', 'Mandera North', 'Mandera South', 'Mandera West',
      'Mandera Central', 'Banissa', 'Lafey',
    ],
    'Marsabit': [
      'North Horr', 'Saku', 'Moyale', 'Laisamis',
    ],
    'Isiolo': [
      'Isiolo North', 'Isiolo South',
    ],
    'Meru': [
      'Buuri', 'North Imenti', 'Central Imenti', 'South Imenti',
      'Tigania West', 'Tigania East', 'Igembe Central',
      'Igembe North', 'Igembe South',
    ],
    'Tharaka Nithi': [
      'Maara', 'Chuka Igambang\'ombe', 'Tharaka',
    ],
    'Embu': [
      'Manyatta', 'Runyenjes', 'Mbeere North', 'Mbeere South',
    ],
    'Kitui': [
      'Kitui East', 'Kitui Rural', 'Kitui South', 'Kitui Central',
      'Kitui West', 'Mwingi North', 'Mwingi Central', 'Mwingi West',
    ],
    'Machakos': [
      'Masinga', 'Yatta', 'Kangundo', 'Matungulu', 'Kathiani',
      'Mavoko', 'Machakos Town', 'Mwala', 'Kaiti',
    ],
    'Makueni': [
      'Kibwezi West', 'Kibwezi East', 'Makueni', 'Kilome', 'Mbooni',
    ],
    'Nairobi': [
      'Westlands', 'Lang\'ata', 'Kibra', 'Dagoretti North',
      'Dagoretti South', 'Embakasi Central', 'Embakasi East',
      'Embakasi North', 'Embakasi South', 'Embakasi West',
      'Kamukunji', 'Makadara', 'Mathare', 'Roysambu', 'Ruaraka',
      'Starehe', 'Kasarani',
    ],
    'Kiambu': [
      'Gatundu South', 'Gatundu North', 'Juja', 'Thika Town',
      'Ruiru', 'Kiambu Town', 'Kabete', 'Kikuyu', 'Limuru',
      'Lari', 'Githunguri', 'Kiambaa',
    ],
    'Murang\'a': [
      'Kiharu', 'Kangema', 'Mathioya', 'Kigumo', 'Gatanga',
      'Kandara', 'Maragwa',
    ],
    'Nyeri': [
      'Tetu', 'Kieni', 'Mathira', 'Othaya', 'Mukurweini',
      'Nyeri Central',
    ],
    'Nyandarua': [
      'Ol Kalou', 'Ol Jorok', 'Kipipiri', 'Ndaragwa', 'Kinangop',
    ],
    'Kirinyaga': [
      'Kirinyaga Central', 'Gichugu', 'Mwea', 'Ndia',
    ],
    'Nakuru': [
      'Nakuru Town East', 'Nakuru Town West', 'Bahati', 'Naivasha',
      'Gilgil', 'Subukia', 'Njoro', 'Molo', 'Kuresoi North',
      'Kuresoi South', 'Rongai',
    ],
    'Narok': [
      'Narok North', 'Narok East', 'Narok South', 'Narok West',
      'Emurua Dikirr', 'Kilgoris',
    ],
    'Kajiado': [
      'Kajiado North', 'Kajiado Central', 'Kajiado East',
      'Kajiado West', 'Kajiado South',
    ],
    'Kericho': [
      'Ainamoi', 'Belgut', 'Kipkelion East', 'Kipkelion West',
      'Sigowet Soin',
    ],
    'Bomet': [
      'Bomet Central', 'Bomet East', 'Chepalungu', 'Sotik', 'Konoin',
    ],
    'Kakamega': [
      'Lugari', 'Likuyani', 'Malava', 'Navakholo', 'Lurambi',
      'Ikolomani', 'Shinyalu', 'Mumias East', 'Mumias West',
      'Matungu', 'Butere', 'Khwisero',
    ],
    'Vihiga': [
      'Vihiga', 'Sabatia', 'Luanda', 'Emuhaya', 'Hamisi',
    ],
    'Bungoma': [
      'Mt Elgon', 'Kabuchai', 'Bumula', 'Kanduyi',
      'Webuye East', 'Webuye West', 'Kimilili', 'Tongaren', 'Sirisia',
    ],
    'Busia': [
      'Teso North', 'Teso South', 'Nambale', 'Matayos',
      'Butula', 'Budalangi', 'Funyula', 'Samia',
    ],
    'Siaya': [
      'Ugenya', 'Ugunja', 'Alego Usonga', 'Gem',
      'Rarieda', 'Bondo',
    ],
    'Kisumu': [
      'Kisumu East', 'Kisumu West', 'Kisumu Central', 'Seme',
      'Nyando', 'Muhoroni', 'Nyakach',
    ],
    'Homa Bay': [
      'Kasipul', 'Kabondo Kasipul', 'Karachuonyo', 'Rangwe',
      'Homa Bay Town', 'Ndhiwa', 'Mbita', 'Suba',
    ],
    'Migori': [
      'Kuria West', 'Kuria East', 'Nyatike', 'Awendo',
      'Suna East', 'Suna West', 'Uriri', 'Rongo',
    ],
    'Kisii': [
      'Bobasi', 'Bomachoge Borabu', 'Bomachoge Chache', 'Bonchari',
      'Kitutu Chache North', 'Kitutu Chache South', 'Nyaribari Chache',
      'Nyaribari Masaba', 'South Mugirango',
    ],
    'Nyamira': [
      'Kitutu Masaba', 'West Mugirango', 'North Mugirango', 'Borabu',
    ],
    'Trans Nzoia': [
      'Kwanza', 'Endebess', 'Saboti', 'Kiminini', 'Cherangany',
    ],
    'Uasin Gishu': [
      'Turbo', 'Ainabkoi', 'Kapseret', 'Kesses', 'Moiben', 'Soy',
    ],
    'Elgeyo Marakwet': [
      'Keiyo North', 'Keiyo South', 'Marakwet East', 'Marakwet West',
    ],
    'Nandi': [
      'Aldai', 'Nandi Hills', 'Emgwen', 'Mosop', 'Tinderet',
      'Chesumei',
    ],
    'West Pokot': [
      'Kacheliba', 'Pokot South', 'Sigor', 'Kapenguria',
    ],
    'Samburu': [
      'Samburu North', 'Samburu Central', 'Samburu East',
    ],
    'Turkana': [
      'Turkana North', 'Turkana South', 'Turkana East',
      'Turkana West', 'Turkana Central', 'Loima',
    ],
    'Laikipia': [
      'Laikipia East', 'Laikipia West', 'Laikipia North',
    ],
    'Baringo': [
      'Baringo Central', 'Baringo South', 'Baringo North',
      'Tiaty', 'Mogotio',
    ],
  };

  /// All 47 county names, in alphabetical order.
  static List<String> get counties {
    final names = countyMap.keys.toList()..sort();
    return names;
  }

  /// Subcounties of a given county.
  static List<String> subcountiesOf(String county) {
    return countyMap[county] ?? const [];
  }
}

// ============================================================
// PROPERTY CATEGORIES + SUBTYPES
//
// Rent: Residential / Commercial / Short Stay
// Buy:  Land / Commercial / Short Stay
// ============================================================

class PropertyCategories {
  PropertyCategories._();

  static const Map<String, List<String>> rentCategories = {
    'Residential': ['Apartment', 'House', 'Studio','Hostel'],
    'Commercial': ['Shop', 'Office', 'Warehouse'],
    'Short Stay': ['Airbnb', 'Guest House', 'Hotel'],
  };

  static const Map<String, List<String>> saleCategories = {
    'Land': ['Residential Plot', 'Agricultural Land', 'Ranch'],
    'Commercial': ['Shop', 'Office', 'Warehouse'],
  };

  /// Categories available for a purpose ('Rent' or 'Buy').
  static List<String> categoriesFor(String purpose) {
    final map =
    purpose == 'Buy' ? saleCategories : rentCategories;
    return map.keys.toList();
  }

  /// Subtypes available within a category for a purpose.
  static List<String> subtypesFor(String purpose, String category) {
    final map =
    purpose == 'Buy' ? saleCategories : rentCategories;
    return map[category] ?? const [];
  }
}