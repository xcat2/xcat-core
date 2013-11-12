require_relative "spec_helper"
require "uri"
require ::File.join ::File.dirname(__FILE__), "..", "libraries", "parse"

describe ::Openstack do
  before do
    @subject = ::Object.new.extend(::Openstack)
  end

  describe "#prettytable_to_array" do
    it "returns [] when no table provided" do
      @subject.prettytable_to_array(nil).should == []
    end
    it "returns [] when table provided is empty" do
      @subject.prettytable_to_array("").should == []
    end
    it "returns proper array of hashes when proper table provided" do
      table =
"+---------+----------------------------------+----------------------------------+
|  tenant |              access              |              secret              |
+---------+----------------------------------+----------------------------------+
| service | 91af731b3be244beb8f30fc59b7bc96d | ce811442cfb549c39390a203778a4bf5 |
+---------+----------------------------------+----------------------------------+"
      @subject.prettytable_to_array(table).should ==
        [{"tenant" => "service",
          "access" => "91af731b3be244beb8f30fc59b7bc96d",
          "secret" => "ce811442cfb549c39390a203778a4bf5"}]
    end
    it "returns proper array of hashes when proper table provided including whitespace" do
      table =
"+---------+----------------------------------+----------------------------------+
|  tenant |              access              |              secret              |
+---------+----------------------------------+----------------------------------+
| service | 91af731b3be244beb8f30fc59b7bc96d | ce811442cfb549c39390a203778a4bf5 |
+---------+----------------------------------+----------------------------------+


"
      @subject.prettytable_to_array(table).should ==
        [{"tenant" => "service",
          "access" => "91af731b3be244beb8f30fc59b7bc96d",
          "secret" => "ce811442cfb549c39390a203778a4bf5"}]
    end
    it "returns a flatten hash when provided a Property/Value table" do
      table =
"+-----------+----------------------------------+
|  Property |              Value               |
+-----------+----------------------------------+
|   access  | 91af731b3be244beb8f30fc59b7bc96d |
|   secret  | ce811442cfb549c39390a203778a4bf5 |
| tenant_id | 429271dd1cf54b7ca921a0017524d8ea |
|  user_id  | 1c4fc229560f40689c490c5d0838fd84 |
+-----------+----------------------------------+"
      @subject.prettytable_to_array(table).should ==
        [{"tenant_id" => "429271dd1cf54b7ca921a0017524d8ea",
          "access" => "91af731b3be244beb8f30fc59b7bc96d",
          "secret" => "ce811442cfb549c39390a203778a4bf5",
          "user_id" => "1c4fc229560f40689c490c5d0838fd84"}]
    end
    it "returns a flatten hash when provided a Property/Value table including whitespace" do
      table =
"

+-----------+----------------------------------+
|  Property |              Value               |
+-----------+----------------------------------+
|   access  | 91af731b3be244beb8f30fc59b7bc96d |
|   secret  | ce811442cfb549c39390a203778a4bf5 |
| tenant_id | 429271dd1cf54b7ca921a0017524d8ea |
|  user_id  | 1c4fc229560f40689c490c5d0838fd84 |
+-----------+----------------------------------+"
      @subject.prettytable_to_array(table).should ==
        [{"tenant_id" => "429271dd1cf54b7ca921a0017524d8ea",
          "access" => "91af731b3be244beb8f30fc59b7bc96d",
          "secret" => "ce811442cfb549c39390a203778a4bf5",
          "user_id" => "1c4fc229560f40689c490c5d0838fd84"}]
    end
  end
end
