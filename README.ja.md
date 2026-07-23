# ZuQL

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

ZuQL は、公開 Zuora データモデルに特化した保守的な自然言語インターフェースです。サポート対象のビジネス質問を、決定的かつ検証済みの Zuora Data Query SQL と、人が確認できる説明へ変換します。

ZuQL の用途は SQL プレビューと開発者向けツールです。テナントへの接続や、生成したクエリの実行は**行いません**。

## できること

- 自然言語の質問を厳密な型付きビジネス意図へ変換します。
- 管理されたオブジェクト、フィールド、メトリクス、ディメンションから用語を解決します。
- レビュー済みのリレーションだけを使って JOIN を計画します。
- コンパイル前に危険な粒度と fan-out を検出します。
- レジストリで許可された物理識別子だけから決定的な SQL を生成します。
- 解決結果、フィルター、メトリクス、JOIN、粒度、前提、マッピング状態、警告を説明します。
- オフライン fixture Provider と OpenAI Responses API Provider をサポートします。
- CLI または Ruby API からターミナル、JSON、Markdown を出力します。

## しないこと

- 汎用 text-to-SQL エンジンではありません。
- SQL の実行、Zuora 認証、結果のダウンロードは行いません。
- テナント Schema、カスタムフィールド、有効な機能を検出しません。
- 公開 canonical model と特定テナントの一致を保証しません。
- モデルが生成した SQL、物理テーブル名、JOIN、バックエンド選択を受け入れません。
- 危険な fan-out を暗黙に書き換えず、安全性を証明できない要求は拒否します。

## クイックスタート

Ruby 3.3 以降と Bundler が必要です。

```sh
git clone <repository-url>
cd ZuQL
bundle install
bundle exec exe/zuql --list-examples
bundle exec exe/zuql "Count active subscriptions"
```

デフォルトは決定的でネットワーク不要のオフラインモードです。`data/fixtures/query_interpretations.yml` にある質問と完全一致する入力を受け付けます。

```sh
bundle exec exe/zuql --list-domains
bundle exec exe/zuql "Count active subscriptions" --json result.json
bundle exec exe/zuql "Count active subscriptions" --markdown result.md
bundle exec exe/zuql --help
```

エクスポートは既存ファイルを上書きしません。

### ライブ Provider

ライブ Provider は、サポート範囲内の未知の質問を解釈できます。その後の計画と SQL 生成は引き続き決定的で、アプリケーションが管理します。

```sh
export OPENAI_API_KEY='your-key'
export ZUQL_OPENAI_MODEL='gpt-5.6-sol' # 任意のデフォルト値
bundle exec exe/zuql --live "Show current MRR by account"
```

資格情報は環境変数からのみ読み込み、Authorization ヘッダーだけに送信します。任意設定は `ZUQL_PROVIDER_OPEN_TIMEOUT`、`ZUQL_PROVIDER_READ_TIMEOUT`、`ZUQL_PROVIDER_MAX_ATTEMPTS`、`ZUQL_PROVIDER_MAX_RESPONSE_BYTES`、`ZUQL_OPENAI_ENDPOINT` です。

### Ruby API

```ruby
require 'zuql'

provider = ZuQL::Providers::FixtureProvider.from_yaml
interpreter = ZuQL::NaturalLanguageInterpreter.new(provider: provider)
pipeline = ZuQL::Pipeline.new(interpreter: interpreter)
result = pipeline.call('Count active subscriptions')

puts result.compiled_query.sql
```

## 開発者向けアーキテクチャ

```text
質問 → Provider → NaturalLanguageInterpreter → QuerySpec
     → SemanticResolver → QueryPlanner / GrainValidator
     → DataQueryCompiler → SqlSafetyValidator
     → QueryExplainer → Terminal / JSON / Markdown
```

信頼境界は意図的に狭くしています。

1. `MetadataRetriever` は canonical metadata の一部だけを選択します。
2. `NaturalLanguageInterpreter` は Provider の構造化された意図をバージョン付き JSON Schema で検証します。Provider は SQL、JOIN、物理識別子、バックエンドを選べません。
3. `SemanticResolver` がビジネス概念を canonical ID に変換します。
4. `QueryPlanner`、`RelationshipGraph`、`GrainValidator` がレビュー済みパスを選び、曖昧・未接続・危険な計画を拒否します。
5. `DataQueryCompiler` は検証済みレジストリからサポート対象 SQL だけを生成します。
6. `SqlSafetyValidator` が型付き計画を再コンパイルして成果物を検証します。
7. `QueryExplainer` と Renderer が結果と provenance を出力します。

オフラインとライブの Provider は境界以降の全ステージを共有するため、fixture テストは本番の解決、計画、コンパイル、安全検証経路を実行します。

主要な場所は、Provider の `lib/zuql/providers/`、不変契約の `lib/zuql/contracts.rb`、レビュー済みメタデータの `data/canonical/`、Provider 境界の `schemas/` と `prompts/`、各種テストの `spec/` です。

## 開発とリリース検証

```sh
bundle exec rake spec
bundle exec rubocop
bundle exec rake metadata_audit
bundle exec rake
bundle exec rake release_gate
```

Release gate は 20 件以上の golden questions を検証し、gem をビルドして隔離 `GEM_HOME` にインストールし、インストール済み CLI を smoke test します。CI は Ruby 3.3、3.4、4.0 で品質チェックを実行します。

詳細は [SQL サブセット](docs/DATA_QUERY_SQL_SUBSET.md)、[MVP リリースガイド](docs/MVP_RELEASE.md)、[実装計画](docs/MVP_IMPLEMENTATION_PLAN.md)を参照してください。

## 既知の制限と将来候補

以下は MVP の対象外であり、将来の提供を約束するものではありません。

- Zuora Data Query の認証、送信、ポーリング、エクスポート取得。
- テナント Schema 検出、overlay、カスタムフィールド、機能プロファイル。
- Snowflake のコンパイルまたは実行。
- 事前集約、CTE、semi-join、複数段階計画による fan-out の自動安全化。
- fuzzy／embedding ベースの検索と追加のライブ LLM Provider。
- ブラウザによるドキュメント収集とスナップショット基盤。
- HTTP API、Web UI、ホスト型サービス、ユーザー、認可、監査ログ、課金。
- 旧 Amendment／InvoicePayment、Revenue Recognition、完全な BI 対応。

読み取り専用テナントで検証できるまでは、すべての結果に公開 canonical model の制約とマッピング状態を表示します。不明または危険な場合は推測せずエラーにします。

## セキュリティとライセンス

Provider 出力は信頼せず、厳密な Schema を通し、SQL を許可しません。物理識別子と JOIN はレジストリだけを情報源とします。エラーは資格情報、Provider 応答、SQL、パス、backtrace を公開せず、エクスポートは既存ファイルを上書きしません。セキュリティ問題は、資格情報やテナントデータを公開 issue に書かず、メンテナーへ非公開で報告してください。

ZuQL は [MIT License](LICENSE.txt) で提供されます。
