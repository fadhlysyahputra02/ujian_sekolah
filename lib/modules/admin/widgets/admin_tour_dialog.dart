import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminTourDialog extends StatefulWidget {
  final bool isAutoPrompt;

  const AdminTourDialog({
    super.key,
    this.isAutoPrompt = false,
  });

  /// Static helper to check if current school admin user has seen the tour
  static Future<bool> hasSeenTour(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localSeen = prefs.getBool('admin_has_seen_tour_$uid');
      if (localSeen == true) return true;

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data()?['hasSeenAdminTour'] == true) {
        await prefs.setBool('admin_has_seen_tour_$uid', true);
        return true;
      }
    } catch (e) {
      debugPrint('[AdminTourDialog] Error checking tour status: $e');
    }
    return false;
  }

  /// Static helper to mark tour as completed
  static Future<void> markTourCompleted(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('admin_has_seen_tour_$uid', true);

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'hasSeenAdminTour': true,
        'tourCompletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AdminTourDialog] Error marking tour completed: $e');
    }
  }

  /// Static helper to reset tour status so it pops up automatically again on next login
  static Future<void> resetTourStatus(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_has_seen_tour_$uid');

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'hasSeenAdminTour': false,
        'tourResetAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AdminTourDialog] Error resetting tour status: $e');
    }
  }

  @override
  State<AdminTourDialog> createState() => _AdminTourDialogState();
}

class _AdminTourDialogState extends State<AdminTourDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  int _currentSubStepPage = 0;

  final List<TourStepItem> _steps = const [
    TourStepItem(
      title: '1. Penambahan & Pengelolaan Mata Pelajaran',
      subtitle: 'Panduan visual penambahan dan pengaturan Mata Pelajaran (Mapel) sekolah',
      icon: Icons.menu_book_rounded,
      badgeText: 'Kurikulum & Mapel',
      gradientColors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
      subSteps: [
        TourSubStep(
          title: 'Langkah 1.1: Halaman Daftar Mapel & Tombol Tambah',
          description:
              'Buka menu "Mata Pelajaran" di navigasi sebelah kiri. Di halaman ini Anda dapat melihat seluruh daftar mata pelajaran yang telah terdaftar serta tombol "+ Tambah Mapel".',
          imagePath: 'assets/images/tour/mapel_step1.png',
          placeholderLabel: 'Screenshot 1: Halaman Data Mapel & Tombol "+ Tambah Mapel"',
          annotationHighlights: [
            'Kotak 1: Tombol "+ Tambah Mapel"',
            'Kotak 2: Tabel Daftar Mata Pelajaran & Kode Mapel',
          ],
        ),
        TourSubStep(
          title: 'Langkah 1.2: Form Input Kode & Nama Mata Pelajaran',
          description:
              'Isi Kode Mapel (misal: MTK, BIN, IPA) dan Nama Lengkap Mata Pelajaran (misal: Matematika, Bahasa Indonesia). Klik "Simpan Data" untuk mendaftarkan mapel baru.',
          imagePath: 'assets/images/tour/mapel_step2.png',
          placeholderLabel: 'Screenshot 2: Modal Form Tambah Mapel (Kode & Nama Mapel)',
          annotationHighlights: [
            'Kotak 1: Kolom Nama Mata Pelajaran',
            'Kotak 2: Kolom Kode Mapel',
            'Kotak 3: Tombol "Tambah"',
          ],
        ),
      ],
      features: [
        'Kelola seluruh mata pelajaran yang diajarkan di sekolah secara fleksibel.',
        'Atur Kode Singkatan Mapel dan Nama Resmi Mapel untuk ujian.',
        'Mata Pelajaran yang dibuat akan otomatis dapat dipilih saat penugasan guru dan pembuatan soal ujian.',
      ],
      tip: 'Tips: Tambahkan seluruh Mata Pelajaran terlebih dahulu sebelum mendaftarkan akun Guru dan penugasan mengajar.',
    ),
    TourStepItem(
      title: '2. Penambahan & Manajemen Guru',
      subtitle: 'Panduan visual penambahan data tenaga pendidik (Manual & Import Excel)',
      icon: Icons.school_rounded,
      badgeText: 'Pendidik & Staf',
      gradientColors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
      subSteps: [
        TourSubStep(
          title: 'Langkah 2.1: Tombol Tambah & Import Guru',
          description:
              'Buka menu "Manajemen Guru" di bilah navigasi kiri. Gunakan tombol "+ Tambah Guru" untuk pengisian manual atau tombol "Import Excel" untuk memasukkan data guru secara massal.',
          imagePath: 'assets/images/tour/guru_step1.png',
          placeholderLabel: 'Screenshot 1: Halaman Data Guru dengan Tombol Tambah & Import',
          annotationHighlights: [
            'Kotak 1: Tombol "+ Tambah Guru" (Input manual)',
            'Kotak 2: Tombol "Import Excel" (Input massal)',
          ],
        ),
        TourSubStep(
          title: 'Langkah 2.2: Pengisian Form Guru Manual',
          description:
              'Isi NIP, Nama Lengkap beserta Gelar, Email aktif guru, Jenis Kelamin, serta centang Mata Pelajaran yang diampu.',
          imagePath: 'assets/images/tour/guru_step2.png',
          placeholderLabel: 'Screenshot 2: Modal Form Tambah Guru (Form Fields & Mapel)',
          annotationHighlights: [
            'Kotak 1: Kolom NIP & Nama Guru.',
            'Kotak 2: Centang Pilihan Mata Pelajaran.',
            'Kotak 3: Tombol "Tambah Guru".',
          ],
        ),
        TourSubStep(
          title: 'Langkah 2.3: Import Massal Guru via Excel',
          description:
              'Unduh terlebih dahulu template format Excel yang disediakan, isi data sesuai kolom, lalu upload kembali file Excel ke sistem.',
          imagePath: 'assets/images/tour/guru_step3.png',
          placeholderLabel: 'Screenshot 3: Modal Import Excel Guru',
          annotationHighlights: [
            'Panah/Kotak 1: Tombol Unduh Template',
            'Panah/Kotak 2: Pilih file & impor',
          ],
        ),
      ],
      features: [
        'Tambah guru secara manual satu per satu atau import massal via file Excel.',
        'Atur NIP, nama lengkap dan jenis kelamin.',
        'Tetapkan mata pelajaran (Mapel) yang diampu oleh setiap guru.',
        'Kredensial login (Email & Password) otomatis dibuatkan oleh sistem.',
      ],
      tip: 'Tips: Gunakan fitur Import Excel untuk memasukkan seluruh daftar guru sekaligus dengan format yang sudah disediakan.',
    ),
    TourStepItem(
      title: '3. Penambahan & Pengelolaan Murid',
      subtitle: 'Panduan visual penambahan data siswa (Manual & Import Excel)',
      icon: Icons.groups_rounded,
      badgeText: 'Peserta Didik',
      gradientColors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
      subSteps: [
        TourSubStep(
          title: 'Langkah 3.1: Tombol Tambah & Import Murid',
          description:
              'Buka menu "Manajemen Murid" di navigasi kiri. Gunakan tombol "+ Tambah Murid" untuk menginput siswa satu per satu, atau tombol "Import Excel" untuk menambahkan seluruh siswa sekaligus.',
          imagePath: 'assets/images/tour/murid_step1.png',
          placeholderLabel: 'Screenshot 1: Halaman Data Murid dengan Tombol Tambah & Import',
          annotationHighlights: [
            'Kotak 1: Tombol "+ Tambah Murid" (Input manual)',
            'Kotak 2: Tombol "Import Excel" (Input massal)',
          ],
        ),
        TourSubStep(
          title: 'Langkah 3.2: Pengisian Form Murid Manual',
          description:
              'Isi NIS, Nama Lengkap Siswa, Angkatan, Pilihan Kelas, Jenis Kelamin, Agama, serta Email (Opsional).',
          imagePath: 'assets/images/tour/murid_step2.png',
          placeholderLabel: 'Screenshot 2: Modal Form Tambah Murid (Form Fields & Kelas)',
          annotationHighlights: [
            'Kotak 1: Kolom NIS & Nama Siswa.',
            'Kotak 2: Pilihan Kelas & Angkatan.',
            'Kotak 3: Tombol "Tambah ".',
          ],
        ),
        TourSubStep(
          title: 'Langkah 3.3: Import Massal Murid via Excel',
          description:
              'Unduh berkas template Excel sampel, isi data murid sesuai kolom yang ditentukan (NISN, Nama, Kelas), lalu unggah kembali file ke sistem.',
          imagePath: 'assets/images/tour/murid_step3.png',
          placeholderLabel: 'Screenshot 3: Modal Import Excel Data Murid',
          annotationHighlights: [
            'Kotak 1: Tombol Download Template Excel Murid.',
            'Kotak 2: Tombol Pilih & Upload File Excel.',
          ],
        ),
      ],
      features: [
        'Input siswa baru atau import berantai ratusan siswa menggunakan Excel/CSV.',
        'Lengkapi NISN, nama siswa, jenis kelamin, dan penempatan kelas.',
        'Filter siswa berdasarkan Angkatan, Kelas, Jenis Kelamin, maupun Agama.',
        'Fitur pencarian cepat untuk mempermudah edit data atau reset password siswa.',
      ],
      tip: 'Tips: Pastikan Nama Kelas sudah dibuat terlebih dahulu di menu Kelas sebelum memasukkan data murid.',
    ),
    TourStepItem(
      title: '4. Setup & Pelaksanaan Event Ujian (7 Langkah Wizard)',
      subtitle: 'Panduan lengkap 7 langkah wizard pembuatan event ujian',
      icon: Icons.event_available_rounded,
      badgeText: 'Pelaksanaan Ujian',
      gradientColors: [Color(0xFFD97706), Color(0xFFF59E0B)],
      subSteps: [
        TourSubStep(
          title: 'Langkah 4.1: Info Dasar Event Ujian',
          description:
              'Klik "+ Buat Event Ujian". Isi Nama Event (misal: UTS   Ganjil 2026), tentukan rentang tanggal pelaksanaan, jenis ujian, serta deskripsi event.',
          imagePath: 'assets/images/tour/event_step1.png',
          placeholderLabel: 'Screenshot 1: Step 1 Wizard - Info Dasar Event Ujian.',
          annotationHighlights: [
            'Kotak 1: Kolom Nama Event Ujian.',
            'Kotak 2: Pemilihan Rentang Tanggal Pelaksanaan.',
            'Kotak 3: Tombol "Lanjut ke Sesi".',
          ],
        ),
        TourSubStep(
          title: 'Langkah 4.2: Konfigurasi Sesi Ujian',
          description:
              'Tentukan jumlah Sesi Ujian harian (misal Sesi 1: 07.30-09.30, Sesi 2: 10.00-12.00)',
          imagePath: 'assets/images/tour/event_step2.png',
          placeholderLabel: 'Screenshot 2: Step 2 Wizard - Konfigurasi Sesi Ujian & Jam Mulai',
          annotationHighlights: [
            'Kotak 1: Waktu Sesi Ujian Yang Terdaftar.',
            'Kotak 2: Atur Nama Untuk Setiap Sesi.',
            'Kotak 3: Atur Waktu Untuk Setiap Sesi.',
            'Kotak 4: Tombol Tambah Sesi (Untuk Menampilkan Pada Kotak 1).',
          ],
        ),
        TourSubStep(
          title: 'Langkah 4.3: Timetable / Jadwal Mata Pelajaran',
          description:
              'Atur jadwal Mata Pelajaran yang diujikan pada tiap sesi, durasi pengerjaan soal (menit), serta jumlah soal ujian.',
          imagePath: 'assets/images/tour/event_step3.png',
          placeholderLabel: 'Screenshot 3: Step 3 Wizard - Timetable Jadwal Mapel & Durasi',
          annotationHighlights: [
            'Kotak 1: Jadwal Mata Pelajaran Yang Telah Terdaftar.',
            'Kotak 2: Klik Untuk Memilih Mata Pelajaran Yang Ingin Ditambahkan.',
            'Kotak 3: Pilih Kelas Mana Saja Yang Mengikuti Ujian Mata Pelajaran Yang Telah Dipilih Pada Kotak Nomor 2.',
            'Kotak 4: Pilih Guru Untuk Pembuat Soal Sesuai Mata Pelajaran Yang Telah Dipilih (Ditandai Rekomendasi Untuk Guru Yang Sesuai Mata Pelajaran Yang Ditugaskan).',
            'Kotak 5: Klik Simpan Jadwal Untuk Menampilkan Informasi Mata Pelajaran dan Kelas Apa Saja Yang Mengikuti (Pada Kotak Nomor 1).',
          ],
        ),
        TourSubStep(
          title: 'Langkah 4.4: Pengaturan Ruangan Ujian',
          description:
              'Tambah ruangan kelas/lab yang digunakan untuk lokasi ujian, serta atur jumlah tempat duduk.',
          imagePath: 'assets/images/tour/event_step4.png',
          placeholderLabel: 'Screenshot 4: Step 4 Wizard - Pengaturan Ruangan & Layout Denah',
          annotationHighlights: [
            'Kotak 1: Tambah Ruangan.',
            'Kotak 2: Nama Ruangan.',
            'Kotak 3: Jumlah Bangku.',
          ],
        ),
        TourSubStep(
          title: 'Langkah 4.5: Alokasi & Distribusi Murid ke Ruangan',
          description:
              'Menampilkan beberapa informasi seperti Ruangan, Layout Ruangan, Total Kursi, dan Kelas',
          imagePath: 'assets/images/tour/event_step5.png',
          placeholderLabel: 'Screenshot 5: Step 5 Wizard - Alokasi Murid ke Ruangan Ujian.',
          annotationHighlights: [
            'Kotak 1: Ruangan (Untuk Menampilkan Informasi Ruangan).',
            'Kotak 2: Atur Untuk Menampilkan Jumlah Kolom Dan Pasang Meja Pada Ruangan Tersebut.',
            'Kotak 3: Atur Posisi Tempat Duduk Setiap Murid.',
            'Kotak 4: Menampilkan Informasi Kelas & Murid Yang Mengikuti Ujian.',
            'Panah 5: Tanda + Untuk Mengalokasikan Berapa Jumlah Murid Kelas Tersebut Yang Masuk Ke Ruangan Yang Ditampilkan.',
            'Panah 6: Tombol Pilih Semua Untuk Memilih Semua Murid Kelas Tersebut Yang Akan Dialokasikan.',
          ],
        ),
        TourSubStep(
          title: 'Langkah 4.6: Atur Jadwal Ujian',
          description:
              'Menampilkan semua hari dan tanggal waktu ujian yang telah di-atur pada langkah 1',
          imagePath: 'assets/images/tour/event_step6.png',
          placeholderLabel: 'Screenshot 6: Step 6 Wizard - Generasi Nomor Peserta Ujian.',
          annotationHighlights: [
            'Kotak 1: Tombol Generate Untuk Langsung Membuat Jadwal Mata Pelajaran Tanpa Perlu Pilih 1 per 1.',
            'Kotak 2: Informasi Jadwal Ujian Setiap Mata Pelajaran Setiap Sesi dan Setiap Hari.',
          ],
        ),
        TourSubStep(
          title: 'Langkah 4.7: Penugasan Pengawas',
          description:
              'Tetapkan Guru Pengawas untuk tiap ruangan dan sesi, lalu klik "Lanjut" Untuk Melihat Halaman Finalisasi.',
          imagePath: 'assets/images/tour/event_step7.png',
          placeholderLabel: 'Screenshot 7: Step 7 Wizard - Penugasan Pengawas & Finalisasi',
          annotationHighlights: [
            'Kotak 1: Menampilkan Informasi Hari, Ruangan dan Sesi.',
            'Panah 2: Klik Untuk Memilih Guru Pengawas.',
            'Kotak 3: Tombol Generate Otomatis Untuk Mengatur Jadwal Pengawas Secara Langsung Tanpa Harus Atur 1 per 1.',
          ],
        ),
       
      ],
      features: [
        'Buat Event Ujian terstruktur melalui 7 langkah wizard otomatis.',
        'Atur Sesi Ujian, Timetable Mapel & Durasi.',
        'Alokasi tempat duduk denah bangku & penugasan guru pengawas.',
        'Monitoring ruang ujian secara real-time (cek siswa aktif, sisa waktu, & reset sesi).',
        'Cetak rekap nilai ujian komprehensif, kartu peserta, dan lembar jawaban.',
      ],
      tip: 'Tips: Ikuti petunjuk 7 langkah wizard secara berurutan untuk memastikan seluruh ruangan, token, dan pengawas terkonfigurasi sempurna.',
    ),
    
  ];

  void _onFinish() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await AdminTourDialog.markTourCompleted(uid);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showImagePreviewDialog(BuildContext context, String imagePath, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(40),
                      color: Colors.white,
                      child: Text(
                        'Gambar tidak ditemukan: $imagePath',
                        style: GoogleFonts.inter(color: Colors.red),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 768;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? size.width * 0.12 : 16,
        vertical: isDesktop ? 30 : 20,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: isDesktop ? 700 : size.height * 0.90,
        ),
        child: Column(
          children: [
            // Top Bar
            _buildDialogHeader(context),

            // Carousel Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                    _currentSubStepPage = 0;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildStepSlide(_steps[index], isDesktop);
                },
              ),
            ),

            // Bottom Navigation Controls
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Color(0xFFA5B4FC),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panduan Penggunaan Aplikasi Admin',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Topik ${_currentPage + 1} dari ${_steps.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _onFinish,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tutup',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.close, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepSlide(TourStepItem step, bool isDesktop) {
    final subSteps = step.subSteps;
    final hasSubSteps = subSteps.isNotEmpty;
    final currentSubStep = hasSubSteps ? subSteps[_currentSubStepPage.clamp(0, subSteps.length - 1)] : null;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Top
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isDesktop ? 16 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: step.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step.icon, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: GoogleFonts.inter(
                          fontSize: isDesktop ? 17 : 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        step.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Sub-step switcher tab if multiple sub-steps exist
          if (hasSubSteps && subSteps.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(subSteps.length, (idx) {
                  final isSelected = _currentSubStepPage == idx;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        'Sub-Langkah 1.${idx + 1}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: step.gradientColors.first,
                      backgroundColor: const Color(0xFFF1F5F9),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _currentSubStepPage = idx;
                          });
                        }
                      },
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // SCREENSHOT / VISUAL DEMO CONTAINER
          if (currentSubStep != null) ...[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sub-step Title Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.image_outlined, size: 18, color: step.gradientColors.first),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentSubStep.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Image Display or Placeholder Box
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentSubStep.description,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF334155),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Image Render Block
                        GestureDetector(
                          onTap: () {
                            _showImagePreviewDialog(
                              context,
                              currentSubStep.imagePath,
                              currentSubStep.title,
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 180, maxHeight: 320),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                currentSubStep.imagePath,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  // Fallback Placeholder when screenshot file is pending
                                  return Container(
                                    padding: const EdgeInsets.all(24),
                                    color: const Color(0xFFF1F5F9),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_a_photo_outlined,
                                          size: 40,
                                          color: step.gradientColors.first.withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          currentSubStep.placeholderLabel,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF334155),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Menunggu Gambar Screenshot: ${currentSubStep.imagePath}',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                        // Annotation Highlights list
                        if (currentSubStep.annotationHighlights.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Petunjuk Elemen Layar (Tanda Panah / Kotak):',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...currentSubStep.annotationHighlights.map((hl) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.arrow_right_rounded,
                                          size: 16,
                                          color: Color(0xFF4F46E5),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            hl,
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              color: const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Core Features Checklist
          Text(
            'Ringkasan Fitur Utama:',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 10),

          ...step.features.map((feature) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: step.gradientColors.first,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF334155),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          // Pro-tip box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFD97706), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.tip,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final isLastPage = _currentPage == _steps.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Step Indicators (Dots)
          Row(
            children: List.generate(_steps.length, (index) {
              final isSelected = _currentPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(right: 6),
                width: isSelected ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSelected
                      ? _steps[_currentPage].gradientColors.first
                      : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const Spacer(),

          // Back button
          if (_currentPage > 0) ...[
            OutlinedButton(
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                foregroundColor: const Color(0xFF475569),
              ),
              child: Text(
                'Sebelumnya',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
          ],

          // Next / Finish button
          ElevatedButton(
            onPressed: () {
              if (isLastPage) {
                _onFinish();
              } else {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _steps[_currentPage].gradientColors.first,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLastPage ? 'Mulai Sekarang' : 'Selanjutnya',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Icon(
                  isLastPage ? Icons.check_circle : Icons.arrow_forward_rounded,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TourStepItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badgeText;
  final List<Color> gradientColors;
  final List<TourSubStep> subSteps;
  final List<String> features;
  final String tip;

  const TourStepItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badgeText,
    required this.gradientColors,
    this.subSteps = const [],
    required this.features,
    required this.tip,
  });
}

class TourSubStep {
  final String title;
  final String description;
  final String imagePath;
  final String placeholderLabel;
  final List<String> annotationHighlights;

  const TourSubStep({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.placeholderLabel,
    this.annotationHighlights = const [],
  });
}
