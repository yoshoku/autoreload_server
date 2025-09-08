# frozen_string_literal: true

RSpec.describe AutoreloadWebServer do
  it "has a version number" do
    expect(AutoreloadWebServer::VERSION).not_to be_nil
  end
end
