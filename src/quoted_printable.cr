module QuotedPrintable
  VERSION = "0.1.3"

  extend self

  class Error < Exception; end

  class InvalidEncodedData < Error
    def initialize(*data : String | Char)
      super(data.map { |s| "\"#{s.inspect.delete("\"'")}\"" }.join(", "))
    end
  end

  enum CharType
    CR
    LF
    WHITE_SPACE
    PRINTABLE
    EQUAL
    OTHER
  end

  LINE_BREAK      = "\r\n"
  SOFT_LINE_BREAK = "=\r\n"
  MAX_LENGTH      = 76

  def encode(data : String | Enumerable(UInt8))
    String.build do |str|
      encode(data, str)
    end
  end

  def encode(bytes : Enumerable(UInt8), io : IO)
    encode_bytes(bytes, 0, false, io)
  end

  def encode(string : String, io : IO)
    lines = 0
    string.split(/\r?\n/).each do |line|
      io << LINE_BREAK if lines > 0
      chars = Char::Reader.new(line)
      char = chars.current_char
      line_length = 0
      until char == '\0'
        has_next = (chars.peek_next_char != '\0')
        char_type = type_of(char)
        line_length = case char_type
                      when CharType::PRINTABLE
                        encode_data(char, line_length, has_next, io)
                      when CharType::WHITE_SPACE
                        if has_next
                          encode_data(char, line_length, has_next, io)
                        else
                          encode_bytes(char.bytes, line_length, has_next, io)
                        end
                      else
                        encode_bytes(char.bytes, line_length, has_next, io)
                      end
        char = chars.next_char
      end
      lines += 1
    end
  end

  private def encode_bytes(bytes : Enumerable(UInt8), line_length, has_next, io)
    byte_size = bytes.size
    bytes.each_with_index do |byte, i|
      line_length = encode_data("=%02X" % byte, line_length, has_next || i + 1 < byte_size, io)
    end
    line_length
  end

  private def encode_data(data : String | Char, line_length, has_next, io)
    byte_size = data.bytesize
    new_length = line_length + byte_size
    if new_length > MAX_LENGTH || (new_length == MAX_LENGTH && has_next)
      io << SOFT_LINE_BREAK
      line_length = 0
    end
    io << data
    line_length += byte_size
  end

  def decode(data : String) : Bytes
    buf = Pointer(UInt8).malloc(decode_size(data))
    appender = buf.appender
    from_quoted_printable(data) { |byte| appender << byte }
    Slice.new(buf, appender.size.to_i32)
  end

  def decode(data : String, io : IO)
    count = 0
    from_quoted_printable(data) do |byte|
      io.write_byte byte
      count += 1
    end
    io.flush
    count
  end

  def decode_string(data : String, encoding : String = "UTF-8", invalid : Symbol? = nil, line_break : String? = nil) : String
    str = String.new(decode(data), encoding, invalid)
    str = str.gsub(/\r\n/, line_break) if line_break
    str
  end

  private def from_quoted_printable(data : String)
    chars = Char::Reader.new(data)
    char = chars.current_char
    until char == '\0'
      case type_of(char)
      when CharType::PRINTABLE, CharType::WHITE_SPACE, CharType::CR, CharType::LF
        yield char.ord.to_u8
      when CharType::EQUAL
        c1 = chars.next_char
        c2 = chars.next_char
        unless c1 == '\r' && c2 == '\n' # soft line break: emit nothing
          hi = c1.to_i?(16)
          lo = c2.to_i?(16)
          if hi && lo
            yield ((hi << 4) | lo).to_u8
          else
            raise InvalidEncodedData.new("=#{c1}#{c2}")
          end
        end
      else
        raise InvalidEncodedData.new(char)
      end
      char = chars.next_char
    end
  end

  private def valid_encoded_string!(string : String)
    matched = string.scan(/([^!-~ \t\r\n]|\r[^\n]|[^\r]\n)/).map { |m| m[0] } + string.scan(/=.{2}/).map { |m| m[0] }.select { |s| s !~ /=([0-9A-F]{2}|\r\n)/ }
    unless matched.empty?
      raise matched.map { |s| s.inspect.sub(/\A'/, '"').sub(/'\z/, '"') }.join(", ")
    end
    string
  end

  # Upper bound on the decoded size: quoted-printable decoding never
  # expands its input, and the caller trims the result to the bytes
  # actually produced. Computing the exact size previously required two
  # full-body regex scans, which dominated decode cost on escape-heavy
  # bodies.
  private def decode_size(string : String)
    string.bytesize
  end

  private def type_of(char) : CharType
    case char
    when '!'..'<', '>'..'~'
      CharType::PRINTABLE
    when '='
      CharType::EQUAL
    when ' ', '\t'
      CharType::WHITE_SPACE
    when '\r'
      CharType::CR
    when '\n'
      CharType::LF
    else
      CharType::OTHER
    end
  end
end
