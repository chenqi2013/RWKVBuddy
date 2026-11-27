import 'agent_controller.dart';

const expertCatalog = <Json>[
  {
    'id': 'reader',
    'name': '资料整理员',
    'prompt': '逐份梳理所选本地文件的主题、事实、日期、金额与关键条款，引用来源，明确提取范围和缺失信息。',
    'icon': 'document',
  },
  {
    'id': 'analyst',
    'name': '数据分析师',
    'prompt': '核对本地表格和文档的数据口径，比较趋势、差异和异常，必要时调用计算工具，不将不同口径数据直接合并。',
    'icon': 'chart',
  },
  {
    'id': 'reviewer',
    'name': '交叉核验员',
    'prompt': '交叉比对所选文件的事实与结论，检查冲突、遗漏和依据不足的问题，逐项注明来源及待确认事项。',
    'icon': 'check',
  },
  {
    'id': 'contract',
    'name': '合同审阅员',
    'prompt': '对比本地合同的权利义务、付款、交付、违约与终止条款，列出版本差异、歧义及修改建议，注明文件来源。',
    'icon': 'contract',
  },
  {
    'id': 'finance',
    'name': '财务分析师',
    'prompt': '分析所选财务资料中的收入、成本、利润、预算和现金流，保留原始单位及统计口径，标明缺失数据和待核实事项。',
    'icon': 'chart',
  },
  {
    'id': 'risk',
    'name': '风险评估师',
    'prompt': '从保守、审慎角度检查资料里的潜在风险和不利情形，区分证据、假设和未知，给出可执行的核验清单。',
    'icon': 'shield',
  },
  {
    'id': 'optimist',
    'name': '机会发现者',
    'prompt': '从积极角度分析本地资料中的机会、优势和可行路径，所有具体事实须有文件依据，明确收益依赖的条件。',
    'icon': 'idea',
  },
  {
    'id': 'innovator',
    'name': '创新建议者',
    'prompt': '结合本地资料提出不同于常规的替代方案，解释适用条件、代价和验证方式，区分建议与已证实事实。',
    'icon': 'idea',
  },
  {
    'id': 'rational',
    'name': '理性分析师',
    'prompt': '基于所选文件的证据、数据和约束进行中立分析，对比选项及其利弊，指出结论依赖的假设。',
    'icon': 'check',
  },
  {
    'id': 'writer',
    'name': '报告撰写员',
    'prompt': '把所选资料中的关键事实整理成清晰的报告结构和行动建议，保留来源与限制，不编造材料未提供的数据。',
    'icon': 'document',
  },
];

List<Json> get teamPresets =>
    [
          {
            'name': '资料分析团队',
            'description': '梳理多份文件，提取关键事实，交叉核对差异与遗漏。',
            'speakingMode': 'parallel',
            'ids': ['reader', 'analyst', 'reviewer'],
          },
          {
            'name': '多视角决策团队',
            'description': '从机会、风险、创新和理性四个角度审视资料，让决策更周全。',
            'speakingMode': 'parallel',
            'ids': ['optimist', 'risk', 'innovator', 'rational'],
          },
          {
            'name': '合同审阅团队',
            'description': '对比合同与补充材料，定位条款差异、履约风险和待确认事项。',
            'speakingMode': 'assigned',
            'ids': ['contract', 'risk', 'reviewer'],
          },
          {
            'name': '财务分析团队',
            'description': '核对表格、预算与经营材料，分析数据变化和口径冲突。',
            'speakingMode': 'assigned',
            'ids': ['finance', 'analyst', 'risk'],
          },
        ]
        .map(
          (preset) => <String, dynamic>{
            ...preset,
            'members': [
              for (final id in preset['ids'] as List)
                Map<String, dynamic>.from(
                  expertCatalog.firstWhere((member) => member['id'] == id),
                ),
            ],
          },
        )
        .toList();
