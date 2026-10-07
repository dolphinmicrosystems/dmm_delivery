import 'package:dmm_delivery/models/run_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads and writes the stored 24-hour form', () {
    expect(parseStartTime('05:00'), (hour: 5, minute: 0));
    expect(parseStartTime('23:59'), (hour: 23, minute: 59));
    expect(encodeStartTime(5, 0), '05:00');
  });

  test('refuses anything the rules would refuse', () {
    expect(parseStartTime('5am'), isNull);
    expect(parseStartTime('24:00'), isNull);
    expect(parseStartTime(null), isNull);
  });

  test('shows times the way people say them', () {
    expect(formatStartTime('05:00'), '5:00 am');
    expect(formatStartTime('12:30'), '12:30 pm');
    expect(formatStartTime('00:15'), '12:15 am');
    expect(formatClock(17, 5), '5:05 pm');
  });

  test('works out when the van should be back', () {
    expect(expectedFinish('05:00', const Duration(hours: 2, minutes: 16)), '7:16 am');
    expect(expectedFinish('23:00', const Duration(hours: 2)), '1:00 am next day');
    expect(expectedFinish(null, const Duration(hours: 2)), isNull);
    expect(expectedFinish('05:00', null), isNull);
  });

  group('StopTime', () {
    test('keeps the setting inside the range the rules accept', () {
      expect(StopTime.sanitize(180), 180);
      expect(StopTime.sanitize(5), StopTime.fallbackSeconds);
      expect(StopTime.sanitize(3600), StopTime.fallbackSeconds);
      expect(StopTime.sanitize(null), StopTime.fallbackSeconds);
    });

    test('reads as people say it', () {
      expect(StopTime.label(60), '1 min');
      expect(StopTime.label(300), '5 min');
      expect(StopTime.label(45), '45 sec');
      expect(StopTime.label(150), '2 min 30');
    });
  });

  group('start and end times', () {
    test('a window reads as people say it', () {
      expect(formatWindow('20:00', '22:44'), '8:00 pm - 10:44 pm');
      expect(formatWindow('05:00', null), '5:00 am');
      expect(formatWindow(null, '07:00'), isNull);
    });

    test('the suggested end is the start plus the estimate, past midnight too', () {
      expect(addToStartTime('20:00', const Duration(hours: 2, minutes: 44)), '22:44');
      expect(addToStartTime('22:30', const Duration(hours: 2)), '00:30');
      expect(addToStartTime(null, const Duration(hours: 2)), isNull);
    });

    test('an end at or before the start is the next morning', () {
      expect(windowLength('20:00', '22:44'), const Duration(hours: 2, minutes: 44));
      expect(windowLength('22:30', '00:30'), const Duration(hours: 2));
      expect(windowLength('05:00', null), isNull);
    });
  });
}
