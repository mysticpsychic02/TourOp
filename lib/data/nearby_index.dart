// lib/data/nearby_index.dart
// Nearby/along-the-way adjacency for quick matching without coordinates.
// Start with Punjab; extend to other states as you need.

const Map<String, List<String>> kNearbyIndex = {
  // —— Punjab core corridor examples ——
  // Ludhiana region
  'Ludhiana': [
    'Moga', 'Khanna', 'Jagraon', 'Raikot', 'Samrala', 'Machhiwara', 'Nabha', 'Malerkotla',
    'Mandi Gobindgarh', 'Doraha', 'Payal', 'Phillaur', 'Rupnagar'
  ],

  // Moga region
  'Moga': [
    'Ludhiana', 'Firozpur', 'Faridkot', 'Kotkapura', 'Barnala', 'Bagha Purana', 'Jagraon'
  ],

  // Firozpur region
  'Firozpur': [
    'Moga', 'Faridkot', 'Fazilka', 'Zira', 'Jalalabad (W)', 'Muktsar', 'Kotkapura'
  ],

  // Faridkot/Kotkapura/Muktsar axis
  'Faridkot': ['Kotkapura', 'Firozpur', 'Moga', 'Sri Muktsar Sahib', 'Bathinda'],
  'Kotkapura': ['Faridkot', 'Moga', 'Firozpur', 'Sri Muktsar Sahib', 'Jaitu'],
  'Sri Muktsar Sahib': ['Kotkapura', 'Malout', 'Gidderbaha', 'Fazilka', 'Abohar', 'Faridkot'],

  // Bathinda side
  'Bathinda': [
    'Rampura Phul', 'Goniana', 'Maur', 'Talwandi Sabo',
    'Mansa', 'Kotkapura', 'Faridkot', 'Barnala'
  ],
  'Barnala': ['Bathinda', 'Mansa', 'Moga', 'Sangrur', 'Dhuri'],
  'Mansa': ['Bathinda', 'Sardulgarh', 'Budhlada', 'Barnala'],

  // Amritsar/Jalandhar/Kapurthala axis
  'Amritsar': ['Tarn Taran Sahib', 'Batala', 'Ajnala', 'Raja Sansi'],
  'Tarn Taran Sahib': ['Amritsar', 'Patti', 'Bhikhiwind'],
  'Jalandhar': ['Phagwara', 'Nakodar', 'Kartarpur', 'Phillaur', 'Hoshiarpur', 'Kapurthala'],
  'Phagwara': ['Jalandhar', 'Kapurthala', 'Hoshiarpur'],
  'Kapurthala': ['Phagwara', 'Sultanpur Lodhi', 'Jalandhar', 'Nakodar'],

  // Patiala/Mohali/Chandigarh belt
  'Patiala': ['Rajpura', 'Samana', 'Nabha', 'Ghanaur'],
  'Mohali': ['Kharar', 'Zirakpur', 'Chandigarh', 'Kurali'],
  'Chandigarh': ['Mohali', 'Panchkula', 'Zirakpur', 'Kharar'],

  // Sangrur/Malerkotla side
  'Sangrur': ['Sunam', 'Dhuri', 'Longowal', 'Malerkotla', 'Barnala'],
  'Malerkotla': ['Sangrur', 'Dhuri', 'Nabha', 'Ludhiana'],

  // Add more cities you actively see in your data…
};
