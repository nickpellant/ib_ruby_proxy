require 'spec_helper'
java_import 'com.ib.client.Contract'
java_import 'com.ib.client.Types'

describe IbRubyProxy::Server::IbRubyClassGenerator do
  describe '#ruby_class_source_for' do
    it 'generates a valid ruby object for a simple ib value object class' do
      generator = IbRubyProxy::Server::IbRubyClassGenerator.new(Contract, namespace: 'IbRubyProxy::Client::Ib::Test1')
      eval generator.ruby_class_source
      contract = IbRubyProxy::Client::Ib::Test1::Contract.new(last_trade_date_or_contract_month: '2018-2-4')
      expect(contract.last_trade_date_or_contract_month).to eq('2018-2-4')
    end
  end

  describe "Generated methods" do
    before(:context) do
      generator = IbRubyProxy::Server::IbRubyClassGenerator.new(Contract, namespace: 'IbRubyProxy::Client::Ib::Test2')
      eval generator.ruby_class_source
    end

    describe "#to_ib" do
      it 'creates an ib object with simple attributes copied' do
        contract = IbRubyProxy::Client::Ib::Test2::Contract.new symbol: 'ES',
                                                                sec_type: 'FUT',
                                                                currency: 'USD',
                                                                exchange: 'GLOBEX',
                                                                last_trade_date_or_contract_month: '201903'
        ib_contract = contract.to_ib
        expect(ib_contract).to be_an_instance_of(Java::ComIbClient::Contract)
        expect(ib_contract.symbol).to eq('ES')
        expect(ib_contract.secType).to eq(Types::SecType::FUT)
        expect(ib_contract.currency).to eq('USD')
        expect(ib_contract.exchange).to eq('GLOBEX')
        expect(ib_contract.lastTradeDateOrContractMonth).to eq('201903')
      end
    end

    describe '.from_ib' do
      it 'creates a ruby object from with the attributes copied from the provided IB object' do
        ib_contract = Java::ComIbClient::Contract.new
        ib_contract.symbol('ES')
        ib_contract.secType('FUT')
        ib_contract.currency('USD')
        ib_contract.exchange('GLOBEX')
        ib_contract.lastTradeDateOrContractMonth('201903')

        ruby_contract = IbRubyProxy::Client::Ib::Test2::Contract.from_ib(ib_contract)
        expect(ruby_contract).to be_instance_of(IbRubyProxy::Client::Ib::Test2::Contract)
        expect(ruby_contract.symbol).to eq('ES')
        expect(ruby_contract.sec_type).to eq(Types::SecType::FUT)
        expect(ruby_contract.currency).to eq('USD')
        expect(ruby_contract.exchange).to eq('GLOBEX')
        expect(ruby_contract.last_trade_date_or_contract_month).to eq('201903')
      end
    end
  end
end
