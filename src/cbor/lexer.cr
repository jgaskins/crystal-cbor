require "./token"

class CBOR::Lexer
  def self.new(string : String)
    new IO::Memory.new(string)
  end

  def self.new(slice : Bytes)
    new IO::Memory.new(slice)
  end

  @current_pos : Int64
  @eof : Bool = false
  # Holds a list of previously opened tokens.
  # When a break in reached, the last entry in the array is
  # the token to close.
  @open_tokens = [] of Kind

  def initialize(@io : IO)
    @current_pos = 0
  end

  # Reads the next concrete value
  def read_value : Type?
    res = read_next
    return nil unless res
    res[:value]
  end

  # Readsn the next concrete value, returning the token kind.
  # Useful when you need to differentiate between Null and Undefined.
  def read_next : Token?
    return nil if @eof

    token = next_token
    return nil unless token

    case token[:kind]
    when Kind::Int,
         Kind::String,
         Kind::Bool,
         Kind::Float,
         Kind::Bytes
      token
    when Kind::Null,
         Kind::Undefined
      {kind: token[:kind], value: nil}
    when Kind::BytesArray
      {kind: token[:kind], value: read_bytes_array}
    end
  end

  # Consumes the bytes array until it reaches a break
  def read_bytes_array : CBOR::BytesArray
    bytes = BytesArray.new

    loop do
      token = next_token
      raise ParseError.new("Unexpected EOF while reading bytes array") unless token
      break if token[:kind] == Kind::BytesArrayEnd
      raise ParseError.new("Illegal token #{token.class} while reading bytes array") unless token[:kind] == Kind::Bytes
      bytes << token[:value].as(Bytes)
    end

    bytes
  end

  private def next_token : Token?
    return nil if @eof

    @current_pos = @io.pos.to_i64
    current_byte = next_byte
    return nil unless current_byte

    case current_byte
    when 0x00..0x17
      consume_int(current_byte)
    when 0x18
      consume_int(read(UInt8))
    when 0x19
      consume_int(read(UInt16))
    when 0x1a
      consume_int(read(UInt32))
    when 0x1b
      consume_int(read(UInt64))
    when 0x20..0x37
      # This range represents values from -1..-24 so we subtract 0x20
      # from the uint8 value to
      consume_int(to_negative_int(current_byte.to_u8 - 0x20))
    when 0x38
      consume_int(to_negative_int(read(UInt8)))
    when 0x39
      consume_int(to_negative_int(read(UInt16)))
    when 0x3a
      consume_int(to_negative_int(read(UInt32)))
    when 0x3b
      consume_int(to_negative_int(read(UInt64)))
    when 0x40..0x57
      # read current_byte - 0x40 bytes ahead
      consume_binary(current_byte - 0x40)
    when 0x58
      consume_binary(read(UInt8))
    when 0x59
      consume_binary(read(UInt16))
    when 0x5a
      consume_binary(read(UInt32))
    when 0x5b
      consume_binary(read(UInt64))
    when 0x5f
      {kind: open_token(Kind::BytesArray), value: nil}
    when 0xff
      {kind: finish_token, value: nil}
    else
      raise ParseError.new("Unexpected first byte 0x#{current_byte.to_s(16)}")
    end
  end

  private def next_byte : UInt8?
    byte = @io.read_byte
    if byte
      byte
    else
      @eof = true
      nil
    end
  end

  private def consume_int(value)
    {kind: Kind::Int, value: value}
  end

  private def consume_binary(size)
    bytes = Bytes.new(size)
    @io.read_fully(bytes)
    {kind: Kind::Bytes, value: bytes}
  end

  private def open_token(kind : Kind) : Kind
    @open_tokens << kind
    kind
  end

  private def finish_token : Kind
    opened_token = @open_tokens.pop

    case opened_token
    when Kind::Array
      Kind::ArrayEnd
    when Kind::BytesArray
      Kind::BytesArrayEnd
    when Kind::StringArray
      Kind::StringArrayEnd
    else
      raise ParseError.new("Unexpected token termination #{opened_token.to_s}")
    end
  end

  # Creates a method overloaded for each UInt sizes to convert the UInt into
  # the respective Int capable of containing the value

  {% begin %}
    {% uints = %w(UInt8 UInt16 UInt32 UInt64) %}
    {% conv = %w(to_i8 to_i16 to_i32 to_i64 to_i128) %}

    {% for uint, index in uints %}
      # Reads the `{{uint.id}}` as a negative integer, returning the samllest
      # integer capable of containing the value.
      def to_negative_int(value : {{uint.id}})
        int = begin
                -value.{{conv[index].id}}
              rescue OverflowError
                -value.{{conv[index + 1].id}}
              end

        int - 1
      end
    {% end %}
  {% end %}

  private def read(type : T.class) forall T
    @io.read_bytes(T, IO::ByteFormat::NetworkEndian)
  end
end
