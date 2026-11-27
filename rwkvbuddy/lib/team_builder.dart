import 'package:flutter/material.dart';
import 'agent_controller.dart';
import 'team_presets.dart';
import 'windows_text_editing.dart';

const _ink = Color(0xFF252525);
const _muted = Color(0xFF92969F);
const _border = Color(0xFFE9EAED);
const _canvas = Color(0xFFF6F7F8);
const _colors = [
  Color(0xFF7186B5),
  Color(0xFF7FA696),
  Color(0xFFB39570),
  Color(0xFF9C89B5),
];

String speakingModeLabel(String? mode) => switch (mode) {
  'assigned' => '按需发言',
  'sequential' => '依次讨论',
  _ => '自由发言',
};

Future<Json?> showTeamBuilder(
  BuildContext context,
  AgentController agent, {
  bool create = false,
}) => showDialog<Json>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .25),
  builder: (_) => TeamBuilder(
    initialTeam: create ? null : agent.team,
    library: agent.expertLibrary,
  ),
);

class TeamBuilder extends StatefulWidget {
  const TeamBuilder({super.key, this.initialTeam, this.library = const []});
  final Json? initialTeam;
  final List<Json> library;
  @override
  State<TeamBuilder> createState() => _TeamBuilderState();
}

class _TeamBuilderState extends State<TeamBuilder> {
  final name = TextEditingController();
  final search = TextEditingController();
  final memberName = TextEditingController();
  final memberPrompt = TextEditingController();
  late List<Json> roster;
  late List<Json> selected;
  int tab = 0;
  String mode = 'parallel';
  String error = '';
  String? editingId;
  bool custom = false;
  Json? preview;

  @override
  void initState() {
    super.initState();
    name.text = widget.initialTeam?['name'] as String? ?? '新群聊';
    mode = widget.initialTeam?['speakingMode'] as String? ?? 'parallel';
    selected = [
      for (final member in widget.initialTeam?['members'] as List? ?? [])
        Map<String, dynamic>.from(member as Map),
    ];
    final all = <String, Json>{};
    for (final member in [...expertCatalog, ...widget.library, ...selected]) {
      all[member['id'] as String] = Map<String, dynamic>.from(member);
    }
    roster = all.values.toList();
  }

  @override
  void dispose() {
    for (final controller in [name, search, memberName, memberPrompt]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toggle(Json member) => setState(() {
    final index = selected.indexWhere((item) => item['id'] == member['id']);
    if (index >= 0) {
      selected.removeAt(index);
    } else if (selected.length < 6) {
      if (selected.any((item) => item['name'] == member['name'])) {
        error = '已有同名成员，请先修改名称';
        return;
      }
      selected.add(Map<String, dynamic>.from(member));
    } else {
      error = '最多选择 6 位专家';
      return;
    }
    error = '';
  });

  void _editMember(Json? member) => setState(() {
    custom = true;
    editingId = member?['id'] as String?;
    memberName.text = member?['name'] as String? ?? '';
    memberPrompt.text = member?['prompt'] as String? ?? '';
    error = '';
  });

  void _saveMember() {
    final title = memberName.text.trim();
    if (title.isEmpty ||
        title.length > 20 ||
        RegExp(r'[\s@，。！？、:：;；]').hasMatch(title) ||
        ['主持人', '全体'].contains(title)) {
      setState(() => error = '专家名称为 1–20 字，不能包含空格、@ 或分隔标点');
      return;
    }
    if (memberPrompt.text.trim().isEmpty) {
      setState(() => error = '请填写专家职责');
      return;
    }
    if (roster.any(
      (item) => item['name'] == title && item['id'] != editingId,
    )) {
      setState(() => error = '已有同名专家，请换一个名称');
      return;
    }
    if (editingId == null && selected.length >= 6) {
      setState(() => error = '最多选择 6 位专家');
      return;
    }
    setState(() {
      final member = <String, dynamic>{
        'id': editingId ?? 'expert_${DateTime.now().microsecondsSinceEpoch}',
        'name': title,
        'prompt': memberPrompt.text.trim(),
        'icon': 'person',
      };
      final index = roster.indexWhere((item) => item['id'] == member['id']);
      if (index < 0) {
        roster.add(member);
        selected.add(Map<String, dynamic>.from(member));
      } else {
        roster[index] = member;
        final chosen = selected.indexWhere(
          (item) => item['id'] == member['id'],
        );
        if (chosen >= 0) selected[chosen] = Map<String, dynamic>.from(member);
      }
      custom = false;
      editingId = null;
      error = '';
    });
  }

  void _save() {
    if (name.text.trim().isEmpty) {
      setState(() => error = '请填写群名称');
      return;
    }
    if (selected.isEmpty) {
      setState(() => error = '至少选择一位专家');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'name': name.text.trim(),
      'speakingMode': mode,
      'members': selected,
    });
  }

  Widget _avatar(Json member, {double size = 38}) {
    final id = member['id'] as String;
    final color =
        _colors[id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
            _colors.length];
    final icon = switch (member['icon']) {
      'chart' => Icons.bar_chart_rounded,
      'shield' => Icons.shield_outlined,
      'check' => Icons.fact_check_outlined,
      'contract' => Icons.description_outlined,
      'document' => Icons.article_outlined,
      'idea' => Icons.lightbulb_outline_rounded,
      _ => Icons.person_outline_rounded,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, size: size * .53, color: color),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    hintStyle: const TextStyle(fontSize: 12, color: _muted),
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _border),
    ),
  );

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(18),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SizedBox(
      width: 1060,
      height: 880,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 14, 6),
            child: Row(
              children: [
                if (preview != null)
                  TextButton.icon(
                    onPressed: () => setState(() => preview = null),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 13),
                    label: const Text('返回列表'),
                  )
                else
                  Expanded(
                    child: Text(
                      widget.initialTeam == null ? '新建群聊' : '编辑群聊',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (preview != null) const Spacer(),
                IconButton(
                  tooltip: '关闭群聊配置',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          if (preview == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _tab('自定义配置', 0),
                  const SizedBox(width: 26),
                  _tab('选择预设团队', 1),
                ],
              ),
            ),
          Expanded(
            child: preview != null
                ? _preview()
                : tab == 0
                ? _configuration()
                : _presets(),
          ),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    error.isNotEmpty
                        ? error
                        : preview != null
                        ? '可在使用模板后调整成员与职责'
                        : '每位成员共享所选本地资料，主持人自动加入并汇总',
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      color: error.isNotEmpty ? Colors.deepOrange : _muted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: preview != null
                      ? () => setState(() {
                          name.text = preview!['name'] as String;
                          mode = preview!['speakingMode'] as String;
                          selected = [
                            for (final member in preview!['members'] as List)
                              Map<String, dynamic>.from(member as Map),
                          ];
                          for (final member in selected) {
                            final index = roster.indexWhere(
                              (item) => item['id'] == member['id'],
                            );
                            if (index < 0) {
                              roster.add(Map<String, dynamic>.from(member));
                            } else {
                              roster[index] = Map<String, dynamic>.from(member);
                            }
                          }
                          preview = null;
                          tab = 0;
                          error = '';
                          custom = false;
                        })
                      : tab == 1 || selected.isEmpty
                      ? null
                      : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 40),
                  ),
                  child: Text(
                    preview != null
                        ? '使用该团队模板'
                        : widget.initialTeam == null
                        ? '创建群聊'
                        : '保存团队',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tab(String title, int value) => InkWell(
    onTap: () => setState(() {
      tab = value;
      error = '';
    }),
    child: Container(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tab == value ? _ink : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: tab == value ? FontWeight.w600 : FontWeight.normal,
          color: tab == value ? _ink : _muted,
        ),
      ),
    ),
  );

  Widget _configuration() => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 720 || constraints.maxHeight < 480;
      final fields = <Widget>[
        _label('群名称'),
        WindowsTextEditing(
          controller: name,
          child: TextField(
            key: const Key('group-name'),
            controller: name,
            maxLength: 40,
            style: const TextStyle(fontSize: 13),
            decoration: _input('为团队起一个名称'),
          ),
        ),
        const SizedBox(height: 22),
        _label('发言模式'),
        if (constraints.maxWidth < 550) ...[
          _modeCard('parallel', '自由发言', '所有专家独立分析资料，按并发配置同时进行，主持人最后汇总。'),
          const SizedBox(height: 10),
          _modeCard('assigned', '按需发言', '主持人根据问题分配任务，仅被分配的专家参与分析。'),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _modeCard(
                  'parallel',
                  '自由发言',
                  '所有专家独立分析资料，按并发配置同时进行，主持人最后汇总。',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _modeCard(
                  'assigned',
                  '按需发言',
                  '主持人根据问题分配任务，仅被分配的专家参与分析。',
                ),
              ),
            ],
          ),
        if (mode == 'sequential')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => setState(() => mode = 'parallel'),
              child: const Text('当前为旧版依次讨论，点击切换自由发言'),
            ),
          ),
        const SizedBox(height: 22),
        _label('添加成员'),
      ];
      if (narrow) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...fields,
              _selectedPanel(),
              const SizedBox(height: 12),
              SizedBox(height: 470, child: _libraryPanel()),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...fields,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _libraryPanel()),
                  const SizedBox(width: 14),
                  SizedBox(width: 240, child: _selectedPanel()),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _modeCard(String value, String title, String description) => InkWell(
    key: Key('mode-$value'),
    onTap: () => setState(() {
      mode = value;
      error = '';
    }),
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mode == value ? const Color(0xFFFAFAFA) : Colors.white,
        border: Border.all(
          color: mode == value ? const Color(0xFF777C83) : _border,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            mode == value ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 19,
            color: mode == value ? _ink : const Color(0xFFCCD0D6),
          ),
        ],
      ),
    ),
  );

  Widget _libraryPanel() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                custom
                    ? editingId == null
                          ? '添加自定义专家'
                          : '编辑专家'
                    : '选择已有专家',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: custom
                  ? () => setState(() {
                      custom = false;
                      error = '';
                    })
                  : () => _editMember(null),
              icon: Icon(custom ? Icons.arrow_back : Icons.add, size: 15),
              label: Text(custom ? '返回' : '自定义'),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('expert-list-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (custom) ...[
                  const SizedBox(height: 12),
                  _label('专家名称'),
                  WindowsTextEditing(
                    controller: memberName,
                    child: TextField(
                      key: const Key('expert-name'),
                      controller: memberName,
                      maxLength: 20,
                      decoration: _input('例如：采购审核员'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('职责与擅长领域'),
                  WindowsTextEditing(
                    controller: memberPrompt,
                    child: TextField(
                      key: const Key('expert-prompt'),
                      controller: memberPrompt,
                      maxLength: 1200,
                      minLines: 5,
                      maxLines: 7,
                      decoration: _input('描述这位专家需要关注的问题、分析方法和交付要求…'),
                      style: const TextStyle(fontSize: 12, height: 1.7),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saveMember,
                      child: Text(editingId == null ? '添加到团队' : '保存专家'),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('expert-search'),
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: _input(
                      '搜索名称或擅长领域',
                    ).copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  for (final member in roster.where(
                    (member) => '${member['name']} ${member['prompt']}'
                        .toLowerCase()
                        .contains(search.text.trim().toLowerCase()),
                  ))
                    _expertRow(member),
                  if (!roster.any(
                    (member) => '${member['name']} ${member['prompt']}'
                        .toLowerCase()
                        .contains(search.text.trim().toLowerCase()),
                  ))
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '没有匹配的专家，可添加自定义专家',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _expertRow(Json member) {
    final chosen = selected.any((item) => item['id'] == member['id']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: chosen ? _canvas : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('select-${member['id']}'),
          onTap: () => _toggle(member),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                _avatar(member),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member['name'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        member['prompt'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Icon(
                  chosen ? Icons.check_circle : Icons.add_circle_outline,
                  size: 20,
                  color: chosen ? _ink : const Color(0xFFC2C5CB),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedPanel() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _canvas,
      borderRadius: BorderRadius.circular(16),
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '已选成员（${selected.length}）',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Text(
                '最多 6 人',
                style: TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (selected.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Column(
                children: [
                  Icon(
                    Icons.group_add_outlined,
                    color: Color(0xFFCCD0D6),
                    size: 32,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '从左侧选择专家\n或添加自定义成员',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: _muted, height: 1.8),
                  ),
                ],
              ),
            ),
          for (final member in selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  _avatar(member, size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => _editMember(member),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          member['name'] as String,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑${member['name']}',
                    onPressed: () => _editMember(member),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                  ),
                  IconButton(
                    tooltip: '移除${member['name']}',
                    onPressed: () => _toggle(member),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          const Divider(height: 24, color: _border),
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 17, color: _muted),
              SizedBox(width: 8),
              Text('主持人', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('自动加入', style: TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '负责整理共识、分歧与最终结论',
            style: TextStyle(fontSize: 10, height: 1.7, color: _muted),
          ),
        ],
      ),
    ),
  );

  Widget _presets() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '为本地资料，组建专业团队',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '选择合适的分析视角，成员与职责均可继续调整',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _avatar(expertCatalog[0], size: 48),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 3
                : constraints.maxWidth >= 540
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final preset in teamPresets)
                  SizedBox(
                    width: width,
                    height: 154,
                    child: _presetCard(preset),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _presetCard(Json preset) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: _border),
    ),
    child: InkWell(
      key: Key('preset-${preset['name']}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        preview = preset;
        error = '';
      }),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preset['name'] as String,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              preset['description'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.8, color: _muted),
            ),
            const Spacer(),
            Row(
              children: [
                for (final member in preset['members'] as List)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: _avatar(member as Json, size: 21),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${(preset['members'] as List).length} 位专家 · ${speakingModeLabel(preset['speakingMode'] as String)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _preview() {
    final preset = preview!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final member in preset['members'] as List)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _avatar(member as Json, size: 42),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            preset['name'] as String,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            preset['description'] as String,
            style: const TextStyle(fontSize: 12, color: _muted, height: 1.8),
          ),
          const SizedBox(height: 30),
          _label('发言模式'),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speakingModeLabel(preset['speakingMode'] as String),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  preset['speakingMode'] == 'assigned'
                      ? '主持人按问题分配任务，相关专家分析后统一汇总。'
                      : '专家独立分析同一批本地资料，主持人汇总各方结论。',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          _label('团队成员（${(preset['members'] as List).length} 人）'),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 850
                  ? 3
                  : constraints.maxWidth >= 540
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final member in preset['members'] as List)
                    SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: _border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _avatar(member as Json, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    member['prompt'] as String,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _muted,
                                      height: 1.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
