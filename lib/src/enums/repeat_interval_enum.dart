enum RepeatIntervalEnum { daily, weekly, monthly, yearly, hourly, minutely }

extension RepeatIntervalEnumExtension on RepeatIntervalEnum {
  String get name {
    switch (this) {
      case RepeatIntervalEnum.daily:
        return 'daily';
      case RepeatIntervalEnum.weekly:
        return 'weekly';
      case RepeatIntervalEnum.monthly:
        return 'monthly';
      case RepeatIntervalEnum.yearly:
        return 'yearly';
      case RepeatIntervalEnum.hourly:
        return 'hourly';
      case RepeatIntervalEnum.minutely:
        return 'minutely';
    }
  }
}
