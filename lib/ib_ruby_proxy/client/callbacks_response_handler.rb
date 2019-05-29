module IbRubyProxy
  module Client
    class CallbacksResponseHandler
      def initialize
        @method_handlers = {}
        @callback_handlers = {}
      end

      def method_invoked(method_name, *arguments, &block)
        method_name = method_name.to_sym
        method_handlers[method_name]&.method_invoked(*arguments, &block)
      end

      def callback_received(callback_name, *arguments)
        callback_name = callback_name.to_sym
        callback_handlers[callback_name]&.callback_received(*arguments, callback_name: callback_name)
      end

      # @todo: Move outside of this class when we add more options
      def self.for_ib
        self.new.tap do |handler|
          handler.configure_single_response_promise_callback method: :req_historical_ticks,
                                                             callback: %i(historical_ticks historical_ticks_bid_ask historical_ticks_last error),
                                                             discriminate_by_argument_nth: 0

          handler.configure_multi_response_promise_callback method: :req_contract_details,
                                                            callback: %i(contract_details error),
                                                            done_callback: :contract_details_end,
                                                            discriminate_by_argument_nth: 0

          handler.configure_block_callback method: :req_tick_by_tick_data,
                                                            callback: %i(tick_by_tick_bid_ask tick_by_tick_all_last tick_by_tick_mid_point error),
                                                            discriminate_by_argument_nth: 0

          handler.configure_block_callback method: :req_positions,
                                           callback: %i(position error),
                                           discriminate_by_argument_nth: 0

          # @todo this is wrong, just for debugging...
          handler.configure_block_callback method: :req_account_updates,
                                                            callback: %i(update_account_value update_portfolio update_account_time error),
                                                            discriminate_by_argument_nth: 0
        end
      end

      def configure_single_response_promise_callback(method:, callback:, discriminate_by_argument_nth: 0)
        validate_can_add_callback_on_method!(method)

        handler = PromiseSingleResponseHandler.new(discriminate_by_argument_nth)

        configure_callback_handler(callback, handler)
        configure_method_handler(method, handler)
      end

      def configure_multi_response_promise_callback(method:, callback:, done_callback:, discriminate_by_argument_nth: 0)
        validate_can_add_callback_on_method!(method)

        handler = PromiseMultipleResponseHandler.new(discriminate_by_argument_nth, done_callback)

        configure_callback_handler(callback, handler)
        configure_callback_handler(done_callback, handler)
        configure_method_handler(method, handler)
      end

      def configure_block_callback(method:, callback:, discriminate_by_argument_nth:)
        validate_can_add_callback_on_method!(method)

        handler = CallbackResponseHandler.new(discriminate_by_argument_nth)

        configure_callback_handler(callback, handler)
        configure_method_handler(method, handler)
      end

      private

      attr_reader :method_handlers, :callback_handlers

      def configure_method_handler(method, handler)
        method_handlers[method.to_sym] = handler
      end

      def configure_callback_handler(callback, handler)
        callback = [callback] unless callback.respond_to?(:each)
        callback.each do |callback_name|
          callback_handlers[callback_name.to_sym] = handler
        end
      end

      def validate_can_add_callback_on_method!(method)
        raise "Already configured handler for #{method}" if method_handlers[method]
      end

      class PromiseSingleResponseHandler
        include IbRubyProxy::Util::HasLogger

        attr_reader :discriminate_by_argument_nth, :promise

        def initialize(discriminate_by_argument_nth)
          @discriminate_by_argument_nth = discriminate_by_argument_nth
          @promises_by_key = {}
        end

        def method_invoked(*arguments)
          key = arguments[discriminate_by_argument_nth]
          raise "Configured with a promise and invoked more than once?" if @promises_by_key[key]
          @promises_by_key[key] = Concurrent::Promises.resolvable_future
        end

        def callback_received(*arguments, callback_name: nil)
          promise = promise_for_arguments(arguments)
          if callback_name.to_s == 'error'
            reject_promise_on_error(promise, arguments)
          else
            promise&.fulfill arguments
          end
        end

        protected

        def promise_for_arguments(arguments)
          key = arguments[discriminate_by_argument_nth]
          @promises_by_key[key]
        end

        private

        def reject_promise_on_error(promise, arguments)
          logger.error "Error received when handling response: #{arguments.inspect}"
          promise&.reject arguments
        end
      end

      class PromiseMultipleResponseHandler < PromiseSingleResponseHandler
        attr_reader :discriminate_by_argument_nth, :promise, :done_callback

        def initialize(discriminate_by_argument_nth, done_callback)
          super(discriminate_by_argument_nth)
          @done_callback = done_callback
          @promises_by_key = {}
          @results_by_key = {}
        end

        def callback_received(*arguments, callback_name: nil)
          promise = promise_for_arguments(arguments)
          key = arguments[discriminate_by_argument_nth]

          case callback_name.to_s
          when done_callback.to_s
            promise&.fulfill @results_by_key[key]
          when 'error'
            reject_promise_on_error(promise, arguments)
          else
            @results_by_key[key] ||= []
            @results_by_key[key] << arguments
          end
        end
      end

      class CallbackResponseHandler
        include IbRubyProxy::Util::HasLogger

        attr_reader :discriminate_by_argument_nth, :block

        def initialize(discriminate_by_argument_nth)
          @discriminate_by_argument_nth = discriminate_by_argument_nth
        end

        def method_invoked(*arguments, &block)
          @block = block
        end

        def callback_received(*arguments, callback_name: nil)
          if callback_name.to_s == 'error'
            raise StandardError, arguments.join('. ')
          else
            @block&.call(*arguments)
          end
        end
      end
    end
  end
end
