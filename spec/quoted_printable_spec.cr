require "./spec_helper"

describe QuotedPrintable do
  describe ".decode_string" do
    it "decodes plain printable text unchanged" do
      QuotedPrintable.decode_string("Hello, World!").should eq("Hello, World!")
    end

    it "decodes =XX hex escapes (uppercase)" do
      QuotedPrintable.decode_string("caf=C3=A9").should eq("café")
    end

    it "decodes =XX hex escapes (lowercase hex digits)" do
      QuotedPrintable.decode_string("caf=c3=a9").should eq("café")
    end

    it "decodes the escaped equals sign" do
      QuotedPrintable.decode_string("1+1=3D2").should eq("1+1=2")
    end

    it "removes soft line breaks" do
      QuotedPrintable.decode_string("foo=\r\nbar").should eq("foobar")
    end

    it "preserves hard line breaks" do
      QuotedPrintable.decode_string("foo\r\nbar").should eq("foo\r\nbar")
    end

    it "decodes multi-byte UTF-8 sequences" do
      QuotedPrintable.decode_string("=E6=97=A5=E6=9C=AC=E8=AA=9E").should eq("日本語")
    end

    it "preserves whitespace and tabs" do
      QuotedPrintable.decode_string("a b\tc").should eq("a b\tc")
    end

    it "handles empty string" do
      QuotedPrintable.decode_string("").should eq("")
    end

    it "decodes mixed content with soft breaks" do
      encoded = "=E3=81=93=E3=82=93=E3=81=AB=E3=81=A1=E3=81=AF=\r\n world"
      QuotedPrintable.decode_string(encoded).should eq("こんにちは world")
    end

    it "applies line_break replacement when given" do
      QuotedPrintable.decode_string("foo\r\nbar", line_break: "\n").should eq("foo\nbar")
    end

    it "raises InvalidEncodedData on bad hex escape" do
      expect_raises(QuotedPrintable::InvalidEncodedData) do
        QuotedPrintable.decode_string("bad=ZZdata")
      end
    end
  end

  describe ".decode" do
    it "returns correct bytes for escapes" do
      QuotedPrintable.decode("=00=01=FF").should eq(Bytes[0x00, 0x01, 0xFF])
    end
  end

  describe ".encode" do
    it "round-trips encode -> decode" do
      original = "Subject: 日本語テスト — with symbols = and dots.\r\nBody line two."
      encoded = QuotedPrintable.encode(original)
      QuotedPrintable.decode_string(encoded).should eq(original.gsub(/\r?\n/, "\r\n"))
    end

    it "escapes the equals sign" do
      QuotedPrintable.encode("a=b").should eq("a=3Db")
    end

    it "wraps lines at 76 characters with soft breaks" do
      encoded = QuotedPrintable.encode("x" * 100)
      encoded.split("=\r\n").each do |line|
        line.bytesize.should be <= 76
      end
      QuotedPrintable.decode_string(encoded).should eq("x" * 100)
    end
  end
end
