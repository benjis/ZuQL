# ZuQL

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

ZuQL 是一个面向公开 Zuora 数据模型、采取保守策略的领域专用自然语言接口。它把受支持的业务问题转换为确定性、经过验证的 Zuora Data Query SQL，并同时给出便于审查的解释。

ZuQL 面向 SQL 预览和开发者工具场景；它**不会**连接租户，也不会执行生成的查询。

## 能做什么

- 将自然语言问题解释为严格的类型化业务意图。
- 使用经过维护的对象、字段、指标和维度注册表解析业务术语。
- 只通过已审查的关系规划 JOIN。
- 在编译前检测不安全的粒度和 fan-out。
- 只使用注册表批准的物理标识符生成确定性 SQL。
- 解释解析结果、过滤器、指标、JOIN、粒度、假设、映射状态和警告。
- 支持离线 fixture Provider 和实时 OpenAI Responses API Provider。
- 通过 CLI 或 Ruby API 输出终端文本、JSON 和 Markdown。

## 不能做什么

- 不是通用 text-to-SQL 引擎。
- 不执行 SQL，不登录 Zuora，也不下载查询结果。
- 不发现租户 Schema、自定义字段或已启用功能。
- 不保证公开规范模型与特定租户完全一致。
- 不接受模型生成的 SQL、物理表名、JOIN 或后端选择。
- 不会静默改写不安全的 fan-out；无法证明安全时会拒绝请求。

## 快速开始

需要 Ruby 3.3+ 和 Bundler：

```sh
git clone <repository-url>
cd ZuQL
bundle install
bundle exec exe/zuql --list-examples
bundle exec exe/zuql "Count active subscriptions"
```

默认使用确定性、无需网络的离线模式，只接受 `data/fixtures/query_interpretations.yml` 中的精确问题。常用命令：

```sh
bundle exec exe/zuql --list-domains
bundle exec exe/zuql "Count active subscriptions" --json result.json
bundle exec exe/zuql "Count active subscriptions" --markdown result.md
bundle exec exe/zuql --help
```

导出采用独占创建，不会覆盖已有文件。

### 实时 Provider

实时 Provider 可以解释此前未见过但处于支持范围内的问题；后续规划和 SQL 生成仍然是确定性且由应用控制的。

```sh
export OPENAI_API_KEY='your-key'
export ZUQL_OPENAI_MODEL='gpt-5.6-sol' # 可选默认值
bundle exec exe/zuql --live "Show current MRR by account"
```

凭证仅从环境变量读取，并只放入授权请求头。可选配置包括 `ZUQL_PROVIDER_OPEN_TIMEOUT`、`ZUQL_PROVIDER_READ_TIMEOUT`、`ZUQL_PROVIDER_MAX_ATTEMPTS`、`ZUQL_PROVIDER_MAX_RESPONSE_BYTES` 和 `ZUQL_OPENAI_ENDPOINT`。

### Ruby API

```ruby
require 'zuql'

provider = ZuQL::Providers::FixtureProvider.from_yaml
interpreter = ZuQL::NaturalLanguageInterpreter.new(provider: provider)
pipeline = ZuQL::Pipeline.new(interpreter: interpreter)
result = pipeline.call('Count active subscriptions')

puts result.compiled_query.sql
```

## 开发者架构

```text
问题 → Provider → NaturalLanguageInterpreter → QuerySpec
     → SemanticResolver → QueryPlanner / GrainValidator
     → DataQueryCompiler → SqlSafetyValidator
     → QueryExplainer → 终端 / JSON / Markdown
```

信任边界刻意保持狭窄：

1. `MetadataRetriever` 只选择有界的规范元数据。
2. `NaturalLanguageInterpreter` 根据版本化 JSON Schema 验证 Provider 的结构化意图；Provider 无权决定 SQL、JOIN、物理标识符或后端。
3. `SemanticResolver` 将业务概念映射到规范 ID。
4. `QueryPlanner`、`RelationshipGraph` 和 `GrainValidator` 选择已审查路径，并拒绝歧义、断连或不安全的计划。
5. `DataQueryCompiler` 只使用验证后的注册表映射生成受支持 SQL 子集。
6. `SqlSafetyValidator` 重新编译类型化计划并验证产物。
7. `QueryExplainer` 和 Renderer 输出结果及其来源说明。

离线与实时 Provider 在 Provider 边界之后共享完全相同的流水线，因此 fixture 测试覆盖生产解析、规划、编译和安全验证路径。

主要目录：`lib/zuql/providers/` 包含 Provider；`lib/zuql/contracts.rb` 定义不可变契约；`data/canonical/` 保存已审查元数据；`schemas/` 与 `prompts/` 定义 Provider 边界；`spec/` 包含单元、集成、安全和 golden 测试。

## 开发与发布检查

```sh
bundle exec rake spec
bundle exec rubocop
bundle exec rake metadata_audit
bundle exec rake
bundle exec rake release_gate
```

Release gate 会额外验证 20+ 条 golden questions、构建 gem、在隔离 `GEM_HOME` 中安装依赖和 gem，并冒烟测试安装后的 CLI。CI 在 Ruby 3.3、3.4 和 4.0 上运行质量检查。

详细约束见 [SQL 子集](docs/DATA_QUERY_SQL_SUBSET.md)、[MVP 发布指南](docs/MVP_RELEASE.md)和[实施计划](docs/MVP_IMPLEMENTATION_PLAN.md)。

## 已知限制与未来可能方向

以下内容不属于 MVP，也不构成未来版本承诺：

- 实时 Zuora Data Query 认证、提交、轮询和导出下载。
- 租户 Schema 发现、overlay、自定义字段和功能档案。
- Snowflake 编译或执行。
- 使用预聚合、CTE、semi-join 或多阶段计划自动安全改写 fan-out。
- 模糊或基于 embedding 的语义检索，以及更多实时 LLM Provider。
- 浏览器文档抓取与快照基础设施。
- HTTP API、Web UI、托管服务、用户、授权、审计日志和计费。
- 旧 Amendment/InvoicePayment 模型、Revenue Recognition 和完整 BI 覆盖。

在可以针对只读租户验证之前，每个结果都会保留公开规范模型限制和映射状态。未知或不安全情况应报错，而不是猜测。

## 安全与许可证

Provider 输出是不可信输入，必须通过严格 Schema，且不能包含 SQL。物理标识符和 JOIN 只能来自注册表；错误不会暴露凭证、Provider 响应、SQL、路径或 backtrace；导出不会覆盖文件。请私下向维护者报告安全问题，不要在公开 issue 中提交凭证或租户数据。

本项目采用 [MIT License](LICENSE.txt)。
