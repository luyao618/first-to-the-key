# First to the Key

2D 俯视角迷宫竞速游戏 —— 两个 LLM Agent 在迷宫中竞速收集钥匙，而玩家唯一的武器是比赛前写下的 prompt。

## 游戏概念

玩家扮演 **prompt 策略师**，通过编写自然语言指令来指挥 AI Agent 导航迷宫。Agent 只能看到有限视野内的信息，而玩家拥有上帝视角。你的 prompt 写得越好，AI 就越聪明。

**核心玩法循环**：编写 prompt → 生成迷宫 → 按顺序收集三把钥匙（黄铜 → 翡翠 → 水晶） → 抢先打开宝箱 → 复盘调优 → 再来一局。

## 游戏模式

| 模式 | 说明 | 阶段 |
|------|------|------|
| **Agent vs Agent** | 双方各写 prompt 指挥 AI 竞速 | MVP |
| **Player vs Agent** | 玩家亲自操控 vs AI Agent | Core |
| **Player vs Player** | 双方各有 LLM 观察员提供指引，呼叫观察员时原地冻结 | Core |

## 技术栈

- **引擎**: Godot 4.6
- **语言**: GDScript（主要），C++ via GDExtension（性能关键路径）
- **渲染**: Compatibility (OpenGL 3.3 / WebGL 2)
- **物理**: Godot Physics 2D
- **AI**: LLM API 集成（玩家自备 API Key）

## 核心系统

- 程序化迷宫生成（保证双方路径公平）
- 基于 tick 的实时网格移动
- 战争迷雾 / 有限视野系统
- 顺序钥匙收集与宝箱胜利条件
- LLM Agent 集成（接收局部视野，返回移动决策）

## 项目结构

```
├── src/          # 游戏源码
├── assets/       # 美术、音频等资源
├── design/       # 游戏设计文档（GDD、系统索引）
├── docs/         # 技术文档
├── tests/        # 测试用例
├── tools/        # 构建与流水线工具
├── prototypes/   # 原型实验
└── production/   # 生产管理（迭代、里程碑）
```

## 当前状态

项目处于 **Pre-Production** 阶段：

- [x] 游戏概念设计
- [x] 引擎配置（Godot 4.6）
- [x] 系统分解与依赖梳理（15 个系统）
- [ ] 各系统详细设计文档
- [ ] LLM 迷宫导航核心假设原型验证
- [ ] 首个 Sprint 规划

## 开发方式

本项目由 **Claude Code Game Studios** 架构驱动，通过 48 个协作 AI Agent 分工管理游戏开发的各个领域（设计、编程、美术、QA、制作等），人类负责决策，Agent 负责执行。

## License

TBD
