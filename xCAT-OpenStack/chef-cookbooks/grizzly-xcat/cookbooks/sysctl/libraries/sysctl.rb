module Sysctl
  class << self
    def compile_attr(prefix, v)
      case v
      when Array
        return "#{prefix}=#{v.join(" ")}"
      when String, Fixnum, Bignum, Float, Symbol
        "#{prefix}=#{v}"
      when Hash, Chef::Node::Attribute
        prefix += "." unless prefix.empty?
        return v.map {|key, value| compile_attr("#{prefix}#{key}", value) }.flatten
      else
        raise Chef::Exceptions::UnsupportedAction, "Sysctl cookbook can't handle values of type: #{v.class}"
      end
    end
  end
end
