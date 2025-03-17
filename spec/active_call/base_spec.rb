# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveCall::Base do
  describe '.call' do
    context 'when validations pass' do
      let(:service_class) do
        Class.new(ActiveCall::Base) do
          attr_accessor :input

          def initialize(input)
            @input = input
          end

          def call
            "Processed: #{input}"
          end
        end
      end

      before do
        stub_const('TestService', service_class)
      end

      it 'returns a service instance' do
        result = TestService.call('test')
        expect(result).to be_an_instance_of(TestService)
      end

      it 'sets the response from the call method' do
        result = TestService.call('test')
        expect(result.response).to eq('Processed: test')
      end

      it 'runs the callbacks around call' do
        callback_executed = false
        callback_service = Class.new(TestService) do
          before_call do
            callback_executed = true
          end
        end

        stub_const('CallbackService', callback_service)

        CallbackService.call('test')
        expect(callback_executed).to be true
      end
    end

    context 'when validations fail' do
      let(:invalid_service_class) do
        Class.new(ActiveCall::Base) do
          attr_accessor :input

          validates :input, presence: true

          def initialize(input)
            @input = input
          end

          def call
            "Processed: #{input}"
          end
        end
      end

      before do
        stub_const('InvalidTestService', invalid_service_class)
      end

      it 'returns the service instance without calling the call method' do
        result = InvalidTestService.call(nil)
        expect(result).to be_an_instance_of(InvalidTestService)
        expect(result.response).to be_nil
      end

      it 'has errors when validations fail' do
        result = InvalidTestService.call(nil)
        expect(result).to be_invalid
        expect(result.errors[:input]).to include("can't be blank")
      end
    end

    context 'with callbacks' do
      let(:callback_service_class) do
        Class.new(ActiveCall::Base) do
          attr_accessor :input, :tracking

          def initialize(input)
            @input = input
            @tracking = []
          end

          before_call :track_before
          after_call :track_after

          def call
            @tracking << :call
            "Processed: #{input}"
          end

          private

          def track_before
            @tracking << :before
          end

          def track_after
            @tracking << :after
          end
        end
      end

      before do
        stub_const('CallbackTestService', callback_service_class)
      end

      it 'executes callbacks in the correct order' do
        result = CallbackTestService.call('test')
        expect(result.tracking).to eq([:before, :call, :after])
      end
    end
  end

  describe '.call!' do
    context 'when validations pass and service succeeds' do
      let(:service_class) do
        Class.new(ActiveCall::Base) do
          attr_accessor :input

          def initialize(input)
            @input = input
          end

          def call
            "Processed: #{input}"
          end
        end
      end

      before do
        stub_const('TestService', service_class)
      end

      it 'returns a service instance' do
        result = TestService.call!('test')
        expect(result).to be_an_instance_of(TestService)
      end

      it 'sets the response from the call method' do
        result = TestService.call!('test')
        expect(result.response).to eq('Processed: test')
      end
    end

    context 'when validations fail' do
      let(:invalid_service_class) do
        Class.new(ActiveCall::Base) do
          attr_accessor :input

          validates :input, presence: true

          def initialize(input)
            @input = input
          end

          def call
            "Processed: #{input}"
          end
        end
      end

      before do
        stub_const('InvalidTestService', invalid_service_class)
      end

      it 'raises a ValidationError' do
        expect { InvalidTestService.call!(nil) }.to raise_error(ActiveCall::ValidationError)
      end
    end

    context 'when service fails' do
      let(:failing_service_class) do
        Class.new(ActiveCall::Base) do
          attr_accessor :input

          after_call :validate_input

          def initialize(input)
            @input = input
          end

          def call
            "Processed: #{input}"
          end

          private

          def validate_input
            errors.add(:base, 'Service failed')
          end
        end
      end

      before do
        stub_const('FailingTestService', failing_service_class)
      end

      it 'raises a RequestError' do
        expect { FailingTestService.call!('test') }.to raise_error(ActiveCall::RequestError)
      end
    end
  end

  describe '#success?' do
    let(:service_class) do
      Class.new(ActiveCall::Base) do
        attr_accessor :input

        def initialize(input = nil)
          @input = input
        end

        def call
          "Processed: #{input}"
        end
      end
    end

    before do
      stub_const('TestService', service_class)
    end

    context 'when there are no errors' do
      it 'returns true' do
        result = TestService.call('test')
        expect(result.success?).to be true
      end
    end

    context 'when there are errors' do
      it 'returns false when validation fails' do
        invalid_service = Class.new(TestService) do
          validates :input, presence: true
        end

        stub_const('InvalidTestService', invalid_service)

        service = InvalidTestService.call(nil)
        expect(service.success?).to be false
      end

      it 'returns false after a failed call' do
        failing_service = Class.new(TestService) do
          after_call :validate_input

          private

          def validate_input
            errors.add(:base, 'Something went wrong')
          end
        end

        stub_const('FailingTestService', failing_service)

        result = FailingTestService.call('test')
        expect(result.success?).to be false
      end
    end
  end

  describe '#valid?' do
    let(:service_class) do
      Class.new(ActiveCall::Base) do
        attr_accessor :input

        validates :input, presence: true

        def initialize(input = nil)
          @input = input
        end

        def call
          "Processed: #{input}"
        end
      end
    end

    before do
      stub_const('TestService', service_class)
    end

    context 'when response is not set' do
      it 'follows normal validation rules' do
        service = TestService.new('test')
        expect(service.valid?).to be true

        service = TestService.new(nil)
        expect(service.valid?).to be false
        expect(service.errors[:input]).to include("can't be blank")
      end
    end

    context 'when response is set' do
      it 'returns true regardless of request errors' do
        failing_service = Class.new(TestService) do
          after_call :validate_input

          private

          def validate_input
            errors.add(:base, 'Something went wrong')
          end
        end

        stub_const('FailingTestService', failing_service)

        service = FailingTestService.new('test')
        expect(service.valid?).to be true

        service.instance_variable_set(:@response, 'Some response')
        expect(service.valid?).to be true
        expect(service.errors).to be_empty
      end
    end
  end
end
