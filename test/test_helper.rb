# frozen_string_literal: true

RUBY_MAIN_OBJ = self

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "scarpe"
require "scarpe/components/unit_test_helpers"
require "scarpe/components/minitest_result"

require "json"
require "fileutils"
require "tmpdir"

require "minitest/autorun"

require "minitest/reporters"
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

# Docs for our Webview lib: https://github.com/Maaarcocr/webview_ruby

SET_UP_TIMEOUT_CHECKS = { setup: false, near_timeout: [] }
TIMEOUT_FRACTION_OF_THRESHOLD = 0.5 # Too low?

class ScarpeTest < Minitest::Test
  include Scarpe::Test::Helpers
  include Scarpe::Test::HTMLAssertions
end

# While Scarpe-Webview has some extra methods available from its ShoesSpec
# classes, this basically uses the ShoesSpec syntax.
class ShoesSpecLoggedTest < Minitest::Test
  include Scarpe::Test::Helpers
  include Scarpe::Test::LoggedTest
  self.logger_dir = File.expand_path("#{__dir__}/../logger")

  SCARPE_EXE = File.expand_path("../exe/scarpe", __dir__)

  def run_scarpe_sspec_code(sspec_code, **kwargs)
    with_tempfile(["scarpe_sspec_test_#{self.class.name}_#{self.name}", ".sspec"], sspec_code) do |filename|
      run_scarpe_sspec(filename, **kwargs)
    end
  end

  def run_scarpe_sspec(
    filename,
    process_success: true,
    expect_assertions_min: nil,
    expect_assertions_max: nil,
    expect_result: :success,
    display_service: "wv_local",
    html_renderer: "calzini"
  )
    test_output = File.expand_path(File.join __dir__, "sspec.json")
    test_method_name = self.name
    test_class_name = self.class.name

    with_tempfile("scarpe_log_config.json", JSON.dump(log_config_for_test)) do |scarpe_log_config|
      # Start the application using the exe/scarpe utility
      # For unit testing always supply --debug so we get the most logging
      cmd = \
        "SCARPE_DISPLAY_SERVICE=#{display_service} " +
        "SCARPE_HTML_RENDERER=#{html_renderer} " +
        "SCARPE_LOG_CONFIG=\"#{scarpe_log_config}\" " +
        "SHOES_MINITEST_EXPORT_FILE=\"#{test_output}\" " +
        "SHOES_MINITEST_CLASS_NAME=\"#{test_class_name}\" " +
        "SHOES_MINITEST_METHOD_NAME=\"#{test_method_name}\" " +
        "LOCALAPPDATA=\"#{Dir.tmpdir}\"" +
        "ruby #{SCARPE_EXE} --debug --dev #{filename}"
      process_result = system(cmd)

      if process_result != process_success
        if process_success
          assert false, "Expected sspec test process to return success and it failed! Exit code: #{$?.exitstatus}"
        else
          assert false, "Expected sspec test process to return failure and it succeeded!"
        end
      end
    end

    result = Scarpe::Components::MinitestResult.new(test_output)
    correct, msg = result.check(expect_result:, min_asserts: expect_assertions_min, max_asserts: expect_assertions_max)

    if correct
      assert_equal true, true # Yup, worked fine
    else
      assert false, "Minitest result: #{msg}"
    end
  end

  def run_test_scarpe_code(
    scarpe_app_code,
    test_extension: ".rb",
    **opts
  )
    with_tempfile(["scarpe_test_app", test_extension], scarpe_app_code) do |test_app_location|
      run_test_scarpe_app(test_app_location, **opts)
    end
  end

  def run_test_scarpe_app(
    test_app_location,
    app_test_code: "",
    timeout: 10.0,
    exit_immediately: false,
    allow_fail: false,
    display_service: "wv_local"
  )
    full_test_code = <<~TEST_CODE
      timeout #{timeout}
      #{exit_immediately ? "exit_on_first_heartbeat" : ""}
      #{app_test_code}
    TEST_CODE

    test_output = File.expand_path(File.join __dir__, "sspec.json")
    File.unlink test_output rescue nil

    test_method_name = self.name
    test_class_name = self.class.name

    with_tempfiles([
      ["scarpe_log_config.json", JSON.dump(log_config_for_test)],
      ["scarpe_app_test.rb", full_test_code],
    ]) do |scarpe_log_config, app_test_path|
      # Start the application using the exe/scarpe utility
      # For unit testing always supply --debug so we get the most logging
      system(
        "SCARPE_DISPLAY_SERVICE=#{display_service} " +
        "SCARPE_LOG_CONFIG=\"#{scarpe_log_config}\" " +
        "SHOES_SPEC_TEST=\"#{app_test_path}\" " +
        "SHOES_MINITEST_EXPORT_FILE=\"#{test_output}\" " +
        "SHOES_MINITEST_CLASS_NAME=\"#{test_class_name}\" " +
        "SHOES_MINITEST_METHOD_NAME=\"#{test_method_name}\" " +
        "LOCALAPPDATA=\"#{Dir.tmpdir}\"" +
        "ruby #{SCARPE_EXE} --debug --dev #{test_app_location}")
    end

    # TODO: this should *require* the process to fail, not allow it.
    if allow_fail
      assert true
      return
    end

    # Check if the process exited normally or crashed (segfault, failure, timeout)
    unless $?.success?
      assert(false, "Scarpe app failed with exit code: #{$?.exitstatus}")
      return
    end

    result = Scarpe::Components::MinitestResult.new(test_output)
    if result.error?
      raise result.error_message
    elsif result.fail?
      assert false, result.fail_message
    elsif result.skip?
      skip
    else
      # Count out the correct number of assertions
      result.assertions.times { assert true }
    end
  end
end

class LoggedScarpeTest < ScarpeTest
  include Scarpe::Test::LoggedTest
  self.logger_dir = File.expand_path("#{__dir__}/../logger")

  def setup
    self.extra_log_config = {
      # file_id is the test name, and comes from LoggedTest
      "Webview" => ["debug", "logger/test_failure_wv_misc_#{file_id}.log"],
      "Webview::API" => ["debug", "logger/test_failure_wv_api_#{file_id}.log"],

      "Webview::CatsCradle" => ["debug", "logger/test_failure_catscradle_#{file_id}.log"],

      # These all go in an events file
      "Webview::RelayDisplayService" => ["debug", "logger/test_failure_events_#{file_id}.log"],
      "Webview::WebviewDisplayService" => ["debug", "logger/test_failure_events_#{file_id}.log"],
      "Webview::ControlInterface" => ["debug", "logger/test_failure_events_#{file_id}.log"],
    }
    super
  end
end
