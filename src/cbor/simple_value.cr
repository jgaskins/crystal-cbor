enum CBOR::SimpleValue : UInt8
  False     = 20
  True
  Null
  Undefined

  def to_diagnostic : String
    case self
    when False
      "false"
    when True
      "true"
    when Null
      "null"
    when Undefined
      "undefined"
    else
      "simple(#{self.value.to_s})"
    end
  end

  def is_nil? : Bool
    case self
    when Null, Undefined
      true
    else
      false
    end
  end
end
