import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/tts_service.dart';
import 'emergency_report_screen.dart';
import 'voice_report_screen.dart';

class _ChatMessage {
  final String text;
  final bool fromUser;
  const _ChatMessage(this.text, this.fromUser);
}

/// كلمات مفتاحية بسيطة تربط كلام المستخدم بنوع البلاغ المناسب، عشان
/// المساعد يرد بإرشاد مفيد بدل رسالة عامة ثابتة.
const Map<String, MapEntry<String, int?>> _keywordReplies = {
  'حريق': MapEntry(
    'إذا في حريق: ابتعد فورًا عن المكان، ولا تحاول إخماد حريق كبير بنفسك. اتصل بالدفاع المدني. أقدر أفتح لك بلاغ حريق الآن جاهز بالتفاصيل، تحب؟',
    0,
  ),
  'حادث': MapEntry(
    'إذا في حادث سير: تأكد من سلامتك أولًا وابتعد عن مسار الحركة. اتصل بالإسعاف لو في إصابات. أقدر أفتح لك بلاغ حادث سير الآن، تحب؟',
    1,
  ),
  'مطر': MapEntry(
    'إذا في أمطار أو وادي: ابتعد عن مجاري السيول فورًا ولا تحاول العبور مهما كان المستوى بسيط. أقدر أفتح لك بلاغ عشان نحذّر الفرق المختصة، تحب؟',
    2,
  ),
  'واد': MapEntry(
    'إذا في وادي جاري: ابتعد فورًا ولا تحاول العبور. أقدر أفتح لك بلاغ عشان نحذّر الفرق المختصة، تحب؟',
    2,
  ),
  'مريض': MapEntry(
    'إذا في حالة صحية طارئة: حافظ على هدوئك وتأكد إن المصاب بوضع آمن، واتصل بالإسعاف. أقدر أفتح لك بلاغ حالة صحية الآن، تحب؟',
    3,
  ),
  'صحة': MapEntry(
    'إذا في حالة صحية طارئة: حافظ على هدوئك وتأكد إن المصاب بوضع آمن، واتصل بالإسعاف. أقدر أفتح لك بلاغ حالة صحية الآن، تحب؟',
    3,
  ),
  'اسعاف': MapEntry(
    'اتصل بالإسعاف فورًا. أقدر أفتح لك بلاغ حالة صحية طارئة الآن مع تحديد الموقع، تحب؟',
    3,
  ),
};

/// شاشة المساعد الذكي (تبويب "المساعد") — تدعم النطق الصوتي للردود
/// والإدخال الصوتي، عشان تكون سهلة الاستخدام لكبار السن والأطفال.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const String _welcomeText = 'مرحباً بك! أنا مساعد أمان الذكي، كيف يمكنني مساعدتك اليوم؟';

  final List<_ChatMessage> _messages = [const _ChatMessage(_welcomeText, false)];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToText _speech = SpeechToText();

  bool _muted = false;
  bool _isListening = false;
  int? _lastSuggestedCategory;

  @override
  void initState() {
    super.initState();
    _muted = TtsService.instance.isMuted;
  }

  @override
  void dispose() {
    TtsService.instance.stop();
    if (_isListening) _speech.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _addBotMessage(String text) {
    setState(() => _messages.add(_ChatMessage(text, false)));
    TtsService.instance.speak(text);
    _scrollToBottom();
  }

  Future<void> _toggleMute() async {
    final muted = await TtsService.instance.toggleMute();
    if (mounted) setState(() => _muted = muted);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التعرف على الصوت غير متاح — تأكد من السماح بالوصول إلى الميكروفون')),
      );
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'ar-SA',
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        });
      },
    );
  }

  void _send([String? quickText]) {
    final text = (quickText ?? _controller.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _controller.clear();
    });
    _scrollToBottom();

    // مطابقة بسيطة بالكلمات المفتاحية لتحديد رد مناسب ونوع بلاغ مقترح
    String? reply;
    int? suggestedCategory;
    for (final entry in _keywordReplies.entries) {
      if (text.contains(entry.key)) {
        reply = entry.value.key;
        suggestedCategory = entry.value.value;
        break;
      }
    }
    reply ??= 'تم استلام رسالتك. تقدر تفتح المرشد الكامل بالأسفل عشان أساعدك خطوة بخطوة حسب نوع المشكلة، أو صف لي وش صار بالتفصيل.';
    setState(() => _lastSuggestedCategory = suggestedCategory);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _addBotMessage(reply!);
    });
  }

  void _openFullGuide() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
    );
  }

  void _openReportWithSuggestion() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmergencyReportScreen(initialCategoryIndex: _lastSuggestedCategory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildQuickChips(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.fromUser ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: msg.fromUser ? AppColors.primaryBlue : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: msg.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.text,
                            textAlign: TextAlign.right,
                            style: AppTextStyles.body.copyWith(
                              color: msg.fromUser ? Colors.white : AppColors.textDark,
                              height: 1.5,
                            ),
                          ),
                          if (!msg.fromUser) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => TtsService.instance.speak(msg.text),
                              child: Icon(Icons.volume_up_rounded, size: 16, color: AppColors.textLight),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
        color: AppColors.scaffoldBg,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _toggleListening,
                      icon: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _isListening ? AppColors.emergencyRed : AppColors.textLight,
                      ),
                      tooltip: 'تحدث بدل الكتابة',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.body,
                        decoration: InputDecoration(
                          hintText: _isListening ? 'أستمع إليك الآن...' : 'اكتب رسالتك هنا...',
                          hintStyle: AppTextStyles.subtitle,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
              child: IconButton(
                onPressed: () => _send(),
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.logoGradient,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المساعد الذكي', style: AppTextStyles.h3),
              Text('متصل الآن', style: AppTextStyles.caption.copyWith(color: AppColors.healthGreen)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: _toggleMute,
            icon: Icon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _muted ? AppColors.textLight : AppColors.primaryBlue,
            ),
            tooltip: _muted ? 'تشغيل الصوت' : 'كتم الصوت',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ActionChip(
            avatar: const Icon(Icons.route_rounded, size: 16, color: AppColors.primaryBlue),
            label: const Text('المرشد الكامل خطوة بخطوة'),
            labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue, fontSize: 12),
            backgroundColor: AppColors.lightBlueBg,
            onPressed: _openFullGuide,
          ),
          const SizedBox(width: 8),
          if (_lastSuggestedCategory != null)
            ActionChip(
              avatar: const Icon(Icons.campaign_rounded, size: 16, color: AppColors.primaryBlue),
              label: const Text('أرسل بلاغًا الآن'),
              labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue, fontSize: 12),
              backgroundColor: AppColors.lightBlueBg,
              onPressed: _openReportWithSuggestion,
            ),
        ],
      ),
    );
  }
}
