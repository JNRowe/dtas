# Copyright (C) 2018 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

# This module gets included in DTAS
module DTAS::Encoding # :nodoc:
  def self.extended(mod)
    mod.instance_eval { @charlock_holmes = nil}
  end

private

  def try_enc_harder(str, enc, old) # :nodoc:
    case @charlock_holmes
    when nil
      begin
        require 'charlock_holmes'
        @charlock_holmes = CharlockHolmes::EncodingDetector.new
      rescue LoadError
        warn "`charlock_holmes` gem not available for encoding detection"
        @charlock_holmes = false
      end
    when false
      enc_fallback(str, enc, old)
    else
      res = @charlock_holmes.detect(str)
      if det = res[:ruby_encoding]
        str.force_encoding(det)
        warn "charlock_holmes detected #{str.inspect} as #{det}..."
        str.valid_encoding? or enc_fallback(str, det, old)
      else
        enc_fallback(str, enc, old)
      end
    end
    str
  end

  def enc_fallback(str, enc, old) # :nodoc:
    str.force_encoding(old)
    warn "could not detect encoding for #{str.inspect} (not #{enc})"
  end

public

  def try_enc(str, enc, harder = true) # :nodoc:
    old = str.encoding
    return str if old == enc
    str.force_encoding(enc)
    unless str.valid_encoding?
      if harder
        try_enc_harder(str, enc, old)
      else
        enc_fallback(str, enc, old)
      end
    end
    str
  end
end
