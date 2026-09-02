part of 'event_editor_wizard.dart';

extension EventEditorWizardMobileExtension on _EventEditorWizardState {
  Widget buildMobile(BuildContext context) {
    final self = this;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Buat Event Ujian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (self._draftStatus == 'saving')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
            )
          else if (self._draftStatus == 'saved')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.cloud_done_rounded, size: 16, color: Color(0xFF10B981)),
            ),
        ],
      ),
      body: self._isLoading
          ? self._buildEventProcessingOverlay()
          : Column(
              children: [
                self._buildMobileStepperHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: self._buildMobileStepContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (self._currentStep > 0)
                        OutlinedButton.icon(
                          onPressed: () => _setStep(self._currentStep - 1),
                          icon: const Icon(Icons.arrow_back_rounded, size: 14),
                          label: const Text('Sebelumnya', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      else
                        const SizedBox(),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (self._currentStep == 0) {
                            if (_formKey1.currentState!.validate() && self._startDate != null && self._endDate != null) {
                              _setStep(self._currentStep + 1);
                              self._autoSaveDraft();
                            } else if (self._startDate == null || self._endDate == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pilih rentang tanggal terlebih dahulu!'), backgroundColor: Colors.red),
                              );
                            }
                          } else if (self._currentStep == 1) {
                            if (self._sessions.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tambahkan minimal 1 sesi ujian!'), backgroundColor: Colors.red),
                              );
                            } else {
                              _setStep(self._currentStep + 1);
                              self._autoSaveDraft();
                            }
                          } else if (self._currentStep == 2) {
                            if (self._timetable.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tambahkan minimal 1 jadwal mata pelajaran!'), backgroundColor: Colors.red),
                              );
                            } else {
                              _setStep(self._currentStep + 1);
                              self._autoSaveDraft();
                            }
                          } else if (self._currentStep == 5) {
                            // Validasi Step 6: semua mapel harus sudah punya jadwal sesi
                            final unscheduled = self._timetable.where((t) => t['sessionId'] == null).length;
                            if (unscheduled > 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Masih ada $unscheduled mata pelajaran yang belum mendapat jadwal!'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } else {
                              _setStep(self._currentStep + 1);
                              self._autoSaveDraft();
                            }
                          } else if (self._currentStep == 6) {
                            // Validasi Step 7: semua ruangan & sesi harus sudah ada pengawasnya
                            final days = self._examDays();
                            final missingSlots = <String>[];
                            for (int d = 0; d < days.length; d++) {
                              for (int s = 0; s < self._sessions.length; s++) {
                                for (final room in self._rooms) {
                                  final rid = (room['id'] ?? '').toString();
                                  final key = 'day_${d}_session_${s}_room_$rid';
                                  if (!self._proctorGrid.containsKey(key) || self._proctorGrid[key] == null) {
                                    final rname = (room['name'] ?? room['code'] ?? rid).toString();
                                    final sname = self._sessions[s]['name'] ?? 'Sesi ${s + 1}';
                                    missingSlots.add('$rname - $sname');
                                  }
                                }
                              }
                            }
                            if (missingSlots.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${missingSlots.length} slot pengawas belum diisi!'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } else {
                              _setStep(self._currentStep + 1);
                              self._autoSaveDraft();
                            }
                          } else if (self._currentStep == 7) {
                            _submit();
                          } else {
                            _setStep(self._currentStep + 1);
                            self._autoSaveDraft();
                          }
                        },
                        icon: Icon(self._currentStep == 7 ? Icons.check_circle_rounded : Icons.arrow_forward_rounded, size: 14),
                        label: Text(self._currentStep == 7 ? 'Simpan' : 'Lanjut', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: self._currentStep == 7 ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMobileStepperHeader() {
    final self = this;
    final stepsMeta = [
      {'title': 'Info', 'icon': Icons.edit_note_rounded},
      {'title': 'Sesi', 'icon': Icons.access_time_filled_rounded},
      {'title': 'Mapel', 'icon': Icons.menu_book_rounded},
      {'title': 'Ruang', 'icon': Icons.meeting_room_rounded},
      {'title': 'Murid', 'icon': Icons.groups_rounded},
      {'title': 'Jadwal', 'icon': Icons.calendar_month_rounded},
      {'title': 'Pengawas', 'icon': Icons.supervisor_account_rounded},
      {'title': 'Final', 'icon': Icons.verified_rounded},
    ];

    final progress = (self._currentStep + 1) / 8.0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Langkah ${self._currentStep + 1}/8: ${stepsMeta[self._currentStep]['title']}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(stepsMeta.length, (i) {
                final isActive = self._currentStep == i;
                final isCompleted = i < self._maxStepReached;
                final isClickable = i <= self._maxStepReached;

                return InkWell(
                  onTap: isClickable ? () => _setStep(i) : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF4F46E5)
                          : isCompleted
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF4F46E5)
                            : isCompleted
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.2)
                                : isCompleted
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFCBD5E1),
                          ),
                          alignment: Alignment.center,
                          child: isCompleted
                              ? const Icon(Icons.check, size: 8, color: Colors.white)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.white : const Color(0xFF475569),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          stepsMeta[i]['title'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.w500,
                            color: isActive
                                ? Colors.white
                                : isCompleted
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeaderBanner({
    required String stepNumber,
    required String title,
    required String subtitle,
    required IconData icon,
    Color iconColor = const Color(0xFF4F46E5),
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }

  Widget _buildMobileStepContent() {
    final self = this;
    switch (self._currentStep) {
      case 0:
        return self._buildMobileStep1();
      case 1:
        return self._buildMobileStep2();
      case 2:
        return self._buildMobileStep3();
      case 3:
        return self._buildMobileStep4();
      case 4:
        return self._buildMobileStep5();
      case 5:
        return self._buildMobileStep6();
      case 6:
        return self._buildMobileStep7();
      case 7:
        return self._buildMobileStep8();
      default:
        return const SizedBox();
    }
  }

  Widget _arrangeMobileToggleBtn({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: active ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: Info Dasar (Mobile) ───────────────────────────────────────────
  Widget _buildMobileStep1() {
    final self = this;
    final examTypes = [
      {'key': 'UTS', 'label': 'UTS', 'icon': Icons.hourglass_top_rounded},
      {'key': 'UAS', 'label': 'UAS', 'icon': Icons.school_rounded},
      {'key': 'UH', 'label': 'UH', 'icon': Icons.assignment_turned_in_rounded},
      {'key': 'TO', 'label': 'Try Out', 'icon': Icons.psychology_rounded},
      {'key': 'US', 'label': 'US', 'icon': Icons.military_tech_rounded},
    ];

    final daysCount = self._startDate != null && self._endDate != null
        ? self._endDate!.difference(self._startDate!).inDays + 1
        : 0;

    return Form(
      key: _formKey1,
      child: ListView(
        children: [
          self._buildMobileHeaderBanner(
            stepNumber: 'Langkah 1',
            title: 'Informasi Dasar Event',
            subtitle: 'Lengkapi identitas event ujian sekolah.',
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFF3B82F6),
          ),

          const Text('Nama Event Ujian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextFormField(
            controller: self._nameController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Contoh: UTS Ganjil 2026',
              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF3B82F6), size: 18),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Nama event harus diisi!' : null,
          ),
          const SizedBox(height: 14),

          const Text('Tipe Ujian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: examTypes.map((et) {
              final isSelected = self._examType == et['key'];
              return InkWell(
                onTap: () => self.updateState(() => self._examType = et['key'] as String),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF3B82F6).withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        et['icon'] as IconData,
                        size: 13,
                        color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        et['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          const Text('Tahun Ajaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextFormField(
            controller: self._academicYearController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Contoh: 2026/2027',
              prefixIcon: const Icon(Icons.calendar_today_rounded, color: Color(0xFF3B82F6), size: 18),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Tahun ajaran harus diisi!' : null,
          ),
          const SizedBox(height: 14),

          const Text('Rentang Tanggal Pelaksanaan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          InkWell(
            onTap: self._selectDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: self._startDate != null ? const Color(0xFF3B82F6).withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                  width: self._startDate != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.date_range_rounded, color: Color(0xFF3B82F6), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          self._startDate != null && self._endDate != null
                              ? '${ExamPdfGenerator.formatIndonesianDate(self._startDate!).split(',')[1].trim()} — ${ExamPdfGenerator.formatIndonesianDate(self._endDate!).split(',')[1].trim()}'
                              : 'Pilih Rentang Tanggal Ujian',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: self._startDate != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          self._startDate != null && self._endDate != null
                              ? 'Durasi: $daysCount hari pelaksanaan'
                              : 'Tap untuk mengatur tanggal',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          const Text('Deskripsi / Tata Tertib (Opsional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextFormField(
            controller: self._descController,
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Tuliskan catatan khusus atau tata tertib...',
              prefixIcon: const Icon(Icons.notes_rounded, color: Color(0xFF3B82F6), size: 18),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Sesi Ujian (Mobile) ────────────────────────────────────────────
  Widget _buildMobileStep2() {
    final self = this;
    final quickPresets = [
      {'name': 'Sesi 1', 'start': const TimeOfDay(hour: 7, minute: 0), 'end': const TimeOfDay(hour: 8, minute: 0), 'label': '07:00-08:00'},
      {'name': 'Sesi 2', 'start': const TimeOfDay(hour: 8, minute: 0), 'end': const TimeOfDay(hour: 9, minute: 0), 'label': '08:00-09:00'},
      {'name': 'Sesi 3', 'start': const TimeOfDay(hour: 9, minute: 0), 'end': const TimeOfDay(hour: 10, minute: 0), 'label': '09:00-10:00'},
    ];

    return ListView(
      children: [
        self._buildMobileHeaderBanner(
          stepNumber: 'Langkah 2',
          title: 'Konfigurasi Sesi Ujian',
          subtitle: 'Atur jam mulai dan selesai sesi ujian harian.',
          icon: Icons.access_time_filled_rounded,
          iconColor: const Color(0xFF06B6D4),
        ),

        // Sesi Terdaftar (List at top)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.list_alt_rounded, size: 16, color: Color(0xFF06B6D4)),
                      SizedBox(width: 6),
                      Text('Sesi Terdaftar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${self._sessions.length} Sesi',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0891B2)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (self._sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('Belum ada sesi ditambahkan', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11))),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: self._sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, idx) {
                    final s = self._sessions[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                              Text('${s['startTime']} - ${s['endTime']}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              self.updateState(() => self._sessions.removeAt(idx));
                              self._autoSaveDraft();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tambah Sesi Baru (Form at bottom)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF06B6D4)),
                  SizedBox(width: 6),
                  Text('Tambah Sesi Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 10),

              const Text('Nama Sesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
              const SizedBox(height: 4),
              TextFormField(
                controller: self._sessionNameController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Contoh: Sesi ${self._sessions.length + 1}',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),

              const Text('Preset Waktu Cepat:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: quickPresets.map((qp) {
                  return ActionChip(
                    avatar: const Icon(Icons.flash_on_rounded, size: 11, color: Color(0xFF0891B2)),
                    label: Text('${qp['name']} (${qp['label']})', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF0E7490))),
                    backgroundColor: const Color(0xFFECFEFF),
                    side: const BorderSide(color: Color(0xFFA5F3FC)),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      self.updateState(() {
                        self._sessionNameController.text = qp['name'] as String;
                        self._startTime = qp['start'] as TimeOfDay;
                        self._endTime = qp['end'] as TimeOfDay;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mulai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final t = await showTimePicker(context: context, initialTime: self._startTime ?? const TimeOfDay(hour: 7, minute: 0));
                            if (t != null) self.updateState(() => self._startTime = t);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(self._startTime == null ? '--:--' : self._startTime!.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF06B6D4)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Selesai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final t = await showTimePicker(context: context, initialTime: self._endTime ?? const TimeOfDay(hour: 8, minute: 30));
                            if (t != null) self.updateState(() => self._endTime = t);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(self._endTime == null ? '--:--' : self._endTime!.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF06B6D4)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: self._addSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0891B2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Tambah Sesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 3: Jadwal Mapel per Kelas (Mobile) ────────────────────────────────
  Widget _buildMobileStep3() {
    final self = this;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _adminUserService.streamClasses(self.widget.schoolId),
      builder: (context, classesSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _adminUserService.streamSubjects(self.widget.schoolId),
          builder: (context, subjectsSnap) {
            return StreamBuilder<List<Teacher>>(
              stream: _adminUserService.streamTeachers(self.widget.schoolId),
              builder: (context, teachersSnap) {
                final bool classesReady = classesSnap.hasData;
                final classes = classesSnap.data ?? [];
                final subjects = subjectsSnap.data ?? [];
                final teachers = teachersSnap.data ?? [];

                final Map<String, Map<String, dynamic>> groupedTimetable = {};
                if (classesReady) {
                  for (var entry in self._timetable) {
                    final subId = entry['subjectId'] as String;
                    if (!groupedTimetable.containsKey(subId)) {
                      groupedTimetable[subId] = {
                        'subjectId': subId,
                        'subjectName': entry['subjectName'],
                        'teacherName': entry['teacherName'],
                        'classes': <String>[],
                      };
                    }
                    final cid = entry['classId'] as String;
                    final classDoc = classes.firstWhere((c) => c['id'] == cid, orElse: () => {});
                    final className = classDoc['name'] as String? ?? cid;
                    groupedTimetable[subId]!['classes'].add(className);
                  }
                }
                final groupedList = groupedTimetable.values.toList();

                return ListView(
                  children: [
                    self._buildMobileHeaderBanner(
                      stepNumber: 'Langkah 3',
                      title: 'Jadwal Mapel',
                      subtitle: 'Hubungkan mata pelajaran dengan kelas pengikut.',
                      icon: Icons.menu_book_rounded,
                      iconColor: const Color(0xFF10B981),
                    ),

                    // Jadwal Terdaftar (Top List)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.list_alt_rounded, size: 16, color: Color(0xFF10B981)),
                                  SizedBox(width: 6),
                                  Text('Jadwal Terdaftar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
                                child: Text('${groupedList.length} Mapel', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (groupedList.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: Text('Belum ada mapel diatur', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11))),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: groupedList.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, idx) {
                                final g = groupedList[idx];
                                final isAllClasses = classes.isNotEmpty && (g['classes'] as List).length == classes.length;
                                final classesText = isAllClasses ? 'Semua Kelas' : (g['classes'] as List<String>).join(', ');
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(g['subjectName'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                            Text('Guru: ${g['teacherName']}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                            Text('Kelas: $classesText', style: const TextStyle(fontSize: 10, color: Color(0xFF4F46E5), fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          self.updateState(() {
                                            self._timetable.removeWhere((t) => t['subjectId'] == g['subjectId']);
                                          });
                                          self._autoSaveDraft();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Tambah Jadwal Baru (Form)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF10B981)),
                              SizedBox(width: 6),
                              Text('Tambah Jadwal Mapel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                            ],
                          ),
                          const SizedBox(height: 10),

                          const Text('Pilih Mata Pelajaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            value: self._selectedSubjectId,
                            decoration: InputDecoration(
                              hintText: 'Pilih mapel',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            ),
                            style: const TextStyle(fontSize: 12, color: Colors.black),
                            items: subjects.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String, style: const TextStyle(fontSize: 12)))).toList(),
                            onChanged: (val) {
                              self.updateState(() {
                                self._selectedSubjectId = val;
                                self._selectedTeacherIds.clear();
                              });
                            },
                          ),
                          const SizedBox(height: 8),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Pilih Kelas (${self._selectedClassIds.length}/${classes.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => self._showMultiSelectClassesBottomSheet(context, classes),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      self._selectedClassIds.isEmpty
                                          ? 'Pilih kelas'
                                          : classes
                                              .where((c) => self._selectedClassIds.contains(c['id']))
                                              .map((c) => c['name'] as String? ?? c['id'] as String)
                                              .join(', '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: self._selectedClassIds.isEmpty ? Colors.grey : Colors.black,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          const Text('Pilih Guru Soal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final selectedSubjectName = self._selectedSubjectId != null
                                  ? subjects.firstWhere((s) => s['id'] == self._selectedSubjectId, orElse: () => {})['name'] as String?
                                  : null;

                              final selectedTeachers = self._selectedTeacherIds
                                  .map((id) => teachers.firstWhere((t) => t.id == id, orElse: () => Teacher(id: '', displayName: '', gender: '', nip: '', subjects: [], schoolId: '', disabled: false, archived: false, createdAt: DateTime.now(), updatedAt: DateTime.now())))
                                  .where((t) => t.id.isNotEmpty)
                                  .toList();
                              final teacherName = selectedTeachers.isNotEmpty 
                                  ? selectedTeachers.map((t) => t.displayName).join(', ') 
                                  : null;

                              return InkWell(
                                onTap: self._selectedSubjectId == null
                                    ? () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Pilih mata pelajaran terlebih dahulu!'), backgroundColor: Colors.red),
                                        );
                                      }
                                    : () => self._showSelectTeacherModal(context, teachers, selectedSubjectName),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: self._selectedSubjectId == null ? const Color(0xFFF1F5F9) : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          self._selectedSubjectId == null
                                              ? 'Pilih mapel terlebih dahulu'
                                              : (teacherName ?? 'Pilih guru pembuat soal'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: self._selectedSubjectId == null || teacherName == null ? Colors.grey : Colors.black,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(Icons.arrow_drop_down, color: self._selectedSubjectId == null ? Colors.grey.shade400 : Colors.grey, size: 20),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                if (self._selectedSubjectId == null || self._selectedClassIds.isEmpty || self._selectedTeacherIds.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Lengkapi mapel, kelas, dan guru pembuat soal!'), backgroundColor: Colors.red),
                                  );
                                  return;
                                }
                                final subName = subjects.firstWhere((s) => s['id'] == self._selectedSubjectId)['name'] as String;
                                final teachName = self._selectedTeacherIds
                                    .map((id) => teachers.firstWhere((t) => t.id == id).displayName)
                                    .join(', ');
                                self.updateState(() {
                                  for (final cid in self._selectedClassIds) {
                                    final already = self._timetable.any((t) => t['subjectId'] == self._selectedSubjectId && t['classId'] == cid);
                                    if (!already) {
                                      self._timetable.add({
                                        'subjectId': self._selectedSubjectId,
                                        'subjectName': subName,
                                        'classId': cid,
                                        'teacherId': List<String>.from(self._selectedTeacherIds),
                                        'teacherName': teachName,
                                        'sessionId': null,
                                        'sessionName': null,
                                      });
                                    }
                                  }
                                  self._selectedSubjectId = null;
                                  self._selectedClassIds.clear();
                                  self._selectedTeacherIds.clear();
                                });
                                self._autoSaveDraft();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              child: const Text('Simpan Jadwal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Step 4: Ruangan Ujian (Mobile) ─────────────────────────────────────────
  Widget _buildMobileStep4() {
    final self = this;
    void showRoomDialog({Map<String, dynamic>? existing, int? index}) {
      final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
      final capCtrl = TextEditingController(text: existing != null ? '${(existing['capacity'] as num?)?.toInt() ?? ''}' : '');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.meeting_room_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                existing == null ? 'Tambah Ruangan' : 'Edit Ruangan',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nama Ruangan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Contoh: Ruang A1',
                  prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFD97706), size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.5)),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Kapasitas Kursi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: capCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Contoh: 30',
                  prefixIcon: const Icon(Icons.event_seat_rounded, color: Color(0xFFD97706), size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.5)),
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Batal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      final cap = int.tryParse(capCtrl.text.trim());
                      if (name.isEmpty || cap == null || cap <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Isi nama & kapasitas dengan benar!'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      self.updateState(() {
                        if (existing == null) {
                          self._rooms.add({'id': 'local_${DateTime.now().millisecondsSinceEpoch}', 'name': name, 'capacity': cap});
                        } else {
                          self._rooms[index!] = {...existing, 'name': name, 'capacity': cap};
                        }
                      });
                      Navigator.pop(ctx);
                      self._autoSaveDraft();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Simpan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final total = self._rooms.fold<int>(0, (sum, r) => sum + ((r['capacity'] as num?)?.toInt() ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        self._buildMobileHeaderBanner(
          stepNumber: 'Langkah 4',
          title: 'Ruangan Ujian',
          subtitle: 'Kelola ruangan dan kapasitas kursi.',
          icon: Icons.meeting_room_rounded,
          iconColor: const Color(0xFFD97706),
          action: ElevatedButton(
            onPressed: () => showRoomDialog(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 12),
                SizedBox(width: 2),
                Text('Tambah', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),

        if (self._rooms.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFDE68A))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('${self._rooms.length} Ruang', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E), fontSize: 11.5)),
                Text('$total Kursi', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E), fontSize: 11.5)),
              ],
            ),
          ),

        Expanded(
          child: self._rooms.isEmpty
              ? const Center(
                  child: Text('Belum ada ruangan ditambahkan.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                )
              : ListView.separated(
                  itemCount: self._rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, idx) {
                    final r = self._rooms[idx];
                    final cap = (r['capacity'] as num?)?.toInt() ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Row(
                        children: [
                          const Icon(Icons.meeting_room_rounded, color: Color(0xFFD97706), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                Text('$cap Kursi', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Color(0xFFD97706), size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => showRoomDialog(existing: r, index: idx),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  self.updateState(() => self._rooms.removeAt(idx));
                                  self._autoSaveDraft();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Step 5: Alokasi Murid ke Ruangan (Mobile) ──────────────────────────────
  Widget _buildMobileStep5() {
    final self = this;
    const classColors = [
      Color(0xFF4F46E5), Color(0xFF10B981), Color(0xFFF59E0B),
      Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF06B6D4),
      Color(0xFFEC4899), Color(0xFF14B8A6),
    ];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(self.widget.schoolId)
          .collection('classes')
          .orderBy('name')
          .snapshots(),
      builder: (context, classSnap) {
        final allClasses = classSnap.data?.docs
                .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
                .toList() ??
            [];
        final configuredClassIds = self._timetable.map((t) => t['classId'] as String).toSet();
        final classes = allClasses.where((c) => configuredClassIds.contains(c['id'] as String)).toList();

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                labelColor: Color(0xFF4F46E5),
                unselectedLabelColor: Color(0xFF64748B),
                indicatorColor: Color(0xFF4F46E5),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(icon: Icon(Icons.meeting_room_outlined, size: 16), text: 'Ruangan'),
                  Tab(icon: Icon(Icons.grid_on_rounded, size: 16), text: 'Denah'),
                  Tab(icon: Icon(Icons.groups_rounded, size: 16), text: 'Kelas'),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    self._buildMobileStep5Tab1(classes),
                    self._buildMobileStep5Tab2(classColors),
                    self._buildMobileStep5Tab3(classes),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileStep5Tab1(List<Map<String, dynamic>> classes) {
    final self = this;
    if (self._rooms.isEmpty) {
      return const Center(
        child: Text('Belum ada ruangan.\nTambah di Langkah 4.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      );
    }
    return ListView.separated(
      itemCount: self._rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, idx) {
        final r = self._rooms[idx];
        final rid = r['id'] as String;
        final isSelected = self._selectedRoomId == rid;
        final asgn = self._roomAssignments[rid] ?? [];
        final total = asgn.fold<int>(0, (s, a) => s + ((a['count'] as num?)?.toInt() ?? 0));
        final cap = (r['capacity'] as num?)?.toInt() ?? 0;
        return GestureDetector(
          onTap: () => self.updateState(() => self._selectedRoomId = rid),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.meeting_room_outlined,
                    color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                    size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['name'] as String? ?? '-',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF0F172A))),
                      Text('$total / $cap kursi terisi', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: const Color(0xFFE2E8F0),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: cap > 0 ? (total / cap).clamp(0.0, 1.0) : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: total > cap ? Colors.red : const Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileStep5Tab2(List<Color> classColors) {
    final self = this;
    final selectedRoom = self._rooms.isEmpty
        ? null
        : self._rooms.firstWhere(
            (r) => r['id'] == self._selectedRoomId,
            orElse: () => {},
          );
    if (selectedRoom == null || selectedRoom.isEmpty) {
      return const Center(
        child: Text('Silakan pilih ruangan di Tab "Ruangan" terlebih dahulu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      );
    }
    final roomCapacity = (selectedRoom['capacity'] as num?)?.toInt() ?? 0;
    final assignments = self._selectedRoomId != null ? (self._roomAssignments[self._selectedRoomId!] ?? []) : <Map<String, dynamic>>[];
    final totalAssigned = assignments.fold<int>(0, (s, a) => s + ((a['count'] as num?)?.toInt() ?? 0));

    final layoutState = self._addState.putIfAbsent(
      'layout_${selectedRoom['id']}',
      () => {'deskPairs': 2, 'colsPerPair': 8, 'arrange': 'normal'},
    );
    layoutState.putIfAbsent('arrange', () => 'normal');
    final int deskPairs = layoutState['deskPairs'] as int;
    final int colsPerPair = (layoutState['colsPerPair'] as int? ?? 8).clamp(4, 10);
    final String arrangeMode = layoutState['arrange'] as String;

    final int totalColumns = colsPerPair;
    final int calculatedRows = (roomCapacity / totalColumns).ceil();

    final List<Color?> classTokens = [];
    for (int i = 0; i < assignments.length; i++) {
      final cnt = (assignments[i]['count'] as num?)?.toInt() ?? 0;
      final color = classColors[i % classColors.length];
      for (int j = 0; j < cnt; j++) {
        classTokens.add(color);
      }
    }

    final seats = List<Color?>.filled(roomCapacity, null);
    final seatStudentNames = List<String?>.filled(roomCapacity, null);

    // Calculate skipCountMap across preceding rooms
    final Map<String, int> skipCountMap = {};
    for (var rMap in self.rooms) {
      final rId = (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
      final rName = (rMap['name'] ?? rMap['code'] ?? rId).toString();
      final curId = (selectedRoom['id'] ?? selectedRoom['code'] ?? selectedRoom['name'] ?? '').toString();
      final curName = (selectedRoom['name'] ?? selectedRoom['code'] ?? curId).toString();

      if (rId == curId || rName == curName) {
        break;
      }

      List rAssgn = [];
      self.roomAssignments.forEach((k, v) {
        if (rAssgn.isNotEmpty) return;
        final kStr = k.toString();
        final kClean = kStr.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        final rIdClean = rId.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        final rNameClean = rName.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');

        if (kStr == rId || kStr == rName || (kClean.isNotEmpty && (kClean == rIdClean || kClean == rNameClean))) {
          if (v is List) rAssgn = v;
        }
      });

      for (var a in rAssgn) {
        if (a is Map) {
          final cName = (a['className'] ?? a['classId'] ?? '').toString().trim();
          final cnt = (a['count'] as num?)?.toInt() ?? 0;
          if (cName.isNotEmpty && cnt > 0) {
            skipCountMap[cName] = (skipCountMap[cName] ?? 0) + cnt;
            final cleanC = cName.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
            if (cleanC.isNotEmpty && cleanC != cName) {
              skipCountMap[cleanC] = (skipCountMap[cleanC] ?? 0) + cnt;
            }
          }
        }
      }
    }

    // Build real student item queues for each class in this room
    final List<List<Map<String, dynamic>>> classQueues = [];
    final List<Map<String, dynamic>> allTokenItems = [];

    for (int i = 0; i < assignments.length; i++) {
      final cnt = (assignments[i]['count'] as num?)?.toInt() ?? 0;
      final cName = (assignments[i]['className'] ?? assignments[i]['classId'] ?? 'Kelas').toString().trim();
      final cleanC = cName.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
      final color = classColors[i % classColors.length];

      final realList = self.classRealStudentsMap[cName] ?? self.classRealStudentsMap[cleanC] ?? [];
      final skipIdx = skipCountMap[cName] ?? skipCountMap[cleanC] ?? 0;

      final classList = <Map<String, dynamic>>[];
      for (int k = 0; k < cnt; k++) {
        final targetIdx = skipIdx + k;
        String sName = '$cName #${k + 1}';
        if (targetIdx < realList.length) {
          final r = realList[targetIdx];
          sName = (r['displayName'] ?? r['studentName'] ?? sName).toString();
        }
        final item = {'color': color, 'label': sName};
        classList.add(item);
        allTokenItems.add(item);
      }
      classQueues.add(classList);
    }

    if (arrangeMode == 'acak') {
      final int seed = layoutState['seed'] as int? ?? (((selectedRoom['id'] as String? ?? '').hashCode.abs() + 42) % 100000);
      final shuffled = List<Map<String, dynamic>>.from(allTokenItems)..shuffle(Random(seed));
      for (int i = 0; i < shuffled.length && i < roomCapacity; i++) {
        seats[i] = shuffled[i]['color'] as Color?;
        seatStudentNames[i] = shuffled[i]['label'] as String?;
      }
    } else if (arrangeMode == 'zigzag') {
      int qi = 0;
      final List<int> qIdx = List.filled(classQueues.length, 0);
      for (int seat = 0; seat < roomCapacity; seat++) {
        int tried = 0;
        while (tried < classQueues.length) {
          final q = qi % classQueues.length;
          if (qIdx[q] < classQueues[q].length) {
            final item = classQueues[q][qIdx[q]++];
            seats[seat] = item['color'] as Color?;
            seatStudentNames[seat] = item['label'] as String?;
            qi = q + 1;
            break;
          }
          qi++;
          tried++;
        }
        if (tried == classQueues.length) break;
      }
    } else {
      int seatIdx = 0;
      for (int q = 0; q < classQueues.length && seatIdx < roomCapacity; q++) {
        for (int k = 0; k < classQueues[q].length && seatIdx < roomCapacity; k++) {
          final item = classQueues[q][k];
          seats[seatIdx] = item['color'] as Color?;
          seatStudentNames[seatIdx] = item['label'] as String?;
          seatIdx++;
        }
      }
    }

    return StatefulBuilder(
      builder: (context, setLocal) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: deskPairs,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pasang Meja',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(3, (i) => i + 1).map((val) {
                      return DropdownMenuItem(value: val, child: Text('$val Pasang', style: const TextStyle(fontSize: 11)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setLocal(() {
                          layoutState['deskPairs'] = val;
                        });
                        self.updateState(() {});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: colsPerPair,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Total Kolom',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(7, (i) => i + 4).map((val) {
                      return DropdownMenuItem(value: val, child: Text('$val Kolom', style: const TextStyle(fontSize: 11)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setLocal(() {
                          layoutState['colsPerPair'] = val;
                        });
                        self.updateState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                self._arrangeMobileToggleBtn(
                  label: 'Normal',
                  icon: Icons.format_list_numbered_rounded,
                  active: arrangeMode == 'normal',
                  onTap: () {
                    setLocal(() => layoutState['arrange'] = 'normal');
                    self.updateState(() {});
                  },
                ),
                const SizedBox(width: 4),
                self._arrangeMobileToggleBtn(
                  label: 'Zigzag',
                  icon: Icons.swap_horiz_rounded,
                  active: arrangeMode == 'zigzag',
                  onTap: () {
                    setLocal(() => layoutState['arrange'] = 'zigzag');
                    self.updateState(() {});
                  },
                ),
                const SizedBox(width: 4),
                self._arrangeMobileToggleBtn(
                  label: 'Acak',
                  icon: Icons.shuffle_rounded,
                  active: arrangeMode == 'acak',
                  onTap: () {
                    setLocal(() {
                      layoutState['arrange'] = 'acak';
                      layoutState['seed'] = DateTime.now().millisecondsSinceEpoch;
                    });
                    self.updateState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double availableWidth = constraints.maxWidth;
                    final int totalGaps = (totalColumns / deskPairs).floor();
                    final double totalGapWidth = totalGaps * 8.0;
                    final double remainingWidth = availableWidth - totalGapWidth - 6.0;
                    final double seatWidth = (remainingWidth / totalColumns) - 2.0;
                    final double dynamicSeatSize = seatWidth.clamp(14.0, 9999.0);

                    return SingleChildScrollView(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: calculatedRows,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, rowIdx) {
                          final rowChildren = <Widget>[];
                          for (int colIdx = 0; colIdx < totalColumns; colIdx++) {
                            if (colIdx > 0 && colIdx % deskPairs == 0) {
                              rowChildren.add(const SizedBox(width: 8));
                            }

                            final seatIndex = (rowIdx * totalColumns) + colIdx;
                            if (seatIndex >= roomCapacity) {
                              rowChildren.add(
                                SizedBox(width: dynamicSeatSize, height: dynamicSeatSize),
                              );
                              continue;
                            }

                            final seatColor = seats[seatIndex];
                            final studentName = seatStudentNames[seatIndex];

                            rowChildren.add(
                              Tooltip(
                                message: seatColor != null
                                    ? 'Kursi #${seatIndex + 1}\n$studentName'
                                    : 'Kursi #${seatIndex + 1} (Kosong)',
                                child: Container(
                                  width: dynamicSeatSize,
                                  height: dynamicSeatSize,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: seatColor != null ? seatColor.withValues(alpha: 0.90) : Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: seatColor != null ? seatColor : const Color(0xFFCBD5E1),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${seatIndex + 1}',
                                        style: TextStyle(
                                          fontSize: (dynamicSeatSize * 0.32).clamp(6.5, 14.0),
                                          fontWeight: FontWeight.w900,
                                          color: seatColor != null ? Colors.white : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                      if (studentName != null && studentName.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 1),
                                          child: Text(
                                            studentName,
                                            style: TextStyle(
                                              fontSize: (dynamicSeatSize * 0.16).clamp(5.5, 9.5),
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white.withValues(alpha: 0.98),
                                              height: 1.05,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: rowChildren,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            if (assignments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (int i = 0; i < assignments.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: classColors[i % classColors.length].withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${assignments[i]['className'] ?? '-'} (${(assignments[i]['count'] as num?)?.toInt() ?? 0})',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('Kosong', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMobileStep5Tab3(List<Map<String, dynamic>> classes) {
    final self = this;
    if (self._selectedRoomId == null) {
      return const Center(
        child: Text('Silakan pilih ruangan di Tab "Ruangan" terlebih dahulu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      );
    }

    final selectedRoom = self._rooms.firstWhere((r) => r['id'] == self._selectedRoomId);

    final sortedClasses = List<Map<String, dynamic>>.from(classes);
    sortedClasses.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

    final int roomCapacity = (selectedRoom['capacity'] as num?)?.toInt() ?? 0;
    final roomAssignmentsList = self._selectedRoomId != null ? (self._roomAssignments[self._selectedRoomId!] ?? []) : <Map<String, dynamic>>[];
    final int currentTotalInRoom = roomAssignmentsList.fold<int>(0, (s, a) => s + ((a['count'] as num?)?.toInt() ?? 0));
    final int roomAvailableSeats = (roomCapacity - currentTotalInRoom).clamp(0, roomCapacity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: currentTotalInRoom >= roomCapacity ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: currentTotalInRoom >= roomCapacity ? const Color(0xFFFCA5A5) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Alokasikan Kelas ke "${selectedRoom['name']}"',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: currentTotalInRoom >= roomCapacity ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$currentTotalInRoom / $roomCapacity Kursi',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: sortedClasses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, ci) {
              final cls = sortedClasses[ci];
              final cid = cls['id'] as String;
              final cname = cls['name'] as String? ?? '-';
              final totalStudents = self._studentCountForClass(cls);
              final existingIdx = self._roomAssignments[self._selectedRoomId]?.indexWhere((a) => a['classId'] == cid) ?? -1;
              final existing = existingIdx >= 0 ? self._roomAssignments[self._selectedRoomId]![existingIdx] : null;

              int allocElsewhere = 0;
              self._roomAssignments.forEach((roomId, list) {
                if (roomId != self._selectedRoomId) {
                  final found = list.firstWhere((a) => a['classId'] == cid, orElse: () => {});
                  if (found.isNotEmpty) allocElsewhere += (found['count'] as num).toInt();
                }
              });

              final int currentAssigned = existing != null ? (existing['count'] as num).toInt() : 0;
              final int maxAvailable = (totalStudents - allocElsewhere).clamp(0, totalStudents);
              final int remaining = (maxAvailable - currentAssigned).clamp(0, maxAvailable);
              final bool isExhaustedElsewhere = maxAvailable == 0 && currentAssigned == 0;

              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isExhaustedElsewhere ? const Color(0xFFF1F5F9) : (remaining == 0 && maxAvailable > 0 ? const Color(0xFFF0FDF4) : Colors.white),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isExhaustedElsewhere ? const Color(0xFFE2E8F0) : (remaining == 0 && maxAvailable > 0 ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(cname, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isExhaustedElsewhere ? const Color(0xFF94A3B8) : const Color(0xFF1E293B))),
                        Text('Sisa: $remaining / $totalStudents', style: TextStyle(fontSize: 10, color: isExhaustedElsewhere ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.remove_circle_outline, color: currentAssigned > 0 ? const Color(0xFFEF4444) : const Color(0xFFCBD5E1), size: 24),
                              onPressed: currentAssigned > 0
                                  ? () {
                                      self.updateState(() {
                                        final list = self._roomAssignments[self._selectedRoomId!]!;
                                        final idx = list.indexWhere((a) => a['classId'] == cid);
                                        if (idx >= 0) {
                                          final currentCount = (list[idx]['count'] as num).toInt();
                                          if (currentCount > 1) {
                                            list[idx]['count'] = currentCount - 1;
                                          } else {
                                            list.removeAt(idx);
                                            if (list.isEmpty) self._roomAssignments.remove(self._selectedRoomId!);
                                          }
                                        }
                                      });
                                      self._autoSaveDraft();
                                    }
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: currentAssigned > 0 ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: currentAssigned > 0 ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                '$currentAssigned Murid',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: currentAssigned > 0 ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.add_circle_outline, color: remaining > 0 ? const Color(0xFF10B981) : const Color(0xFFCBD5E1), size: 24),
                              onPressed: remaining > 0
                                  ? () {
                                      if (roomAvailableSeats <= 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Ruangan "${selectedRoom['name']}" sudah penuh ($currentTotalInRoom/$roomCapacity kursi terisi)!'),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                        return;
                                      }
                                      self.updateState(() {
                                        self._roomAssignments.putIfAbsent(self._selectedRoomId!, () => []);
                                        final list = self._roomAssignments[self._selectedRoomId!]!;
                                        final idx = list.indexWhere((a) => a['classId'] == cid);
                                        if (idx >= 0) {
                                          final currentCount = (list[idx]['count'] as num).toInt();
                                          list[idx]['count'] = currentCount + 1;
                                        } else {
                                          list.add({
                                            'classId': cid,
                                            'className': cname,
                                            'count': 1,
                                            'isAll': false,
                                          });
                                        }
                                      });
                                      self._autoSaveDraft();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (currentAssigned > 0) ...[
                              ElevatedButton.icon(
                                icon: const Icon(Icons.remove_done_rounded, size: 13),
                                label: const Text('Lepas Semua', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFEF2F2),
                                  foregroundColor: const Color(0xFFDC2626),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  minimumSize: const Size(0, 0),
                                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () {
                                  self.updateState(() {
                                    final list = self._roomAssignments[self._selectedRoomId!];
                                    if (list != null) {
                                      list.removeWhere((a) => a['classId'] == cid);
                                      if (list.isEmpty) self._roomAssignments.remove(self._selectedRoomId!);
                                    }
                                  });
                                  self._autoSaveDraft();
                                },
                              ),
                            ],
                            if (remaining > 0) ...[
                              if (currentAssigned > 0) const SizedBox(width: 6),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.done_all_rounded, size: 13),
                                label: const Text('Pilih Semua', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  minimumSize: const Size(0, 0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () {
                                  if (roomAvailableSeats <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Ruangan "${selectedRoom['name']}" sudah penuh ($currentTotalInRoom/$roomCapacity kursi terisi)!'),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                    return;
                                  }

                                  final int addCount = remaining <= roomAvailableSeats ? remaining : roomAvailableSeats;
                                  if (remaining > roomAvailableSeats) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Hanya $addCount murid dapat dimasukkan ke "${selectedRoom['name']}" karena sisa $roomAvailableSeats kursi.'),
                                        backgroundColor: Colors.orange,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }

                                  self.updateState(() {
                                    self._roomAssignments.putIfAbsent(self._selectedRoomId!, () => []);
                                    final list = self._roomAssignments[self._selectedRoomId!]!;
                                    final idx = list.indexWhere((a) => a['classId'] == cid);
                                    if (idx >= 0) {
                                      final currentCount = (list[idx]['count'] as num).toInt();
                                      list[idx]['count'] = currentCount + addCount;
                                      list[idx]['isAll'] = addCount == remaining;
                                    } else {
                                      list.add({
                                        'classId': cid,
                                        'className': cname,
                                        'count': addCount,
                                        'isAll': addCount == remaining,
                                      });
                                    }
                                  });
                                  self._autoSaveDraft();
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Step 6: Jadwal Ruangan (Mobile) ────────────────────────────────────────
  Widget _buildMobileStep6() {
    final self = this;
    final days = self._examDays();
    final totalSubjectsCount = self._timetable.length;
    final scheduledSubjectsCount = self._timetable.where((t) => t['sessionId'] != null).length;
    final unscheduledSubjectsCount = totalSubjectsCount - scheduledSubjectsCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        self._buildMobileHeaderBanner(
          stepNumber: 'Langkah 6',
          title: 'Jadwal Ruangan',
          subtitle: 'Tentukan mata pelajaran ujian untuk masing-masing kelas.',
          icon: Icons.calendar_month_rounded,
          iconColor: const Color(0xFF6366F1),
          action: ElevatedButton(
            onPressed: self._timetable.isEmpty
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        title: const Text('Generate Otomatis?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        content: const Text('Jadwal kelas akan dibuat otomatis. Jadwal lama akan ditimpa.', style: TextStyle(fontSize: 12)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(fontSize: 12))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                            onPressed: () {
                              Navigator.pop(ctx);
                              self._autoGenerateSchedule();
                            },
                            child: const Text('Generate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 36),
              elevation: 2,
              shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 15),
                const SizedBox(width: 6),
                const Text('Generate Otomatis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.2)),
              ],
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(
            children: [
              Icon(
                unscheduledSubjectsCount == 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: unscheduledSubjectsCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unscheduledSubjectsCount == 0
                      ? 'Semua mapel kelas sudah terjadwal!'
                      : 'Terjadwal: $scheduledSubjectsCount/$totalSubjectsCount ($unscheduledSubjectsCount sisa).',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: unscheduledSubjectsCount == 0 ? const Color(0xFF047857) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Expanded(
          child: days.isEmpty
              ? const Center(child: Text('Belum ada tanggal pelaksanaan.', style: TextStyle(fontSize: 11)))
              : self._sessions.isEmpty
                  ? const Center(child: Text('Belum ada sesi ditambahkan.', style: TextStyle(fontSize: 11)))
                  : self._rooms.isEmpty
                      ? const Center(child: Text('Belum ada ruangan ditambahkan.', style: TextStyle(fontSize: 11)))
                      : Builder(
                          builder: (context) {
                            if (self._selectedStep6DayIdx >= days.length) {
                              self._selectedStep6DayIdx = 0;
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 48,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: days.length,
                                    itemBuilder: (ctx, idx) {
                                      final day = days[idx];
                                      final isSelected = idx == self._selectedStep6DayIdx;
                                      final dayLabel = ExamPdfGenerator.formatIndonesianDate(day);
                                      final parts = dayLabel.split(',');
                                      final dayName = parts[0].trim();
                                      final dateStr = parts.length > 1 ? parts[1].replaceAll(' 2026', '').trim() : dayLabel;

                                      return GestureDetector(
                                        onTap: () => self.updateState(() => self._selectedStep6DayIdx = idx),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          margin: const EdgeInsets.only(right: 6, bottom: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'Hari ${idx + 1}',
                                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : const Color(0xFF64748B)),
                                              ),
                                              Text(
                                                '$dayName, $dateStr',
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF1E293B)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: self._rooms.map((room) {
                                        final rid = room['id'] as String;
                                        final rname = room['name'] as String? ?? room['code'] as String;
                                        final roomClasses = self._roomAssignments[rid] ?? [];

                                        return Card(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFE2E8F0))),
                                          elevation: 0,
                                          child: Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              leading: const Icon(Icons.meeting_room_rounded, size: 18, color: Color(0xFF6366F1)),
                                              title: Text('Ruangan: $rname', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                              subtitle: Text('(${roomClasses.length} kelas)', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                              childrenPadding: const EdgeInsets.all(8),
                                              children: [
                                                if (roomClasses.isEmpty)
                                                  const Padding(
                                                    padding: EdgeInsets.symmetric(vertical: 8),
                                                    child: Text('Belum ada kelas dialokasikan di Langkah 5.', style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                                                  )
                                                else
                                                  ...List.generate(self._sessions.length, (sIdx) {
                                                    final session = self._sessions[sIdx];
                                                    final sessionKey = 'day_${self._selectedStep6DayIdx}_session_$sIdx';

                                                    return Container(
                                                      margin: const EdgeInsets.only(bottom: 8),
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFF1F5F9))),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text('${session['name']} (${session['startTime']} - ${session['endTime']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155))),
                                                          const Divider(height: 10, color: Color(0xFFE2E8F0)),
                                                          ...roomClasses.map((cls) {
                                                            final cid = cls['classId'] as String;
                                                            final cname = cls['className'] as String;
                                                            final classSubjects = self._timetable.where((t) => t['classId'] == cid).toList();

                                                            final Map<String, String> uniqueClassSubs = {};
                                                            for (var t in classSubjects) {
                                                              final sid = t['subjectId'] as String? ?? '';
                                                              final sname = t['subjectName'] as String? ?? sid;
                                                              if (sid.isNotEmpty) uniqueClassSubs[sid] = sname;
                                                            }

                                                            final currentScheduledEntry = self._timetable.firstWhere(
                                                              (t) => t['classId'] == cid && t['sessionId'] == sessionKey,
                                                              orElse: () => {},
                                                            );
                                                            final currentSubjectId = currentScheduledEntry.isNotEmpty ? currentScheduledEntry['subjectId'] as String? : null;

                                                            return Padding(
                                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(cname, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                                                  const SizedBox(height: 2),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                                    width: double.infinity,
                                                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
                                                                    child: DropdownButtonHideUnderline(
                                                                      child: DropdownButton<String?>(
                                                                        value: currentSubjectId,
                                                                        isDense: true,
                                                                        isExpanded: true,
                                                                        hint: const Text('Belum Dijadwalkan', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                                                        items: [
                                                                          const DropdownMenuItem<String?>(
                                                                            value: null,
                                                                            child: Text('Belum Dijadwalkan', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                                                                          ),
                                                                          ...uniqueClassSubs.entries.map((e) {
                                                                            return DropdownMenuItem<String?>(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 11)));
                                                                          }),
                                                                        ],
                                                                        onChanged: (val) {
                                                                          self.updateState(() {
                                                                            for (var t in self._timetable) {
                                                                              if (t['classId'] == cid && t['sessionId'] == sessionKey) {
                                                                                t['sessionId'] = null;
                                                                                t['sessionName'] = null;
                                                                              }
                                                                            }
                                                                            if (val != null) {
                                                                              final target = self._timetable.firstWhere((t) => t['classId'] == cid && t['subjectId'] == val);
                                                                              target['sessionId'] = sessionKey;
                                                                              target['sessionName'] = session['name'];
                                                                            }
                                                                          });
                                                                          self._autoSaveDraft();
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }),
                                                        ],
                                                      ),
                                                    );
                                                  }),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
        ),
      ],
    );
  }

  // ── Step 7: Penugasan Pengawas Ruang (Mobile) ──────────────────────────────
  Widget _buildMobileStep7() {
    final self = this;
    final days = self._examDays();

    return StreamBuilder<List<Teacher>>(
      stream: _adminUserService.streamTeachers(self.widget.schoolId),
      builder: (context, teachersSnap) {
        final teachers = {for (var t in (teachersSnap.data ?? <Teacher>[])) t.id: t}.values.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            self._buildMobileHeaderBanner(
              stepNumber: 'Langkah 7',
              title: 'Penugasan Pengawas',
              subtitle: 'Atur guru pengawas untuk setiap ruangan di setiap sesi.',
              icon: Icons.supervisor_account_rounded,
              iconColor: const Color(0xFF8B5CF6),
              action: ElevatedButton(
                onPressed: teachers.isEmpty || self._rooms.isEmpty || days.isEmpty
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            title: const Text('Generate Otomatis?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            content: const Text('Guru pengawas akan ditugaskan secara otomatis. Tugas lama akan ditimpa.', style: TextStyle(fontSize: 12)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(fontSize: 12))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  self._autoGenerateProctors(teachers);
                                },
                                child: const Text('Generate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: const Size(0, 36),
                  elevation: 2,
                  shadowColor: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shuffle_rounded, size: 15),
                    const SizedBox(width: 6),
                    const Text('Generate Otomatis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.2)),
                  ],
                ),
              ),
            ),

            Expanded(
              child: days.isEmpty
                  ? const Center(child: Text('Belum ada tanggal pelaksanaan.', style: TextStyle(fontSize: 11)))
                  : self._sessions.isEmpty
                      ? const Center(child: Text('Belum ada sesi ditambahkan.', style: TextStyle(fontSize: 11)))
                      : self._rooms.isEmpty
                          ? const Center(child: Text('Belum ada ruangan ditambahkan.', style: TextStyle(fontSize: 11)))
                          : Builder(
                              builder: (context) {
                                if (self._selectedStep7DayIdx >= days.length) {
                                  self._selectedStep7DayIdx = 0;
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      height: 48,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: days.length,
                                        itemBuilder: (ctx, idx) {
                                          final day = days[idx];
                                          final isSelected = idx == self._selectedStep7DayIdx;
                                          final dayLabel = ExamPdfGenerator.formatIndonesianDate(day);
                                          final parts = dayLabel.split(',');
                                          final dayName = parts[0].trim();
                                          final dateStr = parts.length > 1 ? parts[1].replaceAll(' 2026', '').trim() : dayLabel;

                                          return GestureDetector(
                                            onTap: () => self.updateState(() => self._selectedStep7DayIdx = idx),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              margin: const EdgeInsets.only(right: 6, bottom: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFF8FAFC),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFE2E8F0)),
                                              ),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'Hari ${idx + 1}',
                                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : const Color(0xFF64748B)),
                                                  ),
                                                  Text(
                                                    '$dayName, $dateStr',
                                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF1E293B)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          children: self._rooms.map((room) {
                                            final rid = room['id'] as String;
                                            final rname = room['name'] as String? ?? room['code'] as String;

                                            return Card(
                                              margin: const EdgeInsets.only(bottom: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFE2E8F0))),
                                              elevation: 0,
                                              child: Theme(
                                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                                child: ExpansionTile(
                                                  leading: const Icon(Icons.meeting_room_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                                  title: Text('Ruangan: $rname', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                                  childrenPadding: const EdgeInsets.all(8),
                                                  children: [
                                                    Padding(
                                                      padding: const EdgeInsets.only(left: 6),
                                                      child: Column(
                                                        children: List.generate(self._sessions.length, (sIdx) {
                                                          final session = self._sessions[sIdx];
                                                          final proctorKey = 'day_${self._selectedStep7DayIdx}_session_${sIdx}_room_$rid';
                                                          final currentTeacherId = self._proctorGrid[proctorKey];
                                                          final teacherExists = currentTeacherId != null && teachers.any((t) => t.id == currentTeacherId);
                                                          final validTeacherId = teacherExists ? currentTeacherId : null;

                                                          return Padding(
                                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text(
                                                                  '${session['name']} (${session['startTime']} - ${session['endTime']})',
                                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                                                ),
                                                                const SizedBox(height: 2),
                                                                Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                                  width: double.infinity,
                                                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
                                                                child: DropdownButtonHideUnderline(
                                                                    child: DropdownButton<String?>(
                                                                      value: validTeacherId,
                                                                      isDense: true,
                                                                      isExpanded: true,
                                                                      hint: const Text('Belum Ditugaskan', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                                                      items: [
                                                                        const DropdownMenuItem<String?>(
                                                                          value: null,
                                                                          child: Text('Belum Ditugaskan', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                                                                        ),
                                                                        ...teachers.map((t) {
                                                                          final isUsed = self._rooms.any((otherRoom) {
                                                                            final otherRid = otherRoom['id'] as String;
                                                                            if (otherRid == rid) return false;
                                                                            final otherKey = 'day_${self._selectedStep7DayIdx}_session_${sIdx}_room_$otherRid';
                                                                            return self._proctorGrid[otherKey] == t.id;
                                                                          });
                                                                          return DropdownMenuItem<String?>(
                                                                            value: t.id,
                                                                            enabled: !isUsed,
                                                                            child: Text(
                                                                              '${t.displayName} ${isUsed ? "(Sudah bertugas)" : ""}',
                                                                              style: TextStyle(fontSize: 11, color: isUsed ? Colors.grey : Colors.black),
                                                                            ),
                                                                          );
                                                                        }),
                                                                      ],
                                                                      onChanged: (val) {
                                                                        if (val != null) {
                                                                          final conflict = self._rooms.any((otherRoom) {
                                                                            final otherRid = otherRoom['id'] as String;
                                                                            if (otherRid == rid) return false;
                                                                            final otherKey = 'day_${self._selectedStep7DayIdx}_session_${sIdx}_room_$otherRid';
                                                                            return self._proctorGrid[otherKey] == val;
                                                                          });
                                                                          if (conflict) {
                                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                                              const SnackBar(
                                                                                content: Text('Guru ini sudah bertugas di ruangan lain pada sesi yang sama!'),
                                                                                backgroundColor: Colors.red,
                                                                                duration: Duration(seconds: 2),
                                                                              ),
                                                                            );
                                                                            return;
                                                                          }
                                                                        }
                                                                        self.updateState(() {
                                                                          if (val == null) {
                                                                            self._proctorGrid.remove(proctorKey);
                                                                          } else {
                                                                            self._proctorGrid[proctorKey] = val;
                                                                          }
                                                                        });
                                                                        self._autoSaveDraft();
                                                                      },
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        }),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }

  // ── Step 8: Review & Publish (Mobile) ─────────────────────────────────────
  Widget _buildMobileStep8() {
    final self = this;
    final days = self._examDays();
    final totalSeats = self._rooms.fold<int>(0, (sum, r) => sum + ((r['capacity'] as num?)?.toInt() ?? 0));
    final uniqueClasses = self._timetable.map((t) => t['classId']).toSet().length;

    Widget infoRow(IconData icon, String label, String value, Color iconColor) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 1),
                  Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget reviewCard(String title, IconData icon, Color accentColor, List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: accentColor.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: accentColor)),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
          ],
        ),
      );
    }

    return ListView(
      children: [
        self._buildMobileHeaderBanner(
          stepNumber: 'Langkah 8',
          title: 'Finalisasi & Publikasi',
          subtitle: 'Rangkuman konfigurasi event ujian sekolah.',
          icon: Icons.verified_rounded,
          iconColor: const Color(0xFF10B981),
        ),

        reviewCard(
          'Ringkasan Informasi Ujian',
          Icons.info_outline_rounded,
          const Color(0xFF3B82F6),
          [
            infoRow(Icons.badge_outlined, 'Nama Event Ujian', self._nameController.text, const Color(0xFF3B82F6)),
            infoRow(Icons.calendar_today_rounded, 'Tahun Ajaran / Tipe', '${self._academicYearController.text}  •  ${self._examType ?? "-"}', const Color(0xFF3B82F6)),
            infoRow(Icons.date_range_rounded, 'Durasi Tanggal', days.isNotEmpty ? '${ExamPdfGenerator.formatIndonesianDate(days.first).split(',')[1].trim()} s/d ${ExamPdfGenerator.formatIndonesianDate(days.last).split(',')[1].trim()} (${days.length} hari)' : '-', const Color(0xFF3B82F6)),
            if (self._descController.text.isNotEmpty) infoRow(Icons.notes_rounded, 'Petunjuk Khusus', self._descController.text, const Color(0xFF3B82F6)),
          ],
        ),

        reviewCard(
          'Statistik Konfigurasi',
          Icons.bar_chart_rounded,
          const Color(0xFF10B981),
          [
            infoRow(Icons.access_time_rounded, 'Jumlah Sesi', '${self._sessions.length} Sesi Harian', const Color(0xFF10B981)),
            infoRow(Icons.menu_book_rounded, 'Jadwal Mapel', '${self._timetable.length} Mapel diujikan', const Color(0xFF10B981)),
            infoRow(Icons.meeting_room_rounded, 'Ruangan Dipakai', '${self._rooms.length} Ruangan', const Color(0xFF10B981)),
            infoRow(Icons.groups_rounded, 'Total Kapasitas Kursi', '$totalSeats Kursi Peserta', const Color(0xFF10B981)),
            infoRow(Icons.school_rounded, 'Jumlah Kelas Terlibat', '$uniqueClasses Kelas', const Color(0xFF10B981)),
          ],
        ),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFEF4444)),
                  SizedBox(width: 6),
                  Text('Ekspor Dokumen PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('PDF Denah Kursi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final daysList = self._examDays();
                    await ExamPdfGenerator.downloadSchedulePerClass(
                      eventName: self._nameController.text,
                      examType: self._examType,
                      startDate: self._startDate,
                      endDate: self._endDate,
                      sessions: self._sessions,
                      timetable: self._timetable,
                      rooms: self._rooms,
                      roomAssignments: self._roomAssignments,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('PDF Kartu Meja & Absen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final daysList = self._examDays();
                    final teachers = await _adminUserService.streamTeachers(self.widget.schoolId).first;
                    await ExamPdfGenerator.downloadProctorSchedule(
                      eventName: self._nameController.text,
                      examType: self._examType,
                      startDate: self._startDate,
                      endDate: self._endDate,
                      sessions: self._sessions,
                      timetable: self._timetable,
                      proctorGrid: self._proctorGrid,
                      rooms: self._rooms,
                      roomAssignments: self._roomAssignments,
                      teachers: teachers.map((t) => {'id': t.id, 'displayName': t.displayName, 'email': t.email}).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA7F3D0))),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Konfigurasi valid. Klik tombol "Simpan" di bawah untuk mempublikasikan.',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMultiSelectClassesBottomSheet(BuildContext context, List<Map<String, dynamic>> classes) {
    final self = this;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final isAllSelected = self._selectedClassIds.length == classes.length;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pilih Kelas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAllSelected ? 'Semua kelas terpilih' : '${self._selectedClassIds.length} kelas terpilih',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      TextButton.icon(
                        icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 16, color: const Color(0xFF10B981)),
                        label: Text(
                          isAllSelected ? 'Batal Semua' : 'Pilih Semua',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                        onPressed: () {
                          setLocalState(() {
                            self.updateState(() {
                              if (isAllSelected) {
                                self._selectedClassIds.clear();
                              } else {
                                self._selectedClassIds.clear();
                                self._selectedClassIds.addAll(classes.map((c) => c['id'] as String));
                              }
                            });
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: classes.length,
                      itemBuilder: (context, index) {
                        final c = classes[index];
                        final cid = c['id'] as String;
                        final isChecked = self._selectedClassIds.contains(cid);
                        return CheckboxListTile(
                          title: Text(c['name'] as String? ?? cid, style: const TextStyle(fontSize: 13)),
                          value: isChecked,
                          activeColor: const Color(0xFF10B981),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) {
                            setLocalState(() {
                              self.updateState(() {
                                if (val == true) {
                                  self._selectedClassIds.add(cid);
                                } else {
                                  self._selectedClassIds.remove(cid);
                                }
                              });
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Terapkan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSelectTeacherModal(BuildContext context, List<Teacher> teachers, String? selectedSubjectName) {
    final self = this;
    String searchQuery = '';

    final sortedTeachers = List<Teacher>.from(teachers);
    if (selectedSubjectName != null) {
      sortedTeachers.sort((a, b) {
        final aRec = a.subjects.any((sub) => sub.toLowerCase() == selectedSubjectName.toLowerCase());
        final bRec = b.subjects.any((sub) => sub.toLowerCase() == selectedSubjectName.toLowerCase());
        if (aRec && !bRec) return -1;
        if (!aRec && bRec) return 1;
        return a.displayName.compareTo(b.displayName);
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final filteredTeachers = sortedTeachers.where((t) {
              if (searchQuery.isEmpty) return true;
              return t.displayName.toLowerCase().contains(searchQuery.toLowerCase()) ||
                  t.nip.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_search_rounded, color: Color(0xFF10B981), size: 20),
                          SizedBox(width: 8),
                          Text('Pilih Guru Soal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => setLocalState(() => searchQuery = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Cari nama atau NIP guru...',
                      prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: filteredTeachers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: Text('Guru tidak ditemukan.', style: TextStyle(fontSize: 12, color: Colors.grey))),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filteredTeachers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final t = filteredTeachers[index];
                              final isSelected = self._selectedTeacherIds.contains(t.id);
                              final isRec = selectedSubjectName != null &&
                                  t.subjects.any((sub) => sub.toLowerCase() == selectedSubjectName.toLowerCase());

                              return InkWell(
                                onTap: () {
                                  setLocalState(() {
                                    if (self._selectedTeacherIds.contains(t.id)) {
                                      self._selectedTeacherIds.remove(t.id);
                                    } else {
                                      self._selectedTeacherIds.add(t.id);
                                    }
                                  });
                                  self.updateState(() {});
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFECFDF5)
                                        : isRec
                                            ? const Color(0xFFF0FDF4)
                                            : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF10B981)
                                          : isRec
                                              ? const Color(0xFFA7F3D0)
                                              : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: isSelected ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                                        child: Icon(
                                          isSelected ? Icons.check : Icons.person_outline,
                                          size: 18,
                                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    t.displayName,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: isSelected || isRec ? FontWeight.bold : FontWeight.w500,
                                                      color: isSelected ? const Color(0xFF065F46) : const Color(0xFF1E293B),
                                                    ),
                                                  ),
                                                ),
                                                if (isRec)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.star_rounded, size: 12, color: Colors.white),
                                                        SizedBox(width: 4),
                                                        Text('Rekomendasi', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (t.nip.isNotEmpty)
                                              Text('NIP: ${t.nip}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Terapkan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

