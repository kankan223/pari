/// Phone number validator for E.164 format
///
/// This validator strictly enforces the E.164 international phone number format
/// which is the standard for phone number representation in telecommunications.
///
/// E.164 format: +[country code][subscriber number]
/// Example: +14155552671
///
/// Security: This validator does not log or store raw phone numbers.
class PhoneValidator {
  /// E.164 regex pattern
  ///
  /// Pattern breakdown:
  /// ^\+ - Must start with a plus sign
  /// [1-9] - Country code must start with 1-9 (not 0)
  /// \d{0,3} - Country code can be 1-4 digits total (1-9 followed by 0-3 more digits)
  /// \d{6,14}$ - Subscriber number must be 6-14 digits
  /// Total length: 8-15 characters (including the + sign)
  static final RegExp _e164Pattern = RegExp(r'^\+[1-9]\d{0,3}\d{6,14}$');

  /// Valid ITU-T E.164 country calling codes (without the + sign).
  ///
  /// Used to strictly validate and extract the country code prefix.
  static const Set<String> _countryCallingCodes = {
    '1', '7', // NANP, Russia/Kazakhstan
    '20', '27', // Egypt, South Africa
    '30', '31', '32', '33', '34', '36', '39', // Greece, NL, BE, FR, ES, HU, IT
    '40', '41', '43', '44', '45', '46', '47', '48',
    '49', // RO, CH, AT, UK, DK, SE, NO, PL, DE
    '51', '52', '53', '54', '55', '56', '57',
    '58', // PE, MX, CU, AR, BR, CL, CO, VE
    '60', '61', '62', '63', '64', '65', '66', // MY, AU, ID, PH, NZ, SG, TH
    '81', '82', '84', '86', // JP, KR, VN, CN
    '90', '91', '92', '93', '94', '95', '98', // TR, IN, PK, AF, LK, MM, IR
    '211', '212', '213', '216', '218', // SS, MA, DZ, TN, LY
    '220', '221', '222', '223', '224', '225', '226', '227', '228',
    '229', // GM, SN, MR, ML, GN, CI, BF, NE, TG, BJ
    '230', '231', '232', '233', '234', '235', '236', '237', '238',
    '239', // MU, LR, SL, GH, NG, TD, CF, CM, CV, ST
    '240', '241', '242', '243', '244', '245', '246', '247', '248',
    '249', // GQ, GA, CG, CD, AO, GW, DG, AC, SC, SD
    '250', '251', '252', '253', '254', '255', '256', '257',
    '258', // RW, ET, SO, DJ, KE, TZ, UG, BI, MZ
    '260', '261', '262', '263', '264', '265', '266', '267', '268',
    '269', // ZM, MG, RE, ZW, NA, MW, LS, BW, SZ, KM
    '290', '291', '297', '298', '299', // SH, ER, AW, FO, GL
    '350', '351', '352', '353', '354', '355', '356', '357', '358',
    '359', // GI, PT, LU, IE, IS, AL, MT, CY, FI, BG
    '370', '371', '372', '373', '374', '375', '376', '377', '378',
    '380', // LT, LV, EE, MD, AM, BY, AD, MC, SM, UA
    '381', '382', '383', '385', '386', '387',
    '389', // RS, ME, XK, HR, SI, BA, MK
    '420', '421', '423', // CZ, SK, LI
    '500', '501', '502', '503', '504', '505', '506', '507', '508',
    '509', // FK, BZ, GT, SV, HN, NI, CR, PA, PM, HT
    '590', '591', '592', '593', '594', '595', '596', '597', '598',
    '599', // GP, BO, GY, EC, GF, PY, MQ, SR, UY, CW
    '670', '672', '673', '674', '675', '676', '677', '678',
    '679', // TL, AQ, BN, NR, PG, TO, SB, VU, FJ
    '680', '681', '682', '683', '685', '686', '687', '688', '689', '690', '691',
    '692', // PW, WF, CK, NU, WS, KI, NC, TV, PF, TK, FM, MH
    '800', '808', '850', '852', '853', '855', '856', '870', '878',
    '880', // UIFN, Shared, KP, HK, MO, KH, LA, Inmarsat, UPT, BD
    '881', '882', '886', '888', // GSM, Global, TW, UNDP
    '960', '961', '962', '963', '964', '965', '966', '967', '968',
    '970', // MV, LB, JO, SY, IQ, KW, SA, YE, OM, PS
    '971', '972', '973', '974', '975', '976', '977',
    '979', // AE, IL, BH, QA, BT, MN, NP, Premium
    '992', '993', '994', '995', '996', '998', // TJ, TM, AZ, GE, KG, UZ
  };

  /// Validate a phone number in E.164 format
  ///
  /// Parameters:
  /// - phoneNumber: The phone number to validate
  ///
  /// Returns: true if valid, false otherwise
  ///
  /// Security: Does not log the phone number to prevent plaintext logging
  static bool isValidE164(String phoneNumber) {
    if (!_matchesE164Format(phoneNumber)) {
      return false;
    }

    // Strict validation: country code must be a known ITU-T calling code
    if (extractCountryCode(phoneNumber) == null) {
      return false;
    }

    return true;
  }

  /// Internal helper: checks the raw E.164 format (regex + length) without
  /// recursing into country-code validation.
  ///
  /// Security: Does not log the phone number to prevent plaintext logging
  static bool _matchesE164Format(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return false;
    }

    // Check if it matches the E.164 pattern
    if (!_e164Pattern.hasMatch(phoneNumber)) {
      return false;
    }

    // Additional validation: check total length
    // E.164 max length is 15 characters (including +)
    if (phoneNumber.length > 15) {
      return false;
    }

    // Additional validation: check minimum length
    // E.164 min length is 8 characters (including +)
    if (phoneNumber.length < 8) {
      return false;
    }

    return true;
  }

  /// Normalize a phone number to E.164 format
  ///
  /// This method attempts to convert various phone number formats to E.164.
  /// It handles common formats like:
  /// - With/without plus sign
  /// - With spaces, dashes, or parentheses
  /// - With country code separated
  ///
  /// Parameters:
  /// - phoneNumber: The phone number to normalize
  /// - countryCode: The country code (e.g., "1" for US)
  ///
  /// Returns: Normalized E.164 phone number, or null if invalid
  ///
  /// Security: Does not log the phone number to prevent plaintext logging
  static String? normalizeToE164(String phoneNumber, {String? countryCode}) {
    // Remove all non-digit characters except plus
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // If it starts with +, it's already in international format
    if (cleaned.startsWith('+')) {
      if (isValidE164(cleaned)) {
        return cleaned;
      }
      return null;
    }

    // If country code is provided, prepend it
    if (countryCode != null && countryCode.isNotEmpty) {
      final normalized = '+$countryCode$cleaned';
      if (isValidE164(normalized)) {
        return normalized;
      }
    }

    return null;
  }

  /// Extract country code from E.164 phone number
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 phone number
  ///
  /// Returns: Country code without the + sign, or null if invalid
  ///
  /// Security: Does not log the phone number to prevent plaintext logging
  static String? extractCountryCode(String phoneNumber) {
    // Use the format-only check to avoid recursion with isValidE164
    if (!_matchesE164Format(phoneNumber)) {
      return null;
    }

    // Remove the + sign
    final withoutPlus = phoneNumber.substring(1);

    // Country calling codes are 1-3 digits.
    // Use longest-prefix matching against the known ITU-T list so that
    // e.g. +44 (UK) is extracted as '44' and not '4'.
    for (int len = 3; len >= 1; len--) {
      if (withoutPlus.length >= len) {
        final potentialCode = withoutPlus.substring(0, len);
        if (_countryCallingCodes.contains(potentialCode)) {
          return potentialCode;
        }
      }
    }

    return null;
  }

  /// Mask a phone number for display purposes
  ///
  /// This method masks all but the last 4 digits of the phone number
  /// for display in UI elements while maintaining some identifiability.
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 phone number to mask
  ///
  /// Returns: Masked phone number (e.g., +1415*****671)
  ///
  /// Security: Does not log the phone number to prevent plaintext logging
  static String maskForDisplay(String phoneNumber) {
    if (!isValidE164(phoneNumber)) {
      return 'Invalid';
    }

    // Keep the country code and last 4 digits
    final countryCode = extractCountryCode(phoneNumber) ?? '';
    final lastFour = phoneNumber.substring(phoneNumber.length - 4);

    // Calculate how many asterisks to add
    final asteriskCount =
        phoneNumber.length - countryCode.length - 4 - 1; // -1 for + sign
    final asterisks = '*' * asteriskCount;

    return '+$countryCode$asterisks$lastFour';
  }
}
