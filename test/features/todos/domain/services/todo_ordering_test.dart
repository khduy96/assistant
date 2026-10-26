import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/services/todo_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 22, 8);

DateTime _min(int m) => _t0.add(Duration(minutes: m));

Todo _todo(
  String id, {
  bool done = false,
  TodoPriority priority = TodoPriority.normal,
  DateTime? due,
  DateTime? completedAt,
  int createdMin = 0,
}) => Todo(
  id: id,
  title: id,
  done: done,
  priority: priority,
  dueDate: due,
  completedAt: completedAt,
  createdAt: _min(createdMin),
  updatedAt: _min(createdMin),
);

List<String> _order(List<Todo> todos) => [
  for (final t in TodoOrdering.sorted(todos)) t.id,
];

void main() {
  test('việc chưa xong lên trước việc đã xong', () {
    expect(
      _order([
        _todo('done', done: true, createdMin: 0),
        _todo('open', createdMin: 5),
      ]),
      ['open', 'done'],
    );
  });

  test('ưu tiên cao lên trước, rồi bình thường, rồi thấp', () {
    expect(
      _order([
        _todo('low', priority: TodoPriority.low),
        _todo('normal'),
        _todo('high', priority: TodoPriority.high),
      ]),
      ['high', 'normal', 'low'],
    );
  });

  test(
    'ưu tiên thắng hạn: việc thấp có hạn vẫn xếp sau việc cao không hạn',
    () {
      expect(
        _order([
          _todo('lowDue', priority: TodoPriority.low, due: _min(1)),
          _todo('highNoDue', priority: TodoPriority.high),
        ]),
        ['highNoDue', 'lowDue'],
      );
    },
  );

  test('cùng ưu tiên: hạn gần trước, có hạn đứng trên không hạn', () {
    expect(
      _order([
        _todo('none', createdMin: 0),
        _todo('later', due: _min(300)),
        _todo('sooner', due: _min(60)),
      ]),
      ['sooner', 'later', 'none'],
    );
  });

  test('cùng ưu tiên, cùng hạn hoặc cùng không hạn: createdAt tăng dần', () {
    expect(
      _order([_todo('newer', createdMin: 9), _todo('older', createdMin: 1)]),
      ['older', 'newer'],
    );
    expect(
      _order([
        _todo('newerDue', due: _min(60), createdMin: 9),
        _todo('olderDue', due: _min(60), createdMin: 1),
      ]),
      ['olderDue', 'newerDue'],
    );
  });

  test('việc đã xong: completedAt giảm dần', () {
    expect(
      _order([
        _todo('first', done: true, completedAt: _min(10)),
        _todo('last', done: true, completedAt: _min(30)),
        _todo('mid', done: true, completedAt: _min(20)),
      ]),
      ['last', 'mid', 'first'],
    );
  });

  test('việc đã xong thiếu completedAt: theo createdAt giảm dần', () {
    expect(
      _order([
        _todo('old', done: true, createdMin: 1),
        _todo('new', done: true, createdMin: 9, completedAt: _min(2)),
      ]),
      ['new', 'old'],
    );
  });

  test('việc đã xong bỏ qua ưu tiên và hạn', () {
    expect(
      _order([
        _todo(
          'highDue',
          done: true,
          priority: TodoPriority.high,
          due: _min(1),
          completedAt: _min(10),
        ),
        _todo(
          'low',
          done: true,
          priority: TodoPriority.low,
          completedAt: _min(20),
        ),
      ]),
      ['low', 'highDue'],
    );
  });

  test('sorted trả list mới, không đổi list vào', () {
    final input = [_todo('b', createdMin: 2), _todo('a', createdMin: 1)];
    final sorted = TodoOrdering.sorted(input);
    expect([for (final t in input) t.id], ['b', 'a']);
    expect([for (final t in sorted) t.id], ['a', 'b']);
  });
}
