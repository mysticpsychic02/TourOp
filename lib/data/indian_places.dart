const List<String> indianPlaces = [
  // States & Union Territories
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa',
  'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala',
  'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland',
  'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
  'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
  'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',

  // Delhi NCR
  'Delhi', 'New Delhi', 'Noida', 'Greater Noida', 'Ghaziabad', 'Faridabad', 'Gurgaon', 'Gurugram',

  // Uttar Pradesh
  'Agra', 'Aligarh', 'Allahabad', 'Ambedkar Nagar', 'Amroha', 'Auraiya', 'Azamgarh', 'Bahraich',
  'Ballia', 'Balrampur', 'Banda', 'Bara Banki', 'Bareilly', 'Basti', 'Bhadohi', 'Bijnor', 'Budaun',
  'Bulandshahr', 'Chandauli', 'Chitrakoot', 'Deoria', 'Etah', 'Etawah', 'Faizabad', 'Farrukhabad',
  'Fatehpur', 'Firozabad', 'Gautam Buddh Nagar', 'Ghaziabad', 'Ghazipur', 'Gonda', 'Gorakhpur', 'Hamirpur',
  'Hardoi', 'Hathras', 'Jalaun', 'Jaunpur', 'Jhansi', 'Kannauj', 'Kanpur', 'Kasganj', 'Kaushambi', 'Kheri',
  'Kushinagar', 'Lalitpur', 'Lucknow', 'Maharajganj', 'Mahoba', 'Mainpuri', 'Mathura', 'Mau', 'Meerut', 'Mirzapur',
  'Moradabad', 'Muzaffarnagar', 'Pilibhit', 'Pratapgarh', 'Rae Bareli', 'Rampur', 'Saharanpur', 'Sant Kabir Nagar',
  'Sant Ravidas Nagar', 'Shahjahanpur', 'Shamli', 'Shravasti', 'Siddharthnagar', 'Sitapur', 'Sonbhadra', 'Sultanpur',
  'Unnao', 'Varanasi',


  // Haryana
  'Ambala', 'Ambala Cantt', 'Asandh', 'Ateli', 'Bahadurgarh', 'Barwala', 'Bawal', 'Beri', 'Bhiwani',
  'Charkhi Dadri', 'Chhachhrauli', 'Charkhi Dadri', 'Dabwali', 'Ellenabad', 'Faridabad', 'Fatehabad',
  'Firozpur Jhirka', 'Ganaur', 'Gharaunda', 'Gohana', 'Gurgaon', 'Haileymandi', 'Hansi', 'Hisar', 'Hodal',
  'Indri', 'Jagadhri', 'Jakhal Mandi', 'Jhajjar', 'Jind', 'Julana', 'Kaithal', 'Kalanaur', 'Kalanwali', 
  'Kalka', 'Kanina', 'Karnal', 'Kharkhoda', 'Kosli', 'Kurukshetra', 'Ladwa', 'Loharu', 'Maham', 'Mahendragarh',
  'Mandi Dabwali', 'Narnaul', 'Narayangarh', 'Nissing', 'Palwal', 'Panchkula', 'Panipat', 'Pehowa', 'Pinjore',
  'Punahana', 'Radaur', 'Ratia', 'Rewari', 'Rohtak', 'Safidon', 'Samalkha', 'Shahabad', 'Sirsa', 'Sohna', 'Sonipat',
  'Taoru', 'Thanesar', 'Tohana', 'Tosham', 'Uchana', 'Yamunanagar',


  // Punjab
  'Amritsar', 'Ajnala', 'Raja Sansi', 'Ramdass', 'Barnala', 'Tapa', 'Dhanaula', 'Bathinda', 
  'Rampura Phul', 'Goniana', 'Maur', 'Talwandi Sabo', 'Faridkot', 'Jaitu', 'Kotkapura', 
  'Fatehgarh Sahib', 'Sirhind-Fategarh', 'Bassi Pathana', 'Khamanon', 'Fazilka', 'Abohar',
  'Jalalabad (W)', 'Firozpur', 'Zira', 'Guru Har Sahai', 'Gurdaspur', 'Batala', 'Qadian',
  'Dera Baba Nanak', 'Hoshiarpur', 'Garhshankar', 'Dasuya', 'Mukerian', 'Jalandhar', 'Phillaur',
  'Nakodar', 'Kartarpur', 'Goraya', 'Nurmahal', 'Kapurthala', 'Phagwara', 'Sultanpur Lodhi',
  'Bholath', 'Ludhiana', 'Khanna', 'Jagraon', 'Samrala', 'Raikot', 'Machhiwara', 'Mansa',
  'Sardulgarh', 'Budhlada', 'Moga', 'Bagha Purana', 'Nihal Singh Wala', 'Pathankot', 'Sujanpur',
  'Dhar Kalan', 'Patiala', 'Rajpura', 'Samana', 'Nabha', 'Ghanaur', 'Rupnagar', 'Nangal', 'Anandpur Sahib',
  'Mohali', 'Kharar', 'Zirakpur', 'Kurali', 'Sangrur', 'Sunam', 'Dhuri', 'Lehragaga', 'Longowal', 'Malerkotla',
  'Nawanshahr', 'Balachaur', 'Banga', 'Sri Muktsar Sahib', 'Malout', 'Gidderbaha', 'Tarn Taran Sahib', 'Patti', 'Bhikhiwind',


  // Rajasthan
  'Ajmer', 'Alwar', 'Banswara', 'Barmer', 'Bharatpur', 'Bhilwara', 'Bikaner', 'Chittorgarh',
  'Hanumangarh', 'Jaipur', 'Jaisalmer', 'Jalore', 'Jhalawar', 'Jhunjhunu', 'Jodhpur', 'Kota',
  'Nagaur', 'Pali', 'Sikar', 'Sri Ganganagar', 'Tonk', 'Udaipur',

  // Uttarakhand
  'Almora', 'Bageshwar', 'Chamoli', 'Champawat', 'Dehradun', 'Haridwar', 'Nainital', 'Pauri',
  'Pithoragarh', 'Rudraprayag', 'Tehri', 'Udham Singh Nagar', 'Uttarkashi', 'Roorkee', 'Kashipur',
  'Haldwani', 'Rishikesh', 'Kotdwar', 'Manglaur', 'Kichha', 'Jaspur', 'Bazpur', 'Sitarganj', 'Tanakpur',


  // Himachal Pradesh
  'Bilaspur', 'Chamba', 'Dalhousie', 'Hamirpur', 'Kangra', 'Dharamshala', 'Kinnaur', 'Kullu',
  'Lahaul and Spiti', 'Mandi', 'Palampur', 'Shimla', 'Solan', 'Una', 'Nahan', 'Paonta Sahib',
  'Sundarnagar', 'Manali', 'Nagrota Bagwan', 'Nurpur', 'Baddi', 'Parwanoo',


  // Jammu & Kashmir / Ladakh
  'Anantnag', 'Baramulla', 'Budgam', 'Ganderbal', 'Jammu', 'Kargil', 'Kathua', 'Kishtwar', 'Kupwara',
  'Leh', 'Poonch', 'Pulwama', 'Rajouri', 'Samba', 'Shopian', 'Srinagar', 'Udhampur',
];
