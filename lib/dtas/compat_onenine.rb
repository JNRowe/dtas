# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

# Make Ruby 1.9.3 look like Ruby 2.0.0 to us
# This exists for Debian wheezy users using the stock Ruby 1.9.3 install.
# We'll drop this interface when Debian wheezy (7.0) becomes unsupported.
class String # :nodoc:
  def b # :nodoc:
    dup.force_encoding(Encoding::BINARY)
  end
end unless String.method_defined?(:b)

def IO # :nodoc:
  def self.pipe # :nodoc:
    super.map! { |io| io.close_on_exec = true; io }
  end
end if RUBY_VERSION.to_f <= 1.9
