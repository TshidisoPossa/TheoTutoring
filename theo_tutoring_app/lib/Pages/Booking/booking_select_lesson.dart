import 'package:flutter/material.dart';

import 'booking_flow_context.dart';
import 'booking_schedule.dart';
import 'booking_api.dart';

class BookingSelectLessonPage extends StatefulWidget {
  const BookingSelectLessonPage({required this.flow, this.api, super.key});

  final BookingFlowContext flow;
  final BookingFlowApi? api;

  @override
  State<BookingSelectLessonPage> createState() =>
      _BookingSelectLessonPageState();
}

class _BookingSelectLessonPageState extends State<BookingSelectLessonPage> {
  String _type = 'Single';
  int _count = 2;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(title: const Text('Lesson')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text(widget.flow.tutor.name),
            subtitle: Text(
              '${widget.flow.subject.subjectName}\n'
              '${widget.flow.tutor.hourlyRate == null ? 'Rate shown at booking' : 'Platform rate: R${widget.flow.tutor.hourlyRate!.toStringAsFixed(2)} per hour'}',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Choose lesson type (60 minutes per lesson)'),
        RadioListTile<String>(
          title: const Text('Single lesson'),
          value: 'Single',
          groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
        ),
        RadioListTile<String>(
          title: const Text('Package'),
          value: 'Package',
          groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
        ),
        if (_type == 'Package')
          DropdownButtonFormField<int>(
            key: const ValueKey('lesson-count'),
            initialValue: _count,
            decoration: const InputDecoration(labelText: 'Lessons to schedule'),
            items: [
              for (var n = 2; n <= 10; n++)
                DropdownMenuItem(value: n, child: Text('$n lessons')),
            ],
            onChanged: (v) => setState(() => _count = v ?? 2),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BookingSchedulePage(
                flow: widget.flow,
                purchaseType: _type,
                lessonCount: _type == 'Single' ? 1 : _count,
                api: widget.api,
              ),
            ),
          ),
          child: const Text('Choose available times'),
        ),
      ],
    ),
  );
}
