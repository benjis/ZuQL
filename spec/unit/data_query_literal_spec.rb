# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::DataQueryLiteral do
  subject(:literal) { described_class.new }

  {
    ['=', "O'Reilly"] => "account.Name = 'O''Reilly'",
    ['!=', 12] => 'account.Name != 12',
    ['>', 12.5] => 'account.Name > 12.5',
    ['=', true] => 'account.Name = TRUE',
    ['=', false] => 'account.Name = FALSE'
  }.each do |(operator, value), expected|
    it "renders #{operator} with #{value.inspect}" do
      expect(literal.filter('account.Name', operator, value)).to eq(expected)
    end
  end

  it 'renders equality and inequality with NULL semantics' do
    expect(literal.filter('account.Name', '=', nil)).to eq('account.Name IS NULL')
    expect(literal.filter('account.Name', '!=', nil)).to eq('account.Name IS NOT NULL')
  end

  it 'renders non-empty IN and NOT IN scalar lists' do
    expect(literal.filter('account.Status', 'IN', %w[Active Pending])).to eq(
      "account.Status IN ('Active', 'Pending')"
    )
    expect(literal.filter('account.Number', 'NOT IN', [1, 2])).to eq(
      'account.Number NOT IN (1, 2)'
    )
  end

  it 'renders contains-style LIKE with escaped wildcards and escape marker' do
    expect(literal.filter('account.Name', 'LIKE', '50%_off')).to eq(
      "account.Name LIKE '%50\\%\\_off%' ESCAPE '\\'"
    )
  end

  it 'rejects empty or non-array IN values' do
    expect { literal.filter('account.Status', 'IN', []) }.to raise_error(ZuQL::CompilationError)
    expect { literal.filter('account.Status', 'IN', 'Active') }.to raise_error(ZuQL::CompilationError)
  end

  it 'rejects arrays outside IN operators and NULL with ordered operators' do
    expect { literal.filter('account.Status', '=', ['Active']) }.to raise_error(ZuQL::CompilationError)
    expect { literal.filter('account.Status', '>', nil) }.to raise_error(ZuQL::CompilationError)
  end

  it 'rejects NULL members, unsupported objects, and non-finite floats' do
    expect { literal.filter('account.Status', 'IN', ['Active', nil]) }.to raise_error(ZuQL::CompilationError)
    expect { literal.filter('account.Name', '=', Object.new) }.to raise_error(ZuQL::CompilationError)
    expect { literal.filter('account.Amount', '=', Float::INFINITY) }.to raise_error(ZuQL::CompilationError)
    expect { literal.filter('account.Amount', '=', Float::NAN) }.to raise_error(ZuQL::CompilationError)
  end

  it 'rejects unknown operators' do
    expect { literal.filter('account.Name', 'DROP', 'x') }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(operator: 'DROP') }
  end
end
