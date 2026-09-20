import 'package:flutter/material.dart';
import '../../teacher/views/teacher_proctor_room_page.dart';

class AdminRoomMonitoringPage extends StatelessWidget {
  final String schoolId;
  final String eventId;
  final String roomId;
  final int dayIndex;
  final int sessionIndex;
  final String? eventName;
  final String? roomName;

  const AdminRoomMonitoringPage({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.roomId,
    required this.dayIndex,
    required this.sessionIndex,
    this.eventName,
    this.roomName,
  });

  @override
  Widget build(BuildContext context) {
    // School Admin monitoring view delegating to the live proctor room engine with isAdminView: true
    return TeacherProctorRoomPage(
      schoolId: schoolId,
      eventId: eventId,
      roomId: roomId,
      dayIndex: dayIndex,
      sessionIndex: sessionIndex,
      isAdminView: true,
    );
  }
}
