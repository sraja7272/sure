require "test_helper"

class Assistant::Function::ImportBankStatementTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @fn = Assistant::Function::ImportBankStatement.new(@user)
    @openai = Provider::Openai.new("test-key")
  end

  test "model_for falls back to Setting when OPENAI_MODEL env is blank" do
    Setting.stubs(:openai_model).returns("llama3")
    with_env_overrides("OPENAI_MODEL" => "") do
      assert_equal "llama3", @fn.send(:model_for, @openai)
    end
  end

  test "model_for prefers OPENAI_MODEL env when set" do
    Setting.stubs(:openai_model).returns("llama3")
    with_env_overrides("OPENAI_MODEL" => "gpt-4o") do
      assert_equal "gpt-4o", @fn.send(:model_for, @openai)
    end
  end

  test "charges the chat user for the statement extraction" do
    import = imports(:pdf)
    import.update!(document_type: "bank_statement")
    PdfImport.any_instance.stubs(:pdf_file_content).returns("fake-pdf")
    provider = mock("llm_provider")
    Provider::Registry.stubs(:preferred_llm_provider).returns(provider)
    provider.expects(:extract_bank_statement)
            .with { |**kwargs| kwargs[:user] == @user && kwargs[:family] == @user.family }
            .returns(Provider::Response.new(success?: false, data: nil, error: Provider::Error.new("stop here")))

    result = @fn.call("pdf_import_id" => import.id, "account_id" => accounts(:depository).id)

    assert_equal "extraction_failed", result[:error]
  end

  test "model_for leaves non-OpenAI providers to their own default" do
    with_env_overrides("OPENAI_MODEL" => "gpt-4o") do
      assert_nil @fn.send(:model_for, Provider::Anthropic.new("test-key"))
    end
  end
end
